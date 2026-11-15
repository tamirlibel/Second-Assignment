"""Stage A extractor for the CC-NEWS pilot.

Streams one local CC-NEWS WARC file, samples response records at a fixed rate,
extracts article text with trafilatura and writes the sampled records to
Parquet in bounded batches. Every sampled record is kept, including failures,
so that extraction losses stay visible. A JSON summary is written last and
marks the file as complete.

Sampling is deterministic: a record is sampled when a hash of
(seed, WARC-Record-ID) falls below the sample rate, so re-running the same
file with the same seed gives the same sample.

Usage:
    uv run --project python python python/extract_ccnews.py \
        --warc data/warc/CC-NEWS-....warc.gz \
        --warc-path crawl-data/CC-NEWS/2026/09/CC-NEWS-....warc.gz \
        --out-dir data/stage_a --sample-rate 0.05 --seed ccnews-pilot-v1
"""

import argparse
import hashlib
import json
import logging
import os
import platform
import shutil
import sys
import time
from collections import Counter
from importlib.metadata import version as pkg_version
from datetime import datetime, timezone
from urllib.parse import urlsplit

import pyarrow as pa
import pyarrow.parquet as pq
import trafilatura
from warcio.archiveiterator import ArchiveIterator

HTML_TYPES = ("text/html", "application/xhtml+xml")

SCHEMA = pa.schema([
    ("warc_path", pa.string()),
    ("warc_record_id", pa.string()),
    ("crawl_date", pa.string()),
    ("target_uri", pa.string()),
    ("url_host", pa.string()),
    ("http_status", pa.string()),
    ("content_type", pa.string()),
    ("content_bytes", pa.int64()),
    ("warc_truncated", pa.string()),
    ("extract_status", pa.string()),
    ("extract_error", pa.string()),
    ("title", pa.string()),
    ("author", pa.string()),
    ("pub_date", pa.string()),
    ("tf_hostname", pa.string()),
    ("sitename", pa.string()),
    ("tf_language", pa.string()),
    ("text", pa.string()),
    ("text_chars", pa.int64()),
])


def is_sampled(record_id, seed, rate):
    """Deterministic Bernoulli sampling on the WARC record ID."""
    digest = hashlib.sha256(f"{seed}|{record_id}".encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big") / 2**64 < rate


def url_host(uri):
    try:
        host = urlsplit(uri).hostname or ""
    except ValueError:
        return None
    return host[4:] if host.startswith("www.") else host


def extract_record(rec, body):
    """Run trafilatura; return (status, error, fields)."""
    try:
        js = trafilatura.extract(body, url=rec["target_uri"], output_format="json",
                                 with_metadata=True)
    except Exception as e:  # trafilatura can fail on malformed HTML
        return "extract_error", f"{type(e).__name__}: {e}"[:500], {}
    if not js:
        return "no_extraction", None, {}
    doc = json.loads(js)
    text = doc.get("text") or None
    if not text or not text.strip():
        return "empty_text", None, {}
    fields = {
        "title": doc.get("title"),
        "author": doc.get("author"),
        "pub_date": doc.get("date"),
        "tf_hostname": doc.get("hostname"),
        "sitename": doc.get("source-hostname"),
        "tf_language": doc.get("language"),
        "text": text,
        "text_chars": len(text),
    }
    return "ok", None, fields


def flush(rows, part_dir, part_no):
    table = pa.Table.from_pylist(rows, schema=SCHEMA)
    pq.write_table(table, os.path.join(part_dir, f"part-{part_no:05d}.parquet"),
                   compression="zstd")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--warc", required=True, help="local WARC file")
    ap.add_argument("--warc-path", required=True,
                    help="path of the WARC in the CC-NEWS manifest (provenance)")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--sample-rate", type=float, default=0.05)
    ap.add_argument("--seed", default="ccnews-pilot-v1")
    ap.add_argument("--batch-size", type=int, default=1000)
    ap.add_argument("--expected-bytes", type=int, default=None,
                    help="Content-Length reported by the server; a mismatch aborts")
    ap.add_argument("--max-records", type=int, default=None,
                    help="stop after this many WARC records (testing only)")
    args = ap.parse_args()

    logging.getLogger("trafilatura").setLevel(logging.ERROR)
    logging.getLogger("htmldate").setLevel(logging.ERROR)

    # warcio stops silently at the end of a cut-off file, so check the size first
    file_bytes = os.path.getsize(args.warc)
    if args.expected_bytes is not None and file_bytes != args.expected_bytes:
        sys.exit(f"Size mismatch for {args.warc}: {file_bytes} bytes on disk, "
                 f"{args.expected_bytes} expected. Download again.")

    stem = os.path.basename(args.warc_path).replace(".warc.gz", "")
    part_dir = os.path.join(args.out_dir, "records", stem)
    summary_dir = os.path.join(args.out_dir, "summaries")
    summary_file = os.path.join(summary_dir, f"{stem}.json")

    # A rerun replaces any partial output from an earlier, interrupted run
    if os.path.isdir(part_dir):
        shutil.rmtree(part_dir)
    os.makedirs(part_dir)
    os.makedirs(summary_dir, exist_ok=True)

    n_records = n_response = n_sampled = 0
    http_counts, mime_counts, sampled_status = Counter(), Counter(), Counter()
    rows, part_no = [], 0
    stream_error = None
    started = time.time()

    with open(args.warc, "rb") as f:
        try:
            for rec in ArchiveIterator(f):
                n_records += 1
                if args.max_records and n_records > args.max_records:
                    break
                if rec.rec_type != "response":
                    continue
                n_response += 1

                status = rec.http_headers.get_statuscode() if rec.http_headers else None
                ctype = rec.http_headers.get_header("Content-Type") if rec.http_headers else None
                mime = (ctype or "").split(";")[0].strip().lower() or None
                http_counts[status or "none"] += 1
                mime_counts[mime or "none"] += 1

                record_id = rec.rec_headers.get_header("WARC-Record-ID")
                if not is_sampled(record_id, args.seed, args.sample_rate):
                    continue
                n_sampled += 1

                row = dict.fromkeys(SCHEMA.names)
                uri = rec.rec_headers.get_header("WARC-Target-URI")
                row.update({
                    "warc_path": args.warc_path,
                    "warc_record_id": record_id,
                    "crawl_date": rec.rec_headers.get_header("WARC-Date"),
                    "target_uri": uri,
                    "url_host": url_host(uri) if uri else None,
                    "http_status": status,
                    "content_type": mime,
                    "warc_truncated": rec.rec_headers.get_header("WARC-Truncated"),
                })

                if status != "200":
                    row["extract_status"] = "http_non200"
                elif mime not in HTML_TYPES:
                    row["extract_status"] = "not_html"
                else:
                    body = rec.content_stream().read()
                    row["content_bytes"] = len(body)
                    st, err, fields = extract_record(row, body)
                    row["extract_status"], row["extract_error"] = st, err
                    row.update(fields)

                sampled_status[row["extract_status"]] += 1
                rows.append(row)
                if len(rows) >= args.batch_size:
                    flush(rows, part_dir, part_no)
                    rows, part_no = [], part_no + 1
        except Exception as e:  # e.g. a truncated or corrupt gzip member
            stream_error = f"{type(e).__name__}: {e}"[:500]

    if rows:
        flush(rows, part_dir, part_no)
        part_no += 1

    summary = {
        "warc_path": args.warc_path,
        "completed": stream_error is None,
        "stream_error": stream_error,
        "file_bytes": file_bytes,
        "expected_bytes": args.expected_bytes,
        "max_records": args.max_records,
        "n_records": n_records,
        "n_response": n_response,
        "n_sampled": n_sampled,
        "n_parts": part_no,
        "sampled_status": dict(sampled_status),
        "http_status_all": dict(http_counts),
        "mime_all": dict(mime_counts.most_common(20)),
        "sample_rate": args.sample_rate,
        "seed": args.seed,
        "seconds": round(time.time() - started, 1),
        "finished_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "versions": {
            "python": platform.python_version(),
            "warcio": pkg_version("warcio"),
            "trafilatura": trafilatura.__version__,
            "pyarrow": pa.__version__,
        },
    }
    tmp = summary_file + ".tmp"
    with open(tmp, "w", encoding="utf-8") as out:
        json.dump(summary, out, indent=2)
    os.replace(tmp, summary_file)

    print(json.dumps({k: summary[k] for k in
                      ("warc_path", "completed", "n_response", "n_sampled",
                       "sampled_status", "seconds")}))
    return 0 if stream_error is None else 2


if __name__ == "__main__":
    sys.exit(main())
