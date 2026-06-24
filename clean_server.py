import re
with open('shiny_app/server.R', 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Remove salary_market from rv
code = re.sub(r'\s*salary_market\s*=\s*NULL,', '', code)
# 2. Remove alternative_jobs from rv
code = re.sub(r',\s*alternative_jobs\s*=\s*NULL', '', code)

# 3. Remove vb_avg_salary block
code = re.sub(r'  # --- Value Box: Average Salary ---.*?(?=  # --- Value Box: Top Skill ---)', '  # Removed vb_avg_salary\n\n', code, flags=re.DOTALL)

# 4. Remove chart_salary_role block
code = re.sub(r'  # --- Chart: Salary by Role \(Box Plot\) ---.*?(?=  # --- Chart: Jobs by Location \(Donut\) ---)', '  # Removed chart_salary_role\n\n', code, flags=re.DOTALL)

# 5. Fix Step 4 (salary comparison) and Step 5 (alternative jobs)
code = re.sub(r'        # --------------------------------------------------\n        # Step 4: Market salary for comparison.*?(?=        # --------------------------------------------------\n        # Store results in reactiveValues)', '        # Removed step 4 & 5\n', code, flags=re.DOTALL)

# 6. Remove alternative_jobs and salary_market assignments
code = re.sub(r'\s*rv\$salary_market\s*<-\s*market_salary\n', '\n', code)
code = re.sub(r'\s*rv\$alternative_jobs\s*<-\s*alt_jobs\n', '\n', code)

# 7. Update jobs_query (salary_min/max -> experience/level)
code = code.replace('SELECT j.job_id, j.title, j.company, j.salary_min, j.salary_max,\n                 j.experience_level, j.location, j.url,', 'SELECT j.job_id, j.title, j.company, j.experience, j.level, j.location, j.url,')
code = code.replace('SELECT j.job_id, j.title, j.company,\n                 j.experience_level, j.location, j.url,', 'SELECT j.job_id, j.title, j.company, j.experience, j.level, j.location, j.url,')
code = code.replace('GROUP BY j.job_id, j.title, j.company, j.salary_min, j.salary_max, j.experience_level, j.location, j.url', 'GROUP BY j.job_id')

# 8. Update salary_match
code = re.sub(r'      # Salary range match.*?(?=      round\(\(skill_match)', '', code, flags=re.DOTALL)
code = code.replace('round((skill_match * 0.55 + title_match + exp_match + salary_match) * 100, 1)', 'round((skill_match * 0.8 + exp_match * 0.2) * 100, 1)')
code = code.replace('exp_match <- if (!is.na(jobs_df$experience_level[i]) &&\n                       tolower(jobs_df$experience_level[i]) == tolower(profile$experience)) 0.15 else 0', 'exp_match <- if (!is.na(jobs_df$experience[i]) &&\n                       tolower(jobs_df$experience[i]) == tolower(profile$experience)) 0.2 else 0')

# 9. Remove chart_salary_compare
code = re.sub(r'  # --- Salary Comparison Chart ---.*?(?=  # --- Job Matches DataTable ---)', '  # Removed chart_salary_compare\n\n', code, flags=re.DOTALL)

# 10. Update table_job_matches
code = re.sub(r'      `Lương \(triệu VND\)` = ifelse\([^)]*\),', '', code, flags=re.DOTALL)
code = code.replace('df$experience_level', 'df$experience')

# 11. Remove profile$salary
code = re.sub(r',\s*salary\s*=\s*NA', '', code)
code = re.sub(r',\s*salary\s*=\s*input\$user_salary', '', code)

# 12. Remove alt_jobs_ui
code = re.sub(r'  # --- Alternative Jobs UI \(shown when fit_score < 50%\) ---.*?(?=  # --- Fallback Functions ---|  # --- END SERVER ---)', '', code, flags=re.DOTALL)

with open('shiny_app/server.R', 'w', encoding='utf-8') as f:
    f.write(code)
