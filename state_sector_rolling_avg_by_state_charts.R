library(ggplot2)
library(ggthemes)
library(dplyr)

# ==============================================================================
# 3-Month Rolling Average Employment Change by Industry — one chart per state
# (Ohio, Pennsylvania, Kentucky, West Virginia)
#
# Reuses the per-state rolling averages already computed by
# state_sector_rolling_avg_chart.R (state_sector_rolling_data.csv), instead of
# summing them across states, and plots one bar-per-sector chart per state.
#
# USAGE:
#   1. First run: Rscript state_sector_rolling_avg_chart.R
#      (this fetches the data and writes state_sector_rolling_data.csv)
#   2. Then run:  Rscript state_sector_rolling_avg_by_state_charts.R
# ==============================================================================

# ---- Settings (match state_sector_rolling_avg_chart.R) ------------------------

chart_month    <- "May"
chart_year     <- 2026
rolling_window <- 3

# ---- Read data ------------------------------------------------------------------

data_file <- "state_sector_rolling_data.csv"
if (!file.exists(data_file)) {
  stop("Data file not found: ", data_file,
       "\nRun state_sector_rolling_avg_chart.R first to generate it.")
}
data <- read.csv(data_file, stringsAsFactors = FALSE)

state_levels <- c("Ohio", "Pennsylvania", "Kentucky", "West Virginia")

source_line <- sprintf("Source: U.S. Bureau of Labor Statistics, State & Area CES | %s %d (preliminary)",
                        chart_month, chart_year)

wv_note <- paste(
  "Note: WV Government swings sharply most Aprils-to-May (+8.9 in 2022, +9.2 in 2024,",
  "+9.6 in 2026) but barely moves in between (+0.2 in 2023, +1.8 in 2025) - a sign of",
  "imperfect seasonal adjustment in this small-sample series, not a genuine hiring",
  "surge. This state's rolling average is still affected, just tempered by averaging",
  "over 3 months."
)

make_chart <- function(state_name) {

  df <- data %>% filter(state == state_name)
  df <- df[order(df$rolling_avg), ]
  df$sector <- factor(df$sector, levels = df$sector)
  df$direction <- ifelse(df$rolling_avg >= 0, "Gain", "Loss")

  caption_text <- if (state_name == "West Virginia") {
    paste0(source_line, "\n", paste(strwrap(wv_note, width = 112), collapse = "\n"))
  } else {
    source_line
  }

  p <- ggplot(df, aes(x = sector, y = rolling_avg, fill = direction)) +
    geom_col(width = 0.7) +
    geom_hline(yintercept = 0, linewidth = 0.5, color = "white") +
    geom_text(
      aes(label = sprintf("%+.1f", rolling_avg),
          hjust = ifelse(rolling_avg >= 0, -0.15, 1.15)),
      size = 3.2, color = "gray15"
    ) +
    coord_flip() +
    scale_fill_manual(values = c("Gain" = "#00a4d9", "Loss" = "#d42e12")) +
    scale_y_continuous(expand = expansion(mult = 0.18)) +
    labs(
      title = sprintf("%s: 3-Month Rolling Avg. Employment Change by Industry (through %s %d)",
                       state_name, chart_month, chart_year),
      subtitle = "Avg. monthly change over trailing 3 months (thousands), seasonally adjusted",
      caption = caption_text,
      x = NULL,
      y = "Avg. Monthly Employment Change (thousands)"
    ) +
    theme_economist(base_size = 12) +
    theme(
      legend.position = "none",
      plot.title = element_text(face = "bold", size = 13),
      plot.subtitle = element_text(size = 10),
      plot.caption = element_text(size = 7, hjust = 0, lineheight = 1.15),
      axis.text.y = element_text(size = 10),
      axis.title.x = element_text(size = 10, margin = margin(t = 8))
    )

  chart_height <- if (state_name == "West Virginia") 7.3 else 6.6

  out_file <- sprintf("%s_%d_%s_rolling_avg_chart.png",
                       tolower(substr(chart_month, 1, 3)), chart_year,
                       tolower(gsub(" ", "_", state_name)))
  ggsave(out_file, plot = p, width = 10, height = chart_height, dpi = 150)
  cat(sprintf("Chart saved to %s\n", out_file))

  p
}

plots <- lapply(state_levels, make_chart)
