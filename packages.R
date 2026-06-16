# packages.R
# Install all packages required to run the analysis.
# Run this once before opening the .Rmd file.
#
#   Rscript packages.R

install.packages(c(
  "ggplot2",
  "testthat"
), repos = "https://cloud.r-project.org")
