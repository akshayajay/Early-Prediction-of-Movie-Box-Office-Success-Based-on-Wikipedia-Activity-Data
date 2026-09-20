# causal_extension.R
# ---------------------------------------------------------------------------
# Causal extension to the WikiPredict replication.
#
# Research question:
#   The predictive model answers "does pre-release Wikipedia activity forecast
#   opening revenue?" That is associational. This script asks a different
#   question: "for films that are otherwise comparable, does high pre-release
#   Wikipedia activity correspond to higher opening revenue?"
#
# Identification strategy: selection on observables.
#   Treatment  D = 1 if cumulative page views at t = -30 are above the median.
#   Outcome    Y = log(opening weekend revenue).
#   Confounders X = log budget, franchise membership, primary genre, runtime,
#                   release month, studio tier.
#
#   The estimand is the ATT under conditional ignorability. This assumption is
#   NOT verifiable from the data. That is why step 6 runs a sensitivity
#   analysis: it reports how strong an unmeasured confounder (marketing spend
#   is the obvious one) would have to be to explain the estimate away.
#
# Note on theaters: opening-weekend theater count is EXCLUDED from X. Studios
#   set theater count partly in response to pre-release buzz, which makes it a
#   mediator, not a confounder. Conditioning on it would block part of the very
#   pathway being estimated. It is kept only as a robustness check in step 7.
#
# Usage:
#   export TMDB_API_KEY=...        # https://www.themoviedb.org/settings/api
#   Rscript R/causal_extension.R
#
# Dependencies: MatchIt, EValue, cobalt, httr, jsonlite, dplyr, ggplot2
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr); library(httr); library(jsonlite)
  library(MatchIt); library(cobalt); library(EValue); library(ggplot2)
})

base_dir  <- Sys.getenv("WIKIPREDICT_DIR", "data")
out_dir   <- "output/causal"
tmdb_key  <- Sys.getenv("TMDB_API_KEY")
horizon   <- -30          # days before release at which treatment is measured
set.seed(2026)

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
if (identical(tmdb_key, "")) stop("Set TMDB_API_KEY before running.")

# --- 1. Load the 312-film sample and the Wikipedia predictor series ---------

meta_path <- file.path(base_dir, "sample_of_312", "sample_of_312")
movies <- read.delim(meta_path, stringsAsFactors = FALSE)
names(movies) <- tolower(names(movies))

# Expected columns: movie_id, title, release_date (or year), revenue, theaters.
# Rename defensively so downstream code does not depend on exact header text.
pick <- function(df, candidates) {
  hit <- intersect(candidates, names(df))
  if (!length(hit)) stop("None of these columns found: ", paste(candidates, collapse = ", "))
  hit[1]
}
movies <- movies %>%
  rename(
    movie_id = !!pick(., c("movie_id", "id")),
    title    = !!pick(., c("title", "name", "movie")),
    revenue  = !!pick(., c("revenue", "opening_weekend", "gross")),
    theaters = !!pick(., c("theaters", "n_theaters", "screens"))
  )

# Cumulative page views at the horizon, one predictor file per movie.
views_at_horizon <- function(movie_id) {
  f <- file.path(base_dir, "sample_of_312", "wikipedia_predictors", as.character(movie_id))
  if (!file.exists(f)) return(NA_real_)
  s <- read.delim(f, stringsAsFactors = FALSE)
  names(s) <- tolower(names(s))
  tcol <- pick(s, c("t", "day", "days_to_release"))
  vcol <- pick(s, c("v", "views", "pageviews"))
  row  <- s[which.min(abs(s[[tcol]] - horizon)), ]
  if (!nrow(row)) NA_real_ else as.numeric(row[[vcol]])
}

movies$views_h <- vapply(movies$movie_id, views_at_horizon, numeric(1))

# --- 2. Pull confounders from TMDb -----------------------------------------

tmdb_lookup <- function(title) {
  Sys.sleep(0.3)  # stay inside TMDb rate limits
  search <- tryCatch(
    GET("https://api.themoviedb.org/3/search/movie",
        query = list(api_key = tmdb_key, query = title)),
    error = function(e) NULL
  )
  if (is.null(search) || status_code(search) != 200) return(NULL)
  hits <- content(search, as = "parsed", simplifyVector = TRUE)$results
  if (is.null(hits) || !length(hits)) return(NULL)

  detail <- tryCatch(
    GET(sprintf("https://api.themoviedb.org/3/movie/%s", hits$id[1]),
        query = list(api_key = tmdb_key)),
    error = function(e) NULL
  )
  if (is.null(detail) || status_code(detail) != 200) return(NULL)
  d <- content(detail, as = "parsed", simplifyVector = TRUE)

  data.frame(
    title         = title,
    budget        = ifelse(is.null(d$budget) || d$budget == 0, NA_real_, d$budget),
    runtime       = ifelse(is.null(d$runtime), NA_real_, d$runtime),
    franchise     = as.integer(!is.null(d$belongs_to_collection)),
    genre         = if (length(d$genres$name)) d$genres$name[1] else NA_character_,
    release_month = as.integer(format(as.Date(d$release_date), "%m")),
    studio        = if (length(d$production_companies$name)) d$production_companies$name[1] else NA_character_,
    stringsAsFactors = FALSE
  )
}

cache <- file.path(out_dir, "tmdb_metadata.csv")
if (file.exists(cache)) {
  tmdb <- read.csv(cache, stringsAsFactors = FALSE)
} else {
  message("Fetching TMDb metadata for ", nrow(movies), " films. This takes a few minutes.")
  tmdb <- bind_rows(lapply(movies$title, tmdb_lookup))
  write.csv(tmdb, cache, row.names = FALSE)
}

# --- 3. Build the analysis frame -------------------------------------------

# Studio tier is a coarse proxy for distribution muscle: major vs everything else.
majors <- c("Warner Bros", "Universal", "Paramount", "Twentieth Century Fox",
            "Walt Disney", "Columbia", "Sony", "Metro-Goldwyn-Mayer", "Lionsgate")

df <- movies %>%
  inner_join(tmdb, by = "title") %>%
  filter(!is.na(views_h), !is.na(budget), !is.na(revenue), revenue > 0) %>%
  mutate(
    D            = as.integer(views_h > median(views_h, na.rm = TRUE)),
    Y            = log(revenue),
    log_budget   = log(budget),
    genre        = factor(ifelse(is.na(genre), "Other", genre)),
    studio_major = as.integer(grepl(paste(majors, collapse = "|"), studio, ignore.case = TRUE)),
    release_month = factor(release_month)
  )

message(sprintf("Analysis sample: %d films (%d treated, %d control).",
                nrow(df), sum(df$D), sum(1 - df$D)))
if (nrow(df) < 80) warning("Small matched sample. TMDb budget coverage may be thin.")

# --- 4. Naive vs adjusted comparison ---------------------------------------
# The naive difference is what the predictive model implicitly reports. It is
# the number the causal estimate should be compared against.

naive <- lm(Y ~ D, data = df)
adj   <- lm(Y ~ D + log_budget + franchise + studio_major + runtime +
              genre + release_month, data = df)

# --- 5. Matching and the ATT -----------------------------------------------

m.out <- matchit(
  D ~ log_budget + franchise + studio_major + runtime + genre + release_month,
  data = df, method = "nearest", distance = "glm",
  caliper = 0.2, std.caliper = TRUE, replace = FALSE
)

bal <- bal.tab(m.out, un = TRUE, thresholds = c(m = 0.1))
print(bal)
ggsave(file.path(out_dir, "love_plot.png"),
       love.plot(m.out, thresholds = c(m = 0.1)), width = 7, height = 5, dpi = 150)

matched <- match.data(m.out)
att_fit <- lm(Y ~ D + log_budget + franchise + studio_major + runtime,
              data = matched, weights = weights)

att      <- coef(att_fit)["D"]
att_se   <- sqrt(sandwich_or_classical <- vcov(att_fit)["D", "D"])
ci       <- att + c(-1.96, 1.96) * att_se
pval     <- summary(att_fit)$coefficients["D", 4]
pct      <- (exp(att) - 1) * 100   # log outcome, so read the effect as a percentage

# --- 6. Sensitivity to unmeasured confounding ------------------------------
# Marketing spend is not in the data and plausibly drives both buzz and revenue.
# The E-value is the minimum strength of association (on the risk-ratio scale)
# that such a confounder would need with BOTH treatment and outcome to explain
# the estimate away. A low E-value means the finding is fragile. Report it
# either way: that is the point of the exercise.

ev <- evalues.OLS(est = att, se = att_se, sd = sd(matched$Y),
                  delta = 1, true = 0)
print(ev)

# --- 7. Robustness ---------------------------------------------------------

rob <- list(
  # Continuous treatment rather than a median split.
  continuous = lm(Y ~ log1p(views_h) + log_budget + franchise + studio_major +
                    runtime + genre, data = df),
  # Top vs bottom tercile, dropping the ambiguous middle.
  terciles = {
    q <- quantile(df$views_h, c(1/3, 2/3), na.rm = TRUE)
    d2 <- df %>% filter(views_h <= q[1] | views_h >= q[2]) %>%
      mutate(D = as.integer(views_h >= q[2]))
    lm(Y ~ D + log_budget + franchise + studio_major + runtime + genre, data = d2)
  },
  # Mediator check: adding theaters should ATTENUATE the estimate if theater
  # count sits on the causal path. If it does, say so rather than reporting
  # the smaller number as the headline.
  with_theaters = lm(Y ~ D + log_budget + franchise + studio_major + runtime +
                       genre + log1p(theaters), data = matched, weights = matched$weights)
)
lapply(rob, function(m) summary(m)$coefficients[2, ])

# --- 8. Report -------------------------------------------------------------

report <- sprintf(
"CAUSAL EXTENSION RESULTS
========================
Sample                : %d films (%d treated / %d control before matching)
Matched pairs         : %d
Treatment             : cumulative Wikipedia page views at t = %d above median
Outcome               : log(opening weekend revenue)

Naive difference      : %.3f log points (%.1f%%)
Regression-adjusted   : %.3f log points
Matched ATT           : %.3f log points (%.1f%%)
95%% CI                : [%.3f, %.3f]
p-value               : %.4f

E-value (estimate)    : %.2f
E-value (CI limit)    : %.2f

Interpretation: an unmeasured confounder would need associations of at least
%.2f with both treatment and outcome, beyond the measured covariates, to move
this estimate to null. Marketing spend is the obvious candidate and is absent
from the data, so treat this as a bounded association under selection on
observables, not a randomized effect.
",
  nrow(df), sum(df$D), sum(1 - df$D), sum(matched$weights > 0),
  horizon,
  coef(naive)["D"], (exp(coef(naive)["D"]) - 1) * 100,
  coef(adj)["D"],
  att, pct, ci[1], ci[2], pval,
  ev[2, "point"], ev[2, "lower"], ev[2, "point"]
)

cat(report)
writeLines(report, file.path(out_dir, "causal_results.txt"))
message("Wrote ", file.path(out_dir, "causal_results.txt"))