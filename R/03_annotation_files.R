##CC-NEWS pilot: calibration set and coder assignment files
##Run after 02_articles.R, from the project root. See docs/annotation_protocol_v1.md

##Cleaning working environment
rm(list=ls())

##Setting working directory
#setwd("C:/...")   #only needed if not running from the project root

##Loading libraries
library(readr)
library(dplyr)
library(nanoparquet)

####PART A: SETTINGS####

derived_dir <- file.path("data", "stage_a", "derived")
annot_dir <- file.path("data", "stage_a", "annotation")
dir.create(file.path(annot_dir, "assigned"), recursive=TRUE, showWarnings=FALSE)
dir.create(file.path(annot_dir, "coded"), recursive=TRUE, showWarnings=FALSE)

coders <- c("C1", "C2")        #coder IDs; add more if available
n_calib <- 30                  #calibration articles, coded by everyone, never evaluated
enr_double_share <- 0.30       #share of enriched-sample articles coded twice
assign_seed <- 20261116

####PART B: INGEST####

cc_canon <- read_parquet(file.path(derived_dir, "articles_canonical_v1.parquet"))
annot_items <- read_csv(file.path(derived_dir, "annotation_items_v1.csv"), show_col_types=FALSE)
annot_key <- read_csv(file.path(derived_dir, "annotation_key_v1.csv"), show_col_types=FALSE)

#Validating
nrow(cc_canon)
nrow(annot_items)
table(annot_key$sample)
if (!setequal(annot_items$annotation_id, annot_key$annotation_id)) stop("Items and key do not match")

####PART C: CALIBRATION SET####

##Drawn from canonical articles outside both evaluation samples
set.seed(assign_seed)
calib <- cc_canon %>%
  filter(!warc_record_id %in% annot_key$warc_record_id) %>%
  slice_sample(n=n_calib) %>%
  mutate(annotation_id=sprintf("K%03d", row_number())) %>%
  select(annotation_id, title, pub_date, url_host, target_uri, text, warc_record_id)

#Validating
nrow(calib)
length(intersect(calib$warc_record_id, annot_key$warc_record_id))

write_excel_csv(calib %>% select(-warc_record_id), file.path(annot_dir, "calibration_items_v1.csv"))
write_csv(calib %>% select(annotation_id, warc_record_id), file.path(annot_dir, "calibration_key_v1.csv"))

####PART D: CODER ASSIGNMENT####

##Which articles are double-coded: all of the probability sample, a fixed share of the enriched sample
enr_ids <- annot_key$annotation_id[annot_key$sample == "enriched"]
enr_double <- sample(enr_ids, round(enr_double_share * length(enr_ids)))
annot_key <- annot_key %>% mutate(n_coders=ifelse(sample == "probability" | annotation_id %in% enr_double, 2, 1))

#How many codings in total?
table(annot_key$sample, annot_key$n_coders)
sum(annot_key$n_coders)

##Assigning each article to the least-loaded coder(s), ties broken at random
if (length(coders) < max(annot_key$n_coders)) stop("Need at least ", max(annot_key$n_coders), " coders")
load <- setNames(rep(0, length(coders)), coders)
assign_rows <- list()
for (i in sample(nrow(annot_key))) {
  k <- annot_key$n_coders[i]
  pick <- names(sort(load + runif(length(load), 0, 0.1)))[seq_len(k)]
  load[pick] <- load[pick] + 1
  assign_rows[[length(assign_rows) + 1]] <- tibble(annotation_id=annot_key$annotation_id[i], coder=pick)
}
annot_assign <- bind_rows(assign_rows) %>% arrange(coder, annotation_id)

#Validating
table(annot_assign$coder)
nrow(annot_assign) == sum(annot_key$n_coders)
any(duplicated(annot_assign))

write_csv(annot_assign, file.path(annot_dir, "assignment_v1.csv"))
write_csv(annot_key %>% select(annotation_id, sample, n_coders), file.path(annot_dir, "annotation_design_v1.csv"))

####PART E: CODER FILES####

##Per coder: items to read, a prefilled articles sheet and an empty mentions sheet
#Items keep the shuffled order from 02_articles.R; coders never see sample labels
mention_cols <- names(read_csv(file.path("annotation", "templates", "mentions_template_v1.csv"), show_col_types=FALSE))

for (cd in coders) {
  ids <- annot_assign$annotation_id[annot_assign$coder == cd]
  items <- annot_items %>% filter(annotation_id %in% ids) %>% arrange(annotation_id)
  write_excel_csv(items, file.path(annot_dir, "assigned", paste0("items_", cd, "_v1.csv")))
  write_excel_csv(tibble(annotation_id=items$annotation_id, coder=cd, article_type="", political_relevant="",
                         extraction_problem="", minutes="", notes=""),
                  file.path(annot_dir, "assigned", paste0("articles_", cd, "_v1.csv")), na="")
  write_excel_csv(as_tibble(setNames(replicate(length(mention_cols), character(0), simplify=FALSE), mention_cols)),
                  file.path(annot_dir, "assigned", paste0("mentions_", cd, "_v1.csv")))
}

#Validating
list.files(file.path(annot_dir, "assigned"))
