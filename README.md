# CC-NEWS → PLOVER event data: Stage A pilot

This is a feasibility pilot. It asks whether Common Crawl's CC-NEWS archive can support reproducible, valid extraction of PLOVER-compatible political event records with existing open-source coders (NGEC-2025).

Stage A covers **corpus construction only**: selecting and streaming WARC files, extracting article text, measuring what is lost along the way, linking syndicated copies, and drawing the annotation samples. Event coding (NGEC-2025), human annotation and the benchmark come in later stages.

## Layout

| Path | Purpose |
|---|---|
| `python/extract_ccnews.py` | Reads one WARC as a stream, samples response records, extracts text with trafilatura, writes Parquet batches and a JSON summary |
| `python/pyproject.toml`, `python/uv.lock` | Pinned Python environment |
| `R/01_ingest.R` | Selects WARC files across the month, downloads them with size checks, runs the extractor, keeps a ledger |
| `R/02_articles.R` | Extraction diagnostics, language ID, publication-date checks, copy-to-canonical table, funnel, annotation samples |
| `renv.lock` | R package versions used for the pilot run |
| `results/stage_a_2026-09/` | Run diagnostics (no article text) |
| `data/` | Local only, not committed: WARC files, extracted text, annotation files |

## Setup

**Python** (3.11 or later, with [uv](https://docs.astral.sh/uv/)):

```
uv sync --project python
```

**R** (4.3 or later):

```r
install.packages(c("readr", "dplyr", "tidyr", "stringr", "curl", "jsonlite", "nanoparquet", "cld2", "digest"))
#or: renv::restore()
```

`nanoparquet` reads and writes the Parquet files without the heavier `arrow` dependency. `arrow::open_dataset()` reads the same files if you prefer it.

## Running

From the project root:

```
Rscript R/01_ingest.R
Rscript R/02_articles.R
```

Settings are at the top of each script: month, number of WARC files, sample rate, seed, publication-date window and sample sizes. `01_ingest.R` can be rerun safely. It skips WARC files whose summary says `completed: true` and redoes any file that was interrupted.

## Design decisions

- **WARC selection.** The script picks the file closest to each of 12 evenly spaced time points in the month. Selection is deterministic.
- **Sampling within a WARC.** A response record is sampled when `sha256(seed | WARC-Record-ID)` falls below the sample rate. This works like Bernoulli sampling, but rerunning with the same seed always gives the same sample.
- **No silent losses.** Every sampled record is kept with an `extract_status`: `ok`, `http_non200`, `not_html`, `no_extraction`, `empty_text` or `extract_error`. The summary also counts HTTP status and MIME type for *all* response records, sampled or not.
- **Integrity.** Each download is checked against the server's Content-Length, and the extractor checks it again. This matters because warcio stops silently at the end of a cut-off file. A summary is written only after all batches, and only then is the file marked complete.
- **Memory.** Records are written in batches of 1,000. Nothing passes through `reticulate`; R only reads the Parquet output.
- **Publication date.** CC-NEWS also captures old articles, so an article counts as "current" only if published between 1 day after and 7 days before the crawl date.
- **Copies.** Exact duplicates are found by hashing normalised text (`digest(..., serialize=FALSE)`). Every copy is kept in `article_copies_v1.parquet` and linked to a canonical article (the earliest crawl).
- **Annotation samples.** The *probability sample* is a simple random sample of canonical English articles, drawn **before** any relevance screen, so the screen's recall can be measured later. The *enriched sample* uses a crude political keyword flag, capped at 3 articles per domain. Coders get one shuffled file with no sample labels. The key is stored separately.

## Known limitations

- **Duplicate rates are understated.** With 5% sampling, two copies of the same story are rarely both sampled. Estimating syndication properly needs a full scan of some WARC files.
- **Near-duplicates are not handled.** Lightly edited wire copy needs MinHash/LSH, which is not implemented yet.
- **The keyword flag is not a relevance classifier.** It only enriches the second sample.
- **Language is identified with cld2 on the extracted text.** Mixed-language pages may be misclassified.
- **Copyright.** Article text and annotation files stay in `data/` and must not be committed or redistributed. Publish only structured records and diagnostics.
