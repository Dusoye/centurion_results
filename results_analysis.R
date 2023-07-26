library(readxl)
library(dplyr)
library(lubridate)
library(ggplot2)
library(data.table)
library(rvest)

times_combined <- data.frame()
for(i in list.files('./data/')){
  data <- read_excel(paste0('./data/',i)) %>%
    rename_all(~ gsub("\\(.*\\)", "", .)) #remove brackets from some checkpoint names to standardise
  times_combined <- bind_rows(times_combined, data, .id = 'id')
  rm(data)
}

# Function to extract the checkpoint names and distnaces from an event
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


times_combined %>%
  #mutate_at(vars(8:20), hms) %>%
  select(colnames(data)) %>%
  mutate(runner = paste0(Bib,"_", Runner)) %>%
  select(c(runner,7:14)) %>%
  reshape2::melt(., id.var = 'runner') %>%
  mutate(value = hms(value)) %>%
  ggplot(aes(x = variable, y = value, colour = runner)) +
  geom_line() +
  theme_minimal()


times_combined %>%
  #mutate_at(vars(8:20), hms) %>%
  select(colnames(data)) %>%
  mutate(runner = paste0(Bib,"_", Runner)) %>%
  select(c(runner,7:14)) %>%
  reshape2::melt(., id.var = 'runner') %>%
  mutate(value = hms(value),
         value_mins = period_to_seconds(value)/60) %>%
  merge(., distances, by.x= 'variable', by.y = 'checkpoint') %>%
  mutate(mpk = value_mins / value.y) -> speed_data


speed_data %>%
  select(runner, variable, value_mins) %>%
  pivot_wider(names_from = variable, values_from = value_mins) %>%
  select(-runner) %>%
  lm(Eastbourne ~ ., .) -> speed_model

speed_data %>%
  filter(variable == 'Eastbourne') %>%
  filter(value_mins >= (23*60) & value_mins < (24*60)) %>%
  select(runner) -> runner_filter

speed_data %>%
  merge(., runner_filter, by = 'runner') %>%
  group_by(variable) %>%
  summarise(mean = mean(value_mins, na.rm = TRUE),
            max = max(value_mins, na.rm = TRUE),
            quantile = quantile(value_mins, p =0.75, na.rm = TRUE),
            mean_hms = seconds_to_period(seconds(mean*60)),
            max_hms = seconds_to_period(seconds(max*60)),
            q_hms = seconds_to_period(seconds(quantile*60))) %>%
  arrange(mean)

speed_data %>%
  merge(., runner_filter, by = 'runner') %>%
  arrange(value.y) %>%
  ggplot(aes(x = variable, y = mpk)) +
  geom_boxplot() +
  theme_minimal()