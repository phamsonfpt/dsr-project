# ==============================================================================
# 01_data_cleaning.R — Làm sạch và nạp dữ liệu CSV vào SQLite
# Job Recommendation & Market Analysis Platform
# ==============================================================================
# Module cung cấp:
#   - clean_and_load_data() : Đọc CSV → làm sạch → nạp vào jobs_clean + job_skills
#   - Tách các kỹ năng từ chuỗi, lọc các kỹ năng IT cốt lõi
#   - Phân tách Job Description thành Mô tả, Yêu cầu, Quyền lợi
# ==============================================================================

# Từ điển các kỹ năng/từ khóa IT cơ bản (dùng để lọc rác)
IT_SKILLS_DICT <- c("java", "python", "sql", "react", "angular", "vue", "node", "javascript", 
                   "html", "css", "c\\+\\+", "c#", "\\.net", "php", "ruby", "go", "rust", 
                   "aws", "azure", "gcp", "docker", "kubernetes", "linux", "git", "api",
                   "spring", "django", "laravel", "flask", "swift", "kotlin", "flutter",
                   "dart", "android", "ios", "machine learning", "ai", "data", "qa", "qc",
                   "tester", "devops", "agile", "scrum", "backend", "frontend", "fullstack",
                   "system", "network", "security", "cloud", "mobile", "web", "UI", "UX",
                   "product", "project", "BA", "business analyst", "software",
                   "engineer", "developer", "lập trình", "công nghệ")

# --- Nạp module cấu hình DB -------------------------------------------------
# Tự động tìm đường dẫn tương đối đến 00_db_config.R
local({
  this_dir <- tryCatch(
    dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
    error = function(e) {
      args <- commandArgs(trailingOnly = FALSE)
      f <- grep("^--file=", args, value = TRUE)
      if (length(f) > 0) dirname(normalizePath(sub("^--file=", "", f[1]), winslash = "/"))
      else getwd()
    }
  )
  config_path <- file.path(this_dir, "00_db_config.R")
  if (!file.exists(config_path)) {
    # Fallback: tìm trong r_processing/ từ project root
    config_path <- file.path(getwd(), "r_processing", "00_db_config.R")
  }
  if (file.exists(config_path)) source(config_path, encoding = "UTF-8")
  else stop("[DATA_CLEAN] Kh\u00f4ng t\u00ecm th\u1ea5y 00_db_config.R")
})

# --- Nạp thư viện -----------------------------------------------------------
for (pkg in c("dplyr", "stringr", "readr", "tidyr")) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg)
}
library(dplyr)
library(stringr)
library(readr)
library(tidyr)

# ==============================================================================
# Bảng mapping tên thành phố (viết tắt / phổ biến → chuẩn hóa)
# ==============================================================================
.city_mapping <- c(
  "hcm"               = "TP.HCM",
  "ho chi minh"       = "TP.HCM",
  "tp hcm"            = "TP.HCM",
  "tp.hcm"            = "TP.HCM",
  "tp. hcm"           = "TP.HCM",
  "thanh pho ho chi minh" = "TP.HCM",
  "sai gon"           = "TP.HCM",
  "saigon"            = "TP.HCM",
  "hn"                = "H\u00e0 N\u1ed9i",
  "ha noi"            = "H\u00e0 N\u1ed9i",
  "hanoi"             = "H\u00e0 N\u1ed9i",
  "dn"                = "\u0110\u00e0 N\u1eb5ng",
  "da nang"           = "\u0110\u00e0 N\u1eb5ng",
  "danang"            = "\u0110\u00e0 N\u1eb5ng",
  "hue"               = "Hu\u1ebf",
  "hai phong"         = "H\u1ea3i Ph\u00f2ng",
  "hp"                = "H\u1ea3i Ph\u00f2ng",
  "can tho"           = "C\u1ea7n Th\u01a1",
  "ct"                = "C\u1ea7n Th\u01a1",
  "bien hoa"          = "Bi\u00ean H\u00f2a",
  "vung tau"          = "V\u0169ng T\u00e0u",
  "nha trang"         = "Nha Trang",
  "quy nhon"          = "Quy Nh\u01a1n",
  "bac ninh"          = "B\u1eafc Ninh",
  "thai nguyen"       = "Th\u00e1i Nguy\u00ean",
  "vinh"              = "Vinh",
  "buon ma thuot"     = "Bu\u00f4n Ma Thu\u1ed9t",
  "long an"           = "Long An",
  "dong nai"          = "\u0110\u1ed3ng Nai",
  "binh duong"        = "B\u00ecnh D\u01b0\u01a1ng"
)

# ==============================================================================
# Hàm chuẩn hóa text: lowercase, bỏ ký tự đặc biệt, trim
# ==============================================================================
.standardize_text <- function(x) {
  x %>%
    str_to_lower() %>%
    str_replace_all("[^\\p{L}\\p{N}\\s.+#/-]", " ") %>%   # giữ chữ, số, dấu chấm, +, #, /, -
    str_squish()                                             # gộp khoảng trắng thừa
}

# ==============================================================================
# Hàm chuẩn hóa tên thành phố
# ==============================================================================
.normalize_city <- function(city_raw) {
  if (is.na(city_raw) || !nzchar(trimws(city_raw))) return(NA_character_)

  # Chuẩn hóa: lowercase, bỏ dấu tiếng Việt cho so sánh, trim
  city_lower <- city_raw %>%
    str_to_lower() %>%
    str_replace_all("[^\\p{L}\\p{N}\\s.]", " ") %>%
    str_squish()

  # Thử tìm trong bảng mapping
  matched <- .city_mapping[city_lower]
  if (!is.na(matched)) return(unname(matched))

  # Nếu không match chính xác, thử tìm partial match

  for (key in names(.city_mapping)) {
    if (str_detect(city_lower, fixed(key))) {
      return(unname(.city_mapping[key]))
    }
  }

  # Không tìm thấy → giữ nguyên (capitalize first letter)
  return(str_to_title(trimws(city_raw)))
}

# Removed .parse_salary()

# ==============================================================================
# Hàm phân loại kinh nghiệm
# Input: chuỗi text mô tả kinh nghiệm (ví dụ "2 năm", "3-5 years")
# Output: Fresher / Junior / Mid / Senior
# ==============================================================================
.classify_experience <- function(exp_text) {
  if (is.na(exp_text) || !nzchar(trimws(exp_text))) return(NA_character_)

  s <- str_to_lower(trimws(exp_text))

  # Nhận diện keyword trực tiếp
  if (str_detect(s, "fresher|intern|th\u1ef1c t\u1eadp|m\u1edbi ra tr\u01b0\u1eddng|kh\u00f4ng y\u00eau c\u1ea7u")) {
    return("Fresher")
  }
  if (str_detect(s, "senior|tr\u01b0\u1edfng|lead|manager|qu\u1ea3n l\u00fd|expert|principal")) {
    return("Senior")
  }

  # Trích xuất số năm kinh nghiệm
  # Pattern: "X năm" hoặc "X-Y năm" hoặc "X years" hoặc "X+"
  range_match <- str_match(s, "(\\d+)\\s*[-–]\\s*(\\d+)\\s*(năm|year)")
  if (!is.na(range_match[1, 1])) {
    years <- mean(c(as.numeric(range_match[1, 2]), as.numeric(range_match[1, 3])))
  } else {
    num_match <- str_match(s, "(\\d+)\\s*(năm|year)")
    if (!is.na(num_match[1, 1])) {
      years <- as.numeric(num_match[1, 2])
    } else {
      return(NA_character_)
    }
  }

  # Phân loại theo số năm
  if (years <= 1)      return("Fresher")
  else if (years <= 3) return("Junior")
  else if (years <= 5) return("Mid")
  else                 return("Senior")
}

# ==============================================================================
# Hàm tách chuỗi skills thành vector riêng biệt
# Input: "Python, SQL, Git" hoặc "Python; SQL; Git" hoặc "Python/SQL/Git"
# Output: c("python", "sql", "git")
# ==============================================================================
.split_skills <- function(skills_text) {
  if (is.na(skills_text) || !nzchar(trimws(skills_text))) return(character(0))

  skills <- skills_text %>%
    str_split("[,;/|]") %>%
    unlist() %>%
    str_squish() %>%
    str_to_lower()

  # Loại bỏ phần tử rỗng
  skills <- skills[nzchar(skills)]
  
  # Chỉ giữ lại skill nếu có chứa một trong các từ khóa thuộc IT_SKILLS_DICT
  valid_skills <- skills[sapply(skills, function(s) any(str_detect(s, IT_SKILLS_DICT)))]
  
  return(unique(valid_skills))
}

# ==============================================================================
# Hàm phân tách Job Description thành 3 phần: Mô tả, Yêu cầu, Quyền lợi
# ==============================================================================
.parse_jd_sections <- function(jd_text) {
  if (is.na(jd_text) || !nzchar(trimws(jd_text))) {
    return(list(desc = NA_character_, req = NA_character_, ben = NA_character_))
  }
  
  # Định nghĩa các pattern chia section (Regex)
  req_pattern <- "(?is)(yêu cầu ứng viên|yêu cầu công việc|kinh nghiệm yêu cầu).*?(?=(quyền lợi|phúc lợi|công ty cung cấp những gì|thời gian làm việc|địa điểm làm việc|$))"
  ben_pattern <- "(?is)(quyền lợi|phúc lợi|công ty cung cấp những gì|chế độ).*?(?=(yêu cầu ứng viên|yêu cầu công việc|thời gian làm việc|địa điểm làm việc|$))"
  
  # Trích xuất Yêu cầu và Quyền lợi
  req_text <- str_extract(jd_text, req_pattern)
  ben_text <- str_extract(jd_text, ben_pattern)
  
  # Mô tả công việc (desc) = Phần còn lại sau khi trừ đi Yêu cầu và Quyền lợi
  desc_text <- jd_text
  if (!is.na(req_text)) desc_text <- str_replace(desc_text, fixed(req_text), "")
  if (!is.na(ben_text)) desc_text <- str_replace(desc_text, fixed(ben_text), "")
  
  # Trừ thêm các thông tin phụ (Thời gian, địa điểm) để mô tả sạch hơn
  extra_pattern <- "(?is)(thời gian làm việc|địa điểm làm việc|thông tin việc làm|cách thức ứng tuyển).*?$"
  desc_text <- str_replace(desc_text, extra_pattern, "")
  
  return(list(
    desc = trimws(desc_text),
    req = if(!is.na(req_text)) trimws(req_text) else NA_character_,
    ben = if(!is.na(ben_text)) trimws(ben_text) else NA_character_
  ))
}

# ==============================================================================
# Hàm tự động phát hiện encoding của file CSV
# ==============================================================================
.detect_encoding <- function(file_path) {
  # Thử đọc vài dòng với UTF-8 trước
  tryCatch({
    readLines(file_path, n = 5, encoding = "UTF-8", warn = FALSE)
    return("UTF-8")
  }, error = function(e) NULL)

  # Fallback: latin1
  return("latin1")
}

# ==============================================================================
# clean_and_load_data()
# Hàm chính: đọc CSV → làm sạch → nạp vào DB
# ==============================================================================
clean_and_load_data <- function() {
  message("\n", strrep("=", 60))
  message("[DATA_CLEAN] B\u1eaft \u0111\u1ea7u quy tr\u00ecnh l\u00e0m s\u1ea1ch d\u1eef li\u1ec7u...")
  message(strrep("=", 60))

  # --- 1. Tìm thư mục data/raw/ -----------------------------------------------
  root <- get_project_root()
  raw_dir <- file.path(root, "data", "raw")
  
  if (!dir.exists(raw_dir)) {
    stop("[DATA_CLEAN] Th\u01b0 m\u1ee5c data/raw/ kh\u00f4ng t\u1ed3n t\u1ea1i: ", raw_dir)
  }

  csv_files <- list.files(raw_dir, pattern = "\\.csv$", full.names = TRUE, ignore.case = TRUE)
  if (length(csv_files) == 0) {
    message("[DATA_CLEAN] Kh\u00f4ng c\u00f3 file CSV n\u00e0o trong data/raw/. K\u1ebft th\u00fac.")
    return(invisible(NULL))
  }

  message("[DATA_CLEAN] T\u00ecm th\u1ea5y ", length(csv_files), " file CSV:")
  for (f in csv_files) message("  \u2192 ", basename(f))

  # --- 2. Đọc và gộp tất cả CSV -----------------------------------------------
  all_data <- list()
  for (csv_path in csv_files) {
    message("\n[DATA_CLEAN] \u0110ang \u0111\u1ecdc: ", basename(csv_path))

    df <- tryCatch({
      enc <- .detect_encoding(csv_path)
      readr::read_csv(
        csv_path,
        locale        = locale(encoding = enc),
        col_types     = cols(.default = "c"),   # đọc tất cả cột dạng text
        show_col_types = FALSE,
        name_repair   = "minimal"
      )
    }, error = function(e) {
      message("[DATA_CLEAN] L\u1ed7i \u0111\u1ecdc file ", basename(csv_path), ": ", conditionMessage(e))
      return(NULL)
    })

    if (is.null(df) || nrow(df) == 0) {
      message("[DATA_CLEAN] File r\u1ed7ng ho\u1eb7c l\u1ed7i, b\u1ecf qua.")
      next
    }

    # Chuẩn hóa tên cột: lowercase, bỏ khoảng trắng
    names(df) <- names(df) %>%
      str_to_lower() %>%
      str_replace_all("[^a-z0-9_]", "_") %>%
      str_replace_all("_+", "_") %>%
      str_remove("^_|_$")

    # Thêm cột source từ tên file (ví dụ: topcv_jobs.csv → topcv)
    df$source <- basename(csv_path) %>%
      str_remove("\\.csv$") %>%
      str_to_lower() %>%
      str_extract("^[a-z]+")

    message("[DATA_CLEAN]   ", nrow(df), " d\u00f2ng, ", ncol(df), " c\u1ed9t")
    all_data[[length(all_data) + 1]] <- df
  }

  if (length(all_data) == 0) {
    message("[DATA_CLEAN] Kh\u00f4ng c\u00f3 d\u1eef li\u1ec7u h\u1ee3p l\u1ec7 n\u00e0o \u0111\u01b0\u1ee3c \u0111\u1ecdc.")
    return(invisible(NULL))
  }

  # Gộp tất cả dataframe (bind_rows xử lý cột thiếu tự động)
  raw_df <- bind_rows(all_data)
  message("\n[DATA_CLEAN] T\u1ed5ng c\u1ed9ng: ", nrow(raw_df), " d\u00f2ng th\u00f4")

  # --- 3. Chuẩn hóa các cột chính ---------------------------------------------
  message("[DATA_CLEAN] \u0110ang chu\u1ea9n h\u00f3a d\u1eef li\u1ec7u...")

  # Tìm tên cột tương ứng (hỗ trợ nhiều tên gọi khác nhau)
  .find_col <- function(df, patterns) {
    for (p in patterns) {
      matched <- grep(p, names(df), value = TRUE, ignore.case = TRUE)
      if (length(matched) > 0) return(matched[1])
    }
    return(NA_character_)
  }

  col_title      <- .find_col(raw_df, c("^title$", "tieu_de", "job_title", "vi_tri", "position"))
  col_company    <- .find_col(raw_df, c("^company$", "cong_ty", "employer", "nha_tuyen_dung"))
  col_location   <- .find_col(raw_df, c("location", "dia_diem", "thanh_pho", "city", "noi_lam_viec"))
  col_url        <- .find_col(raw_df, c("^url$", "link", "href", "job_url"))
  col_jd         <- .find_col(raw_df, c("job_description", "description", "jd", "mo_ta"))
  col_req        <- .find_col(raw_df, c("requirements", "req", "yeu_cau"))
  col_ben        <- .find_col(raw_df, c("benefits", "ben", "quyen_loi", "phuc_loi"))
  col_level      <- .find_col(raw_df, c("^level$", "cap_bac"))
  col_exp        <- .find_col(raw_df, c("experience", "kinh_nghiem"))

  # Kiểm tra cột bắt buộc
  if (is.na(col_title) || is.na(col_company) || is.na(col_url)) {
    stop("[DATA_CLEAN] Thiếu cột bắt buộc (title, company, url). ",
         "Các cột hiện có: ", paste(names(raw_df), collapse = ", "))
  }

  # Xây dựng dataframe chuẩn
  clean_df <- data.frame(
    title      = trimws(raw_df[[col_title]]),
    company    = trimws(raw_df[[col_company]]),
    location_raw = if (!is.na(col_location)) raw_df[[col_location]] else NA_character_,
    url        = trimws(raw_df[[col_url]]),
    experience = if (!is.na(col_exp)) raw_df[[col_exp]] else NA_character_,
    job_description = if (!is.na(col_jd)) raw_df[[col_jd]] else NA_character_,
    requirements = if (!is.na(col_req)) raw_df[[col_req]] else NA_character_,
    benefits = if (!is.na(col_ben)) raw_df[[col_ben]] else NA_character_,
    level = if (!is.na(col_level)) raw_df[[col_level]] else NA_character_,
    source     = raw_df$source,
    stringsAsFactors = FALSE
  )
  
  # Nếu cột yêu cầu hoặc quyền lợi hoàn toàn rỗng, ta fallback dùng hàm parse text (dành cho dữ liệu cũ)
  if (all(is.na(clean_df$requirements) | clean_df$requirements == "")) {
    message("[DATA_CLEAN] Không tìm thấy cột requirements từ CSV, tự động phân tách Job Description...")
    parsed_jd <- lapply(clean_df$job_description, .parse_jd_sections)
    clean_df$job_description <- sapply(parsed_jd, `[[`, "desc")
    clean_df$requirements <- sapply(parsed_jd, `[[`, "req")
    clean_df$benefits <- sapply(parsed_jd, `[[`, "ben")
  }

  # Cập nhật experience nếu thiếu
  if (all(is.na(clean_df$experience) | clean_df$experience == "")) {
    clean_df$experience <- sapply(clean_df$requirements, .classify_experience, USE.NAMES = FALSE)
  }

  # --- 4. Normalize location ----------------------------------------------------
  message("[DATA_CLEAN] Đang chuẩn hóa địa điểm...")
  clean_df$location <- sapply(clean_df$location_raw, .normalize_city, USE.NAMES = FALSE)

  # --- 5. Classify experience fallback ------------------------------------------
  # Đã xử lý ở trên, ta không cần ghi đè bằng phân loại cũ nữa unless requested.

  # --- 7. Deduplicate -----------------------------------------------------------
  n_before <- nrow(clean_df)
  clean_df <- clean_df %>%
    distinct(title, company, url, .keep_all = TRUE)
  n_after <- nrow(clean_df)
  message("[DATA_CLEAN] Lo\u1ea1i tr\u00f9ng: ", n_before, " \u2192 ", n_after,
          " (b\u1ecf ", n_before - n_after, " b\u1ea3n ghi tr\u00f9ng)")

  # Loại bỏ hàng thiếu URL
  clean_df <- clean_df %>% filter(!is.na(url), nzchar(url))
  message("[DATA_CLEAN] Sau l\u1ecdc URL h\u1ee3p l\u1ec7: ", nrow(clean_df), " b\u1ea3n ghi")

  # --- 8. Tách skills thành bảng riêng ------------------------------------------
  message("[DATA_CLEAN] \u0110ang t\u00e1ch k\u1ef9 n\u0103ng t\u1eeb nội dung...")
  skills_list <- lapply(seq_len(nrow(clean_df)), function(i) {
    text_to_search <- paste(clean_df$job_description[i], clean_df$requirements[i], sep = " ")
    text_to_search <- str_to_lower(text_to_search)
    
    # Tìm các từ khóa IT nguyên vẹn (dùng regex boundary để tránh match nhầm như "html" trong "xhtml")
    found_skills <- c()
    for (s in IT_SKILLS_DICT) {
      if (str_detect(text_to_search, regex(paste0("\\b", s, "\\b"), ignore_case = TRUE))) {
        found_skills <- c(found_skills, s)
      }
    }
    
    # C++ và C# cần regex đặc biệt
    if (str_detect(text_to_search, fixed("c++"))) found_skills <- c(found_skills, "c++")
    if (str_detect(text_to_search, fixed("c#"))) found_skills <- c(found_skills, "c#")
    if (str_detect(text_to_search, fixed(".net"))) found_skills <- c(found_skills, ".net")
    
    found_skills <- unique(found_skills)
    
    if (length(found_skills) > 0) {
      tibble(row_idx = i, skill_name = found_skills)
    } else {
      NULL
    }
  })
  skills_df <- bind_rows(skills_list)
  message("[DATA_CLEAN] T\u1ed5ng s\u1ed1 c\u1eb7p job-skill: ", nrow(skills_df))

  # --- 9. Ghi vào DB -----------------------------------------------------------
  message("\n[DATA_CLEAN] \u0110ang ghi d\u1eef li\u1ec7u v\u00e0o SQLite...")
  con <- get_db_connection()

  tryCatch({
    # Bắt đầu transaction cho performance
    dbBegin(con)

    # Xóa dữ liệu cũ để đảm bảo mỗi lần chạy là dữ liệu mới (theo yêu cầu user)
    dbExecute(con, "DELETE FROM jobs_clean")
    dbExecute(con, "DELETE FROM job_skills")
    dbExecute(con, "DELETE FROM market_trends")
    
    # Đặt lại bộ đếm AUTOINCREMENT về 0 (để id và job_id bắt đầu lại từ 1)
    dbExecute(con, "DELETE FROM sqlite_sequence WHERE name='jobs_clean'")
    dbExecute(con, "DELETE FROM sqlite_sequence WHERE name='job_skills'")
    dbExecute(con, "DELETE FROM sqlite_sequence WHERE name='market_trends'")

    # UPSERT jobs_clean: dùng INSERT OR REPLACE (url là UNIQUE)
    jobs_insert <- clean_df %>%
      select(title, company, location, url, source, experience, job_description, requirements, benefits, level) %>%
      mutate(
        scraped_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        updated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      )

    # Chuẩn bị câu lệnh INSERT OR REPLACE
    insert_sql <- paste0(
      "INSERT OR REPLACE INTO jobs_clean ",
      "(title, company, location, url, source, experience, job_description, requirements, benefits, level, scraped_at, updated_at) ",
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    )

    stmt <- dbSendStatement(con, insert_sql)
    n_inserted <- 0

    for (i in seq_len(nrow(jobs_insert))) {
      row <- jobs_insert[i, ]
      tryCatch({
        dbBind(stmt, list(
          row$title, row$company, row$location,
          row$url, row$source, row$experience,
          row$job_description, row$requirements, row$benefits, row$level,
          row$scraped_at, row$updated_at
        ))
        n_inserted <- n_inserted + 1
      }, error = function(e) {
        message("[DATA_CLEAN]   C\u1ea3nh b\u00e1o d\u00f2ng ", i, ": ", conditionMessage(e))
      })
    }
    dbClearResult(stmt)
    message("[DATA_CLEAN] \u0110\u00e3 ghi ", n_inserted, "/", nrow(jobs_insert), " b\u1ea3n ghi v\u00e0o jobs_clean")

    # Lấy lại job_id cho mỗi URL (để map skills)
    url_to_id <- dbGetQuery(con, "SELECT job_id, url FROM jobs_clean")

    # Ghi job_skills
    if (nrow(skills_df) > 0) {
      # Map row_idx → url → job_id
      skills_df$url <- clean_df$url[skills_df$row_idx]
      skills_df <- skills_df %>%
        inner_join(url_to_id, by = "url") %>%
        select(job_id, skill_name)

      # Xóa skills cũ của các job được cập nhật
      affected_ids <- unique(skills_df$job_id)
      if (length(affected_ids) > 0) {
        placeholders <- paste(rep("?", length(affected_ids)), collapse = ",")
        dbExecute(
          con,
          paste0("DELETE FROM job_skills WHERE job_id IN (", placeholders, ")"),
          params = as.list(affected_ids)
        )
      }

      # INSERT skills mới
      skill_sql <- "INSERT OR IGNORE INTO job_skills (job_id, skill_name) VALUES (?, ?)"
      skill_stmt <- dbSendStatement(con, skill_sql)
      n_skills <- 0
      for (i in seq_len(nrow(skills_df))) {
        tryCatch({
          dbBind(skill_stmt, list(skills_df$job_id[i], skills_df$skill_name[i]))
          n_skills <- n_skills + 1
        }, error = function(e) NULL)
      }
      dbClearResult(skill_stmt)
      message("[DATA_CLEAN] \u0110\u00e3 ghi ", n_skills, " b\u1ea3n ghi v\u00e0o job_skills")
    }

    dbCommit(con)
    message("\n[DATA_CLEAN] \u2705 Ho\u00e0n t\u1ea5t quy tr\u00ecnh l\u00e0m s\u1ea1ch d\u1eef li\u1ec7u!")

  }, error = function(e) {
    dbRollback(con)
    message("[DATA_CLEAN] \u274c L\u1ed7i: ", conditionMessage(e))
    stop(e)
  }, finally = {
    close_db_connection(con)
  })

  # Trả về summary
  invisible(list(
    total_jobs   = nrow(clean_df),
    total_skills = nrow(skills_df),
    files_read   = length(csv_files)
  ))
}

message("[DATA_CLEAN] Module 01_data_cleaning.R \u0111\u00e3 s\u1eb5n s\u00e0ng.")
message("  G\u1ecdi clean_and_load_data() \u0111\u1ec3 ch\u1ea1y quy tr\u00ecnh l\u00e0m s\u1ea1ch.")
