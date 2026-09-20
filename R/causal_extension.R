# R/causal_extension.R
# ---------------------------------------------------------------------------
# Causal extension to the WikiPredict replication.
#
# The replication answers an associational question: does pre-release Wikipedia
# activity forecast opening revenue? This script asks a different one: among
# films that are otherwise comparable, is high pre-release activity associated
# with higher opening revenue once budget, franchise status, studio, genre and
# runtime are accounted for?
#
# Identification: selection on observables.
#   D = 1 if cumulative page views at t = -30 are above the sample median
#   Y = log(opening weekend revenue)
#   X = log budget, franchise flag, major-studio flag, runtime, genre, month
#
# The estimand is the ATT under conditional ignorability, which the data cannot
# verify. Step 6 therefore reports an E-value: how strong an unmeasured
# confounder (marketing spend being the obvious one) would have to be to move
# the estimate to null.
#
# Theater count is deliberately EXCLUDED from X. Studios set opening theater
# count partly in response to pre-release buzz, which makes it a mediator on the
# pathway being estimated rather than a confounder. It appears only in step 7.
#
# Usage:
#   Rscript packages.R
#   export TMDB_API_KEY="..."
#   export WIKIPREDICT_DIR="data"      # optional, defaults to data/
#   Rscript R/causal_extension.R
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr); library(httr); library(jsonlite)
  library(MatchIt); library(cobalt); library(EValue); library(ggplot2)
})

base_dir <- Sys.getenv("WIKIPREDICT_DIR", "data")
out_dir  <- file.path("output", "causal")
tmdb_key <- Sys.getenv("TMDB_API_KEY")
horizon  <- -30
set.seed(2026)

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
if (!nzchar(tmdb_key)) stop("TMDB_API_KEY is not set. See README.")
if (!dir.exists(base_dir)) stop("Dataset directory not found: ", base_dir)

# --- helpers ---------------------------------------------------------------

find_col <- function(df, candidates) {
  nm <- tolower(names(df))
  hit <- which(nm %in% tolower(candidates))
  if (!length(hit)) NA_character_ else names(df)[hit[1]]
}

require_col <- function(df, candidates, what, where) {
  col <- find_col(df, candidates)
  if (is.na(col)) {
    stop(sprintf("Could not find a %s column in %s.\n  Looked for: %s\n  Found: %s",
                 what, where, paste(candidates, collapse = ", "),
                 paste(names(df), collapse = ", ")), call. = FALSE)
  }
  col
}

# --- 1. Load the 312-film sample -------------------------------------------

meta_path <- file.path(base_dir, "sample_of_312", "sample_of_312")
if (!file.exists(meta_path)) stop("Metadata file not found: ", meta_path)

movies_raw <- read.delim(meta_path, stringsAsFactors = FALSE, check.names = TRUE)

id_col       <- require_col(movies_raw, c("movie_id", "id", "movieid"), "movie id", meta_path)
title_col    <- require_col(movies_raw, c("title", "name", "movie", "movie_title"), "title", meta_path)
revenue_col  <- require_col(movies_raw, c("revenue", "opening_weekend", "gross",
                                          "opening_revenue", "box_office",
                                          "first_weekend_revenue_usd"), "revenue", meta_path)
theaters_col <- find_col(movies_raw, c("theaters", "n_theaters", "screens", "theatres",
                                      "number_of.theaters"))

movies <- movies_raw %>%
  transmute(
    movie_id = .data[[id_col]],
    title    = .data[[title_col]],
    revenue  = suppressWarnings(as.numeric(.data[[revenue_col]])),
    theaters = if (is.na(theaters_col)) NA_real_
               else suppressWarnings(as.numeric(.data[[theaters_col]]))
  )

# --- 2. Cumulative page views at the horizon -------------------------------

pred_dir <- file.path(base_dir, "sample_of_312", "wikipedia_predictors")
if (!dir.exists(pred_dir)) stop("Predictor directory not found: ", pred_dir)

time_names  <- c("t", "day", "days_to_release", "movie_time", "time", "days",
                 "day_.movie_time.")
views_names <- c("v", "views", "pageviews", "page_views", "movie_views")

views_at_horizon <- function(movie_id) {
  f <- file.path(pred_dir, as.character(movie_id))
  if (!file.exists(f)) return(NA_real_)
  s <- tryCatch(read.delim(f, stringsAsFactors = FALSE, check.names = TRUE),
                error = function(e) NULL)
  if (is.null(s) || !nrow(s)) return(NA_real_)

  tcol <- find_col(s, time_names)
  vcol <- find_col(s, views_names)
  # Fall back to position, which is what the replication notebook relies on.
  if (is.na(tcol) && ncol(s) >= 1) tcol <- names(s)[1]
  if (is.na(vcol) && ncol(s) >= 2) vcol <- names(s)[2]
  if (is.na(tcol) || is.na(vcol)) return(NA_real_)

  tv <- suppressWarnings(as.numeric(s[[tcol]]))
  vv <- suppressWarnings(as.numeric(s[[vcol]]))
  ok <- !is.na(tv) & !is.na(vv)
  if (!any(ok)) return(NA_real_)
  vv[ok][which.min(abs(tv[ok] - horizon))]
}

movies$views_h <- vapply(movies$movie_id, views_at_horizon, numeric(1))
message(sprintf("Page views at t=%d recovered for %d of %d films.",
                horizon, sum(!is.na(movies$views_h)), nrow(movies)))

# --- 3. Confounders from TMDb ----------------------------------------------

tmdb_lookup <- function(title) {
  Sys.sleep(0.3)
  empty <- data.frame(title = title, budget = NA_real_, runtime = NA_real_,
                      franchise = NA_integer_, genre = NA_character_,
                      release_month = NA_integer_, studio = NA_character_,
                      stringsAsFactors = FALSE)

  search <- tryCatch(GET("https://api.themoviedb.org/3/search/movie",
                         query = list(api_key = tmdb_key, query = title)),
                     error = function(e) NULL)
  if (is.null(search) || status_code(search) != 200) return(empty)
  hits <- content(search, as = "parsed", simplifyVector = TRUE)$results
  if (is.null(hits) || !length(hits) || !nrow(hits)) return(empty)

  detail <- tryCatch(GET(sprintf("https://api.themoviedb.org/3/movie/%s", hits$id[1]),
                         query = list(api_key = tmdb_key)),
                     error = function(e) NULL)
  if (is.null(detail) || status_code(detail) != 200) return(empty)
  d <- content(detail, as = "parsed", simplifyVector = TRUE)

  month <- suppressWarnings(as.integer(format(as.Date(d$release_date), "%m")))

  data.frame(
    title         = title,
    budget        = if (is.null(d$budget) || identical(d$budget, 0)) NA_real_ else as.numeric(d$budget),
    runtime       = if (is.null(d$runtime)) NA_real_ else as.numeric(d$runtime),
    franchise     = as.integer(!is.null(d$belongs_to_collection)),
    genre         = if (!is.null(d$genres) && length(d$genres$name)) d$genres$name[1] else NA_character_,
    release_month = if (length(month)) month else NA_integer_,
    studio        = if (!is.null(d$production_companies) && length(d$production_companies$name))
                      d$production_companies$name[1] else NA_character_,
    stringsAsFactors = FALSE
  )
}

cache <- file.path(out_dir, "tmdb_metadata.csv")
if (file.exists(cache)) {
  tmdb <- read.csv(cache, stringsAsFactors = FALSE)
  message("Using cached TMDb metadata (", nrow(tmdb), " rows). Delete ", cache, " to refetch.")
} else {
  message("Fetching TMDb metadata for ", nrow(movies), " films. Takes a few minutes.")
  tmdb <- bind_rows(lapply(movies$title, tmdb_lookup))
  write.csv(tmdb, cache, row.names = FALSE)
}

# --- 4. Analysis frame ------------------------------------------------------

majors <- c("Warner Bros", "Universal", "Paramount", "Twentieth Century Fox",
            "Walt Disney", "Columbia", "Sony", "Metro-Goldwyn-Mayer", "Lionsgate",
            "New Line", "DreamWorks")

df <- movies %>%
  inner_join(tmdb, by = "title") %>%
  filter(!is.na(views_h), !is.na(budget), !is.na(revenue), revenue > 0, budget > 0) %>%
  mutate(
    D             = as.integer(views_h > median(views_h, na.rm = TRUE)),
    Y             = log(revenue),
    log_budget    = log(budget),
    runtime       = ifelse(is.na(runtime), median(runtime, na.rm = TRUE), runtime),
    genre         = ifelse(is.na(genre), "Other", genre),
    studio_major  = as.integer(!is.na(studio) &
                      grepl(paste(majors, collapse = "|"), studio, ignore.case = TRUE)),
    franchise     = ifelse(is.na(franchise), 0L, franchise),
    release_month = factor(ifelse(is.na(release_month), 0L, release_month))
  ) %>%
  group_by(genre) %>%
  mutate(genre = if (n() < 5) "Other" else genre) %>%
  ungroup() %>%
  mutate(genre = factor(genre))

message(sprintf("Analysis sample: %d films (%d treated, %d control).",
                nrow(df), sum(df$D), sum(1 - df$D)))
if (nrow(df) < 80)
  warning("Small sample. TMDb budget coverage is the usual cause; inspect tmdb_metadata.csv.")

# --- 5. Naive, adjusted, and matched estimates -----------------------------

naive <- lm(Y ~ D, data = df)
adj   <- lm(Y ~ D + log_budget + franchise + studio_major + runtime + genre + release_month,
            data = df)

m.out <- matchit(D ~ log_budget + franchise + studio_major + runtime + genre,
                 data = df, method = "nearest", distance = "glm",
                 caliper = 0.2, std.caliper = TRUE, replace = FALSE)

balance <- bal.tab(m.out, un = TRUE, binary = "std", thresholds = c(m = 0.1))
print(balance)
write.csv(balance$Balance, file.path(out_dir, "covariate_balance.csv"))
covariate_smd <- balance$Balance$Diff.Adj[balance$Balance$Type != "Distance"]
ggsave(file.path(out_dir, "love_plot.png"),
       love.plot(m.out, binary = "std", thresholds = c(m = 0.1)),
       width = 7, height = 5, dpi = 150, bg = "white")

matched <- match.data(m.out)
att_fit <- lm(Y ~ D + log_budget + franchise + studio_major + runtime,
              data = matched, weights = weights)

att_row <- summary(att_fit)$coefficients["D", ]
att     <- unname(att_row[1])
att_se  <- unname(att_row[2])
pval    <- unname(att_row[4])
ci      <- att + c(-1.96, 1.96) * att_se
pct     <- (exp(att) - 1) * 100

# --- 6. Sensitivity to unmeasured confounding ------------------------------

ev <- evalues.OLS(est = att, se = att_se, sd = sd(matched$Y), delta = 1, true = 0)
print(ev)
ev_point <- ev["E-values", "point"]
ev_ci    <- if (!is.na(ev["E-values", "lower"])) ev["E-values", "lower"] else ev["E-values", "upper"]

# --- 7. Robustness ---------------------------------------------------------

rob_continuous <- lm(Y ~ log1p(views_h) + log_budget + franchise + studio_major +
                       runtime + genre, data = df)

q  <- quantile(df$views_h, c(1/3, 2/3), na.rm = TRUE)
d2 <- df %>% filter(views_h <= q[1] | views_h >= q[2]) %>%
  mutate(D = as.integer(views_h >= q[2]))
rob_terciles <- lm(Y ~ D + log_budget + franchise + studio_major + runtime + genre, data = d2)

rob_theaters <- if (all(is.na(matched$theaters))) NULL else
  lm(Y ~ D + log_budget + franchise + studio_major + runtime + log1p(theaters),
     data = matched, weights = matched$weights)

rob_line <- function(fit, term) {
  if (is.null(fit)) return("not available (no theater column in dataset)")
  cf <- summary(fit)$coefficients[term, ]
  sprintf("%.3f (SE %.3f, p %s)", cf[1], cf[2],
          if (cf[4] < 0.0001) "< 0.0001" else sprintf("= %.4f", cf[4]))
}

# --- 8. Report -------------------------------------------------------------

report <- sprintf(
"CAUSAL EXTENSION RESULTS
========================
Treatment          : cumulative Wikipedia page views at t = %d above sample median
Outcome            : log(opening weekend revenue)
Sample             : %d films (%d treated, %d control)
Matched sample     : %d films (%d treated, %d control)
Excluded before analysis: %d of %d films
Treated retained by matching: %.1f%%
Maximum absolute covariate SMD after matching: %.3f
Covariate indicators above |SMD| = 0.1: %d

Naive difference   : %.3f log points (%.1f%%)
Regression-adjusted: %.3f log points
Matched ATT        : %.3f log points (%.1f%%)
95%% CI             : [%.3f, %.3f]
p-value            : %.4f

E-value (estimate) : %.2f
E-value (CI limit) : %.2f

Robustness
  Continuous treatment (log views): %s
  Top vs bottom tercile           : %s
  Adding theaters (mediator)      : %s

Reading: an unmeasured confounder would need associations of at least %.2f with
both treatment and outcome, beyond the measured covariates, to move this estimate
to null. Marketing spend is the obvious candidate and is absent from the data, so
this is a bounded association under selection on observables, not a randomized
causal effect.
",
  horizon, nrow(df), sum(df$D), sum(1 - df$D), nrow(matched),
  sum(matched$D), sum(1 - matched$D), nrow(movies) - nrow(df), nrow(movies),
  100 * sum(matched$D) / sum(df$D),
  max(abs(covariate_smd), na.rm = TRUE),
  sum(abs(covariate_smd) > 0.1, na.rm = TRUE),
  coef(naive)["D"], (exp(coef(naive)["D"]) - 1) * 100,
  coef(adj)["D"],
  att, pct, ci[1], ci[2], pval,
  ev_point, ev_ci,
  rob_line(rob_continuous, "log1p(views_h)"),
  rob_line(rob_terciles, "D"),
  rob_line(rob_theaters, "D"),
  ev_point
)

cat(report)
writeLines(report, file.path(out_dir, "causal_results.txt"))
writeLines(capture.output(sessionInfo()), file.path(out_dir, "session_info.txt"))
message("Wrote ", file.path(out_dir, "causal_results.txt"))
