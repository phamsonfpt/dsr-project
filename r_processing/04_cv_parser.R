# ==============================================================================
# 04_cv_parser.R
# Module trích xuất thông tin từ file PDF CV
#
# Chức năng:
# - Đọc file PDF.
# - Rút trích vị trí ứng tuyển (Position).
# - Rút trích kỹ năng (Skills).
# - Rút trích số năm kinh nghiệm (Experience).
# ==============================================================================

if (!require("pdftools", quietly = TRUE)) {
  stop("Vui lòng cài đặt thư viện 'pdftools'.")
}
if (!require("stringr", quietly = TRUE)) {
  stop("Vui lòng cài đặt thư viện 'stringr'.")
}

# --- Từ điển kỹ năng IT mẫu ---
IT_SKILLS_DICT <- c(
  "python", "r", "java", "c++", "c#", "javascript", "typescript",
  "html", "css", "react", "angular", "vue", "node.js", "nodejs",
  "express", "django", "flask", "fastapi", "spring", "asp.net",
  "sql", "mysql", "postgresql", "mongodb", "redis", "elasticsearch",
  "aws", "azure", "gcp", "docker", "kubernetes", "jenkins", "git",
  "machine learning", "deep learning", "nlp", "computer vision",
  "tensorflow", "pytorch", "keras", "scikit-learn", "pandas", "numpy",
  "hadoop", "spark", "kafka", "airflow", "tableau", "power bi",
  "figma", "ui/ux", "agile", "scrum", "linux", "bash", "shell"
)

# --- Từ điển Vị trí / Title ---
IT_ROLES_DICT <- c(
  "data scientist", "data analyst", "data engineer", "machine learning engineer",
  "backend developer", "frontend developer", "fullstack developer", "web developer",
  "mobile developer", "ios developer", "android developer", "software engineer",
  "devops engineer", "system administrator", "cloud engineer", "security engineer",
  "qa engineer", "tester", "business analyst", "product manager", "project manager",
  "ui/ux designer", "game developer", "embedded engineer", "ai engineer"
)

# ==============================================================================
# parse_cv_features()
#
# Tham số:
#   pdf_path: Đường dẫn đến file PDF.
#
# Trả về: list(skills, experience, position)
# ==============================================================================
parse_cv_features <- function(pdf_path) {
  # 1. Đọc text từ PDF
  text <- pdftools::pdf_text(pdf_path)
  full_text <- paste(text, collapse = " ")
  text_lower <- tolower(full_text)

  # 2. Rút trích Kỹ năng
  found_skills <- c()
  for (skill in IT_SKILLS_DICT) {
    # Dùng regex bound \b để khớp chính xác từ (ví dụ \br\b không khớp chữ 'r' trong 'string')
    pattern <- paste0("\\b", str_replace_all(skill, "\\+", "\\\\+"), "\\b")
    if (str_detect(text_lower, pattern)) {
      found_skills <- c(found_skills, skill)
    }
  }
  # Chuẩn hóa format
  if ("node.js" %in% found_skills) found_skills <- unique(c(found_skills, "nodejs"))

  # 3. Rút trích Vị trí (Title)
  found_position <- "Software Engineer" # Default
  for (role in IT_ROLES_DICT) {
    if (str_detect(text_lower, role)) {
      found_position <- tools::toTitleCase(role)
      break
    }
  }

  # 4. Rút trích Kinh nghiệm (Experience)
  # Phân tích theo số năm hoặc level
  experience <- "Chưa có kinh nghiệm"
  if (str_detect(text_lower, "senior|trên 5 năm|> 5 years|5\\+ years|lead|manager")) {
    experience <- "Trên 5 năm"
  } else if (str_detect(text_lower, "middle|3 năm|4 năm|5 năm|3 - 5 năm|3 to 5 years")) {
    experience <- "3 - 5 năm"
  } else if (str_detect(text_lower, "junior|1 năm|2 năm|3 năm|1 - 3 năm|1 to 3 years")) {
    experience <- "1 - 3 năm"
  } else if (str_detect(text_lower, "fresher|dưới 1 năm|< 1 year")) {
    experience <- "Dưới 1 năm"
  } else if (str_detect(text_lower, "intern|thực tập sinh")) {
    experience <- "Chưa có kinh nghiệm"
  } else {
    # Nếu có đề cập đến năm
    nums <- str_extract_all(text_lower, "\\b\\d+\\s*(năm|years)\\b")[[1]]
    if (length(nums) > 0) {
      max_year <- max(as.numeric(str_extract(nums, "\\d+")))
      if (max_year >= 5) experience <- "Trên 5 năm"
      else if (max_year >= 3) experience <- "3 - 5 năm"
      else if (max_year >= 1) experience <- "1 - 3 năm"
      else experience <- "Dưới 1 năm"
    }
  }

  return(list(
    skills = found_skills,
    experience = experience,
    position = found_position
  ))
}
