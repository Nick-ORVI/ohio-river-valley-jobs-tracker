library(httr)
library(jsonlite)

# ==============================================================================
# BLS State Employment Data Fetcher — OH, PA, KY, WV by industry sector
# Pulls Current Employment Statistics (CES), State & Area, seasonally adjusted
#
# USAGE:
#   1. Update target_year / target_month below to change the target month
#   2. Run: Rscript fetch_state_sector_data.R
#   3. Then run: Rscript state_sector_chart.R
#
# Series ID format (State & Area, seasonally adjusted):
#   SMS + state FIPS (2) + area code (5, 00000 = statewide)
#       + supersector code (2) + industry code (6, 000000 = supersector total)
#       + data type (2, 01 = all employees)
# ==============================================================================

# ---- Settings (update these to shift the month) -----------------------------

api_key      <- Sys.getenv("BLS_API_KEY")
if (api_key == "") stop("BLS_API_KEY environment variable is not set. See README.md.")
target_year  <- 2026
target_month <- 5    # 1 = January, 2 = February, ... 12 = December

# ---- States -------------------------------------------------------------------

states <- data.frame(
  fips  = c("39", "42", "21", "54"),
  state = c("Ohio", "Pennsylvania", "Kentucky", "West Virginia"),
  stringsAsFactors = FALSE
)

# ---- BLS CES Supersector Definitions ------------------------------------------
# Same supersector codes used in fetch_bls_data.R (national version)

sectors <- data.frame(
  supersector = c("10", "20", "30", "40", "42", "43", "50", "55", "60", "65", "70", "80", "90"),
  sector = c(
    "Mining & Logging",
    "Construction",
    "Manufacturing",
    "Trade, Transp & Utilities",
    "Retail Trade",
    "Transp & Warehousing",
    "Information",
    "Financial Activities",
    "Professional & Business Svcs",
    "Education & Health Svcs",
    "Leisure & Hospitality",
    "Other Services",
    "Government"
  ),
  # "supersector" rows sum to total nonfarm employment change.
  # "subsector" rows (Retail Trade, Transp & Warehousing) are already
  # included inside the "Trade, Transp & Utilities" supersector and must
  # be excluded from any total to avoid double-counting.
  level = c(
    "supersector", "supersector", "supersector", "supersector",
    "subsector", "subsector",
    "supersector", "supersector", "supersector", "supersector",
    "supersector", "supersector", "supersector"
  ),
  stringsAsFactors = FALSE
)

build_series_id <- function(fips, supersector) {
  sprintf("SMS%s00000%s00000001", fips, supersector)
}

# ---- Determine date range for API request ------------------------------------

target_period <- sprintf("M%02d", target_month)

if (target_month == 1) {
  prior_year  <- target_year - 1
  prior_month <- 12
} else {
  prior_year  <- target_year
  prior_month <- target_month - 1
}
prior_period <- sprintf("M%02d", prior_month)

start_year <- min(target_year, prior_year)
end_year   <- max(target_year, prior_year)

cat("=== BLS State Sector Data Fetcher ===\n")
cat(sprintf("States       : %s\n", paste(states$state, collapse = ", ")))
cat(sprintf("Target month : %d-%s (%s %d)\n",
            target_year, target_period, month.name[target_month], target_year))
cat(sprintf("Prior month  : %d-%s (%s %d)\n",
            prior_year, prior_period, month.name[prior_month], prior_year))
cat("\n")

# ---- Call BLS API v2 (one request per state; 13 series each, under the 50 cap) --

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

all_results <- list()

for (i in seq_len(nrow(states))) {
  st_fips  <- states$fips[i]
  st_name  <- states$state[i]

  series_ids <- vapply(sectors$supersector, build_series_id, character(1), fips = st_fips)

  cat(sprintf("Fetching %s...\n", st_name))
  result <- fetch_bls(series_ids, start_year, end_year, api_key)

  for (j in seq_len(nrow(result$Results$series))) {
    sid  <- result$Results$series$seriesID[j]
    data <- result$Results$series$data[[j]]

    ss   <- substr(sid, 11, 12)
    name <- sectors$sector[sectors$supersector == ss]
    if (length(name) == 0) name <- sid
    lvl  <- sectors$level[sectors$supersector == ss]
    if (length(lvl) == 0) lvl <- "supersector"

    target_val <- NA
    prior_val  <- NA

    if (!is.null(data) && nrow(data) > 0) {
      for (k in seq_len(nrow(data))) {
        yr  <- as.integer(data$year[k])
        per <- data$period[k]
        if (yr == target_year & per == target_period) target_val <- as.numeric(data$value[k])
        if (yr == prior_year  & per == prior_period)  prior_val  <- as.numeric(data$value[k])
      }
    }

    all_results[[length(all_results) + 1]] <- data.frame(
      state        = st_name,
      sector       = name,
      level        = lvl,
      target_value = target_val,
      prior_value  = prior_val,
      stringsAsFactors = FALSE
    )
  }
}

output <- do.call(rbind, all_results)
output$change <- output$target_value - output$prior_value

# ---- Display -------------------------------------------------------------------

cat(sprintf("\n%-15s %-30s %10s %10s %10s\n", "State", "Sector",
            sprintf("%s %d", month.abb[target_month], target_year),
            sprintf("%s %d", month.abb[prior_month], prior_year),
            "Change"))
cat(paste(rep("-", 90), collapse = ""), "\n")
for (i in seq_len(nrow(output))) {
  marker <- if (output$level[i] == "subsector") " *" else ""
  cat(sprintf("%-15s %-30s %10.1f %10.1f %+10.1f%s\n",
              output$state[i], output$sector[i],
              output$target_value[i], output$prior_value[i], output$change[i], marker))
}
cat("\n* subsector of \"Trade, Transp & Utilities\" — excluded from any state total\n")

for (st_name in states$state) {
  total <- sum(output$change[output$state == st_name & output$level == "supersector"])
  cat(sprintf("Total nonfarm employment change, %-14s %+.1f (thousand)\n", st_name, total))
}

# ---- Write CSV -----------------------------------------------------------------

output_file <- "state_sector_data.csv"
write.csv(output[, c("state", "sector", "level", "change")], output_file, row.names = FALSE)
cat(sprintf("\nData written to %s\n", output_file))
cat("Now run: Rscript state_sector_chart.R\n")
