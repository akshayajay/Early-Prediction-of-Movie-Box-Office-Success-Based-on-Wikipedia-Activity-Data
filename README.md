# Early Prediction of Movie Box Office Success Using Wikipedia Activity Data

[![Tests](https://github.com/akshayajay/Early-Prediction-of-Movie-Box-Office-Success-Based-on-Wikipedia-Activity-Data/actions/workflows/tests.yml/badge.svg)](https://github.com/akshayajay/Early-Prediction-of-Movie-Box-Office-Success-Based-on-Wikipedia-Activity-Data/actions/workflows/tests.yml)

Can pre-release Wikipedia activity predict a movie's opening weekend revenue — weeks before it hits theatres?

**Hypothesis:** Movies with higher Wikipedia page views (V), unique editors (U), revisions (R), and editors (E) before release will earn higher opening weekend box office revenue.

---

## Overview

This project replicates and extends the methodology from the paper *"Predicting Box-Office Success of Motion Pictures with Wikipedia Clicks"* using the WikiPredict dataset (312 movies). It tests whether Wikipedia collaborative activity data — available weeks before release — outperforms Twitter-based predictions.

Key findings from the replication:
- In-sample R² exceeds **0.92** as early as 30 days before release
- Out-of-sample performance is lower: 10-fold cross-validated R² is **0.78** at the same
  horizon. This is the figure to quote when comparing against other predictive models,
  since the in-sample number is fit on the same 312 films it is evaluated on.
- The combined feature set `{V, U, R, E, theaters}` consistently outperforms single-predictor models
- Wikipedia activity surpasses the Twitter-based benchmark (R² = 0.98) near release date

---

## Dataset

**WikiPredict** — available as [Dataset S1 of the original paper](https://journals.plos.org/plosone/article/file?id=10.1371/journal.pone.0071226.s002&type=supplementary).
Extract the contents of `wikipredict_data_pack/` into `data/`.

The dataset contains:
- `sample_of_312/` — 312 movies with opening weekend revenue and Wikipedia predictor time series
- `asur_huberman_sample_of_24/` — 24-movie subset used in the Twitter comparison

Expected folder structure after download:

```
data/
├── sample_of_312/
│   ├── sample_of_312          # tab-separated movie metadata
│   └── wikipedia_predictors/  # one file per movie_id
└── asur_huberman_sample_of_24/
    ├── asur_huberman_sample_of_24
    └── wikipedia_predictors/
```

Update `base_dir` in `box_office_prediction.Rmd` to point to your local `data/` folder before running.

---

## Wikipedia Predictors (V, U, R, E)

| Variable | Description |
|---|---|
| V | Cumulative page views |
| U | Unique editors |
| R | Total revisions |
| E | Number of editors |
| T | Number of theaters (opening weekend) |

All measured as cumulative totals at a given time `t` relative to release date (t=0).

---

## Quickstart

### 1. Clone the repo

```bash
git clone https://github.com/akshayajay/Early-Prediction-of-Movie-Box-Office-Success-Based-on-Wikipedia-Activity-Data.git
cd Early-Prediction-of-Movie-Box-Office-Success-Based-on-Wikipedia-Activity-Data
```

### 2. Install R packages

```r
Rscript packages.R
```

### 3. Download the data

Download the WikiPredict dataset and place it in a `data/` folder as described above.

### 4. Run the analysis

Open `box_office_prediction.Rmd` in RStudio and update `base_dir` to your local data path, then knit.

### 5. Run tests

```r
Rscript -e "testthat::test_dir('tests/testthat')"
```

---

## Causal Extension

The replication above answers an associational question: does pre-release
Wikipedia activity forecast opening revenue? `R/causal_extension.R` asks a
different one. Among films that are otherwise comparable on budget, franchise
status, studio, genre and runtime, is high pre-release activity associated
with higher opening revenue?

**Design.** Treatment is cumulative page views at t = -30 above the median of
films eligible for analysis. The outcome is log opening weekend revenue.
TMDb provides production budget, franchise membership, runtime, primary genre,
release month and the first listed production company (used as a major-studio
proxy, not a verified distributor). Estimation uses nearest-neighbour propensity
score matching without replacement and a 0.2 standard-deviation caliper on the
estimated propensity score. Matching includes log budget, franchise status,
studio, runtime and genre; release month enters the regression-adjusted comparison
only. The intended estimand is the ATT under selection on observables, restricted
to retained treated films when calipers exclude unmatched films.

**Theater count is excluded from the matching covariates.** The analysis treats
opening theater count as a potential mediator: studios may set it partly in
response to pre-release buzz. It appears only as a robustness check. Whether it
actually lies on that causal pathway is an assumption, not established by these data.

**Results — run on September 20, 2026** (matched sample of **92 films, 46 treated**).
All 312 films had page views at exactly t = -30. Budget eligibility excluded
112 films (2 missing budgets and 110 nonpositive budgets), leaving 200 films:
100 treated and 100 controls. Matching retained 46 films per group, or **46% of
the eligible treated films**. The naive and regression-adjusted estimates below
use all 200 eligible films; the matched estimate uses the retained 92.

| Estimate | Value |
|---|---|
| Naive difference | 3.761 log points |
| Regression-adjusted | 2.122 log points |
| Matched ATT estimate | 1.420 log points (313.8%) |
| 95% CI | [0.384, 2.457] log points |
| p-value | 0.0087 |
| E-value (estimate) | 2.51 |
| E-value (CI limit) | 1.51 |

**Balance remains inadequate.** The plot in `output/causal/love_plot.png` shows
four covariate indicators above an absolute standardized mean difference of 0.1:
runtime (0.216), Action (0.109), Fantasy (0.155), and Romance (0.218).
The propensity-score distance also remains imbalanced (0.120). These diagnostics
and the substantial loss of treated films limit a causal interpretation; the
positive estimate should be treated as exploratory.

**Robustness.** The coefficient is 0.515 for continuous log views and 4.019 for
top-versus-bottom terciles. Adding theaters to the matched regression reduces the
high-activity coefficient from 1.420 to 0.932 log points. That attenuation alone
does not establish mediation. Full standard errors and p-values are in the report.

**What this does and does not show.** The E-value of 2.51 summarizes the strength
of associations an unmeasured confounder would need with both treatment and
outcome to explain away the estimate, under the E-value assumptions and the
continuous-outcome conversion. Marketing spend is an obvious missing confounder.
Sensitivity analysis does not repair the remaining measured imbalance. The script
uses the first TMDb title-search result, so film identity matches also require
validation. Reported uncertainty uses conventional `lm` standard errors, not
matched-pair robust inference. This is an exploratory adjusted association under
selection on observables, not an established causal effect; the identifying
assumption cannot be verified from these data.

### Running it

```bash
Rscript packages.R
export TMDB_API_KEY="your-tmdb-api-key"
export WIKIPREDICT_DIR="data"          # optional, defaults to data/
Rscript R/causal_extension.R
```

Get a TMDb key from your [TMDb account settings](https://www.themoviedb.org/settings/api).
Keep it in your environment or a local `.Renviron` file, which is ignored by Git.
The script accepts the original supplementary dataset's column names and common
aliases, with a positional fallback for predictor columns.

Outputs land in `output/causal/` (gitignored):

- `tmdb_metadata.csv` — cached TMDb metadata, reused on later runs
- `love_plot.png` — standardized covariate balance before and after matching
- `covariate_balance.csv` — numeric balance diagnostics
- `causal_results.txt` — estimates, sample retention, sensitivity and robustness checks
- `session_info.txt` — R and package versions for the run

Metadata for this extension comes from [TMDb](https://www.themoviedb.org/).
This product uses the TMDB API but is not endorsed or certified by TMDB.

---

## Project Structure

```
├── box_office_prediction.Rmd   # Replication and predictive extension
├── R/
│   ├── causal_extension.R      # Matching, ATT estimation, and sensitivity analysis
│   └── utils.R                 # Utility functions (compute_correlations, cv_r2, etc.)
├── tests/
│   └── testthat/
│       └── test_utils.R        # Unit tests (no data files required)
├── output/causal/              # Generated results (gitignored)
├── packages.R                  # Package installer
├── .gitignore
└── README.md
```

---

## Tech Stack

`R` · `ggplot2` · `MatchIt` · `cobalt` · `EValue` · `testthat` · base R (`lm`, `cor`)

---

## Context

Built for DATA 2020 (Statistical Inference for Data Science) at Brown University, 2026.

---

## Author

**Akshaya J** · [github.com/akshayajay](https://github.com/akshayajay)
