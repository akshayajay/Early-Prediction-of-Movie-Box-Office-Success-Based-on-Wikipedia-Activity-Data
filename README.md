# Early Prediction of Movie Box Office Success Using Wikipedia Activity Data

[![Tests](https://github.com/akshayajay/Early-Prediction-of-Movie-Box-Office-Success-Based-on-Wikipedia-Activity-Data/actions/workflows/tests.yml/badge.svg)](https://github.com/akshayajay/Early-Prediction-of-Movie-Box-Office-Success-Based-on-Wikipedia-Activity-Data/actions/workflows/tests.yml)

Can pre-release Wikipedia activity predict a movie's opening weekend revenue — weeks before it hits theatres?

**Hypothesis:** Movies with higher Wikipedia page views (V), unique editors (U), revisions (R), and editors (E) before release will earn higher opening weekend box office revenue.

---

## Overview

This project replicates and extends the methodology from the paper *"Predicting Box-Office Success of Motion Pictures with Wikipedia Clicks"* using the WikiPredict dataset (312 movies). It tests whether Wikipedia collaborative activity data — available weeks before release — outperforms Twitter-based predictions.

Key findings from the replication:
- Wikipedia-based predictors achieve **R² > 0.92** as early as 30 days before release
- The combined feature set `{V, U, R, E, theaters}` consistently outperforms single-predictor models
- Wikipedia activity surpasses the Twitter-based benchmark (R² = 0.98) near release date

---

## Dataset

**WikiPredict** — publicly available at [wikimovies.github.io](https://wikimovies.github.io) or the original paper's repository.

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

## Project Structure

```
├── box_office_prediction.Rmd   # Full analysis (replication + extension)
├── R/
│   └── utils.R                 # Utility functions (compute_correlations, cv_r2, etc.)
├── tests/
│   └── testthat/
│       └── test_utils.R        # Unit tests (no data files required)
├── packages.R                  # Package installer
├── .gitignore
└── README.md
```

---

## Tech Stack

`R` · `ggplot2` · `testthat` · base R (`lm`, `cor`)

---

## Context

Built for DATA 2020 (Statistical Inference for Data Science) at Brown University, 2026.

---

## Author

**Akshaya J** · [github.com/akshayajay](https://github.com/akshayajay)
