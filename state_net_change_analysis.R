library(dplyr)

# ==============================================================================
# State & Region Net Employment Change — Ohio, Pennsylvania, Kentucky, West Virginia
# Single-month change: calculates each state's net change (sum of supersectors,
# seasonally adjusted) for one month vs. the prior month, and the combined
# 4-state region total. This is NOT a rolling average - see
# state_sector_rolling_avg_chart.R for the 3-month trailing average version.
#
# "subsector" rows (Retail Trade, Transp & Warehousing) are already counted
# inside the "Trade, Transp & Utilities" supersector, so they're excluded here
# to avoid double-counting — same rule used in fetch_state_sector_data.R.
#
# USAGE:
#   1. First run: Rscript fetch_state_sector_data.R   (to pull fresh data)
#   2. Then run:  Rscript state_net_change_analysis.R
# ---- Settings (update these to match the month in fetch_state_sector_data.R) --

chart_month <- "May"
chart_year  <- 2026
prior_month <- "April"

data_file <- "state_sector_data.csv"
if (!file.exists(data_file)) {
  stop("Data file not found: ", data_file,
       "\nRun fetch_state_sector_data.R first to generate it.")
}
data <- read.csv(data_file, stringsAsFactors = FALSE)

state_levels <- c("Ohio", "Pennsylvania", "Kentucky", "West Virginia")

# ---- Per-state net change (supersectors only) ---------------------------------

state_totals <- data %>%
  filter(level == "supersector") %>%
  group_by(state) %>%
  summarise(net_change = sum(change, na.rm = TRUE), .groups = "drop") %>%
  mutate(state = factor(state, levels = state_levels)) %>%
  arrange(state)

# ---- Region total (sum of the 4 states) ----------------------------------------

region_total <- sum(state_totals$net_change)

# ---- Report --------------------------------------------------------------------

cat("=== State & Region Net Employment Change ===\n")
cat(sprintf("%s %d vs. %s %d (single month, not a rolling average)\n\n",
            chart_month, chart_year, prior_month, chart_year))
cat(sprintf("%-16s %12s\n", "State", "Net Change"))
cat(paste(rep("-", 30), collapse = ""), "\n")
for (i in seq_len(nrow(state_totals))) {
  cat(sprintf("%-16s %+12.1f\n", as.character(state_totals$state[i]), state_totals$net_change[i]))
}
cat(paste(rep("-", 30), collapse = ""), "\n")
cat(sprintf("%-16s %+12.1f\n", "Region Total", region_total))
cat("\n(thousands, seasonally adjusted; supersectors only, subsectors excluded)\n")

cat("\nNote: West Virginia's Government supersector swings sharply most Aprils-to-May\n")
cat("(+8.9 in 2022, +9.2 in 2024, +9.6 in 2026) but barely moves in between (+0.2 in\n")
cat("2023, +1.8 in 2025) - a sign of imperfect seasonal adjustment in this small-sample\n")
cat("series, not a genuine hiring surge. WV's state and region totals above should be\n")
cat("read with that in mind.\n")

# ---- Write summary CSV ----------------------------------------------------------

note_text <- paste(
  "WV Government swings sharply most Aprils-to-May (+8.9 in 2022, +9.2 in 2024, +9.6 in 2026)",
  "but barely moves in between (+0.2 in 2023, +1.8 in 2025) - likely imperfect seasonal",
  "adjustment in this small-sample series, not a genuine hiring surge."
)

summary_out <- rbind(
  data.frame(state = as.character(state_totals$state), net_change = state_totals$net_change),
  data.frame(state = "Region Total", net_change = region_total)
)
summary_out$note <- ifelse(summary_out$state == "West Virginia", note_text, "")
summary_out$period <- sprintf("%s %d vs. %s %d", chart_month, chart_year, prior_month, chart_year)

out_file <- "state_net_change_summary.csv"
write.csv(summary_out, out_file, row.names = FALSE)
cat(sprintf("\nSummary written to %s\n", out_file))
