##CC-NEWS pilot: converting subagent (LLM) coder output to the standard coding sheets
##Reads data/stage_a/annotation/agent/out/<batch_id>.json and writes
##data/stage_a/annotation/coded/articles_<coder>_v1.csv and mentions_<coder>_v1.csv,
##so the validator (04) and agreement analysis (06) treat LLM and human coders alike.

##Cleaning working environment
rm(list=ls())

##Setting working directory
#setwd("C:/...")   #only needed if not running from the project root

##Loading libraries
library(readr)
library(dplyr)
library(purrr)
library(jsonlite)

####PART A: SETTINGS####

agent_dir <- file.path("data", "stage_a", "annotation", "agent")
coded_dir <- file.path("data", "stage_a", "annotation", "coded")
dir.create(coded_dir, recursive=TRUE, showWarnings=FALSE)

####PART B: INGEST####

out_files <- list.files(file.path(agent_dir, "out"), pattern="\\.json$", full.names=TRUE)
length(out_files)
if (length(out_files) == 0) stop("No subagent output found")

agent_raw <- lapply(out_files, read_json)
names(agent_raw) <- basename(out_files)

#Batches per coder
table(sapply(agent_raw, function(x) x$coder))

####PART C: FLATTENING####

##Helpers for list fields: entities joined with "; ", sectors within an entity with "+"
#Semicolons inside entity names are replaced so the list separator stays unambiguous
na_if_empty <- function(x) if (is.null(x) || length(x) == 0 || identical(x, "")) NA_character_ else as.character(x)
ent_field <- function(ents, field) {
  if (length(ents) == 0) return(NA_character_)
  vals <- sapply(ents, function(e) {
    if (field == "sectors") paste(unlist(e$sectors), collapse="+") else gsub(";", ",", as.character(e[[field]]))
  })
  paste(vals, collapse="; ")
}

agent_articles <- map_dfr(agent_raw, function(b) map_dfr(b$articles, function(a) tibble(
  annotation_id=a$annotation_id, coder=b$coder, batch_id=b$batch_id,
  article_type=na_if_empty(a$article_type), political_relevant=na_if_empty(a$political_relevant),
  extraction_problem=na_if_empty(a$extraction_problem),
  minutes="0",                 #not meaningful for LLM coders
  notes=na_if_empty(a$notes))))

agent_mentions <- map_dfr(agent_raw, function(b) map_dfr(b$articles, function(a) {
  if (length(a$mentions) == 0) return(NULL)
  imap_dfr(a$mentions, function(m, k) tibble(
    annotation_id=a$annotation_id, coder=b$coder, mention_no=as.character(k),
    event_type=na_if_empty(m$event_type), modes=na_if_empty(paste(unlist(m$modes), collapse=";")),
    status=na_if_empty(m$status),
    actor_text=ent_field(m$actors, "text"), actor_country=ent_field(m$actors, "country"), actor_sector=ent_field(m$actors, "sectors"),
    recipient_text=ent_field(m$recipients, "text"), recipient_country=ent_field(m$recipients, "country"),
    recipient_sector=ent_field(m$recipients, "sectors"),
    location_text=na_if_empty(m$location_text), location_country=na_if_empty(m$location_country),
    date_text=na_if_empty(m$date_text), event_date=na_if_empty(m$event_date), date_precision=na_if_empty(m$date_precision),
    evidence=na_if_empty(m$evidence), crime_only=na_if_empty(m$crime_only),
    confidence=na_if_empty(m$confidence), notes=na_if_empty(m$notes)))
}))

#Validating
nrow(agent_articles)
length(unique(paste(agent_articles$annotation_id, agent_articles$coder)))
nrow(agent_mentions)
table(agent_mentions$event_type, useNA="ifany")

####PART D: SAVING####

##One articles sheet and one mentions sheet per coder, in the template's column order
art_cols <- names(read_csv(file.path("annotation", "templates", "articles_template_v1.csv"), show_col_types=FALSE))
men_cols <- names(read_csv(file.path("annotation", "templates", "mentions_template_v1.csv"), show_col_types=FALSE))

if (nrow(agent_mentions) == 0) agent_mentions <- as_tibble(setNames(replicate(length(men_cols), character(0), simplify=FALSE), men_cols))

for (cd in sort(unique(agent_articles$coder))) {
  write_csv(agent_articles %>% filter(coder == cd) %>% arrange(annotation_id) %>% select(all_of(art_cols)),
            file.path(coded_dir, paste0("articles_", cd, "_v1.csv")), na="")
  write_csv(agent_mentions %>% filter(coder == cd) %>% arrange(annotation_id, as.integer(mention_no)) %>% select(all_of(men_cols)),
            file.path(coded_dir, paste0("mentions_", cd, "_v1.csv")), na="")
}

#Validating
list.files(coded_dir)
