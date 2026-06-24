# ==============================================================================
# test_cv_pipeline.R — Kiểm thử luồng xử lý CV phức tạp
# ==============================================================================
# Kịch bản:
# - User nhập một CV chi tiết (Education, Experience, Projects, Skills)
# - Vị trí muốn apply (Target Position)
# Hệ thống sẽ:
# 1. Ghép tất cả thành 1 đoạn văn bản (để khớp TF-IDF vectorizer)
# 2. Tính điểm phù hợp (Fit Score)
# 3. Phân tích Skill Gap
# 4. Tìm việc thay thế (Alternative positions qua K-Means)
# 5. Liệt kê công ty tuyển dụng cho vị trí ban đầu và vị trí thay thế

source("r_processing/00_db_config.R", encoding = "UTF-8")
source("r_processing/03_recommendation.R", encoding = "UTF-8")

# --- KỊCH BẢN ỨNG VIÊN ---
candidate_profile <- list(
  target_position = "Data Engineer",
  education = "Đại học Bách Khoa Hà Nội, chuyên ngành Khoa học Máy tính. GPA: 3.2/4.0",
  experience = "2 năm kinh nghiệm làm Data Analyst tại FPT Software. Xây dựng dashboard báo cáo và xử lý dữ liệu ETL.",
  projects = "Xây dựng hệ thống ETL Pipeline tự động với Airflow và Python. Thiết kế Data Warehouse bằng PostgreSQL.",
  skills = "Python, SQL, PostgreSQL, AWS, Airflow, PowerBI, ETL, Data Warehouse",
  languages = "IELTS 6.5",
  certificates = "AWS Certified Cloud Practitioner"
)

# Gộp tất cả text lại để mô hình TF-IDF có thể bám sát các từ khoá (nếu có trong JD)
rich_cv_text <- paste(
  candidate_profile$target_position,
  candidate_profile$education,
  candidate_profile$experience,
  candidate_profile$projects,
  candidate_profile$skills,
  candidate_profile$languages,
  candidate_profile$certificates,
  sep = " "
)

cat("\n============================================================\n")
cat("TEST LUỒNG RECOMMENDATION VỚI CV CHI TIẾT\n")
cat("============================================================\n")
cat("Ứng viên:\n")
cat("- Vị trí muốn apply:", candidate_profile$target_position, "\n")
cat("- Kỹ năng chính:", candidate_profile$skills, "\n")
cat("- Kinh nghiệm & Dự án:", paste(candidate_profile$experience, candidate_profile$projects, sep=" | "), "\n")

con <- get_db_connection()

tryCatch({
  # 1. Build TF-IDF Model
  model <- build_tfidf_model(con)

  # 2. Compute Fit Score
  # candidate_experience trong hàm gốc chỉ là đoạn text ngắn, nhưng ta có thể pass rich_cv_text vào đó
  # candidate_skills có thể giữ lại để dùng cho skill gap.
  skills_vec <- unlist(strsplit(candidate_profile$skills, ",\\s*"))
  
  scores <- compute_fit_score(
    candidate_skills = skills_vec,
    candidate_experience = rich_cv_text,  # truyền nguyên cục CV vào đây để tokenizer băm ra
    target_title = candidate_profile$target_position,
    model = model,
    con = con
  )

  # 3. Phân tích Skill Gap cho top 1 job
  if (nrow(scores) > 0) {
    top_job_id <- scores$job_id[1]
    gap <- analyze_skill_gap(skills_vec, top_job_id, con)
    cat("\n[!] Skill Gap cho vị trí Top 1 (", scores$title[1], "):\n", sep="")
    cat("    - Yêu cầu:", paste(gap$required_skills, collapse=", "), "\n")
    cat("    - Bạn đang thiếu:", paste(gap$missing_skills, collapse=", "), "\n")
  } else {
    cat("\nKhông tìm thấy công việc nào khớp với title:", candidate_profile$target_position, "\n")
  }

  # 4. Tìm việc làm thay thế (Alternative Positions)
  # Tạo document TF-IDF từ CV
  it_cand <- itoken(
    rich_cv_text,
    tokenizer   = .simple_tokenizer,
    ids         = "candidate",
    progressbar = FALSE
  )
  cand_dtm <- create_dtm(it_cand, model$vectorizer)
  cand_tfidf <- transform(cand_dtm, model$tfidf)
  
  alternatives <- find_alternative_jobs(cand_tfidf, model, n_clusters = 5, top_n = 5)
  
  cat("\n============================================================\n")
  cat("TỔNG KẾT KẾT QUẢ ĐẦU RA\n")
  cat("============================================================\n")
  
  cat("1. CÁC CÔNG TY ĐANG TUYỂN VỊ TRÍ MUỐN APPLY (", candidate_profile$target_position, "):\n", sep="")
  if (nrow(scores) > 0) {
    # Lấy top 5 công ty khác nhau
    companies_hiring <- unique(scores$company)
    cat(paste("   -", head(companies_hiring, 5)), sep="\n")
  } else {
    cat("   (Không có dữ liệu)\n")
  }
  
  cat("\n2. CÁC VỊ TRÍ THAY THẾ (ALTERNATIVE POSITIONS):\n")
  if (nrow(alternatives) > 0) {
    for (i in 1:nrow(alternatives)) {
      cat(sprintf("   - [%.1f%% Fit] %s @ %s\n", 
                  # Tính lại điểm cosine để in ra (nếu cần, tạm bỏ fit_score_pct ở đây vì find_alternative trả về raw meta)
                  0.0, # Placeholder
                  alternatives$title[i], 
                  alternatives$company[i]))
    }
    
    cat("\n3. CÔNG TY TUYỂN VỊ TRÍ THAY THẾ:\n")
    alt_companies <- unique(alternatives$company)
    cat(paste("   -", head(alt_companies, 5)), sep="\n")
  }

}, error = function(e) {
  cat("Lỗi:", conditionMessage(e), "\n")
}, finally = {
  close_db_connection(con)
})
