library(httr)
library(jsonlite)

# ==============================================================================
# YTD Job Growth Rate vs. National — OH, PA, KY, WV
#
# For each state and for the nation, computes year-to-date total nonfarm
# employment growth as a percentage (change from December of the prior year
# to the target month, divided by the December level). Then computes each
# state's growth rate minus the national growth rate, in percentage points -
# positive means the state grew faster than the nation YTD, negative means
# slower.
#
# USAGE:
#   1. Update target_year / target_month below to match fetch_state_sector_ytd_data.R
#   2. Run: Rscript fetch_ytd_growth_vs_national.R
#
# Series IDs (Total Nonfarm, seasonally adjusted):
#   National : CES0000000001
#   State    : SMS + state FIPS (2) + area code (5, 00000 = statewide)
#                  + "00" (total nonfarm supersector) + "000000" + "01"
# ==============================================================================

# ---- Settings (update these to shift the month; keep in sync with the other fetch scripts) --

api_key      <- Sys.getenv("BLS_API_KEY")
if (api_key == "") stop("BLS_API_KEY environment variable is not set. See README.md.")
target_year  <- 2026
target_month <- 5    # 1 = January, 2 = February, ... 12 = December

# ---- States ---------------------------------------------------------------------

states <- data.frame(
  fips  = c("39", "42", "21", "54"),
  state = c("Ohio", "Pennsylvania", "Kentucky", "West Virginia"),
  stringsAsFactors = FALSE
)

national_series_id <- "CES0000000001"

# Total Nonfarm state series: same builder pattern used in the other fetch
# scripts (SMS + FIPS + 00000 area + supersector + 000000 industry + 01
# datatype), with supersector "00" (total nonfarm).
build_state_series_id <- function(fips) {
  sprintf("SMS%s00000%s00000001", fips, "00")
}

# ---- Baseline is December of the prior year (the standard YTD anchor) -----------

target_period   <- sprintf("M%02d", target_month)
baseline_year   <- target_year - 1
baseline_period <- "M12"

start_year <- baseline_year
end_year   <- target_year

cat("=== YTD Job Growth Rate vs. National ===\n")
cat(sprintf("Baseline     : December %d\n", baseline_year))
cat(sprintf("Target month : %s %d\n", month.name[target_month], target_year))
cat("\n")

# ---- Call BLS API v2 -------------------------------------------------------------

fetch_bls <- function(series_ids, start, end, key) {
  payload <- list(
    seriesid        = series_ids,
    startyear       = as.character(start),
    endyear         = as.character(end),
    registrationkey = key
  )
  resp <- POST(
    url    = "https://api.bls.gov/publicAPI/v2/timeseries/data/",
    body   = toJSON(payload, auto_unbox = TRUE),
    encode = "raw",
    content_type_json()
  )
  if (http_error(resp)) {
    stop("BLS API request failed with status: ", status_code(resp))
  }
  result <- fromJSON(content(resp, as = "text", encoding = "UTF-8"))
  if (result$status != "REQUEST_SUCCEEDED") {
    stop("BLS API returned status: ", result$status,
         if (length(result$message) > 0) paste0(" (", paste(result$message, collapse = "; "), ")") else "")
  }
  result
}

extract_baseline_target <- function(data) {
  baseline_val <- NA
  target_val   <- NA
  if (!is.null(data) && nrow(data) > 0) {
    for (k in seq_len(nrow(data))) {
      yr  <- as.integer(data$year[k])
      per <- data$period[k]
      if (yr == baseline_year & per == baseline_period) baseline_val <- as.numeric(data$value[k])
      if (yr == target_year   & per == target_period)   target_val   <- as.numeric(data$value[k])
    }
  }
  c(baseline = baseline_val, target = target_val)
}

# ---- National total nonfarm -------------------------------------------------------

cat("Fetching national total nonfarm...\n")
national_result <- fetch_bls(list(national_series_id), start_year, end_year, api_key)
national_vals   <- extract_baseline_target(national_result$Results$series$data[[1]])
national_pct    <- (national_vals["target"] - national_vals["baseline"]) / national_vals["baseline"] * 100

# ---- State total nonfarm ----------------------------------------------------------

state_series_ids <- unname(vapply(states$fips, build_state_series_id, character(1)))

cat("Fetching state total nonfarm...\n")
state_result <- fetch_bls(state_series_ids, start_year, end_year, api_key)

rows <- list()
for (j in seq_len(nrow(state_result$Results$series))) {
  sid  <- state_result$Results$series$seriesID[j]
  data <- state_result$Results$series$data[[j]]
  fips <- substr(sid, 4, 5)
  st_name <- states$state[states$fips == fips]

  vals <- extract_baseline_target(data)
  state_pct <- (vals["target"] - vals["baseline"]) / vals["baseline"] * 100

  rows[[length(rows) + 1]] <- data.frame(
    state                = st_name,
    state_baseline_level = vals["baseline"],
    state_target_level   = vals["target"],
    state_pct_growth     = state_pct,
    national_pct_growth  = national_pct,
    relative_growth_pp   = state_pct - national_pct,
    stringsAsFactors     = FALSE
  )
}

output <- do.call(rbind, rows)
rownames(output) <- NULL

# ---- Display -----------------------------------------------------------------------

cat(sprintf("\nNational YTD total nonfarm growth: %+.3f%%\n\n", national_pct))
cat(sprintf("%-15s %12s %12s %14s\n", "State", "State %", "US %", "State - US (pp)"))
cat(paste(rep("-", 56), collapse = ""), "\n")
for (i in seq_len(nrow(output))) {
  cat(sprintf("%-15s %+12.3f %+12.3f %+14.3f\n",
              output$state[i], output$state_pct_growth[i],
              output$national_pct_growth[i], output$relative_growth_pp[i]))
}

# ---- Write CSV -----------------------------------------------------------------------

output_file <- "state_ytd_growth_vs_national.csv"
write.csv(output[, c("state", "state_pct_growth", "national_pct_growth", "relative_growth_pp")],
          output_file, row.names = FALSE)
cat(sprintf("\nData written to %s\n", output_file))
