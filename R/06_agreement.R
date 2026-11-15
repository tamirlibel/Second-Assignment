##CC-NEWS pilot: inter-coder agreement (protocol section 9)
##Reads the validated coding sheets in data/stage_a/annotation/coded/ and reports agreement
##separately for the calibration round (K ids, all coders) and the main round (double-coded A ids).

##Cleaning working environment
rm(list=ls())

##Setting working directory
#setwd("C:/...")   #only needed if not running from the project root

##Loading libraries
library(readr)
library(dplyr)
library(tidyr)
library(stringr)
library(purrr)

####PART A: SETTINGS AND INGEST####

annot_dir <- file.path("data", "stage_a", "annotation")
coded_dir <- file.path(annot_dir, "coded")
out_dir <- file.path(annot_dir, "agreement")
dir.create(out_dir, showWarnings=FALSE)

coded_art <- bind_rows(lapply(list.files(coded_dir, "^articles_.*\\.csv$", full.names=TRUE), read_csv, col_types=cols(.default="c")))
coded_men <- bind_rows(lapply(list.files(coded_dir, "^mentions_.*\\.csv$", full.names=TRUE), read_csv, col_types=cols(.default="c")))

#Validating
table(coded_art$coder)
table(coded_men$coder)

coded_art <- coded_art %>% mutate(round=ifelse(str_starts(annotation_id, "K"), "calibration", "main"))
coded_men <- coded_men %>% mutate(round=ifelse(str_starts(annotation_id, "K"), "calibration", "main"))

####PART B: KRIPPENDORFF'S ALPHA (NOMINAL)####

##Units x coders, missing values allowed; standard coincidence-matrix formula
#Written out because it is short and avoids an extra dependency
kripp_nominal <- function(unit, value) {
  d <- tibble(unit=unit, value=value) %>% filter(!is.na(value)) %>% group_by(unit) %>% filter(n() >= 2) %>% ungroup()
  if (nrow(d) == 0 || n_distinct(d$value) < 2) return(NA_real_)
  coinc <- d %>% group_by(unit) %>% group_modify(function(g, k) {
    m <- nrow(g)
    expand_grid(i=seq_len(m), j=seq_len(m)) %>% filter(i != j) %>%
      transmute(c=g$value[i], k=g$value[j], w=1 / (m - 1))
  }) %>% ungroup() %>% group_by(c, k) %>% summarise(o=sum(w), .groups="drop")
  n_c <- coinc %>% group_by(c) %>% summarise(n=sum(o))
  n <- sum(n_c$n)
  d_o <- sum(coinc$o[coinc$c != coinc$k]) / n
  d_e <- (n^2 - sum(n_c$n^2)) / (n * (n - 1))
  1 - d_o / d_e
}

####PART C: ARTICLE-LEVEL AGREEMENT####

has_event <- coded_men %>% filter(status == "occurred", crime_only == "no") %>% distinct(annotation_id, coder) %>% mutate(has_event="yes")
art_level <- coded_art %>%
  left_join(has_event, by=c("annotation_id", "coder")) %>%
  mutate(has_event=coalesce(has_event, "no"))

##Units coded by at least two coders
art_multi <- art_level %>% group_by(round, annotation_id) %>% filter(n() >= 2) %>% ungroup()

agree_article <- art_multi %>%
  pivot_longer(c(political_relevant, has_event, article_type), names_to="variable", values_to="value") %>%
  group_by(round, variable) %>%
  summarise(n_units=n_distinct(annotation_id), alpha=kripp_nominal(annotation_id, value),
            share_yes=mean(value == "yes"), .groups="drop")
agree_article

##Event-type presence per article (does the coder see at least one mention of type X?)
types_present <- coded_men %>% filter(status == "occurred", crime_only == "no") %>% distinct(annotation_id, coder, event_type)
agree_types <- art_multi %>% select(round, annotation_id, coder) %>%
  crossing(event_type=unique(coded_men$event_type)) %>%
  left_join(types_present %>% mutate(present="yes"), by=c("annotation_id", "coder", "event_type")) %>%
  mutate(present=coalesce(present, "no")) %>%
  group_by(round, event_type) %>%
  summarise(n_units=n_distinct(annotation_id), n_present=sum(present == "yes"),
            alpha=kripp_nominal(annotation_id, present), .groups="drop") %>%
  arrange(round, desc(n_present))
agree_types

####PART D: MENTION MATCHING####

##Normalising text for matching
norm_txt <- function(x) str_squish(str_remove_all(str_to_lower(coalesce(x, "")), "[[:punct:]]"))
split_list <- function(x) lapply(str_split(coalesce(x, ""), ";"), function(v) { v <- str_trim(v); v[v != ""] })

men <- coded_men %>%
  mutate(ev_norm=norm_txt(evidence),
         actors=lapply(split_list(actor_text), norm_txt),
         actor_cty=lapply(split_list(actor_country), sort),
         recip_cty=lapply(split_list(recipient_country), sort),
         mode_set=lapply(str_split(coalesce(modes, ""), ";"), function(v) sort(v[v != ""])),
         default_subset=status == "occurred" & crime_only == "no")

##Two mentions match if same event type and (evidence overlaps, or actors share an entity
##with dates no more than one day apart when both are day-precise); one-to-one, evidence matches first
mentions_match <- function(a, b) {
  if (a$event_type != b$event_type) return(0)
  ev <- nzchar(a$ev_norm) && nzchar(b$ev_norm) && (str_detect(a$ev_norm, fixed(b$ev_norm)) || str_detect(b$ev_norm, fixed(a$ev_norm)))
  if (ev) return(2)
  act <- any(outer(a$actors[[1]], b$actors[[1]], function(x, y) mapply(function(p, q) nzchar(p) && nzchar(q) && (str_detect(p, fixed(q)) || str_detect(q, fixed(p))), x, y)))
  date_ok <- !(a$date_precision %in% "day" && b$date_precision %in% "day") ||
    abs(as.numeric(as.Date(a$event_date) - as.Date(b$event_date))) <= 1
  if (act && isTRUE(date_ok)) return(1)
  0
}

match_pair <- function(ma, mb) {
  if (nrow(ma) == 0 || nrow(mb) == 0) return(tibble(ia=integer(), ib=integer()))
  sc <- outer(seq_len(nrow(ma)), seq_len(nrow(mb)), Vectorize(function(i, j) mentions_match(ma[i, ], mb[j, ])))
  pairs <- tibble(ia=integer(), ib=integer())
  for (level in c(2, 1)) {
    for (i in seq_len(nrow(ma))) {
      if (i %in% pairs$ia) next
      js <- which(sc[i, ] == level & !seq_len(nrow(mb)) %in% pairs$ib)
      if (length(js) > 0) pairs <- bind_rows(pairs, tibble(ia=i, ib=js[1]))
    }
  }
  pairs
}

##All coder pairs on every multiply-coded article
coder_pairs <- art_multi %>% distinct(round, annotation_id, coder) %>%
  inner_join(art_multi %>% distinct(round, annotation_id, coder), by=c("round", "annotation_id"), relationship="many-to-many") %>%
  filter(coder.x < coder.y) %>% rename(coder_a=coder.x, coder_b=coder.y)

pair_results <- pmap_dfr(coder_pairs, function(round, annotation_id, coder_a, coder_b) {
  ma <- men %>% filter(annotation_id == !!annotation_id, coder == coder_a)
  mb <- men %>% filter(annotation_id == !!annotation_id, coder == coder_b)
  out <- list()
  for (subset in c("all", "default")) {
    a <- if (subset == "default") filter(ma, default_subset) else ma
    b <- if (subset == "default") filter(mb, default_subset) else mb
    p <- match_pair(a, b)
    attr_eq <- if (nrow(p) > 0) {
      ra <- a[p$ia, ]; rb <- b[p$ib, ]
      tibble(mode=map2_lgl(ra$mode_set, rb$mode_set, identical),
             status=ra$status == rb$status,
             actor_country=map2_lgl(ra$actor_cty, rb$actor_cty, identical),
             recipient_country=map2_lgl(ra$recip_cty, rb$recip_cty, identical),
             location_country=coalesce(ra$location_country, "") == coalesce(rb$location_country, ""),
             event_date=coalesce(ra$event_date, "") == coalesce(rb$event_date, ""))
    } else NULL
    out[[subset]] <- tibble(round=round, annotation_id=annotation_id, coder_a=coder_a, coder_b=coder_b, subset=subset,
                            n_a=nrow(a), n_b=nrow(b), n_matched=nrow(p),
                            attrs=list(attr_eq))
  }
  bind_rows(out)
})

####PART E: MENTION-LEVEL SUMMARY####

##Detection: F1 = 2 * matched / (n_a + n_b), pooled over articles
agree_mentions <- pair_results %>%
  group_by(round, subset) %>%
  summarise(n_pairs=n(), mentions_a=sum(n_a), mentions_b=sum(n_b), matched=sum(n_matched),
            detection_f1=2 * matched / (mentions_a + mentions_b), .groups="drop")
agree_mentions

##Attribute agreement on matched mentions, and complete-record agreement
agree_attrs <- pair_results %>% filter(map_lgl(attrs, ~ !is.null(.x))) %>%
  select(round, subset, attrs) %>% unnest(attrs) %>%
  mutate(complete_record=actor_country & recipient_country & location_country & event_date) %>%
  group_by(round, subset) %>%
  summarise(n_matched=n(), across(c(mode, status, actor_country, recipient_country, location_country, event_date, complete_record), mean),
            .groups="drop")
agree_attrs

##Detection F1 per coder pair (calibration: are some coders systematically different?)
agree_by_pair <- pair_results %>% filter(subset == "default") %>%
  group_by(round, coder_a, coder_b) %>%
  summarise(n_articles=n(), detection_f1=2 * sum(n_matched) / (sum(n_a) + sum(n_b)), .groups="drop")
agree_by_pair

##Mentions per coder (do some coders code much more?)
coder_volume <- art_level %>% group_by(round, coder) %>% summarise(n_articles=n(), .groups="drop") %>%
  left_join(coded_men %>% group_by(round, coder) %>% summarise(n_mentions=n(), .groups="drop"), by=c("round", "coder")) %>%
  mutate(mentions_per_article=n_mentions / n_articles)
coder_volume

####PART F: SAVING####

write_csv(agree_article, file.path(out_dir, "agreement_article_v1.csv"))
write_csv(agree_types, file.path(out_dir, "agreement_event_types_v1.csv"))
write_csv(agree_mentions, file.path(out_dir, "agreement_mentions_v1.csv"))
write_csv(agree_attrs, file.path(out_dir, "agreement_attributes_v1.csv"))
write_csv(agree_by_pair, file.path(out_dir, "agreement_by_pair_v1.csv"))
write_csv(coder_volume, file.path(out_dir, "coder_volume_v1.csv"))
write_csv(pair_results %>% select(-attrs), file.path(out_dir, "pair_results_v1.csv"))

#Validating
list.files(out_dir)
