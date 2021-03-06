  # 0. Libraries and loading R objects
library(epiR)
library(PropCIs)
library(gridExtra)
library(cowplot)
library(tableone)
library(epitools)
library(viridis)
library(knitr)
library(gridExtra)
library(ggplot2)
library(ggforce)
library(ggpubr)
library(feather)
library(tidyverse)
library(reshape2)
library(fakeR)

# Directly read in the cohorts into the global environment
cohort <- read_feather("data/raw/fakeR_cohort.feather") %>%
  group_by(id)

infections <- read_feather("data/raw/fakeR_infections.feather") %>%
  group_by(id)

infections <- split(infections, f = infections$infection)

# Function to omit the scientific notation from in-line R markdown output and rounding to integers
PY_format <- function(PY_number) {
  
  format(round(PY_number), scientific = F)
  
}

### COUNT PERSON-YEARS OF FOLLOW-UP ###

# 1. Create function:
# Input will be a tibble with rows of patients in a certain stratum
# Output will be the total number of person-years (PY) per stratum per year

# 1.1. Create matrix with one row per patient in the cohort and one column per year of the study period (2003-2019)
# 1.2. Fill the matrix with the amount of follow-up (years) per patient per year of the study period
# 1.3. Create a new matrix with one row per year of the study period and one column for the cumulative number of PY per year

py_strat <- function(strat_tibble) {
  
  strat_tibble <- strat_tibble %>%
    select(FUyears,  startFU, endFU) %>%
    separate(startFU, into = c("yostartFU", "mostartFU", "dostartFU"), remove = F, convert = T) %>%
    separate(endFU, into = c("yoendFU", "moendFU", "doendFU"), remove = F, convert = T)
  
  PY <- matrix(NA, nrow(strat_tibble), ncol = 17)
  
  for(i in 1:17) {
    
    yostudy <- i + 2002
    
    # For each patient, indicate the amount of follow-up in each calendar year of the study period
    PY[,i] <- ifelse(strat_tibble$yostartFU == yostudy & strat_tibble$yoendFU == yostudy, strat_tibble$FUyears,
                     ifelse(strat_tibble$yostartFU < yostudy & strat_tibble$yoendFU > yostudy, 1,
                            ifelse(strat_tibble$yostartFU == yostudy & strat_tibble$yoendFU > yostudy, as.numeric(as.Date(paste("31/12/", yostudy, sep = ""), "%d/%m/%Y")-strat_tibble$startFU)/365.25,
                                   ifelse(strat_tibble$yostartFU < yostudy & strat_tibble$yoendFU == yostudy, as.numeric(strat_tibble$endFU-as.Date(paste("01/01/", yostudy, sep = ""), "%d/%m/%Y"))/365.25, 0))))
    
  }
  
  # Sum the amount of follow in each calendar year and make into a single-column tibble
  PY_cum <- matrix(NA, 17, 1) 
  
  for (i in 1:17) {
    
    PY_cum[i,] <- sum(PY[,i])
    
  }
  
  PY_cum <- as_tibble(PY_cum) %>%
    rename(PY = V1)
  
  PY_cum[18,] = sum(PY_cum[1:17,])
  
  return(PY_cum)
}

# Stratify the cohort tibble by gender, and keep the overall cohort ('nostrat')
cohorts_strat <- list(nostrat = cohort,
                      men = subset(cohort, cohort$gender == 1),
                      women = subset(cohort, cohort$gender == 2))

# Count the number of PY of follow-up
all_PY <- lapply(cohorts_strat, py_strat)

# Results  

## Baseline table  

## Select the covariates to include in the baseline table
BLvars <- c("gender", "FUyears", "inf_history")

## Indicate which covariates are categorical variables
BLcatvars <- c("gender", "age_group", "inf_history")

## Indicate which variables are non-normally distributed
BLnnvars <- "FUyears"

## Create the baseline table
all_BL <- CreateTableOne(vars = BLvars, data = cohort, factorVars = BLcatvars)

## Print the baseline table with median and interquartile range (IQR) for non-normally distributed variables
print(all_BL, nonnormal = BLnnvars)
```
## Infection rate per person-year over the study period  
```{r, echo = F, warning=FALSE}
# Function to indicate whether a record of infection was part of an ongoing episode (inf_newepi = 0) or the start of a new episode (inf_newepi = 1)
infections_episodes <- function(allinf, yearstoBL, epis_duration) {
  
  # Infections that started before the period of observation,
  # but of which episodes extend into the observation period
  inf_beforeFU <- allinf %>%
    filter(eventdate < startFU - (yearstoBL*365.25 + epis_duration)) %>%
    arrange(id, desc(eventdate)) %>%
    distinct(id, .keep_all = T) %>%
    mutate(infepisdate = eventdate) %>%
    select(id, infepisdate)
  
  # Infections that started during the period of observation
  inf_duringFU <- allinf %>%
    filter(eventdate >= startFU - (yearstoBL*365.25 + epis_duration))
  
  # The first infection that occurred during the observation period
  inf1stduringFU <- inf_duringFU %>%
    arrange(id, eventdate) %>%
    distinct(id, .keep_all = T)
  
  # Records of infections that occurred during an episode of infection that
  # started before the period of observation
  inf1stepis <- inner_join(inf1stduringFU, inf_beforeFU, by = "id") %>%
    filter((eventdate - epis_duration) <= infepisdate)
  
  # Infections that were the start of new episodes
  inf1stnew <- anti_join(inf1stduringFU, inf1stepis, by = "id") %>%
    mutate(inf_newepi = 1)
  
  # For all first infections during the observation period,
  # indicate it if they occurred during an ongoing episode
  inf_1st <- rbind(inf1stnew, inf1stepis) %>%
    select(id, eventdate, inf_newepi, startFU) %>%
    mutate(inf_newepi = replace_na(inf_newepi, 0))
  
  # Repeat the steps above in this function for all subsequent infections during the observation period
  
  # The infections that were not the first occurrence of infection during the observation period
  inf_notbeforeprev <- anti_join(inf_duringFU, inf_1st, by  = c("id", "eventdate")) %>%
    group_by(id) %>%
    arrange(id, eventdate)
  
  # The second records of infection during the observation period only 
  inf_prev <- inf_notbeforeprev %>%
    distinct(id, .keep_all = T)
  
  # Join the second to the first records of infection to compare dates below
  inf_prev <- inner_join(inf_prev, inf_1st, by = c("id", "startFU")) %>%
    select(id, eventdate.x, eventdate.y, startFU) %>%
    mutate(eventdate = eventdate.x,
           infepisdate = eventdate.y) %>%
    select(id, eventdate, infepisdate, startFU)
  
  # Indicate record of ongoing infection,
  # if the two records are not separated by at least the duration of an episode of infection
  inf_previnfepis <- inf_prev %>%
    filter((eventdate - epis_duration) <= infepisdate) %>%
    mutate(inf_newepi = 0)
  
  # Otherwise, indicate that the second record is the start of a new episode of infection
  inf_previnfnew <- anti_join(inf_prev, inf_previnfepis, by = "id") %>%
    mutate(inf_newepi = 1) %>%
    select(id, eventdate, inf_newepi, startFU)
  
  # Re-unite all second records of infection, with indication of new or ongoing episode of infection
  inf_prev <- rbind(inf_previnfepis, inf_previnfnew) %>%
    select(id, eventdate, inf_newepi, startFU)
  
  # Create one tibble with both first and second records of infection during the observation period
  inf_all <- rbind(inf_1st, inf_prev) %>%
    group_by(id) %>%
    arrange(id, eventdate)
  
  repeat{
    
    # Records of infection not yet classified as new or ongoing episode of infection
    inf_notbefore <- anti_join(inf_notbeforeprev, inf_prev, by  = c("id", "eventdate")) %>%
      group_by(id) %>%
      arrange(id, eventdate)
    
    # Earliest of the records yet to be classified
    inf_next <- inf_notbefore %>%
      distinct(id, .keep_all = T)
    
    # Binding the earlier records to the directly preceeding records for comparison of the dates
    inf_next <- inner_join(inf_next, inf_prev, by = c("id", "startFU")) %>%
      select(id, eventdate.x, eventdate.y, startFU) %>%
      mutate(eventdate = eventdate.x,
             infepisdate = eventdate.y) %>%
      select(id, eventdate, infepisdate, startFU)
    
    # Indicate ongoing episode if the two records are not separated by
    # at least the duration of an episode of infection
    inf_nextepis <- inf_next %>%
      filter((eventdate - epis_duration) <= infepisdate) %>%
      mutate(inf_newepi = 0)
    
    # Otherwise, if the two records are at least the duration of an episode of infection apart,
    # indicate the start of a new episode of infection
    inf_nextnew <- anti_join(inf_next, inf_nextepis, by = "id") %>%
      mutate(inf_newepi = 1) %>%
      select(id, eventdate, inf_newepi, startFU)
    
    # Complete tibble of newly classified records of infection as ongoing or new episode of infection
    inf_next <- rbind(inf_nextepis, inf_nextnew) %>%
      select(id, eventdate, inf_newepi, startFU)
    
    rm(inf_nextepis, inf_nextnew)
    
    # Complete tibble with the newly classified records of infection
    # and all previously classiefied records of infection
    inf_all <- rbind(inf_all, inf_next) %>%
      group_by(id) %>%
      arrange(id, eventdate)
    
    # Newly classified records become the records immediately preceedinng
    # the next earliest records of infection to be classified
    inf_prev <- inf_next
    
    # Remaining records of records of infection yet to be classified
    inf_notbeforeprev <- inf_notbefore
    
    # Indicate the end of the loop once all records of infection have been classified
    if(nrow(inf_notbefore) == 0) break
    
  }
  
  # Return the tibble with all classified records of infection
  return(inf_all)
}

# Indicate for all infections whether they were part of an ongoing episode or the start of a new episode
FU_inf <- lapply(infections, infections_episodes, yearstoBL = 1, epis_duration = 28)

# Keep records of infection of new episodes that occurred during the follow-up period
FU_inf <- lapply(FU_inf, function(x) x <- x %>%
                   filter(eventdate > startFU & 
                            inf_newepi == 1) %>%
                   select_at(vars(-contains("inf_newepi"))))

FU_inf$any <- dplyr::bind_rows(FU_inf)

# Join the records of new episodes of infection to the cohort tibble
inf_strat <- lapply(cohorts_strat, function(x) semi_join(FU_inf$any, x, by = "id"))

# Function to sum the number of episodes of infection per year of the study period
inf_strat_fun <- function(strat_tibble) {
  
  strat_tibble <- strat_tibble %>%
    separate(eventdate, into = c("yoi", "moi", "doi"), remove = F, convert = T)
  
  inf <- matrix(NA, nrow = 17, ncol = 1)
  
  for(i in 1:17) {
    
    yostudy <- i + 2002
    
    inf[i,] <- sum(strat_tibble$yoi == yostudy)
    
  }
  
  inf_cum <- as_tibble(inf) %>%
    rename(inf = V1) 
  
  inf_cum[18,] = sum(inf_cum[1:17,])
  
  return(inf_cum)
}

# Use the function to sum the number of new episodes of infection per calendar year of the study period by stratum and cohort
inf_strat <- lapply(inf_strat, inf_strat_fun)

# Calculate the infection rates per calendar year of the study period by stratum and cohort
inf_rate_overall <- mapply(function(x, y) pois.exact(x$inf,
                                                     pt = y$PY,
                                                     conf.level = 0.95) %>%
                             select(rate, lower, upper) %>%
                             mutate(year = c(as.character(2003:2019), "total")),
                           SIMPLIFY = F,
                           inf_strat, all_PY)

# Make one tibble of infection rates with indication of the group
inf_rate_overall <- dplyr::bind_rows(inf_rate_overall, .id = "group")

# Plot the infection rates of any type by gender, and overall
infrate_P <- ggplot(data = subset(inf_rate_overall, inf_rate_overall$year != "total"),
                    aes(x = as.numeric(year),
                        y = rate,
                        group = group)) +
  geom_line(aes(colour = group)) +
  geom_point(aes(colour = group)) +
  geom_ribbon(alpha = 0.3,
              aes(fill = group,
                  ymin = lower,
                  ymax = upper)) +
  scale_fill_discrete(name = element_blank()) +
  scale_colour_discrete(name = element_blank()) +
  scale_colour_viridis(discrete = T,
                       name = element_blank(),
                       option = "plasma",
                       begin = 0, end = 0.8) +
  scale_fill_viridis(discrete = T,
                     name = element_blank(),
                     option = "plasma",
                     begin = 0, end = 0.8) +
  labs(x = "Year",
       y = "Infection rate per PY") +
  theme_bw() +
  theme(legend.position = "top")

infrate_P

  ## Infections over time by type of infection and stratified on gender
# Infection rates by type: join the records of infection by type to the stratified cohort tibbles
inf_strat_type <- lapply(FU_inf, function(x) lapply(cohorts_strat, function(y) semi_join(x, y, by = "id")))

# Count the numbers of new episodes of infection by type and by stratum
inf_strat_type <- lapply(inf_strat_type, function(x) lapply(x, inf_strat_fun))

# Function to calculate the incidence rate ratio (IRR)
# Input: list with number of infections in "exposure" group, PY in this group, infections in reference group, and PY in reference group
# Output: tibble with estimate (est) of the incidence rate ratio with its Wald 95% CI (lower, upper)
IRR_fun <- function(var_list) {
  
  dat <- as.table(matrix(c(unlist(var_list)),
                         nrow = 2, byrow = T))
  
  rval <- epi.2by2(dat = dat, method = "cohort.time", conf.level = 0.95,
                   units = 1, outcome = "as.columns")
  
  IRR <- round(summary(rval)$IRR.strata.wald, digits = 2)
  
}

# List of total number of infections by type and the number of PY over the study period in men and women to pass into the function to calculate IRRs
IRR_inftypes <- lapply(inf_strat_type, function(x) c(x$women[18,1], all_PY$women[18,1],
                                                     x$men[18,1], all_PY$men[18,1]))

# Calculate the ratios of infection rates by type of infection, men vs. women
IRRelu_inftypes <- lapply(IRR_inftypes, IRR_fun)

# Calculate the infection rates by type and by stratum
inf_rate_type <- lapply(inf_strat_type, function(x) mapply(function(x, y) pois.exact(x$inf,
                                                                                     pt = y$PY,
                                                                                     conf.level = 0.95) %>%
                                                             select(rate, lower, upper) %>%
                                                             mutate(year = c(as.character(2003:2019), "total")),
                                                           SIMPLIFY = F,
                                                           x, all_PY))

# List of infection rates by type of infection, per study group
infrate_menwomen <- lapply(inf_rate_type, function(x) list(overall = x$nostrat[18,1:3],
                                                           men = x$men[18,1:3],
                                                           women = x$women[18,1:3]))

# Keep one tibble of infection rates per type of infection with indication of the study group in which the infections were recorded
infrate_menwomen <- lapply(infrate_menwomen, function(x) bind_rows(x, .id = "group"))

# Make the list of tibbles with infection rates into one tibble with indication of the type of infection, and indicate that all infections during the follow-up period were included in the analysis
infrate_menwomen <- bind_rows(infrate_menwomen, .id = "infection") %>%
  mutate(event = "all infections")

# Make the separate tibbles with the infection rates per stratum into a bigger tibble with indication of the stratifying variable and the stratum itself
inf_rate_type <- lapply(inf_rate_type, function(x) dplyr::bind_rows(x, .id = "group") %>%
                          mutate(stratum = ifelse(grepl("men", group), "gender", "nostrat")))

# Make one tibble of infection rates with indication of the type of infection
inf_rate_type <- dplyr::bind_rows(inf_rate_type, .id = "infection")

# Split the tibble with infection rates into tibbles by stratifying variable, again to make separate plots
inf_rate_type <- split(inf_rate_type, f = inf_rate_type$stratum)

# Plot the infection rates per type of infection by stratifying variable
infratetype_P <- lapply(inf_rate_type, function(x)
  ggplot(data = subset(x, x$year != "total"),
         aes(x = as.numeric(year),
             y = rate,
             group = group)) +
    geom_line(aes(colour = group)) +
    geom_point(aes(colour = group)) +
    geom_ribbon(alpha = 0.3,
                aes(fill = group,
                    ymin = lower,
                    ymax = upper)) +
    scale_fill_discrete(name = element_blank()) +
    scale_colour_discrete(name = element_blank()) +
    scale_colour_viridis(discrete = T,
                         name = element_blank(),
                         option = "plasma",
                         begin = 0, end = 0.8) +
    scale_fill_viridis(discrete = T,
                       name = element_blank(),
                       option = "plasma",
                       begin = 0, end = 0.8) +
    #                        scale_y_continuous(limits = c(0, 0.8)) +
    labs(x = "Year",
         y = "Infection rate per PY") +
    theme_bw() +
    theme(legend.position = "top") +
    facet_wrap(~infection))

# Lay out the plots of infection rates per type of infection by stratifying variable
ggarrange(infratetype_P$nostrat,
          infratetype_P$gender,
          ncol = 1, nrow = 2,
          labels = c("AUTO"))

  ## Infections 5 years pre- and post-index date
### COUNT PERSON-YEARS OF FOLLOW-UP BY STRATA OF CALENDAR YEAR OF INDEX DATE ###

# 1. Create function:
# Input will be a tibble with rows of patients in a certain stratum of year of index date
# Output will be the total number of person-years (PY) per stratum per year

# 1.1. Create matrix with one row per patient in the cohort and one column per year of the study period (2003-2019)
# 1.2. Fill the matrix with the amount of follow-up (years) per patient per year of the study period
# 1.3. Create a new matrix with one row per year of the study period and one column for the cumulative number of PY per year

pystrat_yod <- function(strat_tibble) {
  
  strat_tibble <- strat_tibble %>%
    select(startFU, FUyears)
  
  PY <- matrix(NA, nrow(strat_tibble), ncol = 10)
  
  PY[, 1:5] <- 1
  
  for(i in 1:5) {
    
    PY[,i+5] <- ifelse(floor(strat_tibble$FUyears) > i, 1,
                       ifelse(ceiling(strat_tibble$FUyears) == i, strat_tibble$FUyears - (i - 1),
                              0))
    
  }
  
  PY_cum <- matrix(NA, 10, 1) 
  
  for (i in 1:10) {
    
    PY_cum[i,] <- sum(PY[,i])
    
  }
  
  PY_cum <- as_tibble(PY_cum) %>%
    rename(PY = V1)
  
  PY_cum[11,] <- sum(PY_cum[1:5,])
  PY_cum[12,] <- sum(PY_cum[6:10,])
  
  return(PY_cum)
}

cohort <- cohort %>%
  separate(startFU, into = c("yoe", "moe", "doe"), remove = F, convert = T) %>%
  mutate(yod_stratum = ifelse(yoe < 2003, "<2003",
                              ifelse(yoe >= 2003 & yoe <= 2005, "2003-2005",
                                     ifelse(yoe >= 2006 & yoe <= 2008, "2006-2008",
                                            ifelse(yoe >= 2009 & yoe <= 2011, "2009-2011",
                                                   ifelse(yoe >= 2012 & yoe <= 2015, "2012-2015", ">= 2016")))))) %>%
  select_at(vars(c(names(cohort), yod_stratum)))

# Function to make tibbles of strata based on year of index date
yodstrat_fun <- function(stratum) {
  
  yodstrat <- subset(cohort, cohort$yod_stratum == stratum)
  
}

# Indicate the four strata, make tibbles, and name them
yod_strata <- lapply(c("2003-2005", "2006-2008", "2009-2011", "2012-2015"), yodstrat_fun)
names(yod_strata) <- c("2003-2005", "2006-2008", "2009-2011", "2012-2015")

# Add the overall cohort to the list of tibbles by stratum of index date
yod_strata$overall <- cohort

# Count the number of PY of follow-up in each stratum
yod_PY <- lapply(yod_strata, pystrat_yod)

### INFECTIONS 5 YEARS PRE- AND POST INDEX DATE
# Indicte for all infection up to 5 years before infex date whether they were part of an ongoing episode or the start of a new episode
inf_prepost <- lapply(infections, infections_episodes, yearstoBL = 5, epis_duration = 28)

# Keep the infections that occurred in the period from 5 years before up until 5 years after the index date
inf_prepost2 <- mapply(function(x, y) inner_join(x, y, by = c("id", "eventdate", "startFU")) %>%
                         select_at(vars(c(names(inf_prepost$RI), endFU))) %>%
                         filter(eventdate >= startFU - 5*365.25 &
                                  eventdate <= startFU + 5*365.25 &
                                  eventdate <= endFU &
                                  inf_newepi == 1) %>%
                         select_at(vars(-contains("inf_newepi"))),
                       SIMPLIFY = F,
                       inf_prepost, infections)

# Re-structure the list of infections
inf_prepost2$any <- dplyr::bind_rows(inf_prepost2)

# Function to sum the number of infections per year relative to the index date
infstrat_yod <- function(strat_tibble) {
  
  inf <- matrix(NA, nrow = 10, ncol = 1)
  
  for(i in 1:4) {
    
    inf[i,] <- sum(floor((strat_tibble$eventdate-strat_tibble$startFU)/365.25) == (i + 1)*-1)
    
  }
  
  inf[5,] <- sum(floor((strat_tibble$eventdate-strat_tibble$startFU)/365.25) == -1 |
                   (strat_tibble$eventdate-strat_tibble$startFU)/365.25 == 0)
  
  for(i in 1:5) {
    
    inf[i+5,] <- sum(ceiling((strat_tibble$eventdate-strat_tibble$startFU)/365.25) == i)
    
  }
  
  inf[1:4] <- inf[4:1]
  
  inf_cum <- as_tibble(inf) %>%
    rename(inf = V1) 
  
  inf_cum[11,] = sum(inf_cum[1:5,])
  inf_cum[12,] = sum(inf_cum[6:10,])
  
  return(inf_cum)
}

# Sequential lapply to the lapply to include all combinations of types of infection and cohort strata
inf_prepost2 <- lapply(inf_prepost2, function(x) lapply(yod_strata, function(y) semi_join(x, y, by = "id")))

# Sum the number of infections by type of infection and by cohort stratum
inf_prepost2 <- lapply(inf_prepost2, function(x) lapply(x, infstrat_yod))

# Calculate the infection rate per year relative to index date by type of infection, in each stratum
inf_rate_prepost_type <- lapply(inf_prepost2, function(x) mapply(function(x, y) pois.exact(x$inf,
                                                                                           pt = y$PY,
                                                                                           conf.level = 0.95) %>%
                                                                   select(rate, lower, upper),
                                                                 SIMPLIFY = F,
                                                                 x, yod_PY))

# Indicate when infections occurred relative to index date,
# and the order in which to plot the years relative to index date when plotting the infection rates below
inf_rate_prepost_type <- lapply(inf_rate_prepost_type, function(x) lapply(x, function(x) x <- x %>%
                                                                            mutate(yrs_since_index = c(as.character(-5:-1), as.character(1:5), "pre", "post"),
                                                                                   position = factor(yrs_since_index, levels = c(-5:-1, 1:5, 0, 6)))))

# Bind the tibbles by stratum into bigger tibbles with indication of the stratum
inf_rate_prepost_type <- lapply(inf_rate_prepost_type, function(x) dplyr::bind_rows(x, .id = "id"))

# Make one tibble with infection rates pre- and post-index date, indicate the type of infection
inf_rate_prepost_type <- bind_rows(inf_rate_prepost_type, .id = "infection")

# Plot the infection rates by type of infection pre- and post-index date
infratepreposttype_P <- ggplot(data = subset(inf_rate_prepost_type, inf_rate_prepost_type$yrs_since_index != "pre" & inf_rate_prepost_type$yrs_since_index != "post"),
                               aes(x = position,
                                   y = rate,
                                   ymin = lower,
                                   ymax = upper,
                                   group = infection,
                                   fill = infection)) +
  geom_bar(size = 1,
           stat = "identity",
           position = "dodge",
           alpha = 0.5) +
  geom_errorbar(position = position_dodge(width = 1),
                aes(width = 0.5)) +
  scale_fill_viridis(discrete = T,
                     option = "plasma",
                     begin = 0, end = 0.8,
                     guide = 'none') +
  labs(x = "Years since index date",
       y = "Infection rate per person-year") +
  scale_x_discrete(breaks = c(as.character(-5:-1), as.character(1:5)),
                   labels = c("", "-4", "", "-2", "", "", "2", "", "4", "")) +
  theme_bw() +
  theme(panel.grid.major.x = element_blank(),
        panel.spacing.x = unit(0, "cm"),
        panel.spacing.y = unit(0.1, "cm")) +
  facet_grid(id ~ infection)

infratepreposttype_P
  