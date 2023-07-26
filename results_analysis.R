library(readxl)
library(dplyr)
library(tidyr)
library(lubridate)
library(ggplot2)
library(data.table)
library(rvest)

# load results data
times_combined <- data.frame()
for(i in list.files('./data/')){
  data <- read_excel(paste0('./data/',i)) %>%
    rename_all(~ gsub("\\(.*\\)", "", .)) #remove brackets from some checkpoint names to standardise
  data <- data %>%
    mutate(year = substr(i,0,4)) %>%
    select(year, Bib, Runner, Sex, Category, everything())
  
  times_combined <- bind_rows(times_combined, data, .id = 'id')
  rm(data)
}

# Extract the checkpoint names and distances from an event
scrape.distance <- function(event){
  url = paste0('https://centurionrunning.com/raceresult/',event)
  webpage <- read_html(url)
  
  # Extract the td tags' content
  td_content <- webpage %>%
    html_nodes("td.nopadding") %>%
    html_text()
  
  td_content <- head(td_content, 11)
  
  # Extract place name and number from the td content
  data <- tibble(
    checkpoint = gsub("\\(.*\\)", "", td_content),
    miles = gsub("[^\\(\\)0-9.]", "", td_content)
  )

  data$miles <- as.numeric(gsub("\\(|\\)", "", data$miles))
  data$km <- 1.62 * data$miles
  return(data)
}

distances <- scrape.distance('612e642b4bd9d6da4fb09a18')

speed_data <- times_combined %>%
  filter(Ashford != 'N/A') %>% # remove DNF runners
  mutate(runner = paste0(year, "_", Bib,"_", Runner)) %>%
  select(-c(id, Bib, Runner, Category, `Date Of Birth`, Position)) %>% 
  pivot_longer(cols = 3:18, names_to = 'checkpoint', values_to = 'time') %>% 
  merge(., distances, by = 'checkpoint') %>%
  mutate(time = hms(time),
         time_mins = period_to_seconds(time)/60,
         mins_per_km = time_mins/km)

speed_data %>%
  select(runner, checkpoint, time_mins) %>%
  pivot_wider(names_from = checkpoint, values_from = time_mins) %>% 
  select(-runner) %>%
  lm(Ashford ~ ., .) -> speed_model

time_range = c(29,30)

summary.table <- function(mintime, maxtime){
  speed_data %>%
    filter(checkpoint == 'Ashford') %>%
    filter(time_mins >= (mintime*60) & time_mins < (maxtime*60)) %>%
    select(runner) -> runner_filter
  
  speed_data %>%
    merge(., runner_filter, by = 'runner') %>%
    group_by(checkpoint) %>%
    summarise(mean = round(mean(time_mins, na.rm = TRUE),1),
              min = min(time_mins, na.rm = TRUE),
              max = max(time_mins, na.rm = TRUE),
              quantile = quantile(time_mins, p =0.75, na.rm = TRUE),
              mean_hms = seconds_to_period(seconds(mean*60)),
              min_hms = seconds_to_period(seconds(min*60)),
              max_hms = seconds_to_period(seconds(max*60))) %>%
    select(-c(mean, min, max, quantile)) %>%
    arrange(mean_hms) -> table.out
  
  return(table.out)
}

summary.plot <- function(mintime, maxtime){
  speed_data %>%
    filter(checkpoint == 'Ashford') %>%
    filter(time_mins >= (mintime*60) & time_mins < (maxtime*60)) %>%
    select(runner) -> runner_filter
  
  speed_data %>%
    merge(., runner_filter, by = 'runner') %>% 
    mutate(checkpoint = reorder(checkpoint, km)) %>%
    ggplot(aes(x = checkpoint, y = mins_per_km, colour = Sex)) +
    geom_boxplot() +
    theme_minimal() +
    ggtitle(paste0('Finishers between ', mintime,":00 and ", maxtime,":00")) -> plot.out
  
  return(plot.out)
}