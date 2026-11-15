##CC-NEWS pilot, Stage A: article layer, diagnostics and annotation samples
##Run after 01_ingest.R, from the project root

##Cleaning working environment
rm(list=ls())

##Setting working directory
#setwd("C:/...")   #only needed if not running from the project root

##Loading libraries
library(readr)
library(dplyr)
library(tidyr)
library(stringr)
library(jsonlite)
library(nanoparquet)
library(cld2)
library(digest)

####PART A: SETTINGS####

out_dir <- file.path("data", "stage_a")
derived_dir <- file.path(out_dir, "derived")
dir.create(derived_dir, recursive=TRUE, showWarnings=FALSE)

pub_window_days <- 7           #article counts as current if published up to 7 days before crawl
keep_missing_pub_date <- FALSE #drop articles with no extractable publication date
short_text_chars <- 500        #flagged, not dropped
n_prob <- 300                  #probability sample for annotation
n_enr <- 300                   #keyword-enriched sample for annotation
domain_cap <- 3                #max articles per domain in the enriched sample
sample_seed_r <- 20261115

####PART B: INGEST####

##Reading the per-WARC summaries
summ_files <- list.files(file.path(out_dir, "summaries"), pattern="\\.json$", full.names=TRUE)
warc_summ <- bind_rows(lapply(summ_files, function(f) {
  s <- read_json(f)
  tibble(warc_path=s$warc_path, completed=isTRUE(s$completed), n_records=s$n_records,
         n_response=s$n_response, n_sampled=s$n_sampled, sample_rate=s$sample_rate,
         seed=s$seed, seconds=s$seconds)
}))

#Validating
warc_summ
table(warc_summ$completed)

##Using completed WARC files only
warc_summ <- warc_summ %>% filter(completed)
if (nrow(warc_summ) == 0) stop("No completed WARC files; run 01_ingest.R first")
if (n_distinct(warc_summ$sample_rate) > 1 || n_distinct(warc_summ$seed) > 1) stop("WARC files were sampled with different settings")

##Reading the sampled records
stems <- str_remove(basename(warc_summ$warc_path), "\\.warc\\.gz$")
part_files <- unlist(lapply(file.path(out_dir, "records", stems), list.files, pattern="\\.parquet$", full.names=TRUE))
cc_records <- bind_rows(lapply(part_files, read_parquet))

#Validating
nrow(cc_records)
sum(warc_summ$n_sampled)
length(unique(cc_records$warc_record_id))
if (nrow(cc_records) != sum(warc_summ$n_sampled)) stop("Record count does not match the WARC summaries")

##Overview of the dataset
glimpse(cc_records)

####PART C: EXTRACTION DIAGNOSTICS####

##Extraction outcome for all sampled records
table(cc_records$extract_status, useNA="ifany")

##Language identification (cld2) for records with text
cc_records <- cc_records %>% mutate(lang=NA_character_)
has_text <- cc_records$extract_status == "ok" & !is.na(cc_records$text) & nzchar(str_trim(cc_records$text))
cc_records$lang[has_text] <- detect_language(cc_records$text[has_text])

#How many records per language?
sort(table(cc_records$lang, useNA="ifany"), decreasing=TRUE)

##Publication date relative to crawl date
#CC-NEWS also captures old articles (e.g. via sitemaps), so this matters for event dating
cc_records <- cc_records %>%
  mutate(pub_day=as.Date(str_sub(pub_date, 1, 10), format="%Y-%m-%d"),
         crawl_day=as.Date(str_sub(crawl_date, 1, 10)),
         pub_lag_days=as.numeric(crawl_day - pub_day),
         pub_current=!is.na(pub_lag_days) & pub_lag_days >= -1 & pub_lag_days <= pub_window_days)

#Distribution of the publication lag (days)
summary(cc_records$pub_lag_days)
table(cut(cc_records$pub_lag_days, c(-Inf, -2, 1, 7, 30, 365, Inf)), useNA="ifany")

##Text length
summary(cc_records$text_chars)
cc_records <- cc_records %>% mutate(short_text=!is.na(text_chars) & text_chars < short_text_chars)

##Diagnostics by domain
domain_diag <- cc_records %>%
  group_by(url_host) %>%
  summarise(n_sampled=n(), n_ok=sum(extract_status == "ok"), share_ok=n_ok/n_sampled,
            n_en=sum(lang %in% "en"), n_en_current=sum(lang %in% "en" & pub_current),
            median_chars=median(text_chars, na.rm=TRUE), .groups="drop") %>%
  arrange(desc(n_sampled))

#How concentrated is the sample? Share of the 10 largest domains
nrow(domain_diag)
sum(head(domain_diag$n_sampled, 10)) / sum(domain_diag$n_sampled)
head(domain_diag, 20)

####PART D: ARTICLE LAYER####

##Analytic set: extracted, English, current
cc_en <- cc_records %>%
  filter(extract_status == "ok", lang %in% "en",
         pub_current | (keep_missing_pub_date & is.na(pub_day)))

#Validating
nrow(cc_en)
sum(is.na(cc_en$text))

##Exact duplicates on normalised text
#serialize=FALSE hashes the text itself, so hashes match across R and Python
cc_en <- cc_en %>% mutate(text_norm=enc2utf8(str_squish(str_to_lower(text))))
cc_en$text_hash <- vapply(cc_en$text_norm, digest, character(1), algo="xxhash64", serialize=FALSE, USE.NAMES=FALSE)

##Copy table: every captured copy linked to one canonical article (earliest crawl)
cc_copies <- cc_en %>%
  arrange(crawl_date, warc_record_id) %>%
  group_by(text_hash) %>%
  mutate(canonical_record_id=first(warc_record_id), n_copies=n(), n_hosts=n_distinct(url_host)) %>%
  ungroup() %>%
  select(warc_record_id, canonical_record_id, text_hash, n_copies, n_hosts,
         warc_path, target_uri, url_host, crawl_date, pub_date)

##Canonical articles
cc_canon <- cc_en %>%
  filter(warc_record_id %in% cc_copies$canonical_record_id) %>%
  left_join(cc_copies %>% distinct(canonical_record_id, n_copies, n_hosts),
            by=c("warc_record_id"="canonical_record_id")) %>%
  select(-text_norm)

#Validating
nrow(cc_copies)
nrow(cc_canon)
length(unique(cc_copies$text_hash))
table(cc_canon$n_copies)

####PART E: FUNNEL####

cc_funnel <- tibble(
  step=c("WARC response records (all)", "Sampled records", "HTTP 200 + HTML",
         "Text extracted", "English", "English + current publication date", "Unique English articles"),
  n=c(sum(warc_summ$n_response), nrow(cc_records),
      sum(cc_records$http_status %in% "200" & !cc_records$extract_status %in% c("http_non200", "not_html")),
      sum(cc_records$extract_status == "ok"), sum(cc_records$lang %in% "en"),
      nrow(cc_en), nrow(cc_canon))
)
cc_funnel

####PART F: ANNOTATION SAMPLES####

##Keyword flag for political/conflict content
#A crude stand-in for the relevance screen, used only to enrich the second sample
pol_terms <- paste0("\\b(protest|demonstrat|riot|strike|clash|attack|kill|bomb|shell|missile|militar|troops|army|",
                    "police|arrest|detain|minister|president|prime minister|government|parliament|election|",
                    "opposition|sanction|ceasefire|negotiat|talks|treaty|summit|rebel|insurgen|militant|terror|",
                    "accus|condemn|threat|embassy|diplomat|refugee|coup|humanitarian aid)")
cc_canon <- cc_canon %>% mutate(kw_political=str_detect(str_to_lower(paste(title, text)), pol_terms))

#Share of canonical articles with the keyword flag
mean(cc_canon$kw_political)

##Probability sample: simple random sample of canonical articles, drawn before any relevance screen
set.seed(sample_seed_r)
prob_sample <- cc_canon %>% slice_sample(n=min(n_prob, nrow(cc_canon))) %>% mutate(sample="probability")

##Enriched sample: keyword-flagged articles, at most domain_cap per domain, excluding the probability sample
enr_sample <- cc_canon %>%
  filter(kw_political, !warc_record_id %in% prob_sample$warc_record_id) %>%
  group_by(url_host) %>% slice_sample(n=domain_cap) %>% ungroup() %>%
  slice_sample(n=n_enr) %>% mutate(sample="enriched")

#Validating
nrow(prob_sample)
nrow(enr_sample)
length(intersect(prob_sample$warc_record_id, enr_sample$warc_record_id))
max(table(enr_sample$url_host))

##Annotation file (shuffled, no sample or keyword labels shown to coders)
annot <- bind_rows(prob_sample, enr_sample) %>%
  slice_sample(prop=1) %>%
  mutate(annotation_id=sprintf("A%04d", row_number()))

annot_items <- annot %>% select(annotation_id, title, pub_date, url_host, target_uri, text)
annot_key <- annot %>% select(annotation_id, sample, kw_political, warc_record_id, warc_path,
                              text_hash, n_copies, crawl_date, text_chars, short_text)

####PART G: SAVING####

write_parquet(cc_canon, file.path(derived_dir, "articles_canonical_v1.parquet"))
write_parquet(cc_copies, file.path(derived_dir, "article_copies_v1.parquet"))
write_csv(cc_funnel, file.path(derived_dir, "funnel_v1.csv"))
write_csv(domain_diag, file.path(derived_dir, "domain_diagnostics_v1.csv"))
write_csv(warc_summ, file.path(derived_dir, "warc_summary_v1.csv"))
write_csv(annot_items, file.path(derived_dir, "annotation_items_v1.csv"))
write_csv(annot_key, file.path(derived_dir, "annotation_key_v1.csv"))

#Validating
list.files(derived_dir)
nrow(read_parquet(file.path(derived_dir, "articles_canonical_v1.parquet")))
