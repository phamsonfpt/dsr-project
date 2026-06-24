source("r_processing/00_db_config.R")
source("r_processing/03_recommendation.R")

con <- get_db_connection()
# Load TF-IDF model
model <- build_tfidf_model(con)

# Test with mock profile
res <- compute_fit_score(
  candidate_skills = c("Python", "Machine Learning"),
  candidate_experience = "1 - 3 nam",
  target_title = "Data Scientist",
  model = model,
  con = con
)

print(res)

# Test fallback
res_fb <- compute_fit_score_fallback(
  profile = list(skills = c("Python"), experience = "1 - 3 nam", position = "Data Scientist"),
  jobs_df = dbGetQuery(con, "SELECT job_id, title, company, experience as experience_level, location, url, 'Python, R' as skills_text FROM jobs_clean")
)
print(res_fb)

dbDisconnect(con)
