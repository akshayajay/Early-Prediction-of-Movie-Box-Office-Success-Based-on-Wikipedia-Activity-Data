# packages.R
# Install all packages required to run the analysis.
# Run this once before opening the .Rmd file or running the causal extension.
#
#   Rscript packages.R

install.packages(c(
  "ggplot2",
  "testthat",
  "dplyr",
  "httr",
  "jsonlite",
  "MatchIt",
  "cobalt",
  "EValue"
), repos = "https://cloud.r-project.org")
