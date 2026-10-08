#!/usr/bin/env python3
"""Write a ~/Tabs/<Artist> - <Title>.tab file from an Ultimate Guitar page, a PDF or a scan.

Stdlib only. Subcommands:

  tab-import.py ug <url>                       one UG tab/chords page
  tab-import.py ug "<artist> - <title>"        search UG, take the most-voted version
                 [--chords]                     (default: the most-voted "Tabs"; --chords
                                                 picks the most-voted "Chords" page)
  tab-import.py pdf <file.pdf>                 text PDF via `pdftotext -layout`
  tab-import.py scan <file.pdf|png|jpg>        rasterise + `tesseract` (lossy; check it)

Common flags: --title --artist --tuning --capo --bpm --scroll --out <dir> --dry-run
The app owns only the `scroll:` key; everything else here is written once and left alone.
"""
import argparse
import html
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/127.0 Safari/537.36")
TABS_DIR = os.environ.get("TABS_DIR") or os.path.expanduser("~/Tabs")

SECTION_WORDS = ("intro", "verse", "pre-chorus", "prechorus", "chorus", "bridge", "outro",
                 "solo", "interlude", "instrumental", "coda", "ending", "riff", "break",
                 "refrain", "hook", "tag", "turnaround", "strumming pattern", "strum")
SECTION_RE = re.compile(
    r"^\s*(?:\[\s*)?(" + "|".join(re.escape(w) for w in SECTION_WORDS) +
    r")(?:\s*[-\s]*\s*([0-9]+|[a-dA-D]|[ivxIVX]+))?\s*(?:\]|:)?\s*(?:\(([^)]*)\))?\s*(x\s*[0-9]+)?\s*$",
    re.IGNORECASE)


# ---------------------------------------------------------------- helpers

def die(msg, code=1):
    print(f"tab-import: {msg}", file=sys.stderr)
    sys.exit(code)


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "en"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def js_store(page):
    """UG renders the whole page state into <div class="js-store" data-content="...">."""
    m = re.search(r'class="js-store" data-content="([^"]+)"', page)
    if not m:
        die("no js-store blob on that page (not a UG tab page, or UG changed its markup)")
    return json.loads(html.unescape(m.group(1)))["store"]["page"]["data"]


def clean_body(text):
    """UG markup → the app's plain format. Also tidies pdftotext / tesseract output."""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"\[/?tab\]", "", text)
    text = re.sub(r"\[ch\](.*?)\[/ch\]", r"\1", text)
    text = re.sub(r"\[/?syllable[^\]]*\]", "", text)
    out = []
    for line in text.split("\n"):
        line = line.expandtabs(4).rstrip()
        m = SECTION_RE.match(line)
        if m and not re.match(r"^[eBGDAE]\|", line):
            name = m.group(1).strip().title().replace("Prechorus", "Pre-Chorus")
            if m.group(2):
                name += " " + m.group(2).upper() if m.group(2).isalpha() and len(m.group(2)) > 1 \
                    else " " + m.group(2)
            if m.group(3):
                name += f" ({m.group(3).strip()})"
            if m.group(4):
                name += " " + m.group(4).replace(" ", "")
            line = f"[{name}]"
        out.append(line)
    body = "\n".join(out)
    body = re.sub(r"\n{3,}", "\n\n", body).strip("\n") + "\n"
    return body


def squash_tuning(s):
    if not s:
        return None
    s = s.strip()
    if " " in s:
        s = s.replace(" ", "")
    return s or None


def safe_name(s):
    return re.sub(r"[/:\\]", "-", s).strip()


def write_tab(meta, body, out_dir, dry_run):
    order = ["title", "artist", "version", "tuning", "capo", "bpm", "scroll", "source"]
    head = ["---"] + [f"{k}: {meta[k]}" for k in order if meta.get(k) not in (None, "")] + ["---"]
    content = "\n".join(head) + "\n" + body
    base = f"{safe_name(meta['artist'])} - {safe_name(meta['title'])}"
    path = os.path.join(out_dir, base + ".tab")
    if os.path.exists(path) and not dry_run:
        # Same song again: keep it as another version the app groups under one row.
        if meta.get("version"):
            path = os.path.join(out_dir, f"{base} ({safe_name(meta['version'])}).tab")
        if os.path.exists(path):
            die(f"{path} exists — delete it or pass --version to label this one")
    if dry_run:
        print(content)
        print(f"\n# dry run — would write {path}", file=sys.stderr)
        return path
    os.makedirs(out_dir, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(path)
    return path


def apply_overrides(meta, args):
    for k in ("title", "artist", "version", "tuning", "capo", "bpm", "scroll"):
        v = getattr(args, k, None)
        if v is not None:
            meta[k] = v
    meta.setdefault("scroll", "0.6")
    if not meta.get("title") or not meta.get("artist"):
        die("need both --title and --artist (could not read them from the source)")
    return meta


# ---------------------------------------------------------------- ug

def ug_search(query, want_chords):
    url = "https://www.ultimate-guitar.com/search.php?" + urllib.parse.urlencode(
        {"search_type": "title", "value": query})
    data = js_store(fetch(url))
    want = "Chords" if want_chords else "Tabs"
    rows = [r for r in data.get("results", [])
            if r.get("tab_url", "").startswith("https://tabs.ultimate-guitar.com/")
            and r.get("type") == want]
    if not rows:
        die(f"no '{want}' results for {query!r} — try the other type or paste a URL")
    rows.sort(key=lambda r: (r.get("votes") or 0, r.get("rating") or 0), reverse=True)
    best = rows[0]
    print(f"# {len(rows)} {want} versions; taking {best['tab_url']} "
          f"({best.get('votes')} votes, {best.get('rating', 0):.2f})", file=sys.stderr)
    return best["tab_url"]


def cmd_ug(args):
    target = args.target
    if not re.match(r"https?://", target):
        target = ug_search(target, args.chords)
    data = js_store(fetch(target))
    tab, view = data["tab"], data["tab_view"]
    if tab.get("type") not in ("Tabs", "Chords", "Bass Tabs", "Ukulele Chords"):
        die(f"UG type {tab.get('type')!r} is a binary (Guitar Pro / Power Tab) — no text to take")
    content = (view.get("wiki_tab") or {}).get("content")
    if not content:
        die("page has no wiki_tab.content (paywalled or official tab)")
    meta_block = view.get("meta") or {}
    tuning = squash_tuning((meta_block.get("tuning") or {}).get("value")) or squash_tuning(tab.get("tuning"))
    capo = meta_block.get("capo") if meta_block.get("capo") not in (None, "") else tab.get("capo")
    tab_id = re.search(r"-(\d+)/?$", target)
    meta = {
        "title": tab.get("song_name"),
        "artist": tab.get("artist_name"),
        "version": f"UG {tab.get('type', '').lower()} {tab_id.group(1) if tab_id else tab.get('id', '')}".strip(),
        "tuning": tuning or "EADGBE",
        "capo": str(capo if capo not in (None, "") else 0),
        "source": target,
    }
    meta = apply_overrides(meta, args)
    write_tab(meta, clean_body(content), args.out, args.dry_run)


# ---------------------------------------------------------------- pdf / scan

def guess_title_artist(lines):
    """Plain-text heuristics: 'Artist - Title', 'Title by Artist', or the first two lines."""
    head = [l.strip() for l in lines[:8] if l.strip()]
    for l in head[:3]:
        m = re.match(r"^(.+?)\s+[-–—]\s+(.+)$", l)
        if m:
            return m.group(2), m.group(1)
        m = re.match(r"^(.+?)\s+by\s+(.+)$", l, re.IGNORECASE)
        if m:
            return m.group(1), m.group(2)
    if len(head) >= 2 and not re.match(r"^[eBGDAE]\|", head[1]):
        return head[0], head[1]
    return (head[0] if head else None), None


def strip_title_lines(body, title, artist):
    """Drop the heading lines we lifted into the frontmatter so they are not shown twice."""
    lines = body.split("\n")
    drop = {s.lower() for s in (title, artist) if s}
    meta_line = re.compile(r"^\s*(capo|tuning|key|tempo|bpm|standard tuning)\b.{0,40}$", re.IGNORECASE)
    i = 0
    while i < len(lines) and i < 6:
        t = lines[i].strip().lower()
        if not t or t in drop or any(d in t for d in drop if len(d) > 3) and len(t) < 80:
            i += 1
        else:
            break
    kept = [l for n, l in enumerate(lines[i:]) if not (n < 10 and meta_line.match(l))]
    return "\n".join(kept).lstrip("\n")


def text_to_tab(text, source, args):
    lines = text.split("\n")
    title, artist = guess_title_artist(lines)
    meta = {"title": title, "artist": artist, "version": os.path.splitext(os.path.basename(source))[0], "tuning": "EADGBE", "capo": "0", "source": source}
    cm = re.search(r"capo[:\s]*(?:on\s*)?(\d+)", text, re.IGNORECASE)
    if cm:
        meta["capo"] = cm.group(1)
    tm = re.search(r"tuning[:\s]*([A-Ga-g#b ]{6,17})\b", text)
    if tm:
        meta["tuning"] = squash_tuning(tm.group(1)) or "EADGBE"
    meta = apply_overrides(meta, args)
    body = strip_title_lines(clean_body(text), meta["title"], meta["artist"])
    write_tab(meta, body, args.out, args.dry_run)


def cmd_pdf(args):
    path = os.path.abspath(args.file)
    if not os.path.exists(path):
        die(f"{path} not found")
    text = subprocess.run(["pdftotext", "-layout", path, "-"], check=True,
                          capture_output=True, text=True).stdout
    if len(text.strip()) < 40:
        die("pdftotext found almost no text — it is probably a scan; use `scan` instead")
    text_to_tab(text, path, args)


def ocr_page_as_columns(img):
    """tesseract's text output trims each line's leading spaces, which is exactly what puts a
    chord over the right syllable. Use the TSV word boxes instead: estimate the monospace
    character width from the words, then place each word at round(left / char_width)."""
    r = subprocess.run(["tesseract", img, "-", "--psm", "4", "-c", "preserve_interword_spaces=1", "tsv"],
                       check=True, capture_output=True, text=True)
    rows = [l.split("\t") for l in r.stdout.splitlines()[1:]]
    words = [(int(c[2]), int(c[3]), int(c[4]), int(c[6]), int(c[7]), int(c[8]), c[11])
             for c in rows if len(c) == 12 and c[0] == "5" and c[11].strip()]
    if not words:
        return ""
    widths = sorted(w / len(t) for (_, _, _, l, tp, w, t) in words if len(t) >= 3)
    cw = widths[len(widths) // 2] if widths else 12.0
    lines = {}
    for blk, par, ln, left, top, w, t in words:
        lines.setdefault((blk, par, ln), {"top": top, "words": []})
        lines[(blk, par, ln)]["words"].append((left, t))
    ordered = sorted(lines.values(), key=lambda d: d["top"])
    heights = [b["top"] - a["top"] for a, b in zip(ordered, ordered[1:]) if b["top"] > a["top"]]
    lh = sorted(heights)[len(heights) // 2] if heights else cw * 2
    margin = min(left for d in ordered for left, _ in d["words"])
    out, prev_top = [], None
    for d in ordered:
        if prev_top is not None:
            gap = round((d["top"] - prev_top) / lh) - 1
            out.extend([""] * max(0, min(gap, 3)))
        line = ""
        for left, t in sorted(d["words"]):
            col = max(len(line) + (1 if line else 0), round((left - margin) / cw))
            line = line.ljust(col) + t
        out.append(line)
        prev_top = d["top"]
    return "\n".join(out) + "\n"


def cmd_scan(args):
    path = os.path.abspath(args.file)
    if not os.path.exists(path):
        die(f"{path} not found")
    with tempfile.TemporaryDirectory() as tmp:
        if path.lower().endswith(".pdf"):
            subprocess.run(["pdftoppm", "-r", "300", "-gray", "-png", path,
                            os.path.join(tmp, "p")], check=True)
            images = sorted(os.path.join(tmp, f) for f in os.listdir(tmp) if f.endswith(".png"))
        else:
            images = [path]
        pages = [ocr_page_as_columns(img) for img in images]
    text = "\n".join(pages)
    print("# OCR output is lossy on tab (dashes merge, 0/O and 1/l swap) — read the result "
          "against the original before playing it", file=sys.stderr)
    text_to_tab(text, path, args)


# ---------------------------------------------------------------- main

def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    def common(sp):
        sp.add_argument("--title")
        sp.add_argument("--artist")
        sp.add_argument("--version", help="label for this arrangement, e.g. \"capo 2\" or \"live\"")
        sp.add_argument("--tuning")
        sp.add_argument("--capo")
        sp.add_argument("--bpm")
        sp.add_argument("--scroll")
        sp.add_argument("--out", default=TABS_DIR)
        sp.add_argument("--dry-run", action="store_true")

    s = sub.add_parser("ug", help="Ultimate Guitar URL or 'artist - title' search")
    s.add_argument("target")
    s.add_argument("--chords", action="store_true", help="prefer the Chords page over Tabs")
    common(s)
    s.set_defaults(fn=cmd_ug)

    s = sub.add_parser("pdf", help="text PDF")
    s.add_argument("file")
    common(s)
    s.set_defaults(fn=cmd_pdf)

    s = sub.add_parser("scan", help="scanned PDF or image, via tesseract")
    s.add_argument("file")
    common(s)
    s.set_defaults(fn=cmd_scan)

    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
