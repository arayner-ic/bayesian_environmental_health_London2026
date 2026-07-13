
library(patchwork)
library(ggplot2)
library(dplyr)

make_density_df <- function(samples, mean_prior, sd_prior, label,
                            xlim = setxlim, n_grid = 500) {
  
  grid <- seq(xlim[1], xlim[2], length.out = n_grid)
  
  prior_df <- data.frame(
    beta = grid,
    density = dnorm(grid, mean = mean_prior, sd = sd_prior),
    distribution = "Prior",
    prior_type = label
  )
  
  post_dens <- density(samples, from = xlim[1], to = xlim[2], n = n_grid)
  
  post_df <- data.frame(
    beta = post_dens$x,
    density = post_dens$y,
    distribution = "Posterior",
    prior_type = label
  )
  
  bind_rows(prior_df, post_df)
}

plot_df <- bind_rows(
  make_density_df(beta_diffuse, mean_prior = 0,    sd_prior = 0.5,   label = "Diffuse"),
  make_density_df(beta_weak,    mean_prior = 0,    sd_prior = 0.1,   label = "Weakly informative"),
  make_density_df(beta_info,    mean_prior = 0.01, sd_prior = 0.005, label = "Informative")
)


ggplot(plot_df, aes(x = beta, y = density, color = prior_type)) +
  geom_line(linewidth = 1.2) +
  facet_wrap(~ distribution, scales = "free_y", ncol = 2) +
  scale_color_manual(values = c(
    "Diffuse" = "#E69F00",
    "Weakly informative" = "#0072B2",
    "Informative" = "#D55E00"
  )) +
  labs(
    x = expression(beta),
    y = "Density",
    color = "Prior choice",
    title = expression("Priors and posteriors for " * beta),
    subtitle = "Chicago ozone-mortality example"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    legend.position = "bottom",
    legend.title = element_text(face = "bold"),
    strip.text = element_text(face = "bold"),
    plot.title = element_text(face = "bold")
  )


ggsave("C:/Users/gkonstan/OneDrive - Imperial College London/ICRF Imperial/Lectures/sharp_bayesian_environmental_health_2026/lectures/priors/figures/chicogo_priors.png", dpi = 300, units = "cm", width = 17, height = 10)


##
## another example

library(dlnm)
library(nimble)
library(coda)
library(dplyr)

data("chicagoNMMAPS")

dat <- chicagoNMMAPS

# Make sure date is Date class
dat$date <- as.Date(dat$date)

# Keep summer only: June, July, August
dat$month <- as.integer(format(dat$date, "%m"))
dat_summer <- dat %>%
  filter(month %in% c(6, 7, 8)) %>%
  select(date, death, temp) %>%
  na.omit()

y <- dat_summer$death
temp <- dat_summer$temp
n <- length(y)

summary(temp)
range(temp)

threshold_code_unif <- nimbleCode({
  for (t in 1:n) {
    y[t] ~ dpois(mu[t])
    log(mu[t]) <- alpha + beta * (temp[t] - psi) * step(temp[t] - psi)
  }
  
  alpha ~ dnorm(0, sd = 100)
  beta  ~ dnorm(0, sd = 0.1)
  psi   ~ dunif(psi_lower, psi_upper)
})


fit_threshold_uniform <- function(psi_lower, psi_upper,
                                  niter = 15000,
                                  nburnin = 3000,
                                  nthin = 10,
                                  nchains = 2) {
  
  constants <- list(
    n = n,
    temp = temp,
    psi_lower = psi_lower,
    psi_upper = psi_upper
  )
  
  data_list <- list(
    y = y
  )
  
  inits <- list(
    alpha = log(mean(y)),
    beta = 0.01,
    psi = mean(c(psi_lower, psi_upper))
  )
  
  model <- nimbleModel(
    code = threshold_code_unif,
    constants = constants,
    data = data_list,
    inits = inits
  )
  
  cmodel <- compileNimble(model)
  
  conf <- configureMCMC(model, monitors = c("alpha", "beta", "psi"))
  mcmc <- buildMCMC(conf)
  cmcmc <- compileNimble(mcmc, project = model)
  
  samples <- runMCMC(
    cmcmc,
    niter = niter,
    nburnin = nburnin,
    thin = nthin,
    nchains = nchains,
    samplesAsCodaMCMC = TRUE,
    summary = TRUE
  )
  
  return(samples)
}


fit_psi_broad <- fit_threshold_uniform(psi_lower = 20, psi_upper = 35)
fit_psi_low   <- fit_threshold_uniform(psi_lower = 24, psi_upper = 28)
fit_psi_high  <- fit_threshold_uniform(psi_lower = 28, psi_upper = 32)


samp_broad <- as.matrix(fit_psi_broad$samples)
samp_low   <- as.matrix(fit_psi_low$samples)
samp_high  <- as.matrix(fit_psi_high$samples)

psi_broad  <- samp_broad[, "psi"]
psi_low    <- samp_low[, "psi"]
psi_high   <- samp_high[, "psi"]

beta_broad <- samp_broad[, "beta"]
beta_low   <- samp_low[, "beta"]
beta_high  <- samp_high[, "beta"]

library(ggplot2)
library(tidyr)
library(dplyr)

make_psi_df <- function(samples, lower, upper, label,
                        xlim = range(temp), n_grid = 500) {
  
  grid <- seq(xlim[1], xlim[2], length.out = n_grid)
  
  prior_df <- data.frame(
    value = grid,
    density = dunif(grid, min = lower, max = upper),
    distribution = "Prior for threshold",
    prior_type = label,
    parameter = "psi"
  )
  
  post_dens <- density(samples, from = xlim[1], to = xlim[2], n = n_grid)
  
  post_df <- data.frame(
    value = post_dens$x,
    density = post_dens$y,
    distribution = "Posterior for threshold",
    prior_type = label,
    parameter = "psi"
  )
  
  bind_rows(prior_df, post_df)
}

make_beta_df <- function(samples, label, xlim = NULL, n_grid = 500) {
  
  if (is.null(xlim)) {
    xlim <- range(samples)
  }
  
  post_dens <- density(samples, from = xlim[1], to = xlim[2], n = n_grid)
  
  data.frame(
    value = post_dens$x,
    density = post_dens$y,
    distribution = "Posterior for slope above threshold",
    prior_type = label,
    parameter = "beta"
  )
}

psi_df <- bind_rows(
  make_psi_df(psi_broad, 20, 35, "Broad prior"),
  make_psi_df(psi_low,   24, 28, "Lower prior"),
  make_psi_df(psi_high,  28, 32, "Higher prior")
)

beta_xlim <- range(c(beta_broad, beta_low, beta_high))

beta_df <- bind_rows(
  make_beta_df(beta_broad, "Broad prior", beta_xlim),
  make_beta_df(beta_low,   "Lower prior", beta_xlim),
  make_beta_df(beta_high,  "Higher prior", beta_xlim)
)

psi_plot_df <- psi_df %>%
  mutate(panel = distribution)

beta_plot_df <- beta_df %>%
  mutate(panel = "Posterior for slope above threshold")

plot_df <- bind_rows(
  psi_plot_df %>% select(value, density, prior_type, panel),
  beta_plot_df %>% select(value, density, prior_type, panel)
)

mean_psi_broad  <- mean(psi_broad)
mean_psi_low    <- mean(psi_low)
mean_psi_high   <- mean(psi_high)

mean_beta_broad <- mean(beta_broad)
mean_beta_low   <- mean(beta_low)
mean_beta_high  <- mean(beta_high)

temp_grid <- seq(min(temp), max(temp), length.out = 200)

curve_broad <- mean_beta_broad * pmax(temp_grid - mean_psi_broad, 0)
curve_low   <- mean_beta_low   * pmax(temp_grid - mean_psi_low, 0)
curve_high  <- mean_beta_high  * pmax(temp_grid - mean_psi_high, 0)


curve_df <- bind_rows(
  data.frame(
    temp = temp_grid,
    value = exp(mean_beta_broad * pmax(temp_grid - mean_psi_broad, 0)),
    prior_type = "Broad prior",
    panel = "Threshold-response function"
  ),
  data.frame(
    temp = temp_grid,
    value = exp(mean_beta_low * pmax(temp_grid - mean_psi_low, 0)),
    prior_type = "Lower prior",
    panel = "Threshold-response function"
  ),
  data.frame(
    temp = temp_grid,
    value = exp(mean_beta_high * pmax(temp_grid - mean_psi_high, 0)),
    prior_type = "Higher prior",
    panel = "Threshold-response function"
  )
)

psi_prior_df <- psi_df %>%
  filter(distribution == "Prior for threshold") %>%
  transmute(
    x = value,
    density = density,
    prior_type = prior_type,
    panel = "Prior for threshold"
  )

psi_post_df <- psi_df %>%
  filter(distribution == "Posterior for threshold") %>%
  transmute(
    x = value,
    density = density,
    prior_type = prior_type,
    panel = "Posterior for threshold"
  )

beta_plot_df <- beta_df %>%
  transmute(
    x = value,
    density = density,
    prior_type = prior_type,
    panel = "Posterior for slope"
  )

p1 <- ggplot(psi_prior_df, aes(x = x, y = density, color = prior_type)) +
  geom_line(linewidth = 1, alpha = 0.6) +
  scale_color_manual(values = c(
    "Broad prior" = "#0072B2",
    "Lower prior" = "#D55E00",
    "Higher prior" = "#009E73"
  )) +
  labs(title = "Prior for threshold", x = expression(psi), y = "Density") +
  theme_minimal(base_size = 13) +
  theme(legend.position = "none")

p2 <- ggplot(psi_post_df, aes(x = x, y = density, color = prior_type)) +
  geom_line(linewidth = 1, alpha = 0.6) +
  scale_color_manual(values = c(
    "Broad prior" = "#0072B2",
    "Lower prior" = "#D55E00",
    "Higher prior" = "#009E73"
  )) +
  labs(title = "Posterior for threshold", x = expression(psi), y = "Density") +
  theme_minimal(base_size = 13) +
  theme(legend.position = "none")

p3 <- ggplot(beta_plot_df, aes(x = x, y = density, color = prior_type)) +
  geom_line(linewidth = 1, alpha = 0.6) +
  scale_color_manual(values = c(
    "Broad prior" = "#0072B2",
    "Lower prior" = "#D55E00",
    "Higher prior" = "#009E73"
  )) +
  labs(title = "Posterior for slope", x = expression(beta), y = "Density") +
  theme_minimal(base_size = 13) +
  theme(legend.position = "none")

p4 <- ggplot(curve_df, aes(x = temp, y = value, color = prior_type)) +
  geom_line(linewidth = 1, alpha = 0.6) +
  scale_color_manual(values = c(
    "Broad prior" = "#0072B2",
    "Lower prior" = "#D55E00",
    "Higher prior" = "#009E73"
  )) +
  labs(
    title = "Estimated threshold-response",
    x = "Temperature",
    y = "Relative risk"
  ) +
  theme_minimal(base_size = 13) +
  theme(legend.position = "bottom")

((p1 | p2) / (p3 | p4)) + plot_layout(guides = "collect") &
  theme(legend.position = "bottom")

ggsave("C:/Users/gkonstan/OneDrive - Imperial College London/ICRF Imperial/Lectures/sharp_bayesian_environmental_health_2026/lectures/priors/figures/linearthrchi_priors.png", dpi = 300, units = "cm", width = 17, height = 14)



library(nimble)
library(coda)
library(dplyr)
library(ggplot2)
library(patchwork)


dat_region <- readRDS("C:/Users/gkonstan/OneDrive - Imperial College London/ICRF Imperial/Lectures/sharp_bayesian_environmental_health_2026/data/italy/italy_mortality.rds")
dat_region$year <- lubridate::year(dat_region$date)
dat_region$month <- lubridate::month(dat_region$date)

dat_region %>%
  dplyr::filter(year == 2013, month == 9) %>% 
  group_by(SIGLA) %>%
  summarise(
    y = sum(deaths),
    E = sum(expected),
    .groups = "drop"
  ) -> dat_region

dat_region <- dat_region %>%
  mutate(region_id = seq_len(n()))

y <- dat_region$y
E <- dat_region$E
R <- nrow(dat_region)
region_names <- dat_region$SIGLA

code_uniform <- nimbleCode({
  for (i in 1:R) {
    y[i] ~ dpois(mu[i])
    mu[i] <- E[i] * lambda[i]
    log(lambda[i]) <- alpha + b[i]
    b[i] ~ dnorm(0, sd = sigma_b)
  }
  
  alpha ~ dnorm(0, sd = 10)
  sigma_b ~ dunif(0, sigma_upper)
})


code_halfnormal <- nimbleCode({
  for (i in 1:R) {
    y[i] ~ dpois(mu[i])
    mu[i] <- E[i] * lambda[i]
    log(lambda[i]) <- alpha + b[i]
    b[i] ~ dnorm(0, sd = sigma_b)
  }
  
  alpha ~ dnorm(0, sd = 10)
  sigma_b ~ T(dnorm(0, sd = sigma_sd), 0, )
})


fit_uniform_model <- function(sigma_upper,
                              niter = 20000,
                              nburnin = 5000,
                              nthin = 10,
                              nchains = 2) {
  
  constants <- list(
    R = R,
    E = E,
    sigma_upper = sigma_upper
  )
  
  data_list <- list(
    y = y
  )
  
  inits <- list(
    alpha = 0,
    sigma_b = sigma_upper / 2,
    b = rep(0, R)
  )
  
  model <- nimbleModel(
    code = code_uniform,
    constants = constants,
    data = data_list,
    inits = inits
  )
  
  cmodel <- compileNimble(model)
  
  conf <- configureMCMC(model, monitors = c("alpha", "sigma_b", "b", "lambda"))
  mcmc <- buildMCMC(conf)
  cmcmc <- compileNimble(mcmc, project = model)
  
  samples <- runMCMC(
    cmcmc,
    niter = niter,
    nburnin = nburnin,
    thin = nthin,
    nchains = nchains,
    samplesAsCodaMCMC = TRUE,
    summary = TRUE
  )
  
  samples
}


fit_halfnormal_model <- function(sigma_sd,
                                 niter = 20000,
                                 nburnin = 5000,
                                 nthin = 10,
                                 nchains = 2) {
  
  constants <- list(
    R = R,
    E = E,
    sigma_sd = sigma_sd
  )
  
  data_list <- list(
    y = y
  )
  
  inits <- list(
    alpha = 0,
    sigma_b = sigma_sd / 2,
    b = rep(0, R)
  )
  
  model <- nimbleModel(
    code = code_halfnormal,
    constants = constants,
    data = data_list,
    inits = inits
  )
  
  cmodel <- compileNimble(model)
  
  conf <- configureMCMC(model, monitors = c("alpha", "sigma_b", "b", "lambda"))
  mcmc <- buildMCMC(conf)
  cmcmc <- compileNimble(mcmc, project = model)
  
  samples <- runMCMC(
    cmcmc,
    niter = niter,
    nburnin = nburnin,
    thin = nthin,
    nchains = nchains,
    samplesAsCodaMCMC = TRUE,
    summary = TRUE
  )
  
  samples
}


fit_u_01 <- fit_uniform_model(0.1)
fit_u_05 <- fit_uniform_model(0.5)
fit_u_1  <- fit_uniform_model(1)


fit_hn_01 <- fit_halfnormal_model(0.1)
fit_hn_05 <- fit_halfnormal_model(0.5)
fit_hn_1  <- fit_halfnormal_model(1)


extract_samples <- function(fit) {
  as.matrix(fit$samples)
}

s_u_01[,"sigma_b"] %>% summary()

s_u_01  <- extract_samples(fit_u_01)
s_u_05  <- extract_samples(fit_u_05)
s_u_1   <- extract_samples(fit_u_1)

s_hn_01 <- extract_samples(fit_hn_01)
s_hn_05 <- extract_samples(fit_hn_05)
s_hn_1  <- extract_samples(fit_hn_1)


make_sigma_df <- function(samples, prior_type, prior_param,
                          family = c("uniform", "halfnormal"),
                          xlim = c(0, 1.2), n_grid = 500) {
  
  family <- match.arg(family)
  grid <- seq(xlim[1], xlim[2], length.out = n_grid)
  
  prior_density <- if (family == "uniform") {
    dunif(grid, 0, prior_param)
  } else {
    2 * dnorm(grid, mean = 0, sd = prior_param)
  }
  
  prior_df <- data.frame(
    sigma_b = grid,
    density = prior_density,
    distribution = "Prior",
    prior = prior_type
  )
  
  post_dens <- density(samples[, "sigma_b"], from = xlim[1], to = xlim[2], n = n_grid)
  
  post_df <- data.frame(
    sigma_b = post_dens$x,
    density = post_dens$y,
    distribution = "Posterior",
    prior = prior_type
  )
  
  bind_rows(prior_df, post_df)
}


sigma_df <- bind_rows(
  make_sigma_df(s_u_01,  "Uniform(0, 0.1)", 0.1, "uniform"),
  make_sigma_df(s_u_05,  "Uniform(0, 0.5)", 0.5, "uniform"),
  make_sigma_df(s_u_1,   "Uniform(0, 1.0)", 1.0, "uniform"),
  make_sigma_df(s_hn_01, "Half-Normal(0.1)", 0.1, "halfnormal"),
  make_sigma_df(s_hn_05, "Half-Normal(0.5)", 0.5, "halfnormal"),
  make_sigma_df(s_hn_1,  "Half-Normal(1.0)", 1.0, "halfnormal")
)


ggplot(sigma_df, aes(x = sigma_b, y = density, color = prior, linetype = distribution)) +
  geom_line(linewidth = 1, alpha = .6) +
  facet_wrap(~ distribution, scales = "free_y", ncol = 2) +
  theme_minimal(base_size = 14) +
  labs(
    x = expression(sigma[b]),
    y = "Density",
    color = "Prior choice",
    linetype = "",
    title = expression("Prior and posterior for " * sigma[b])
  ) +
  theme(legend.position = "bottom")


ggsave("C:/Users/gkonstan/OneDrive - Imperial College London/ICRF Imperial/Lectures/sharp_bayesian_environmental_health_2026/lectures/priors/figures/iidItaly_priors.png", dpi = 300, units = "cm", width = 17, height = 10)
