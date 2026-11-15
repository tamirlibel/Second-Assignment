# Stage A pilot results: CC-NEWS, September 2026

Run on 15 November 2026 with `R/01_ingest.R` and `R/02_articles.R` (seed `ccnews-pilot-v1`, 5% sampling). This folder holds diagnostics only. Article text, the canonical and copy tables, and the annotation files are in `data/stage_a/` locally and are not committed.

## Design

- 12 of the month's 374 WARC files, the closest to evenly spaced time points from 1 to 30 September (`selected_warc_v1.csv`)
- 5% of response records sampled within each file
- All 12 files completed and passed the size check. The run took 27 minutes, about 2.2 minutes per 1 GB file (`ledger_v1.csv`).

## Funnel (`funnel_v1.csv`)

| Step | n | Share of previous step |
|---|---|---|
| WARC response records (all) | 251,193 | |
| Sampled records | 12,491 | 5.0% |
| HTTP 200 + HTML | 12,442 | 99.6% |
| Text extracted | 12,314 | 99.0% |
| English (cld2) | 3,009 | 24.4% |
| English + current publication date | 2,156 | 71.7% |
| Unique English articles | 2,063 | 95.7% |

## Findings

1. **Extraction is not the bottleneck.** 99% of HTML records give text. Failures cluster in a few sites rather than spreading evenly (see `domain_diagnostics_v1.csv`), so they bias coverage more than the overall rate suggests.
2. **Only about a quarter of CC-NEWS is English.** Russian (21%) and Spanish (10%) are the next largest. An English-only pipeline, as NGEC-2025 currently is, sees a quarter of the archive.
3. **Many articles are old.** 24% of all sampled records were published more than 30 days before the crawl, and 28% of English records fail the 7-day window. Some sites are almost entirely old content (brighteon.com: 414 English records, none current). Without this filter, old stories would be coded as current events, which is the historical-events problem POLECAT discusses.
4. **Sources are concentrated, and English coverage leans to India.** The 10 largest domains account for 26% of sampled records, and for 25% of unique English articles (536 domains). 13 of the 25 largest English sources are Indian outlets. This resembles the India over-representation that the POLECAT paper reports for ICEWS (p. 11). Country-level analysis will need source weighting or a fixed source panel.
5. **Syndication is visible even at 5% sampling.** There are 61 groups of identical text, none of them recrawls of the same URL. 35 groups span several sites, mostly US public-radio stations sharing NPR copy (up to 5 stations per story). The true copy rate is higher, because both copies must be sampled to be seen.
6. **Not all of CC-NEWS is news.** Large sources include quran.com, tes.com (education) and sports sites. The relevance screen before event coding is needed.
7. **The keyword flag is too broad.** It marks 59% of unique English articles as political, so the enriched annotation sample is only weakly enriched. It should be replaced by a proper relevance classifier before annotation.

## Rough monthly scale

There are 374 files at about 20,900 responses each, or about 7.8 million records a month. About 16.5% of sampled records become unique, current English articles. That is roughly 1.3 million a month before any relevance screen, an order-of-magnitude estimate from 12 files. This number sets the throughput NGEC-2025 would need on the relevant subset.

## Files

| File | Content |
|---|---|
| `funnel_v1.csv` | Counts at each step |
| `domain_diagnostics_v1.csv` | Sampled, extracted, English and current-English counts per domain |
| `warc_summary_v1.csv` | Per-WARC record counts and timing |
| `warc_summaries/*.json` | Full extractor summaries, including HTTP status and MIME counts for all records and package versions |
| `selected_warc_v1.csv`, `ledger_v1.csv` | WARC selection and run log |
