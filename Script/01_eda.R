library("dplyr")
library("GGally")
library("ggplot2")
library("PCAmixdata")
library("purrr")
library("readr")
library("tidyr")

# Load transformed growlogs data.
all_growlogs <- read_rds("Data/all_growlogs_transf.rds")

# Keep growlogs which have our interest outcome variable (weight).
growlogs <- filter(all_growlogs, !is.na(weight))

# Keep growlogs of users which have set their units as inch and fahrenheit.
growlogs <- filter(
  growlogs,
  user.lengthUnit == "LengthEnum.inch" & user.temperatureUnit == "TemperatureEnum.fahrenheit"
)

clean_logs <- growlogs
# (outl_lim <- quantile(growlogs$weight, .75) + 1.5 * IQR(growlogs$weight))
# clean_logs <- filter(clean_logs, 0 < weight & weight < outl_lim)
clean_logs <- filter(clean_logs, 0 < weight)

# Select interesting variables.
int_vars <- c(
  "weight",
  "breeder_name",
  "strain",
  "strain.type",
  "strain.strainClass",
  "tree_medium",
  "germination_days",
  "vegetative_days",
  "flowering_days",
  "env",
  "exposure_time",
  "indoor_height",
  "indoor_length",
  "indoor_width",
  "indoor_dims",
  "total_wattage",
  "n_lights",
  "light_n_types"
)

# Clean some categorical variables.
clean_logs <- mutate(
  clean_logs,
  strain.type = gsub("^seeds.type.", "", strain.type),
  strain.strainClass = gsub("^seeds.class.", "", strain.strainClass),
  tree_medium = gsub("^MediumTypeEnum.", "", tree_medium),
  tree_medium = ifelse(tree_medium == "null", NA, tree_medium),
  env = gsub("^EnvironmentTypeEnum.", "", env),
)

# Save it to be used at Rmd file.
# select_at(clean_logs, int_vars) %>% write_csv("Data/clean_logs.csv")

# Let's check with PCA.
split <- select_at(clean_logs, setdiff(int_vars, c("weight", "breeder_name", "strain"))) %>%
  splitmix()
res.pcamix <- PCAmix(X.quanti = split$X.quanti, X.quali = split$X.quali, rename.level = TRUE)
head(res.pcamix$eig)
res.pca <- PCAmix(X.quanti = split$X.quanti, rename.level = TRUE)
head(res.pca$eig)

my_pca_plot <- function(pcamix_data, size_values = rep(1, nrow(res.pca$ind$coord))) {
  features <- as.data.frame(pcamix_data$quanti$coord)
  features <- mutate(features, feature = rownames(features), from_x = 0, from_y = 0)
  points <- as.data.frame(pcamix_data$ind$coord) %>%
    mutate(size = size_values)
  labs <- paste0("Dim ", 1:2, " (", round(pcamix_data$eig[1:2, "Proportion"], 2), " %)")
  ggplot() +
    geom_segment(
      aes(x = from_x, xend = `dim 1`, y = from_y, yend = `dim 2`),
      data = features, linetype = "dotdash", arrow = arrow(), alpha = 0.2
    ) +
    geom_text(aes(x = `dim 1`, y = `dim 2`, label = feature), data = features) +
    geom_point(aes(x = `dim 1`, y = `dim 2`, size = size), data = points, color = "red", alpha = 0.2) +
    theme_light() +
    theme(legend.position = "none") +
    xlab(labs[[1]]) +
    ylab(labs[[2]])
}
my_pca_plot(res.pca, clean_logs$weight) +
  coord_cartesian(xlim = c(-1, 2), ylim = c(-1, 1))
# ggsave("Images/pca.png")


# Let's check correlations for numerical values.
select_at(clean_logs, setdiff(int_vars, c("breeder_name", "strain"))) %>%
  select_if(is.numeric) %>%
  # ggpairs(upper = list(continuous = wrap("cor", family="sans")))
  ggcorr(label = TRUE, label_round = 2, hjust = .75)
# ggsave("Images/corrs.png")


# Let's check dependencies for categorical values.

signif_features <- function(data, dep_var, c_off, columns) {
  map(columns, function(column) {
    aov_res <- aov(as.formula(paste(dep_var, "~", column)), data = data)
    feature_test <- as.data.frame(summary(aov_res)[[1]][1, ])
    res <- list(feature_test = feature_test)
    if (feature_test$`Pr(>F)` <= c_off) {
      res$contrasts_test <- TukeyHSD(aov_res)[[column]] %>%
        as_tibble(rownames = "contrast") %>%
        filter(`p adj` <= c_off)
    }
    res
  }) %>%
    setNames(columns)
}

# Set a p-value cutoff of 0.1 .
c_off <- 0.1
signif_res <- int_vars[map_lgl(int_vars, ~ !is.numeric(pull(clean_logs, .x)))] %>%
  signif_features(clean_logs, "weight", c_off, .)
map(signif_res, ~ .x$feature_test) %>%
  bind_rows() %>%
  mutate(Variable = rownames(.), `Significant at 0.1` = `Pr(>F)` <= c_off, `p-value` = `Pr(>F)`) %>%
  select(Variable, `p-value`, `Significant at 0.1`) %>%
  arrange(`p-value`)

# Some plots relating categorical variables with `weight`.
select_at(clean_logs, setdiff(int_vars, c("breeder_name", "strain"))) %>%
  select_if(negate(is.numeric)) %>%
  bind_cols(select(clean_logs, weight), .) %>%
  ggpairs(upper = list(continuous = wrap("cor", family="sans")))

# `weight` summaries of categorical variables.
int_vars[map_lgl(int_vars, ~ !is.numeric(pull(clean_logs, .x)))] %>%
  map(function(int_var) {
    group_by_at(clean_logs, int_var) %>%
      summarise(
        n_logs = n(),
        mean_weight = mean(weight),
        median_weight = median(weight),
        .groups = "drop"
      ) %>%
      arrange(desc(mean_weight)) %>%
      filter(n_logs >= 3) %>%
      drop_na() %>%
      slice_head(n = 5)
  })
