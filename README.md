# Ohio River Valley Jobs Tracker — Update Guide

This folder contains everything for the "Ohio River Valley Jobs Tracker" dashboard
(`index.qmd` → `index.html`), covering Ohio, Pennsylvania, Kentucky, and West
Virginia employment data from the BLS Current Employment Statistics (CES),
State & Area program.

This README explains, step by step, how to refresh the dashboard when a new
month of BLS data drops.

---

## 1. How the pieces fit together

```
BLS API (api.bls.gov)
   │
   ├─ fetch_state_sector_data.R        →  state_sector_data.csv            (single month vs. prior month)
   ├─ fetch_state_sector_ytd_data.R    →  state_sector_ytd_data.csv        (December baseline vs. target month)
   ├─ state_sector_rolling_avg_chart.R →  state_sector_rolling_data.csv    (3-month trailing average per state)
   └─ fetch_ytd_growth_vs_national.R   →  state_ytd_growth_vs_national.csv (state YTD % growth minus national YTD % growth)

state_sector_data.csv
   └─ state_net_change_analysis.R    →  state_net_change_summary.csv

state_sector_data.csv + state_sector_rolling_data.csv + state_sector_ytd_data.csv
+ state_net_change_summary.csv + state_ytd_growth_vs_national.csv
   └─ index.qmd  (reads all 5 CSVs directly)  →  quarto render  →  index.html  (the dashboard)
```

**The dashboard (`index.qmd`) only reads from the 5 CSVs above.** It does not
call the BLS API itself and does not re-run any R script automatically. So the
monthly workflow is: (1) refresh the CSVs by running the fetch/analysis
scripts, (2) update two settings in `index.qmd`, (3) re-render.

The other four scripts (`state_sector_chart.R`, `state_sector_chart_clustered.R`,
`state_sector_rolling_avg_by_state_charts.R`, and the PNGs they produce) are
**optional, standalone chart generators** — they make static PNG versions of
the charts for sharing outside the dashboard. They are not required for
`index.qmd` to work, but update them too if you want fresh static images.

---

## 2. Before you start: check state data availability

State-level CES data is released a few weeks **after** the national jobs
report for the same month. When picking a target month, confirm BLS has
already published state data for it — otherwise the fetch scripts will
return `NA` values for that month (this happened when June 2026 was chosen
before state data existed; May 2026 had to be used instead). If a script's
console output shows `NA` for the target month, drop back one month.

---

## 3. Step-by-step monthly update

### Step A — Update settings and run the 3 data-refresh scripts

Each script has a `target_year` / `target_month` (or `chart_year` /
`chart_month`) block near the top. Update these to the new month, then run
the script from this folder:

1. **`fetch_state_sector_data.R`** — lines 22–23 (`target_year`, `target_month`).
   ```
   Rscript fetch_state_sector_data.R
   ```
   Produces `state_sector_data.csv` (current month vs. prior month, by
   state and sector).

2. **`fetch_state_sector_ytd_data.R`** — lines 26–27 (`target_year`,
   `target_month`). The December baseline year is computed automatically
   (`target_year - 1`), so you only ever need to change these two lines,
   even across a calendar-year boundary.
   ```
   Rscript fetch_state_sector_ytd_data.R
   ```
   Produces `state_sector_ytd_data.csv` (December baseline vs. target month).

3. **`state_sector_rolling_avg_chart.R`** — lines 27–29 (`target_year`,
   `target_month`, `rolling_window`). Leave `rolling_window` at `3` unless
   you intentionally want a different trailing average window.
   ```
   Rscript state_sector_rolling_avg_chart.R
   ```
   Produces `state_sector_rolling_data.csv` (3-month trailing average, by
   state and sector) plus its own standalone PNG.

4. **`fetch_ytd_growth_vs_national.R`** — lines 26–27 (`target_year`,
   `target_month`). Should match `fetch_state_sector_ytd_data.R` (step A.2),
   since both compute the same December-baseline-to-target-month window.
   ```
   Rscript fetch_ytd_growth_vs_national.R
   ```
   Produces `state_ytd_growth_vs_national.csv` — each state's YTD total
   nonfarm growth rate (%), the national YTD growth rate (%), and the
   difference in percentage points (state minus national). This drives the
   green/red "YTD growth vs. U.S." value boxes on the Year to Date tab.

### Step B — Run the net-change analysis

**`state_net_change_analysis.R`** — lines 19–21 (`chart_month`, `chart_year`,
`prior_month`). This must match what you used in `fetch_state_sector_data.R`
(step A.1), since it reads `state_sector_data.csv`.
```
Rscript state_net_change_analysis.R
```
Produces `state_net_change_summary.csv` (each state's net change + region
total + the West Virginia caveat note).

### Step C — Update the two settings at the top of `index.qmd`

Every date label on every tab (Current Month, 3-Month Rolling Avg. by
Industry, Year to Date) is now derived from two variables in the setup
chunk near the top of `index.qmd`:

```r
chart_month_num <- 5      # 1 = January, 2 = February, ... 12 = December
chart_year      <- 2026
```

Update just these two lines. The prior month (for the single-month
comparison behind the value boxes on the Current Month tab) and the
year-to-date baseline (December of the prior calendar year, for the "Year
to Date" tab) are both computed automatically from
them — including correctly rolling back to December of the previous year if
you ever set `chart_month_num <- 1`. Every card title and footnote that
mentions a month or year (`!expr sprintf(...)` in the chunk title options,
or plain `sprintf()` calls in the Year to Date footnote) pulls from these
same two variables, so nothing else in `index.qmd` needs manual editing for
a routine monthly update.

**Special annual note:** the West Virginia seasonal-adjustment footnote
(in `index.qmd`'s Current Month and Year to Date tabs, and in
`state_net_change_analysis.R`) lists specific past Aprils-to-May swings
(2022, 2024, ... 2026) as static
text — this is intentionally *not* derived from `chart_month_num`/
`chart_year`, since the quirk is specifically about April→May transitions
regardless of what month the dashboard currently targets. It only needs a
manual update once a year, when a new April→May transition happens — append
the new year's swing rather than replacing old ones, so the pattern stays
visible. Search for "Aprils-to-May" in both files to find it.

### Step D — Re-render the dashboard

```
quarto render index.qmd
```

This regenerates `index.html` and the `index_files/` folder. Quarto CLI was
installed without admin rights to `~/.local/quarto` (symlinked at
`~/.local/bin/quarto`); if `quarto` isn't found, add it to your PATH first:
```
export PATH="$HOME/.local/bin:$PATH"
```

### Step E — Preview / sanity check

Open `index.html` directly in a browser, or serve it locally:
```
python3 -m http.server 4173 --directory .
```
Then visit `http://localhost:4173/index.html` and click through all 3 tabs
(Current Month, 3-Month Rolling Avg. by Industry, Year to Date) to confirm
the numbers and titles reflect the new month.

### Step F (optional) — Refresh the standalone static PNGs

Only needed if you distribute the individual chart images outside the
dashboard. Update `chart_month`/`chart_year` (and `target_year`/
`target_month` where applicable) at the top of each, then run:
```
Rscript state_sector_chart.R
Rscript state_sector_chart_clustered.R
Rscript state_sector_rolling_avg_by_state_charts.R
```

---

## 4. Quick reference: run order for a routine month

```
Rscript fetch_state_sector_data.R
Rscript fetch_state_sector_ytd_data.R
Rscript state_sector_rolling_avg_chart.R
Rscript fetch_ytd_growth_vs_national.R
Rscript state_net_change_analysis.R
# then update chart_month_num / chart_year in index.qmd (see Step C)
quarto render index.qmd
```

---

## 5. File reference

| File | Type | Purpose |
|---|---|---|
| `fetch_state_sector_data.R` | script | Pulls current-month vs. prior-month state/sector data → `state_sector_data.csv` |
| `fetch_state_sector_ytd_data.R` | script | Pulls December-baseline vs. target-month data → `state_sector_ytd_data.csv` |
| `state_sector_rolling_avg_chart.R` | script | Pulls monthly levels, computes 3-month rolling average → `state_sector_rolling_data.csv` (+ standalone PNG) |
| `fetch_ytd_growth_vs_national.R` | script | Pulls state + national total-nonfarm levels, computes YTD % growth and state-minus-national gap → `state_ytd_growth_vs_national.csv` |
| `state_net_change_analysis.R` | script | Reads `state_sector_data.csv`, computes per-state + region totals → `state_net_change_summary.csv` (drives the net-change value boxes on the Current Month tab) |
| `state_sector_chart.R` | script (optional) | Standalone stacked-bar PNG, current month |
| `state_sector_chart_clustered.R` | script (optional) | Standalone clustered-bar PNG, current month, with per-sector totals |
| `state_sector_rolling_avg_by_state_charts.R` | script (optional) | Standalone rolling-average PNGs, one per state |
| `state_sector_data.csv` | data | Current month change, by state and sector |
| `state_sector_ytd_data.csv` | data | Year-to-date cumulative change, by state and sector |
| `state_sector_rolling_data.csv` | data | 3-month rolling average change, by state and sector |
| `state_net_change_summary.csv` | data | Per-state and region net change totals + WV caveat note (shown as value boxes + footnote on the Current Month tab) |
| `state_ytd_growth_vs_national.csv` | data | Per-state YTD % growth, national YTD % growth, and the difference in percentage points |
| `index.qmd` | dashboard source | Quarto dashboard — reads the 5 CSVs above, builds all 3 tabs |
| `index.html` / `index_files/` | dashboard output | Rendered static site (regenerate with `quarto render index.qmd`) |

---

## 6. Known quirk worth remembering

West Virginia's "Government" sector shows a large, recurring April→May spike
in the *seasonally adjusted* series that reverses the following month. This
has been confirmed as a small-sample seasonal-adjustment artifact, not real
hiring (see the footnote on the Current Month and Year to Date tabs). It
will keep showing up every year around the same time — that's expected, not
a bug in these scripts. It also inflates West Virginia's "YTD growth vs.
U.S." value box on the Year to Date tab (a small state's total nonfarm base
means one oversized sector swing moves the whole percentage a lot), which is
why that box's footnote calls it out specifically.
