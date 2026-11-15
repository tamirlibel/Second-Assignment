##CC-NEWS pilot: validating coded annotation sheets
##Coders save their sheets as data/stage_a/annotation/coded/articles_<coder>_v1.csv
##and mentions_<coder>_v1.csv. Run from the project root; fix every reported problem.

##Cleaning working environment
rm(list=ls())

##Setting working directory
#setwd("C:/...")   #only needed if not running from the project root

##Loading libraries
library(readr)
library(dplyr)
library(tidyr)
library(stringr)

####PART A: SETTINGS AND CODEBOOK####

annot_dir <- file.path("data", "stage_a", "annotation")
coded_dir <- file.path(annot_dir, "coded")
cb_dir <- file.path("annotation", "codebook")

cb_events <- read_csv(file.path(cb_dir, "plover_event_modes_v1.csv"), show_col_types=FALSE)
cb_sectors <- read_csv(file.path(cb_dir, "plover_sectors_v1.csv"), show_col_types=FALSE)$sector
cb_status <- read_csv(file.path(cb_dir, "status_values_v1.csv"), show_col_types=FALSE)$status
cb_types <- read_csv(file.path(cb_dir, "article_type_values_v1.csv"), show_col_types=FALSE)$article_type
cb_modes <- cb_events %>%
  mutate(mode=str_split(coalesce(modes, ""), ";")) %>% unnest(mode) %>% filter(mode != "") %>% select(event_type, mode)

##Assignment (main round) and calibration ids
annot_assign <- read_csv(file.path(annot_dir, "assignment_v1.csv"), show_col_types=FALSE)
calib_ids <- read_csv(file.path(annot_dir, "calibration_key_v1.csv"), show_col_types=FALSE)$annotation_id

##Item texts, to check that evidence sentences are copied verbatim
items <- bind_rows(read_csv(file.path("data", "stage_a", "derived", "annotation_items_v1.csv"), show_col_types=FALSE),
                   read_csv(file.path(annot_dir, "calibration_items_v1.csv"), show_col_types=FALSE)) %>%
  mutate(text_squish=str_squish(paste(title, text)))

####PART B: INGEST CODED SHEETS####

art_files <- list.files(coded_dir, pattern="^articles_.*\\.csv$", full.names=TRUE)
men_files <- list.files(coded_dir, pattern="^mentions_.*\\.csv$", full.names=TRUE)
if (length(art_files) == 0) stop("No coded sheets in ", coded_dir)

coded_art <- bind_rows(lapply(art_files, function(f) read_csv(f, col_types=cols(.default="c")) %>% mutate(file=basename(f), row=row_number() + 1)))
coded_men <- bind_rows(lapply(men_files, function(f) read_csv(f, col_types=cols(.default="c")) %>% mutate(file=basename(f), row=row_number() + 1)))

#Validating
nrow(coded_art)
nrow(coded_men)
table(coded_art$coder, useNA="ifany")

##Collecting problems as rows: file, row, annotation_id, field, problem
problems <- list()
flag <- function(df, cond, field, problem) {
  bad <- df[which(cond), ]
  if (nrow(bad) > 0) problems[[length(problems) + 1]] <<- tibble(file=bad$file, row=bad$row, annotation_id=bad$annotation_id, field=field, problem=problem)
}

####PART C: ARTICLES SHEET####

flag(coded_art, is.na(coded_art$coder), "coder", "missing")
flag(coded_art, !coded_art$article_type %in% cb_types, "article_type", "missing or not a valid value")
flag(coded_art, !coded_art$political_relevant %in% c("yes", "no"), "political_relevant", "must be yes or no")
flag(coded_art, !coded_art$extraction_problem %in% c("none", "partial", "boilerplate", "wrong_language", "unreadable"), "extraction_problem", "missing or not a valid value")
flag(coded_art, is.na(suppressWarnings(as.numeric(coded_art$minutes))), "minutes", "missing or not a number")
flag(coded_art, duplicated(coded_art[, c("annotation_id", "coder")]), "annotation_id", "duplicate row for this coder")

##Every assigned article coded, nothing coded that was not assigned (calibration ids are coded by all)
assigned_main <- annot_assign %>% mutate(key=paste(annotation_id, coder))
coded_main <- coded_art %>% filter(!annotation_id %in% calib_ids) %>% mutate(key=paste(annotation_id, coder))
flag(coded_main, !coded_main$key %in% assigned_main$key, "annotation_id", "not assigned to this coder")
missing_main <- assigned_main %>% filter(coder %in% coded_art$coder, !key %in% coded_main$key)
if (nrow(missing_main) > 0) problems[[length(problems) + 1]] <- tibble(file=paste0("articles_", missing_main$coder), row=NA,
                                                                       annotation_id=missing_main$annotation_id, field="annotation_id", problem="assigned but not coded")

####PART D: MENTIONS SHEET####

if (nrow(coded_men) > 0) {

  ##Mentions must belong to a coded article of the same coder
  art_keys <- paste(coded_art$annotation_id, coded_art$coder)
  flag(coded_men, !paste(coded_men$annotation_id, coded_men$coder) %in% art_keys, "annotation_id", "no matching row in the articles sheet")
  flag(coded_men, duplicated(coded_men[, c("annotation_id", "coder", "mention_no")]), "mention_no", "duplicate mention number")

  ##Event type and modes
  flag(coded_men, !coded_men$event_type %in% cb_events$event_type, "event_type", "missing or not one of the 16 PLOVER types")
  men_modes <- coded_men %>% filter(!is.na(modes)) %>%
    mutate(mode=str_split(modes, ";")) %>% unnest(mode) %>% mutate(mode=str_trim(mode)) %>%
    left_join(cb_modes %>% mutate(ok=TRUE), by=c("event_type", "mode"))
  flag(men_modes, is.na(men_modes$ok), "modes", "mode not valid for this event type")

  ##Status, confidence, crime flag
  flag(coded_men, !coded_men$status %in% cb_status, "status", "missing or not a valid value")
  flag(coded_men, !coded_men$confidence %in% c("1", "2", "3"), "confidence", "must be 1, 2 or 3")
  flag(coded_men, coded_men$confidence %in% "1" & is.na(coded_men$notes), "notes", "required when confidence is 1")
  flag(coded_men, !coded_men$crime_only %in% c("yes", "no"), "crime_only", "must be yes or no")

  ##Actors and recipients: aligned lists, valid countries and sectors
  for (role in c("actor", "recipient")) {
    txt <- coded_men[[paste0(role, "_text")]]
    cty <- coded_men[[paste0(role, "_country")]]
    sec <- coded_men[[paste0(role, "_sector")]]
    n_txt <- ifelse(is.na(txt), 0, str_count(txt, ";") + 1)
    n_cty <- ifelse(is.na(cty), 0, str_count(cty, ";") + 1)
    n_sec <- ifelse(is.na(sec), 0, str_count(sec, ";") + 1)
    flag(coded_men, n_txt != n_cty | n_txt != n_sec, paste0(role, "_*"), "text, country and sector lists differ in length")
    cty_bad <- sapply(str_split(coalesce(cty, ""), ";"), function(x) any(!str_trim(x[x != ""]) %in% c("INT", "UNK") & !str_detect(str_trim(x[x != ""]), "^[A-Z]{3}$")))
    flag(coded_men, cty_bad, paste0(role, "_country"), "use ISO3 codes, INT or UNK")
    sec_bad <- sapply(str_split(coalesce(sec, ""), "[;+]"), function(x) any(!str_trim(x[x != ""]) %in% cb_sectors))
    flag(coded_men, sec_bad, paste0(role, "_sector"), "unknown sector code")
  }
  flag(coded_men, is.na(coded_men$actor_text), "actor_text", "missing (use UNK/UAF codes for unidentified actors)")
  rec_req <- cb_events$event_type[cb_events$recipient_required == "yes"]
  flag(coded_men, coded_men$event_type %in% rec_req & is.na(coded_men$recipient_text), "recipient_text", "required for this event type")

  ##Location country
  flag(coded_men, !is.na(coded_men$location_country) & !str_detect(coded_men$location_country, "^[A-Z]{3}$"), "location_country", "use an ISO3 code")

  ##Dates: format must match precision
  date_pattern <- c(day="^\\d{4}-\\d{2}-\\d{2}$", week="^\\d{4}-\\d{2}-\\d{2}$", month="^\\d{4}-\\d{2}$", year="^\\d{4}$")
  flag(coded_men, !coded_men$date_precision %in% c(names(date_pattern), "none"), "date_precision", "missing or not a valid value")
  date_ok <- mapply(function(d, p) {
    if (is.na(p) || !p %in% c(names(date_pattern), "none")) return(TRUE)   #already flagged above
    if (p == "none") return(is.na(d))
    !is.na(d) && str_detect(d, date_pattern[[p]])
  }, coded_men$event_date, coded_men$date_precision)
  flag(coded_men, !date_ok, "event_date", "format does not match date_precision (empty when precision is none)")

  ##Evidence: present and copied verbatim from the item
  ev <- coded_men %>% left_join(items %>% select(annotation_id, text_squish), by="annotation_id") %>%
    mutate(found=!is.na(evidence) & !is.na(text_squish) & str_detect(text_squish, fixed(str_squish(evidence))))
  flag(ev, is.na(ev$evidence), "evidence", "missing")
  flag(ev, !is.na(ev$evidence) & !ev$found, "evidence", "not found verbatim in the article text")
}

####PART E: REPORT####

annot_problems <- bind_rows(problems)
if (nrow(annot_problems) == 0) {
  message("No problems found")
} else {
  annot_problems <- annot_problems %>% arrange(file, row)
  print(count(annot_problems, field, problem, sort=TRUE), n=50)
}
write_csv(annot_problems, file.path(annot_dir, "validation_report_v1.csv"))
