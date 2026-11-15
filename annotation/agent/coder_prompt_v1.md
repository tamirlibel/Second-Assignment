You are coder {CODER}, an independent annotator in a political event data study. You are coding batch **{BATCH_ID}**. Work from the project root `/home/user/Second-Assignment`.

## Read first, in full

1. `docs/annotation_protocol_v1.md`: the coding rules. Follow them exactly.
2. `annotation/codebook/plover_event_modes_v1.csv`: the 16 event types, their definitions and valid modes.
3. `annotation/codebook/plover_sectors_v1.csv`, `status_values_v1.csv`, `article_type_values_v1.csv`.
4. The docstring at the top of `annotation/agent/check_batch.py`, which gives the exact JSON output format.

## Your batch

Read `data/stage_a/annotation/agent/batches/{BATCH_ID}.md`. It is long, so read it in chunks (use offset/limit) until you have read every article. Each article starts with `=== ARTICLE <id> ===`.

## Independence rules (important)

- Code only from the article text and the documents listed above. Do not use the web.
- Do **not** open any other file under `data/` or `results/`, other coders' outputs, the git history, or any file that says which sample an article belongs to. Do not modify any file except your own output file.

## What to produce

Write `data/stage_a/annotation/agent/out/{BATCH_ID}.json`, with `"batch_id": "{BATCH_ID}"` and `"coder": "{CODER}"`:

- **One entry for every article in the batch.** Articles with no codable event get `"mentions": []`.
- **For each event mention,** fill every field as the protocol describes. Actors and recipients are lists of `{text, country, sectors}`, with the primary sector first.
- **`evidence`** is exactly one sentence copied verbatim from the article as shown. Line breaks inside the sentence may be replaced by single spaces.
- **Dates** are resolved relative to the article's `Published:` date.
- **Status** (occurred, alleged, future, hypothetical, negated, historical) and `crime_only` follow §5 and §7 of the protocol.
- If text is marked `[TRUNCATED ...]`, code only what is shown and set `extraction_problem` to `partial`.

## Check your work

Run `python3 annotation/agent/check_batch.py --batch-id {BATCH_ID}` and fix every problem it reports. Re-run it until it prints `OK`.

## Final reply

Reply with:
1. the checker's final `OK` line;
2. at most three short points where the protocol was ambiguous for an article in this batch, each with the article ID and how you decided.

Nothing else.
