##CC-NEWS pilot, Stage A: selecting, downloading and extracting WARC files
##Run from the project root (the folder that holds R/, python/ and data/)

##Cleaning working environment
rm(list=ls())

##Setting working directory
#setwd("C:/...")   #only needed if not running from the project root

##Loading libraries
library(readr)
library(dplyr)
library(stringr)
library(curl)
library(jsonlite)

####PART A: SETTINGS####

##Pilot design
cc_month <- "2026/09"          #CC-NEWS month (YYYY/MM)
n_warc <- 12                   #WARC files, spread evenly across the month
sample_rate <- 0.05            #share of response records sampled within each WARC
sample_seed <- "ccnews-pilot-v1"
keep_warc <- FALSE             #delete each ~1GB WARC after extraction

##Paths
warc_dir <- file.path("data", "warc")
out_dir <- file.path("data", "stage_a")
ledger_file <- file.path(out_dir, "ledger_v1.csv")
dir.create(warc_dir, recursive=TRUE, showWarnings=FALSE)
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)

##Python extractor (needs uv; run "uv sync --project python" once beforehand)
uv_cmd <- "uv"
extractor <- file.path("python", "extract_ccnews.py")

####PART B: SELECTING WARC FILES####

##Reading the monthly manifest
cc_paths <- read_lines(paste0("https://data.commoncrawl.org/crawl-data/CC-NEWS/", cc_month, "/warc.paths.gz"))

#How many WARC files this month?
length(cc_paths)
if (length(cc_paths) == 0) stop("Empty manifest for ", cc_month)

##Crawl time from the file name (CC-NEWS-YYYYMMDDHHMMSS-NNNNN.warc.gz)
cc_files <- tibble(warc_path=cc_paths) %>%
  mutate(warc_time=as.POSIXct(str_extract(warc_path, "(?<=CC-NEWS-)\\d{14}"),
                              format="%Y%m%d%H%M%S", tz="UTC")) %>%
  arrange(warc_time)

#Validating
sum(is.na(cc_files$warc_time))
range(cc_files$warc_time)

##Choosing the file closest to each of n_warc evenly spaced time points
#Deterministic, so the same month always gives the same files
target_times <- seq(min(cc_files$warc_time), max(cc_files$warc_time), length.out=n_warc)
pick <- unique(sapply(target_times, function(t) which.min(abs(as.numeric(cc_files$warc_time - t, units="secs")))))
cc_sel <- cc_files[pick, ]

#Validating
nrow(cc_sel)
table(as.Date(cc_sel$warc_time))

write_csv(cc_sel, file.path(out_dir, "selected_warc_v1.csv"))

####PART C: DOWNLOADING AND EXTRACTING####

##Downloading one WARC, checking its size against the server's Content-Length
#Retries with backoff, because a 1GB transfer can be cut off
download_warc <- function(url, dest, tries=4) {
  head_res <- curl_fetch_memory(url, handle=new_handle(nobody=TRUE))
  if (head_res$status_code != 200) stop("HEAD failed (", head_res$status_code, ") for ", url)
  expected <- as.numeric(parse_headers_list(head_res$headers)[["content-length"]])
  for (i in seq_len(tries)) {
    ok <- tryCatch({curl_download(url, dest, quiet=TRUE); TRUE}, error=function(e) FALSE)
    if (ok && file.size(dest) == expected) return(expected)
    message("  download attempt ", i, " failed or incomplete; retrying")
    Sys.sleep(2^i)
  }
  stop("Could not download a complete copy of ", url)
}

for (i in seq_len(nrow(cc_sel))) {

  warc_path <- cc_sel$warc_path[i]
  stem <- str_remove(basename(warc_path), "\\.warc\\.gz$")
  summary_file <- file.path(out_dir, "summaries", paste0(stem, ".json"))

  #Skipping files already completed in an earlier run
  if (file.exists(summary_file) && isTRUE(read_json(summary_file)$completed)) {
    message(i, "/", nrow(cc_sel), " ", stem, ": already done, skipping")
    next
  }

  message(i, "/", nrow(cc_sel), " ", stem, ": downloading")
  t0 <- Sys.time()
  local_warc <- file.path(warc_dir, basename(warc_path))
  expected <- download_warc(paste0("https://data.commoncrawl.org/", warc_path), local_warc)

  message(i, "/", nrow(cc_sel), " ", stem, ": extracting")
  status <- system2(uv_cmd, c("run", "--project", "python", "python", extractor,
                              "--warc", local_warc, "--warc-path", warc_path,
                              "--out-dir", out_dir, "--sample-rate", sample_rate,
                              "--seed", sample_seed, "--expected-bytes", format(expected, scientific=FALSE)))

  if (!keep_warc) file.remove(local_warc)

  #Recording the outcome in the ledger
  done <- file.exists(summary_file) && isTRUE(read_json(summary_file)$completed)
  ledger_row <- tibble(warc_path=warc_path, bytes=expected, exit_status=status, completed=done,
                       minutes=round(as.numeric(Sys.time() - t0, units="mins"), 1),
                       finished=format(Sys.time(), tz="UTC", usetz=TRUE))
  write_csv(ledger_row, ledger_file, append=file.exists(ledger_file))

  if (!done) warning(stem, " did not complete (exit status ", status, "); rerun this script to retry")
}

####PART D: CHECKING THE RUN####

##Ledger
ledger <- read_csv(ledger_file, show_col_types=FALSE)
ledger

##All selected files completed?
summ_files <- file.path(out_dir, "summaries", paste0(str_remove(basename(cc_sel$warc_path), "\\.warc\\.gz$"), ".json"))
completed <- sapply(summ_files, function(f) file.exists(f) && isTRUE(read_json(f)$completed))
sum(completed)
if (!all(completed)) warning(sum(!completed), " selected WARC files are not complete; rerun this script")
