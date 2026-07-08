library(httr)
library(jsonlite)
library(ggplot2)
library(ggthemes)
library(dplyr)

# ==============================================================================
# 3-Month Rolling Average Employment Change by Industry — OH + PA + KY + WV
#
# For each state and sector: pull monthly employment levels, compute the
# month-over-month change for each of the trailing `rolling_window` months,
# and average those changes (a 3-month rolling average of the monthly change).
# Then sum that rolling average across the 4 states for each sector, and plot
# one bar per sector.
#
# Averaging over 3 months tempers (but does not eliminate) one-off seasonal-
# adjustment noise like West Virginia's alternating-year Government swings
# (see state_net_change_analysis.R) — a single anomalous month still moves
# the average, just by 1/3 as much instead of the full amount.
#
# USAGE: Rscript state_sector_rolling_avg_chart.R
# ==============================================================================

# ---- Settings -----------------------------------------------------------------

api_key        <- Sys.getenv("BLS_API_KEY")
if (api_key == "") stop("BLS_API_KEY environment variable is not set. See README.md.")
target_year    <- 2026
target_month   <- 5     # most recent month with state-level data available
rolling_window <- 3     # number of month-over-month changes to average

chart_month <- month.name[target_month]
chart_year  <- target_year

# ---- States and sectors --------------------------------------------------------

states <- data.frame(
  fips  = c("39", "42", "21", "54"),
  state = c("Ohio", "Pennsylvania", "Kentucky", "West Virginia"),
  stringsAsFactors = FALSE
)

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
  # "supersector" rows sum to total nonfarm employment; "subsector" rows
  # (Retail Trade, Transp & Warehousing) are already included inside
  # "Trade, Transp & Utilities" and are excluded from the chart to avoid
  # double-counting.
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

# ---- Work out which (year, month) pairs are needed ------------------------------
# `rolling_window` monthly changes require rolling_window + 1 consecutive
# monthly levels, ending at target_month.

months_needed <- rolling_window + 1
target_idx    <- target_year * 12 + (target_month - 1)
month_idxs    <- seq(target_idx - months_needed + 1, target_idx)   # oldest -> newest
needed_months <- data.frame(
  year   = month_idxs %/% 12,
  month  = month_idxs %% 12 + 1
)
needed_months$period <- sprintf("M%02d", needed_months$month)

start_year <- min(needed_months$year)
end_year   <- max(needed_months$year)

cat("=== 3-Month Rolling Average Employment Change (OH, PA, KY, WV) ===\n")
cat(sprintf("Target month : %s %d\n", chart_month, chart_year))
cat(sprintf("Rolling window: trailing %d monthly changes (%s %d - %s %d)\n\n",
            rolling_window,
            month.name[needed_months$month[1]], needed_months$year[1],
            month.name[needed_months$month[nrow(needed_months)]], needed_months$year[nrow(needed_months)]))

# ---- Fetch monthly levels, one BLS API request per state -----------------------

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

rows <- list()

for (i in seq_len(nrow(states))) {
  st_fips <- states$fips[i]
  st_name <- states$state[i]

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

    values <- rep(NA_real_, nrow(needed_months))
    if (!is.null(data) && length(data) > 0 && nrow(data) > 0) {
      for (k in seq_len(nrow(data))) {
        yr  <- as.integer(data$year[k])
        per <- data$period[k]
        m   <- which(needed_months$year == yr & needed_months$period == per)
        if (length(m) == 1) values[m] <- as.numeric(data$value[k])
      }
    }

    monthly_changes <- diff(values)              # rolling_window changes, oldest -> newest
    rolling_avg     <- mean(monthly_changes, na.rm = TRUE)

    rows[[length(rows) + 1]] <- data.frame(
      state       = st_name,
      sector      = name,
      level       = lvl,
      rolling_avg = rolling_avg,
      stringsAsFactors = FALSE
    )
  }
}

state_data <- do.call(rbind, rows)

out_data_file <- "state_sector_rolling_data.csv"
write.csv(state_data, out_data_file, row.names = FALSE)
cat(sprintf("\nPer-state rolling averages written to %s\n", out_data_file))

# ---- Sum the 4 states' rolling averages for each sector -------------------------

sector_totals <- state_data %>%
  group_by(sector, level) %>%
  summarise(rolling_avg = sum(rolling_avg, na.rm = TRUE), .groups = "drop") %>%
  arrange(rolling_avg)

sector_totals$sector <- factor(sector_totals$sector, levels = sector_totals$sector)
sector_totals$direction <- ifelse(sector_totals$rolling_avg >= 0, "Gain", "Loss")

cat(sprintf("\n%-30s %15s\n", "Sector", "3-Mo Avg Change"))
cat(paste(rep("-", 46), collapse = ""), "\n")
for (i in seq_len(nrow(sector_totals))) {
  marker <- if (sector_totals$level[i] == "subsector") " *" else ""
  cat(sprintf("%-30s %+15.2f%s\n", sector_totals$sector[i], sector_totals$rolling_avg[i], marker))
}
cat("\n* subsector of \"Trade, Transp & Utilities\" — excluded from any total\n")

# ---- Plot -----------------------------------------------------------------------

p <- ggplot(sector_totals, aes(x = sector, y = rolling_avg, fill = direction)) +
  geom_col(width = 0.7) +
  geom_hline(yintercept = 0, linewidth = 0.5, color = "white") +
  geom_text(
    aes(label = sprintf("%+.1f", rolling_avg),
        hjust = ifelse(rolling_avg >= 0, -0.15, 1.15)),
    size = 3.2, color = "gray15"
  ) +
  coord_flip() +
  scale_fill_manual(values = c("Gain" = "#00a4d9", "Loss" = "#d42e12")) +
  scale_y_continuous(expand = expansion(mult = 0.15)) +
  labs(
    title = sprintf("3-Month Rolling Avg. Employment Change by Industry (through %s %d)",
                     chart_month, chart_year),
    subtitle = "Avg. monthly change over trailing 3 months (thousands), seasonally adjusted - sum of OH, PA, KY, WV",
    caption = paste0(
      sprintf("Source: U.S. Bureau of Labor Statistics, State & Area CES | %s %d (preliminary)\n",
              chart_month, chart_year),
      paste(strwrap(
        paste("Note: averaging over 3 months tempers but does not remove one-off seasonal-adjustment",
              "noise, such as West Virginia's alternating-year Government swings (see",
              "state_net_change_analysis.R) - a single anomalous month still shifts the average by",
              "about a third of its size."),
        width = 112), collapse = "\n")
    ),
    x = NULL,
    y = "Avg. Monthly Employment Change (thousands)"
  ) +
  theme_economist(base_size = 12) +
  theme(
    legend.position = "none",
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 10),
    plot.caption = element_text(size = 7, hjust = 0, lineheight = 1.15),
    axis.text.y = element_text(size = 10),
    axis.title.x = element_text(size = 10, margin = margin(t = 8))
  )

print(p)

out_file <- sprintf("%s_%d_state_sector_rolling_avg_chart.png", tolower(substr(chart_month, 1, 3)), chart_year)
ggsave(out_file, plot = p, width = 10, height = 7.1, dpi = 150)
cat(sprintf("\nChart saved to %s\n", out_file))
