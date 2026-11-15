"""Split coder item files into batches for LLM (subagent) coders.

For each batch it writes:
  <out>/batches/<batch_id>.md          articles to read (what the coder sees)
  <out>/batches/<batch_id>_items.json  the same items, used by check_batch.py

Usage:
  python annotation/agent/make_batches.py --annot-dir data/stage_a/annotation \
      --coders C1 C2 C3 C4 --batch-size 25
"""
import argparse
import csv
import json
import os
import sys
import textwrap

MAX_CHARS = 15000  # longer pages are cut, with a visible marker

csv.field_size_limit(sys.maxsize)


def read_items(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def display_text(text):
    """Cap very long pages and wrap long lines at word boundaries.

    Wrapping only changes whitespace; check_batch.py compares evidence after
    collapsing whitespace, so verbatim copying still works."""
    text = text or ""
    cut = len(text) - MAX_CHARS
    if cut > 0:
        text = text[:MAX_CHARS] + f"\n[TRUNCATED: {cut} more characters not shown]"
    out = []
    for para in text.split("\n"):
        out.extend(textwrap.wrap(para, width=400, break_long_words=False,
                                 break_on_hyphens=False) or [""])
    return "\n".join(out)


def write_batch(out_dir, batch_id, coder, items):
    lines = [f"# Batch {batch_id} (coder {coder}): {len(items)} articles", ""]
    for it in items:
        lines += [f"=== ARTICLE {it['annotation_id']} ===",
                  f"Title: {it.get('title') or ''}",
                  f"Published: {it.get('pub_date') or ''}",
                  f"Source: {it.get('url_host') or ''}",
                  "Text:", display_text(it.get("text")), ""]
    with open(os.path.join(out_dir, f"{batch_id}.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    keep = ("annotation_id", "title", "pub_date", "url_host", "text")
    with open(os.path.join(out_dir, f"{batch_id}_items.json"), "w", encoding="utf-8") as f:
        json.dump({"batch_id": batch_id, "coder": coder,
                   "items": [{**{k: it.get(k) for k in keep},
                              "text": (it.get("text") or "")[:MAX_CHARS]} for it in items]}, f, ensure_ascii=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--annot-dir", default="data/stage_a/annotation")
    ap.add_argument("--coders", nargs="+", default=["C1", "C2", "C3", "C4"])
    ap.add_argument("--batch-size", type=int, default=25)
    args = ap.parse_args()

    out_dir = os.path.join(args.annot_dir, "agent", "batches")
    os.makedirs(out_dir, exist_ok=True)
    manifest = []

    calib = read_items(os.path.join(args.annot_dir, "calibration_items_v1.csv"))
    for cd in args.coders:
        bid = f"{cd}_calib"
        write_batch(out_dir, bid, cd, calib)
        manifest.append({"batch_id": bid, "coder": cd, "round": "calibration", "n": len(calib)})

    for cd in args.coders:
        items = read_items(os.path.join(args.annot_dir, "assigned", f"items_{cd}_v1.csv"))
        items.sort(key=lambda r: r["annotation_id"])
        for b, start in enumerate(range(0, len(items), args.batch_size), 1):
            bid = f"{cd}_b{b:02d}"
            chunk = items[start:start + args.batch_size]
            write_batch(out_dir, bid, cd, chunk)
            manifest.append({"batch_id": bid, "coder": cd, "round": "main", "n": len(chunk)})

    with open(os.path.join(args.annot_dir, "agent", "batch_manifest.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["batch_id", "coder", "round", "n"])
        w.writeheader()
        w.writerows(manifest)
    print(f"{len(manifest)} batches written to {out_dir}")


if __name__ == "__main__":
    main()
