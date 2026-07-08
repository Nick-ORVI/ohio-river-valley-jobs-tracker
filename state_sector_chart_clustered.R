library(ggplot2)
library(ggthemes)
library(dplyr)

# ==============================================================================
# Employment change by industry — Ohio, Pennsylvania, Kentucky, West Virginia
# Industry on the y-axis; 4 dodged bars per industry, one per state,
# with a single total (4-state sum) labeled past the end of each group.
# Source: BLS Current Employment Statistics (CES), State & Area, seasonally adjusted
#
# USAGE:
#   1. First run: Rscript fetch_state_sector_data.R   (to pull fresh data)
#   2. Then run:  Rscript state_sector_chart_clustered.R
# ---- Settings (update these to match the month in fetch_state_sector_data.R) --

chart_month <- "May"
chart_year  <- 2026

# ---- Read data ---------------------------------------------------------------

data_file <- "state_sector_data.csv"
if (!file.exists(data_file)) {
  stop("Data file not found: ", data_file,
       "\nRun fetch_state_sector_data.R first to generate it.")
}
data <- read.csv(data_file, stringsAsFactors = FALSE)

state_levels <- c("Ohio", "Pennsylvania", "Kentucky", "West Virginia")
data$state <- factor(data$state, levels = state_levels)

# Order sectors by total (4-state) change, ascending left to right.
sector_order <- data %>%
  group_by(sector) %>%
  summarise(total = sum(change, na.rm = TRUE)) %>%
  arrange(total) %>%
  pull(sector)

data$sector <- factor(data$sector, levels = sector_order)

state_colors <- c(
  "Ohio"           = "#00a4d9",
  "Pennsylvania"   = "#d42e12",
  "Kentucky"       = "#f2af00",
  "West Virginia"  = "#3d3d3d"
)

# One total per sector (sum across the 4 states), placed just past the
# extreme edge of that sector's bar group, in the direction of the total's sign.
pad <- 0.4
totals <- data %>%
  group_by(sector) %>%
  summarise(
    total   = sum(change, na.rm = TRUE),
    max_val = max(change, na.rm = TRUE),
    min_val = min(change, na.rm = TRUE)
  ) %>%
  mutate(
    label_pos = ifelse(total >= 0, max_val + pad, min_val - pad),
    label     = sprintf("%+.1f", total)
  )

p <- ggplot(data, aes(x = sector, y = change, fill = state)) +
  geom_col(width = 0.8, position = position_dodge2(width = 0.9, padding = 0.1)) +
  geom_hline(yintercept = 0, linewidth = 0.5, color = "gray30") +
  geom_text(
    data = totals,
    aes(x = sector, y = label_pos, label = label,
        hjust = ifelse(total >= 0, 0, 1)),
    inherit.aes = FALSE, size = 3, fontface = "bold", color = "gray15"
  ) +
  coord_flip() +
  scale_fill_manual(values = state_colors, name = NULL) +
  scale_y_continuous(expand = expansion(mult = 0.14)) +
  labs(
    title = sprintf("%s %d Nonfarm Employment Change by Industry", chart_month, chart_year),
    subtitle = "Month-over-month change (thousands), seasonally adjusted - OH, PA, KY, WV",
    caption = paste0(
      sprintf("Source: U.S. Bureau of Labor Statistics, State & Area CES | %s %d (preliminary)\n",
              chart_month, chart_year),
      paste(strwrap(
        paste("Note: WV Government swings sharply most Aprils-to-May (+8.9 in 2022, +9.2 in 2024,",
              "+9.6 in 2026) but barely moves in between (+0.2 in 2023, +1.8 in 2025) - a sign of",
              "imperfect seasonal adjustment in this small-sample series, not a genuine hiring surge."),
        width = 112), collapse = "\n")
    ),
    x = NULL,
    y = "Employment Change (thousands)"
  ) +
  theme_economist(base_size = 12) +
  theme(
    legend.position = "top",
    legend.text = element_text(size = 10),
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 10),
    plot.caption = element_text(size = 7, hjust = 0, lineheight = 1.15),
    axis.text.y = element_text(size = 10),
    axis.title.x = element_text(size = 10, margin = margin(t = 8))
  )

print(p)

out_file <- sprintf("%s_%d_state_sector_chart_clustered.png", tolower(substr(chart_month, 1, 3)), chart_year)
ggsave(out_file, plot = p, width = 10, height = 7.1, dpi = 150)
cat(sprintf("Chart saved to %s\n", out_file))
