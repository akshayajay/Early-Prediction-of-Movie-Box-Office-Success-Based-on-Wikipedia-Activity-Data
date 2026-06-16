# tests/testthat/test_utils.R
# ---------------------------------------------------------------------------
# Unit tests for R/utils.R using synthetic data.
# No dataset files or network access required.
# ---------------------------------------------------------------------------

library(testthat)
source("../../R/utils.R")


# ---------------------------------------------------------------------------
# Synthetic data fixture
# ---------------------------------------------------------------------------

make_df <- function(n = 50, seed = 42) {
  set.seed(seed)
  data.frame(
    V        = runif(n, 100, 50000),
    U        = runif(n, 10,  5000),
    R        = runif(n, 1,   1000),
    E        = runif(n, 1,   500),
    theaters = sample(500:4000, n, replace = TRUE),
    revenue  = runif(n, 1e5, 1e8)
  )
}


# ---------------------------------------------------------------------------
# validate_columns()
# ---------------------------------------------------------------------------

test_that("validate_columns passes on a complete data frame", {
  df <- make_df()
  expect_true(validate_columns(df))
})

test_that("validate_columns errors when a column is missing", {
  df <- make_df()
  df$revenue <- NULL
  expect_error(validate_columns(df), "revenue")
})

test_that("validate_columns errors listing all missing columns", {
  df <- data.frame(x = 1:5)
  expect_error(validate_columns(df))
})

test_that("validate_columns accepts custom required list", {
  df <- data.frame(a = 1:3, b = 4:6)
  expect_true(validate_columns(df, required = c("a", "b")))
})


# ---------------------------------------------------------------------------
# compute_correlations()
# ---------------------------------------------------------------------------

test_that("compute_correlations returns a named numeric vector of length 5", {
  df   <- make_df()
  cors <- compute_correlations(df)
  expect_type(cors, "double")
  expect_length(cors, 5)
  expect_named(cors, c("V", "U", "R", "E", "theaters"))
})

test_that("compute_correlations values are between -1 and 1", {
  df   <- make_df()
  cors <- compute_correlations(df)
  expect_true(all(cors >= -1 & cors <= 1))
})

test_that("compute_correlations returns 1.0 for a perfectly correlated predictor", {
  df <- make_df()
  df$V <- df$revenue   # perfect correlation
  cors <- compute_correlations(df)
  expect_equal(cors["V"], c(V = 1.0))
})

test_that("compute_correlations returns -1.0 for a perfectly negatively correlated predictor", {
  df <- make_df()
  df$V <- -df$revenue
  cors <- compute_correlations(df)
  expect_equal(cors["V"], c(V = -1.0))
})

test_that("compute_correlations handles NAs with use = complete.obs", {
  df <- make_df()
  df$V[c(1, 5, 10)] <- NA
  expect_no_error(compute_correlations(df))
})


# ---------------------------------------------------------------------------
# cv_r2()
# ---------------------------------------------------------------------------

test_that("cv_r2 returns a list with mean_r2, sd_r2, all_r2", {
  df  <- make_df()
  out <- cv_r2(df, c("V", "theaters"), k = 5)
  expect_type(out, "list")
  expect_named(out, c("mean_r2", "sd_r2", "all_r2"))
})

test_that("cv_r2 all_r2 has length equal to k", {
  df  <- make_df()
  out <- cv_r2(df, c("V"), k = 5)
  expect_length(out$all_r2, 5)
})

test_that("cv_r2 mean_r2 is a single numeric value", {
  df  <- make_df()
  out <- cv_r2(df, c("V", "U"), k = 5)
  expect_type(out$mean_r2, "double")
  expect_length(out$mean_r2, 1)
})

test_that("cv_r2 is reproducible with the same seed", {
  df   <- make_df()
  out1 <- cv_r2(df, c("V", "theaters"), k = 5, seed = 99)
  out2 <- cv_r2(df, c("V", "theaters"), k = 5, seed = 99)
  expect_equal(out1$mean_r2, out2$mean_r2)
})

test_that("cv_r2 with all five features gives different result than one feature", {
  df    <- make_df()
  out1  <- cv_r2(df, c("V"), k = 5)
  out5  <- cv_r2(df, c("V", "U", "R", "E", "theaters"), k = 5)
  expect_false(isTRUE(all.equal(out1$mean_r2, out5$mean_r2)))
})

test_that("cv_r2 sd_r2 is non-negative", {
  df  <- make_df()
  out <- cv_r2(df, c("V"), k = 5)
  expect_gte(out$sd_r2, 0)
})


# ---------------------------------------------------------------------------
# add_log_features()
# ---------------------------------------------------------------------------

test_that("add_log_features adds 6 new columns", {
  df     <- make_df()
  n_cols <- ncol(df)
  df2    <- add_log_features(df)
  expect_equal(ncol(df2), n_cols + 6)
})

test_that("add_log_features log_V is log1p of V", {
  df  <- make_df()
  df2 <- add_log_features(df)
  expect_equal(df2$log_V, log1p(df$V))
})

test_that("add_log_features log_revenue is log (not log1p) of revenue", {
  df  <- make_df()
  df2 <- add_log_features(df)
  expect_equal(df2$log_revenue, log(df$revenue))
})

test_that("add_log_features produces no NaN for positive inputs", {
  df  <- make_df()
  df2 <- add_log_features(df)
  log_cols <- c("log_V", "log_U", "log_R", "log_E", "log_theaters", "log_revenue")
  expect_false(any(is.nan(as.matrix(df2[log_cols]))))
})

test_that("add_log_features handles zero V values via log1p", {
  df    <- make_df()
  df$V  <- 0
  df2   <- add_log_features(df)
  expect_equal(df2$log_V, rep(0, nrow(df)))  # log1p(0) == 0
})
