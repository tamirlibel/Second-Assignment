"""Check one subagent coding batch (JSON) against the codebook.

Usage:
  python3 annotation/agent/check_batch.py --batch-id C1_calib

Reads   data/stage_a/annotation/agent/batches/<batch_id>_items.json
        data/stage_a/annotation/agent/out/<batch_id>.json
Prints every problem; exits 0 only when the batch is clean.

Output JSON format (one object per batch):
{
  "batch_id": "C1_calib", "coder": "C1",
  "articles": [
    {"annotation_id": "K001", "article_type": "news_report", "political_relevant": "no",
     "extraction_problem": "none", "notes": "",
     "mentions": [
       {"event_type": "CONSULT", "modes": ["visit"], "status": "occurred",
        "actors": [{"text": "Narendra Modi", "country": "IND", "sectors": ["GOV"]}],
        "recipients": [{"text": "Joe Biden", "country": "USA", "sectors": ["GOV"]}],
        "location_text": "Washington", "location_country": "USA",
        "date_text": "on Tuesday", "event_date": "2026-09-22", "date_precision": "day",
        "evidence": "<one sentence copied verbatim from the article>",
        "crime_only": "no", "confidence": 3, "notes": ""}
     ]}
  ]
}
"""
import argparse
import csv
import json
import os
import re
import sys

CB = "annotation/codebook"


def squish(s):
    return re.sub(r"\s+", " ", s or "").strip()


def load_codebook():
    with open(os.path.join(CB, "plover_event_modes_v1.csv"), encoding="utf-8") as f:
        ev = list(csv.DictReader(f))
    modes = {r["event_type"]: set(m for m in (r["modes"] or "").split(";") if m) for r in ev}
    rec_req = {r["event_type"] for r in ev if r["recipient_required"] == "yes"}

    def col(name, field):
        with open(os.path.join(CB, name), encoding="utf-8") as f:
            return {r[field] for r in csv.DictReader(f)}
    return (modes, rec_req, col("plover_sectors_v1.csv", "sector"),
            col("status_values_v1.csv", "status"), col("article_type_values_v1.csv", "article_type"))


DATE_RE = {"day": r"^\d{4}-\d{2}-\d{2}$", "week": r"^\d{4}-\d{2}-\d{2}$",
           "month": r"^\d{4}-\d{2}$", "year": r"^\d{4}$"}
EXTRACTION = {"none", "partial", "boilerplate", "wrong_language", "unreadable"}


def check_entities(ents, role, sectors, where, probs):
    if not isinstance(ents, list):
        probs.append(f"{where}: {role} must be a list")
        return
    for j, e in enumerate(ents, 1):
        w = f"{where} {role}[{j}]"
        if not isinstance(e, dict) or not squish(e.get("text")):
            probs.append(f"{w}: needs non-empty 'text'")
            continue
        c = e.get("country")
        if not (c in ("INT", "UNK") or (isinstance(c, str) and re.match(r"^[A-Z]{3}$", c))):
            probs.append(f"{w}: country must be an ISO3 code, INT or UNK (got {c!r})")
        secs = e.get("sectors")
        if not isinstance(secs, list) or not secs:
            probs.append(f"{w}: sectors must be a non-empty list (primary first)")
        else:
            bad = [s for s in secs if s not in sectors]
            if bad:
                probs.append(f"{w}: unknown sector code(s) {bad}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch-id", required=True)
    ap.add_argument("--agent-dir", default="data/stage_a/annotation/agent")
    args = ap.parse_args()

    modes, rec_req, sectors, statuses, art_types = load_codebook()
    with open(os.path.join(args.agent_dir, "batches", f"{args.batch_id}_items.json"), encoding="utf-8") as f:
        batch = json.load(f)
    texts = {it["annotation_id"]: squish(f"{it.get('title') or ''} {it.get('text') or ''}") for it in batch["items"]}

    out_path = os.path.join(args.agent_dir, "out", f"{args.batch_id}.json")
    try:
        with open(out_path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"Cannot read {out_path}: {e}")
        return 1

    probs = []
    if data.get("batch_id") != args.batch_id or data.get("coder") != batch["coder"]:
        probs.append(f"batch_id/coder must be {args.batch_id!r}/{batch['coder']!r}")
    arts = data.get("articles", [])
    ids = [a.get("annotation_id") for a in arts]
    missing = sorted(set(texts) - set(ids))
    extra = sorted(set(ids) - set(texts))
    dups = sorted({i for i in ids if ids.count(i) > 1})
    if missing:
        probs.append(f"articles missing: {missing}")
    if extra:
        probs.append(f"articles not in this batch: {extra}")
    if dups:
        probs.append(f"articles listed more than once: {dups}")

    n_mentions = 0
    for a in arts:
        aid = a.get("annotation_id")
        if a.get("article_type") not in art_types:
            probs.append(f"{aid}: article_type must be one of {sorted(art_types)}")
        if a.get("political_relevant") not in ("yes", "no"):
            probs.append(f"{aid}: political_relevant must be yes or no")
        if a.get("extraction_problem") not in EXTRACTION:
            probs.append(f"{aid}: extraction_problem must be one of {sorted(EXTRACTION)}")
        ments = a.get("mentions")
        if not isinstance(ments, list):
            probs.append(f"{aid}: mentions must be a list (empty if no codable event)")
            continue
        for k, m in enumerate(ments, 1):
            n_mentions += 1
            w = f"{aid} mention {k}"
            et = m.get("event_type")
            if et not in modes:
                probs.append(f"{w}: event_type must be one of the 16 PLOVER types (got {et!r})")
            md = m.get("modes", [])
            if not isinstance(md, list):
                probs.append(f"{w}: modes must be a list")
            elif et in modes:
                bad = [x for x in md if x not in modes[et]]
                if bad:
                    probs.append(f"{w}: mode(s) {bad} not valid for {et}; valid: {sorted(modes[et]) or 'none'}")
            if m.get("status") not in statuses:
                probs.append(f"{w}: status must be one of {sorted(statuses)}")
            check_entities(m.get("actors"), "actors", sectors, w, probs)
            if isinstance(m.get("actors"), list) and not m["actors"]:
                probs.append(f"{w}: actors must not be empty (use UNK/UAF sectors for unidentified actors)")
            check_entities(m.get("recipients", []), "recipients", sectors, w, probs)
            if et in rec_req and not m.get("recipients"):
                probs.append(f"{w}: {et} requires a recipient")
            lc = m.get("location_country")
            if lc not in (None, "") and not re.match(r"^[A-Z]{3}$", str(lc)):
                probs.append(f"{w}: location_country must be ISO3 or empty")
            prec, d = m.get("date_precision"), m.get("event_date")
            if prec == "none":
                if d not in (None, ""):
                    probs.append(f"{w}: event_date must be empty when date_precision is none")
            elif prec in DATE_RE:
                if not (isinstance(d, str) and re.match(DATE_RE[prec], d)):
                    probs.append(f"{w}: event_date {d!r} does not match precision {prec}")
            else:
                probs.append(f"{w}: date_precision must be day, week, month, year or none")
            ev = squish(m.get("evidence"))
            if not ev:
                probs.append(f"{w}: evidence missing")
            elif ev not in texts.get(aid, ""):
                probs.append(f"{w}: evidence not found verbatim in the article (copy one sentence exactly)")
            if m.get("crime_only") not in ("yes", "no"):
                probs.append(f"{w}: crime_only must be yes or no")
            if m.get("confidence") not in (1, 2, 3):
                probs.append(f"{w}: confidence must be 1, 2 or 3")
            if m.get("confidence") == 1 and not squish(m.get("notes")):
                probs.append(f"{w}: notes required when confidence is 1")

    if probs:
        print(f"{len(probs)} problem(s) in {args.batch_id}:")
        for p in probs:
            print(" -", p)
        return 1
    print(f"OK: {args.batch_id}: {len(arts)} articles, {n_mentions} mentions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
