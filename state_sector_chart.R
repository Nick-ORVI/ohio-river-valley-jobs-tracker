library(ggplot2)
library(ggthemes)
library(dplyr)

# ==============================================================================
# Employment change by industry — Ohio, Pennsylvania, Kentucky, West Virginia
# Each bar is a sector; each bar is divided into colored chunks, one per state.
# Source: BLS Current Employment Statistics (CES), State & Area, seasonally adjusted
#
# USAGE:
#   1. First run: Rscript fetch_state_sector_data.R   (to pull fresh data)
#   2. Then run:  Rscript state_sector_chart.R
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

# Order sectors by total (4-state) change, so the chart reads like the
# national version but grouped by state within each sector bar.
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

# Light-fill states (Kentucky gold) need dark text; others read fine in white.
label_colors <- c(
  "Ohio"           = "white",
  "Pennsylvania"   = "white",
  "Kentucky"       = "gray15",
  "West Virginia"  = "white"
)
data$label_color <- label_colors[as.character(data$state)]

# Skip labels on segments too thin to read to avoid overlap clutter.
label_min <- 0.4
data$label <- ifelse(abs(data$change) >= label_min, sprintf("%+.1f", data$change), "")

p <- ggplot(data, aes(x = sector, y = change, fill = state)) +
  geom_col(width = 0.7, position = "stack") +
  geom_hline(yintercept = 0, linewidth = 0.5, color = "white") +
  geom_text(
    aes(label = label, color = state),
    position = position_stack(vjust = 0.5),
    size = 2.6, fontface = "bold", show.legend = FALSE
  ) +
  coord_flip() +
  scale_fill_manual(values = state_colors, name = NULL) +
  scale_color_manual(values = label_colors) +
  labs(
    title = sprintf("%s %d Nonfarm Employment Change by Industry", chart_month, chart_year),
    subtitle = "Month-over-month change (thousands), seasonally adjusted - OH, PA, KY, WV",
    caption = sprintf("Source: U.S. Bureau of Labor Statistics, State & Area CES | %s %d (preliminary)",
                      chart_month, chart_year),
    x = NULL,
    y = "Employment Change (thousands)"
  ) +
  theme_economist(base_size = 12) +
  theme(
    legend.position = "top",
    legend.text = element_text(size = 10),
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 10),
    plot.caption = element_text(size = 8, hjust = 0),
    axis.text.y = element_text(size = 10),
    axis.title.x = element_text(size = 10, margin = margin(t = 8))
  )

print(p)

out_file <- sprintf("%s_%d_state_sector_chart.png", tolower(substr(chart_month, 1, 3)), chart_year)
ggsave(out_file, plot = p, width = 10, height = 6, dpi = 150)
cat(sprintf("Chart saved to %s\n", out_file))
