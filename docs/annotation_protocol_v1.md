# Annotation protocol v1: PLOVER event mentions in CC-NEWS

**Status:** draft for the Stage A pilot (September 2026 sample). Revise after the calibration round, and record every change in the change log at the end.

## 1. Purpose

Human coders produce a **gold standard** of political events in the pilot articles. The gold standard is used to:

1. estimate how many CC-NEWS articles contain codable political events (probability sample);
2. evaluate NGEC-2025, and any LLM-based coder, on event detection, event type, mode, actors, recipients, location and date (both samples);
3. measure the recall of the relevance screen built later. This works because the probability sample was drawn before any screen.

Coders work **blind**: they never see model output, which sample an article comes from, or the keyword flag. The gold standard must stay independent of every system it is used to evaluate.

## 2. Reference codebook

- **PLOVER manual,** `PLOVER_MANUAL.tex`/`.pdf` in [openeventdata/PLOVER](https://github.com/openeventdata/PLOVER), pinned to commit `5e0c24fba623f2d8df5ae3c7de7a94dba90d5b6f`. The file calls itself "DRAFT Version 2.0" and the README calls it "Version 0.8 draft", so cite it by commit.
- The repository README still says 18 event types. The manual and POLECAT use **16**, and this protocol follows the manual.
- Machine-readable extracts used by the validator are in `annotation/codebook/`: event types and modes, sectors, status values and article types.
- **Background reading:** Halterman et al. (2023), *PLOVER and POLECAT* (ISA working paper), pp. 5–16; Halterman et al. (2023), *Creating Custom Event Data Without Dictionaries*, arXiv:2304.01331, §§2.1–2.6.

Where this protocol and the manual disagree, this protocol wins **for this project**, and the difference is listed in §10.

## 3. Units of annotation

| Unit | Definition | Sheet |
|---|---|---|
| **Article** | One canonical article (`annotation_id`) | `articles` |
| **Event mention** | One reported occurrence of one PLOVER event type with one combination of actors, recipients, location and date | `mentions` |

### When to create a new mention

- **The same event in several sentences is one mention.** "Obama and Macron met on Tuesday … During the meeting, the two leaders…" is one CONSULT. Use the most specific details from anywhere in the article. For example, the location is "Aybak" from paragraph 2, not "northern Afghanistan" from the lead.
- **Create a separate mention** when the event type differs, or when the actor set, recipient set, location or date differs. Three attacks on the same day in three towns are three ASSAULT mentions.
- **Several modes of one event go in one mention.** A demonstration that also blocks roads is one PROTEST mention with `modes = demo;obstruct`.
- **Multi-party events are not split into pairs.** A four-country summit is one CONSULT with four actors. *(Manual; POLECAT p. 9)*
- **Code the whole article,** not only the lead. The evidence sentence (§5) records where each mention is, so lead-only and full-text coding can be compared later.

## 4. The articles sheet

One row per article per coder. All fields are required unless marked otherwise.

| Field | Values | Rule |
|---|---|---|
| `annotation_id` | from the item file | |
| `coder` | your coder ID | |
| `article_type` | see `article_type_values_v1.csv` | Classify the item as a whole |
| `political_relevant` | `yes` / `no` | `yes` if the article is mainly about politics, government, international relations, conflict, protest, security or repression, **even if it contains no codable event**. This is the target for the relevance screen. |
| `extraction_problem` | `none` / `partial` / `boilerplate` / `wrong_language` / `unreadable` | Problems with the extracted text itself |
| `minutes` | number | Time spent on this article, for cost estimates |
| `notes` | free text, optional | |

An article with **no codable event** has a row in `articles` and no rows in `mentions`.

## 5. The mentions sheet

One row per event mention per coder.

| Field | Rule |
|---|---|
| `mention_no` | 1, 2, 3 … within the article |
| `event_type` | One of the 16 PLOVER types (§6) |
| `modes` | Zero or more modes **valid for that type**, separated by `;`. Leave empty when none applies or the type has no modes (AGREE, SUPPORT, CONCEDE, COOPERATE, AID). |
| `status` | `occurred`, `alleged`, `future`, `hypothetical`, `negated` or `historical` (§7) |
| `actor_text` | The actor(s) as written in the text, separated by `;`. Use the most specific mention (a name over "officials"). |
| `actor_country` | ISO 3166-1 alpha-3 code for each actor, separated by `;`, in the same order. Use `INT` for international organisations and NGOs, and `UNK` if unknown. |
| `actor_sector` | Sector code(s) for each actor, separated by `;`. Join several sectors for one actor with `+`, primary sector first (e.g. `PTY+OPP`). Use `UNK` if unclear. |
| `recipient_text`, `recipient_country`, `recipient_sector` | Same format as the actor fields. Leave empty if there is no recipient. Required for COOPERATE, AID and SANCTION. |
| `location_text` | Where the event happened, as written. Leave empty if not stated. **Do not use the dateline city** unless the text says the event happened there. *(POLECAT p. 12)* |
| `location_country` | ISO3 code of the event location. Leave empty if unknown. |
| `date_text` | The date expression as written ("on Tuesday", "last week"). Leave empty if none. |
| `event_date` | Resolved against the article's publication date. Format follows `date_precision`: `YYYY-MM-DD` for `day` and `week` (for `week`, use the first day), `YYYY-MM` for `month`, `YYYY` for `year`, empty for `none`. |
| `date_precision` | `day`, `week`, `month`, `year` or `none` (no date expression in the text) |
| `evidence` | The **one sentence** that best reports the event, copied verbatim from the item text. It is used to locate the mention, so copy it exactly. |
| `crime_only` | `yes` if every actor and recipient is a private individual or criminal and nothing political is involved (e.g. a robbery or a domestic homicide); otherwise `no`. POLECAT removes street crime, so this flag lets the evaluation do the same. |
| `confidence` | `1` = unsure, `2` = fairly sure, `3` = sure |
| `notes` | Optional. Required when confidence is `1` (say what is ambiguous). |

## 6. Event types: decision rules

Definitions are in `plover_event_modes_v1.csv` and, in full, in the manual. The rules below cover the cases coders most often disagree on.

- **Statements are events.** A speech act is coded as the speaker's action: a minister's criticism is ACCUSE-disapprove, an appeal is REQUEST, an endorsement is SUPPORT. Code the speech act, not its subject, unless the subject is itself reported as an event (§7).
- **Future cooperation becomes AGREE.** Promises of future CONSULT, SUPPORT, COOPERATE or AID are coded AGREE, with status `occurred`, because the promise is the event. An announced future withdrawal is CONCEDE, not RETREAT. *(Manual)*
- **Refusals are REJECT,** not negation. "Will not sign the treaty" is REJECT with status `occurred`. *(Bag-of-Tricks §2.2.2)*
- **Protests.** The demand behind a protest is not coded as a separate REQUEST. Events that triggered the protest are coded as their own mentions if reported. *(Manual)*
- **MOBILIZE.** Code it only when deployment, mobilisation or a move of forces is **explicitly reported**. Do not infer it, for example from police being present at a protest. NGEC may infer it (Bag-of-Tricks §2.1), so this is a known difference to check in the evaluation (§10).
- **CONSULT actors.** If host and visitor are clear, the visitor is the actor and the host the recipient. Otherwise all participants are actors and there is no recipient. *(Manual)*
- **ASSAULT actors.** In two-sided fighting, all sides are actors. In one-sided violence, the perpetrator is the actor and the victim the recipient. *(Manual)*
- **Unknown perpetrators.** Use `UAF` for "unknown gunmen" and `UNK` for wholly unidentified actors. Do not leave the actor empty if an attack is reported.
- **Not events:** forecasts by analysts, polls, general descriptions of situations ("tensions remain high"), statistics without a specific action, and sports or business news without a political actor or action.

## 7. Status: decision rules

PLOVER defines historical, future, hypothetical and negated markers, but the manual says they "have not yet been fully implemented". This protocol records status for every mention, so the evaluation can include or exclude each group explicitly.

| Status | Use when | Example |
|---|---|---|
| `occurred` | The article reports the event as having happened, including through attribution ("police said") | "Troops shelled the village on Monday, officials said." |
| `alleged` | The event is only an accusation by someone else and the article does not confirm it. **The accusation is a separate ACCUSE-allege mention with status `occurred`.** | "Kyiv accused Moscow of shelling a hospital" gives two mentions: ACCUSE-allege (occurred) and ASSAULT (alleged) |
| `future` | Announced, planned or scheduled but not yet happened, *except* where §6 recodes it (AGREE, CONCEDE) | "Unions will strike next week" is PROTEST-strike (future) |
| `hypothetical` | Conditional or possible | "Sanctions could follow if…" is SANCTION (hypothetical) |
| `negated` | Explicitly did not happen | "No shots were fired" is ASSAULT (negated) |
| `historical` | Happened more than 30 days before the article's publication date | Background on a 2014 war |

## 8. Procedure

1. **Training.** Read §§2–3 of the PLOVER manual and this protocol. Code the 5 worked examples in §11 and compare your answers with the key.
2. **Calibration.** All coders independently code the calibration set (`calibration_items_v1.csv`). These articles are drawn from outside both evaluation samples and are never used in the evaluation. Disagreements are discussed and the protocol is revised (v1.1, …) **before** the main round.
3. **Main round.** Code your assigned file in the given (random) order. Do not discuss individual articles with other coders until adjudication.
   - There are four coders (C1–C4). Each double-coded article goes to a pair of coders chosen to balance workload, so all six coder pairs share articles.
   - Every probability-sample article is coded by two coders.
   - 30% of enriched-sample articles are coded by two coders; the rest by one.
4. **Validation.** Run `R/04_validate_annotations.R` on your sheets and fix every error it reports before submitting.
5. **Calibration meetings** every two weeks during the main round, to raise general questions, not individual articles (as in POLECAT, p. 14). Every rule clarification is added to the change log.
6. **Adjudication.** The PI resolves double-coded disagreements. Both original codings are kept, and the adjudicated version becomes the gold standard.

## 9. Reliability and evaluation metrics

The same matching rules are used for coder-vs-coder reliability and for system-vs-gold evaluation.

- **Article level:** Krippendorff's alpha for `political_relevant`, `article_type` and "has at least one event".
- **Mention matching:** two mentions in the same article match if they have the same `event_type`, and either (a) their evidence sentences overlap, or (b) their actor sets share at least one normalised entity, with dates no more than one day apart when both are given. One-to-one matches are found with the Hungarian algorithm.
- **Mention detection:** precision, recall and F1 of matched mentions.
- **Attributes,** on matched mentions only: agreement on mode, status, actor, recipient, location country and event date (given the precision).
- **Complete-record accuracy:** the share of mentions with type, actor, recipient, location and date all correct. This is the strictest measure and the one closest to how event data are used.
- **Default evaluation subset:** `status = occurred`, `crime_only = no`. Report the other statuses separately.

## 10. Known differences from POLECAT/NGEC

These differences are deliberate. The evaluation must report them rather than count them as coder or model error.

| Topic | This protocol | POLECAT/NGEC |
|---|---|---|
| MOBILIZE | Explicit mentions only | May be inferred from context |
| Text coded | Full article | First 512 word pieces (~1,024 characters in the original implementation) |
| Status | Recorded for every mention | Negated sentences removed; other markers not implemented |
| Crime | Coded and flagged (`crime_only`) | Crime stories filtered out |
| Domestic US events | Coded | Purely domestic US events excluded from POLECAT |
| Contexts | Not coded in v1 | Story-level classifier, 37 contexts |

**Contexts are left out of v1** to keep the first round manageable. If NGEC's context output is to be evaluated, add a context pass in v2.

## 11. Worked examples

1. *"President Obama and Emmanuel Macron met Tuesday in Paris to discuss the ongoing war in Syria. The meeting follows a chemical weapons attack last week against Syrian civilians in Aleppo carried out by the Damascus regime."* (published 2015-04-01)
   - CONSULT, occurred; actors `Obama; Macron` (`USA; FRA`, `GOV; GOV`); no recipient; location Paris (FRA); date "Tuesday", resolved to the Tuesday before publication, precision `day`.
   - ASSAULT-unconventional, occurred; actor `Damascus regime` (SYR, GOV); recipient `Syrian civilians` (SYR, CVL); location Aleppo (SYR); "last week", precision `week`.
2. *"The opposition accused the government of rigging Sunday's vote."* ACCUSE-allege (occurred), actor opposition (OPP), recipient government (GOV). Also code the alleged act if it has a PLOVER type. Election rigging has none, so there is only one mention.
3. *"Police dispersed hundreds of protesters with tear gas in Nairobi on Friday."* Two mentions:
   - PROTEST-demo (occurred), actor protesters (KEN, CVL);
   - ASSAULT-crowd-control (occurred), actor police (KEN, COP), recipient protesters (KEN, CVL).

   No MOBILIZE, because deployment is not explicit.
4. *"The minister said the country would not join the alliance."* REJECT (occurred), actor minister (GOV), recipient the alliance (INT).
5. *"Two men shot dead a shopkeeper during a robbery in Leeds on Saturday."* ASSAULT-firearms (occurred), actor two men (GBR, CRM), recipient shopkeeper (GBR, CVL), `crime_only = yes`. A robbery with no physical harm is not an event.

The answers above are provisional. They are confirmed or revised at the first calibration meeting.

## Change log

| Version | Date | Change |
|---|---|---|
| v1 | 2026-11-15 | First draft for the pilot |
