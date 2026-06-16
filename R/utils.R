# R/utils.R
# ---------------------------------------------------------------------------
# Pure utility functions for the Wikipedia box office prediction pipeline.
# Extracted here so they can be unit-tested with testthat independently of
# the full RMarkdown analysis and dataset files.
# ---------------------------------------------------------------------------


#' Compute Pearson correlations of Wikipedia predictors with revenue
#'
#' @param df  Data frame containing columns V, U, R, E, theaters, revenue.
#' @return Named numeric vector of Pearson r values.
#' @export
compute_correlations <- function(df) {
  vars <- c("V", "U", "R", "E", "theaters")
  cors <- sapply(vars, function(x) cor(df[[x]], df$revenue, use = "complete.obs"))
  return(cors)
}


#' K-fold cross-validated R² for a linear regression
#'
#' @param df           Data frame with outcome column `revenue`.
#' @param feature_cols Character vector of predictor column names.
#' @param k            Number of folds (default 10).
#' @param seed         Random seed for reproducibility (default 42).
#' @return List with `mean_r2`, `sd_r2`, and `all_r2` (per-fold values).
#' @export
cv_r2 <- function(df, feature_cols, k = 10, seed = 42) {
  set.seed(seed)
  n     <- nrow(df)
  folds <- sample(rep(1:k, length.out = n))

  formula_str  <- paste("revenue ~", paste(feature_cols, collapse = " + "))
  model_formula <- as.formula(formula_str)

  r2_list <- vapply(seq_len(k), function(fold) {
    train <- df[folds != fold, ]
    test  <- df[folds == fold, ]

    model <- lm(model_formula, data = train)
    pred  <- predict(model, newdata = test)

    y_true <- test$revenue
    ss_res <- sum((y_true - pred)^2)
    ss_tot <- sum((y_true - mean(y_true))^2)

    if (ss_tot == 0) return(NA_real_)
    1 - ss_res / ss_tot
  }, numeric(1))

  list(
    mean_r2 = mean(r2_list, na.rm = TRUE),
    sd_r2   = sd(r2_list,   na.rm = TRUE),
    all_r2  = r2_list
  )
}


#' Log-transform Wikipedia predictors (V, U, R, E, theaters)
#'
#' Applies log1p to avoid log(0) issues.
#'
#' @param df Data frame with columns V, U, R, E, theaters.
#' @return The same data frame with additional log_* columns appended.
#' @export
add_log_features <- function(df) {
  df$log_V        <- log1p(df$V)
  df$log_U        <- log1p(df$U)
  df$log_R        <- log1p(df$R)
  df$log_E        <- log1p(df$E)
  df$log_theaters <- log1p(df$theaters)
  df$log_revenue  <- log(df$revenue)
  df
}


#' Validate that required columns are present in a data frame
#'
#' @param df       Data frame to check.
#' @param required Character vector of required column names.
#' @return Invisible TRUE; stops with an error if any column is missing.
#' @export
validate_columns <- function(df, required = c("V", "U", "R", "E", "theaters", "revenue")) {
  missing_cols <- setdiff(required, colnames(df))
  if (length(missing_cols) > 0) {
    stop(paste("Missing required columns:", paste(missing_cols, collapse = ", ")))
  }
  invisible(TRUE)
}
