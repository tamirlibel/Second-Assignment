# Calibration round v1: LLM subagent coders

Four Claude subagent coders (C1–C4) each coded the same 30 calibration articles under protocol v1. Calibration articles are drawn from outside both evaluation samples. These are **silver** annotations (protocol §9a): agreement among them measures one model's self-consistency, not human inter-coder reliability.

All four batches passed the codebook checker and the R validator. The coders found 25–30 event mentions each, 110 in total.

## Agreement (`R/06_agreement.R`)

| Measure | Value |
|---|---|
| Krippendorff's α, `political_relevant` | 1.00 (20% of articles relevant) |
| α, has at least one codable event (occurred, not crime-only) | 0.92 (27% of articles) |
| α, `article_type` | 0.82 |
| Mention detection F1, all pairs, default subset | 0.91 (pairs range 0.87–0.95) |
| On matched mentions: mode / status / actor country / recipient country | 0.89 / 1.00 / 0.93 / 0.88 |
| On matched mentions: location country / event date | 0.71 / 0.87 |
| Complete-record agreement | 0.60 |

## Problems found and v1.1 changes

| Problem | Evidence | v1.1 rule |
|---|---|---|
| Location country inferred from actor nationality by some coders but not others | Weakest attribute (0.71) | `location_country` only with a named place; the checker enforces it |
| An event both alleged and older than 30 days | Raised by all 4 coders (K018) | Status precedence: negated > hypothetical > future > alleged > historical > occurred |
| Police investigating ordinary crime were not `crime_only` under the literal rule | Raised by 3 coders (K019) | `crime_only` covers police and courts handling ordinary crime |
| Agreeing to a demand: AGREE or CONCEDE | Coders split (K018) | Under pressure or after resisting = CONCEDE; cooperation = AGREE |
| Undated background events marked historical | K023 | `historical` needs a date or clear wording |
| Routine administration and domestic disaster response | K008, K027, K029 | Not events; cross-border aid is AID |
| No mode fits (strangulation) | K004 | Leave empty and add a note |

The figures above are from v1. The main round uses v1.1.
