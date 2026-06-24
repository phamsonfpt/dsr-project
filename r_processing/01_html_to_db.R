# ==============================================================================
# 01_html_to_db.R — Pipeline: HTML + CSV → Database SQLite
# Job Recommendation & Market Analysis Platform
# ==============================================================================
# Chức năng:
#   1. Đọc toàn bộ file *.html trong data/HTML/ (Nguồn TopCV)
#   2. Đọc file CSV trong data/raw/vnw_jobs_raw.csv (Nguồn VietnamWorks)
#   3. Parse, chuẩn hóa, và gộp chung vào schema thống nhất 21 cột
#   4. Tách các kỹ năng IT dựa trên mô tả công việc (IT_SKILLS_DICT)
#   5. Xuất bản ghi trung gian ra CSV và ghi đè vào SQLite an toàn bằng WAL mode
# ==============================================================================

suppressPackageStartupMessages({
  if (!requireNamespace("rvest",     quietly = TRUE)) install.packages("rvest")
  if (!requireNamespace("dplyr",     quietly = TRUE)) install.packages("dplyr")
  if (!requireNamespace("stringr",   quietly = TRUE)) install.packages("stringr")
  if (!requireNamespace("tibble",    quietly = TRUE)) install.packages("tibble")
  if (!requireNamespace("readr",     quietly = TRUE)) install.packages("readr")
  if (!requireNamespace("jsonlite",  quietly = TRUE)) install.packages("jsonlite")
  if (!requireNamespace("purrr",     quietly = TRUE)) install.packages("purrr")
  if (!requireNamespace("DBI",       quietly = TRUE)) install.packages("DBI")
  if (!requireNamespace("RSQLite",   quietly = TRUE)) install.packages("RSQLite")
  library(rvest)
  library(dplyr)
  library(stringr)
  library(tibble)
  library(readr)
  library(jsonlite)
  library(purrr)
  library(DBI)
  library(RSQLite)
})

# ==============================================================================
# 0. CONFIGURATIONS & COALESCING OPERATORS
# ==============================================================================

# Custom coalescing operator that handles NULL, NA, and empty/length-0 vectors
`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a
}

# Đảm bảo giá trị trả về luôn là 1 scalar an toàn (không bị NULL hoặc length 0)
safe_scalar <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0) return(default)
  val <- x[1]
  if (is.na(val)) return(default)
  val
}

# Từ điển các kỹ năng/từ khóa IT cơ bản (dùng để lọc rác)
IT_SKILLS_DICT <- c("java", "python", "sql", "react", "angular", "vue", "node", "javascript", 
                   "html", "css", "c++", "c#", ".net", "php", "ruby", "go", "rust", 
                   "aws", "azure", "gcp", "docker", "kubernetes", "linux", "git", "api",
                   "spring", "django", "laravel", "flask", "swift", "kotlin", "flutter",
                   "dart", "android", "ios", "machine learning", "ai", "data", "qa", "qc",
                   "tester", "devops", "agile", "scrum", "backend", "frontend", "fullstack",
                   "system", "network", "security", "cloud", "mobile", "web", "UI", "UX",
                   "product", "project", "BA", "business analyst", "software",
                   "engineer", "developer", "lập trình", "công nghệ")

# Bảng mapping tên thành phố chuẩn hóa
.city_mapping <- c(
  "hcm"               = "TP.HCM",
  "ho chi minh"       = "TP.HCM",
  "tp hcm"            = "TP.HCM",
  "tp.hcm"            = "TP.HCM",
  "tp. hcm"           = "TP.HCM",
  "thanh pho ho chi minh" = "TP.HCM",
  "sai gon"           = "TP.HCM",
  "saigon"            = "TP.HCM",
  "hn"                = "Hà Nội",
  "ha noi"            = "Hà Nội",
  "hanoi"             = "Hà Nội",
  "dn"                = "Đà Nẵng",
  "da nang"           = "Đà Nẵng",
  "danang"            = "Đà Nẵng",
  "hue"               = "Huế",
  "hai phong"         = "Hải Phòng",
  "hp"                = "Hải Phòng",
  "can tho"           = "Cần Thơ",
  "ct"                = "Cần Thơ",
  "bien hoa"          = "Biên Hòa",
  "vung tau"          = "Vũng Tàu",
  "nha trang"         = "Nha Trang",
  "quy nhon"          = "Quy Nhơn",
  "bac ninh"          = "Bắc Ninh",
  "thai nguyen"       = "Thái Nguyên",
  "vinh"              = "Vinh",
  "buon ma thuot"     = "Buôn Ma Thuột",
  "long an"           = "Long An",
  "dong nai"          = "Đồng Nai",
  "binh duong"        = "Bình Dương"
)

# ==============================================================================
# 1. HELPERS — CLEANING AND PARSING
# ==============================================================================

clean_text <- function(x) {
  x <- safe_scalar(x)
  if (is.na(x)) return(NA_character_)
  x <- str_replace_all(x, "\\s+", " ")
  x <- str_trim(x)
  if (x == "") return(NA_character_)
  x
}

clean_html_text <- function(nodes) {
  if (length(nodes) == 0) return(NA_character_)
  txt <- tryCatch(html_text2(nodes), error = function(e) NA_character_)
  clean_text(txt)
}

get_text <- function(page, selector) {
  clean_html_text(html_element(page, selector))
}

get_attr <- function(page, selector, attr) {
  node <- html_element(page, selector)
  if (length(node) == 0 || inherits(node, "xml_missing")) return(NA_character_)
  clean_text(html_attr(node, attr))
}

hash_str <- function(s) {
  s <- safe_scalar(s, default = "")
  if (!nzchar(s)) return("unknown")
  raw_bytes <- charToRaw(s)
  if (length(raw_bytes) == 0) return("unknown")
  h <- 5381
  for (b in as.integer(raw_bytes)) {
    h <- (h * 33 + b) %% 2147483647
  }
  paste0("hash_", h)
}

# Chuẩn hóa tên thành phố
.normalize_city <- function(city_raw) {
  city_raw <- safe_scalar(city_raw, default = "Khác")
  if (is.na(city_raw) || !nzchar(trimws(city_raw))) return("Khác")
  
  city_lower <- city_raw %>%
    str_to_lower() %>%
    str_replace_all("[^\\p{L}\\p{N}\\s.]", " ") %>%
    str_squish()
  
  matched <- .city_mapping[city_lower]
  if (!is.na(matched)) return(unname(matched))
  
  for (key in names(.city_mapping)) {
    if (str_detect(city_lower, fixed(key))) {
      return(unname(.city_mapping[key]))
    }
  }
  return(str_to_title(trimws(city_raw)))
}

# Parse lương từ text sang khoảng số (triệu VND)
.parse_salary <- function(salary_text) {
  result <- list(salary_min = NA_real_, salary_max = NA_real_)
  salary_text <- safe_scalar(salary_text)
  if (is.na(salary_text) || !nzchar(trimws(salary_text))) return(result)
  
  s <- str_to_lower(trimws(salary_text))
  if (str_detect(s, "thỏa thuận|negotiable|cạnh tranh|competitive|theo năng lực")) {
    return(result)
  }
  
  is_usd <- str_detect(s, "usd|\\$")
  usd_to_trieu <- 25000 / 1e6 # Giả định 1 USD = 25,000 VND
  
  # Pattern 1: Khoảng "10 - 15 triệu", "10-15tr", "$1000 - $2000"
  range_match <- str_match(s, "([\\d.,]+)\\s*[-–~đến to]\\s*([\\d.,]+)")
  if (!is.na(range_match[1, 1])) {
    v1 <- as.numeric(str_replace_all(range_match[1, 2], ",", ""))
    v2 <- as.numeric(str_replace_all(range_match[1, 3], ",", ""))
    
    if (is_usd) {
      result$salary_min <- v1 * usd_to_trieu
      result$salary_max <- v2 * usd_to_trieu
    } else if (v1 > 100) {
      result$salary_min <- v1 / 1e6
      result$salary_max <- v2 / 1e6
    } else {
      result$salary_min <- v1
      result$salary_max <- v2
    }
    return(result)
  }
  
  # Pattern 2: "Trên X triệu", "Từ X"
  above_match <- str_match(s, "(trên|từ|tối thiểu|above|from|min)\\s*[:]?\\s*([\\d.,]+)")
  if (!is.na(above_match[1, 1])) {
    v <- as.numeric(str_replace_all(above_match[1, 3], ",", ""))
    if (is_usd) v <- v * usd_to_trieu
    else if (v > 100) v <- v / 1e6
    result$salary_min <- v
    return(result)
  }
  
  # Pattern 3: "Đến X triệu", "Tối đa X"
  below_match <- str_match(s, "(đến|tối đa|dưới|up to|max|to)\\s*[:]?\\s*([\\d.,]+)")
  if (!is.na(below_match[1, 1])) {
    v <- as.numeric(str_replace_all(below_match[1, 2], ",", ""))
    if (is_usd) v <- v * usd_to_trieu
    else if (v > 100) v <- v / 1e6
    result$salary_max <- v
    return(result)
  }
  
  # Pattern 4: Số đơn lẻ
  single_match <- str_match(s, "([\\d.,]+)\\s*(triệu|tr|million|m)")
  if (!is.na(single_match[1, 1])) {
    v <- as.numeric(str_replace_all(single_match[1, 2], ",", ""))
    if (is_usd) v <- v * usd_to_trieu
    result$salary_min <- v
    result$salary_max <- v
    return(result)
  }
  
  return(result)
}

# Phân loại mức kinh nghiệm (Fresher, Junior, Mid, Senior)
.classify_experience <- function(exp_text) {
  exp_text <- safe_scalar(exp_text, default = "Junior")
  if (is.na(exp_text) || !nzchar(trimws(exp_text))) return("Junior")
  
  s <- str_to_lower(trimws(exp_text))
  if (str_detect(s, "fresher|intern|thực tập|mới ra trường|không yêu cầu")) {
    return("Fresher")
  }
  if (str_detect(s, "senior|trưởng|lead|manager|quản lý|expert|principal")) {
    return("Senior")
  }
  
  # Thử tìm số năm
  range_match <- str_match(s, "(\\d+)\\s*[-–]\\s*(\\d+)\\s*(năm|year)")
  if (!is.na(range_match[1, 1])) {
    years <- mean(c(as.numeric(range_match[1, 2]), as.numeric(range_match[1, 3])))
  } else {
    num_match <- str_match(s, "(\\d+)\\s*(năm|year)")
    if (!is.na(num_match[1, 1])) {
      years <- as.numeric(num_match[1, 2])
    } else {
      return("Junior")
    }
  }
  
  if (years <= 1)      return("Fresher")
  else if (years <= 3) return("Junior")
  else if (years <= 5) return("Mid")
  else                 return("Senior")
}

parse_json_ld <- function(page) {
  scripts <- html_elements(page, 'script[type="application/ld+json"]')
  for (s in scripts) {
    raw <- tryCatch(html_text(s), error = function(e) "")
    if (!nzchar(raw)) next
    parsed <- tryCatch(fromJSON(raw, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(parsed)) next
    if (identical(parsed[["@type"]], "JobPosting")) return(parsed)
  }
  return(NULL)
}

parse_salary_currency <- function(salary_text) {
  salary_text <- safe_scalar(salary_text)
  if (is.na(salary_text)) return(NA_character_)
  s <- str_to_lower(salary_text)
  if (str_detect(s, "usd|\\$"))         return("USD")
  if (str_detect(s, "triệu|tr\\.|vnd|đ")) return("VND")
  NA_character_
}

parse_experience_years <- function(text) {
  text <- safe_scalar(text)
  if (is.na(text) || !nzchar(text)) return(NA_real_)
  s <- str_to_lower(text)
  if (str_detect(s, "không yêu cầu|chưa có|no experience|fresher|intern")) return(0)
  num <- str_extract(s, "\\d+(\\.\\d+)?")
  if (is.na(num)) return(NA_real_)
  as.numeric(num)
}

extract_date <- function(x) {
  x <- safe_scalar(x)
  if (is.na(x)) return(NA_character_)
  m <- str_extract(as.character(x), "\\d{4}-\\d{2}-\\d{2}")
  if (is.na(m)) return(NA_character_)
  m
}

# ==============================================================================
# 2. TOPCV HTML PARSING FUNCTION
# ==============================================================================

parse_topcv_job <- function(file_path) {
  page <- tryCatch(
    read_html(file_path, encoding = "UTF-8"),
    error = function(e) {
      message(sprintf("  [LỖI đọc file] %s: %s", basename(file_path), e$message))
      return(NULL)
    }
  )
  if (is.null(page)) return(NULL)

  canonical <- safe_scalar(get_attr(page, 'link[rel="canonical"]', "href"))
  job_id    <- str_extract(canonical, "/\\d+\\.html") |> str_extract("\\d+")
  job_id    <- safe_scalar(job_id)
  if (is.na(job_id)) {
    job_id <- str_remove(basename(file_path), "\\.html$")
  }

  ld <- parse_json_ld(page)

  job_title <- clean_text(ld[["title"]])
  if (is.na(job_title)) {
    job_title <- get_text(page, ".job-detail__info--title") %||%
                 get_text(page, ".premium-job-basic-information__header--title") %||%
                 get_text(page, "h1.title-job")
  }

  company_name <- clean_text(ld[["hiringOrganization"]][["name"]])
  if (is.na(company_name)) {
    company_name <- get_text(page, ".job-detail__company--information-item.company-name .name") %||%
                    get_text(page, ".company-name-label")
  }

  salary_text <- NA_character_
  main_info_nodes <- html_elements(page, ".job-detail__info--section")
  main_info <- list()
  for (node in main_info_nodes) {
    key   <- html_element(node, ".job-detail__info--section-content-title") |>
              html_text2() |> clean_text() |> str_to_lower()
    value <- html_element(node, ".job-detail__info--section-content-value") |>
              html_text2() |> clean_text()
    if (!is.na(key)) main_info[[key]] <- value
  }
  salary_text     <- safe_scalar(main_info[["mức lương"]])
  city            <- safe_scalar(main_info[["địa điểm"]])
  experience_text <- safe_scalar(main_info[["kinh nghiệm"]])

  if (is.na(salary_text)) {
    bs <- ld[["baseSalary"]]
    if (!is.null(bs)) {
      val <- bs[["value"]]
      if (!is.null(val)) {
        salary_text <- tryCatch({
          if (!is.null(val[["minValue"]]) && !is.null(val[["maxValue"]])) {
            paste0(val[["minValue"]], " - ", val[["maxValue"]], " ", bs[["currency"]])
          } else if (!is.null(val[["value"]])) {
            as.character(val[["value"]])
          } else NA_character_
        }, error = function(e) NA_character_)
      }
    }
  }

  if (is.na(city)) {
    loc <- ld[["jobLocation"]][["address"]]
    if (!is.null(loc)) city <- clean_text(loc[["addressRegion"]])
  }

  if (is.na(experience_text) || !nzchar(trimws(experience_text))) {
    exp_req <- ld[["experienceRequirements"]]
    if (!is.null(exp_req) && !is.null(exp_req[["monthsOfExperience"]])) {
      months <- as.numeric(exp_req[["monthsOfExperience"]])
      experience_text <- paste0(round(months / 12, 1), " năm")
    }
  }

  sections <- list()
  desc_nodes <- html_elements(page, ".job-description__item")
  for (node in desc_nodes) {
    title_node <- html_element(node, "h3")
    content_node <- html_element(node, ".job-description__item--content")
    sec_title   <- html_text2(title_node) |> clean_text()
    sec_content <- html_text2(content_node) |> clean_text()
    if (!is.na(sec_title)) {
      sec_title <- str_squish(sec_title)
      if (str_detect(sec_title, "Địa điểm làm việc")) sec_title <- "Địa điểm làm việc"
      sections[[sec_title]] <- sec_content
    }
  }

  if (length(desc_nodes) == 0) {
    prem_nodes <- html_elements(page, ".premium-job-description__box")
    for (node in prem_nodes) {
      h2 <- html_element(node, "h2")
      content <- html_element(node, ".premium-job-description__box--content")
      sec_title   <- html_text2(h2) |> clean_text()
      sec_content <- html_text2(content) |> clean_text()
      if (!is.na(sec_title)) {
        sec_title <- str_squish(sec_title)
        sections[[sec_title]] <- sec_content
      }
    }
  }

  job_description <- safe_scalar(sections[["Mô tả công việc"]])
  requirements    <- safe_scalar(sections[["Yêu cầu ứng viên"]])
  benefits        <- safe_scalar(sections[["Quyền lợi"]] %||% sections[["Quyền lợi được hưởng"]])

  if (is.na(job_description) && !is.null(ld[["description"]])) {
    raw_desc <- ld[["description"]]
    job_description <- tryCatch(
      html_text2(read_html(paste0("<div>", raw_desc, "</div>"))) |> clean_text(),
      error = function(e) NA_character_
    )
  }

  date_posted <- extract_date(ld[["datePosted"]])
  deadline    <- extract_date(ld[["validThrough"]])

  if (is.na(deadline)) {
    dl_txt <- get_text(page, ".job-detail__info--deadline-date")
    if (is.na(dl_txt)) {
      dl_txt <- get_text(page, ".job-detail__information-detail--actions-label") |>
                str_remove("Hạn nộp hồ sơ:") |> clean_text()
    }
    deadline <- clean_text(dl_txt)
  }

  level <- NA_character_
  general_nodes <- html_elements(page, ".box-general-group-info")
  for (node in general_nodes) {
    key   <- html_element(node, ".box-general-group-info-title") |> html_text2() |> clean_text()
    value <- html_element(node, ".box-general-group-info-value") |> html_text2() |> clean_text()
    if (!is.na(key) && str_to_lower(key) == "cấp bậc") {
      level <- value
      break
    }
  }
  if (is.na(level)) level <- clean_text(ld[["occupationalCategory"]])

  raw_text_for_matching <- paste(
    safe_scalar(job_title, ""),
    safe_scalar(company_name, ""),
    safe_scalar(job_description, ""),
    safe_scalar(requirements, ""),
    sep = " "
  ) |> str_replace_all("\\s+", " ") |> str_trim()

  sal_p <- .parse_salary(salary_text)
  
  tibble(
    job_id               = safe_scalar(job_id),
    title                = safe_scalar(job_title, "Không có tiêu đề"),
    company              = safe_scalar(company_name, "Không có tên công ty"),
    url                  = safe_scalar(canonical, paste0("topcv_local_", job_id)),
    salary_text          = safe_scalar(salary_text),
    salary_currency      = safe_scalar(parse_salary_currency(salary_text)),
    salary_min           = as.numeric(safe_scalar(sal_p$salary_min, NA)),
    salary_max           = as.numeric(safe_scalar(sal_p$salary_max, NA)),
    experience_years_min = as.numeric(safe_scalar(parse_experience_years(experience_text), NA)),
    experience_level     = safe_scalar(.classify_experience(experience_text %||% requirements)),
    location             = safe_scalar(.normalize_city(city)),
    job_description      = safe_scalar(job_description),
    requirements         = safe_scalar(requirements),
    benefits             = safe_scalar(benefits),
    date_posted          = safe_scalar(date_posted),
    deadline             = safe_scalar(deadline),
    level                = safe_scalar(level),
    scraped_at           = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    source               = "TopCV",
    source_file          = basename(file_path),
    raw_text_for_matching = raw_text_for_matching
  )
}

# ==============================================================================
# 3. MAIN RUN PIPELINE FUNCTION
# ==============================================================================

html_to_db <- function(html_folder = NULL, db_path = NULL, csv_output = NULL) {
  root_dir <- if (exists("PROJECT_ROOT")) {
    PROJECT_ROOT
  } else {
    current_dir <- getwd()
    found_root <- current_dir
    for (i in 1:4) {
      if (file.exists(file.path(current_dir, "database", "init_db.sql"))) {
        found_root <- current_dir
        break
      }
      current_dir <- dirname(current_dir)
    }
    found_root
  }

  if (is.null(html_folder)) {
    html_folder <- file.path(root_dir, "data", "HTML") |> normalizePath(winslash = "/", mustWork = FALSE)
  }
  if (is.null(db_path)) {
    db_path <- file.path(root_dir, "database", "job_market.sqlite") |> normalizePath(winslash = "/", mustWork = FALSE)
  }
  if (is.null(csv_output)) {
    csv_dir <- file.path(root_dir, "data", "processed") |> normalizePath(winslash = "/", mustWork = FALSE)
    dir.create(csv_dir, showWarnings = FALSE, recursive = TRUE)
    csv_output <- file.path(csv_dir, "jobs_raw.csv")
  }

  # -----------------------------------------------------------
  # BƯỚC A: Parse dữ liệu từ các file HTML TopCV
  # -----------------------------------------------------------
  message("[html_to_db] Đang tìm kiếm các file HTML tại: ", html_folder)
  html_files <- list.files(html_folder, pattern = "\\.html?$", full.names = TRUE, ignore.case = TRUE)
  
  df_topcv <- tibble()
  if (length(html_files) > 0) {
    file_nums  <- suppressWarnings(as.numeric(str_extract(basename(html_files), "\\d+")))
    html_files <- html_files[order(file_nums)]
    
    total <- length(html_files)
    message(sprintf("[html_to_db] Phát hiện %d file HTML TopCV. Bắt đầu parse...", total))
    
    results <- vector("list", total)
    for (i in seq_along(html_files)) {
      fp <- html_files[i]
      bn <- basename(fp)
      if (i %% 100 == 0 || i == 1 || i == total) {
        message(sprintf("  [%d/%d] %s", i, total, bn))
      }
      row <- tryCatch(
        parse_topcv_job(fp),
        error = function(e) {
          message(sprintf("  [LỖI] %s: %s", bn, e$message))
          NULL
        }
      )
      results[[i]] <- row
    }
    valid <- keep(results, ~ !is.null(.x))
    if (length(valid) > 0) {
      df_topcv <- bind_rows(valid)
      message(sprintf("[html_to_db] Parse TopCV thành công: %d/%d file.", nrow(df_topcv), total))
    }
  } else {
    message("[html_to_db] Cảnh báo: Không tìm thấy file HTML TopCV nào.")
  }

  # -----------------------------------------------------------
  # BƯỚC B: Nạp và xử lý dữ liệu VietnamWorks từ CSV
  # -----------------------------------------------------------
  vnw_path <- file.path(root_dir, "data", "raw", "vnw_jobs_raw.csv")
  df_vnw <- tibble()
  
  if (file.exists(vnw_path)) {
    message("\n[html_to_db] Phát hiện file VietnamWorks CSV tại: ", vnw_path)
    df_vnw_raw <- tryCatch({
      readr::read_csv(vnw_path, col_types = cols(.default = "c"), show_col_types = FALSE)
    }, error = function(e) {
      message("[html_to_db] Lỗi đọc CSV VietnamWorks: ", e$message)
      NULL
    })
    
    if (!is.null(df_vnw_raw) && nrow(df_vnw_raw) > 0) {
      names(df_vnw_raw) <- names(df_vnw_raw) %>%
        str_to_lower() %>%
        str_replace_all("[^a-z0-9_]", "_") %>%
        str_replace_all("_+", "_") %>%
        str_remove("^_|_$")
      
      message("[html_to_db] Đang chuẩn hóa dữ liệu VietnamWorks (", nrow(df_vnw_raw), " dòng)...")
      
      # Extract IDs and map columns
      vnw_mapped <- df_vnw_raw %>%
        rowwise() %>%
        mutate(
          job_id = {
            id_m <- str_match(url, "--(\\d+)-jv")[, 2]
            if (is.na(id_m)) id_m <- str_match(url, "/(\\d+)-jv")[, 2]
            if (is.na(id_m)) id_m <- hash_str(url)
            id_m
          },
          salary_text = salary,
          salary_currency = parse_salary_currency(salary),
          salary_min = .parse_salary(salary)$salary_min,
          salary_max = .parse_salary(salary)$salary_max,
          experience_years_min = parse_experience_years(requirements),
          experience_level = .classify_experience(requirements),
          location = .normalize_city(location),
          date_posted = extract_date(scraped_at),
          deadline = NA_character_,
          level = NA_character_,
          source_file = "vnw_jobs_raw.csv",
          raw_text_for_matching = paste(
            safe_scalar(title, ""),
            safe_scalar(company, ""),
            safe_scalar(job_description, ""),
            safe_scalar(requirements, ""),
            sep = " "
          ) |> str_replace_all("\\s+", " ") |> str_trim()
        ) %>%
        ungroup() %>%
        select(
          job_id, title, company, url, salary_text, salary_currency, salary_min, salary_max,
          experience_years_min, experience_level, location, job_description, requirements,
          benefits, date_posted, deadline, level, scraped_at, source, source_file, raw_text_for_matching
        )
      
      df_vnw <- vnw_mapped
      message("[html_to_db] Xử lý thành công dữ liệu VietnamWorks: ", nrow(df_vnw), " dòng.")
    }
  } else {
    message("\n[html_to_db] Cảnh báo: Không tìm thấy file vnw_jobs_raw.csv.")
  }

  # -----------------------------------------------------------
  # BƯỚC C: Gộp dữ liệu 2 nguồn & Dedup & Chuẩn hóa ràng buộc NOT NULL
  # -----------------------------------------------------------
  if (nrow(df_topcv) == 0 && nrow(df_vnw) == 0) {
    stop("[html_to_db] LỖI: Không nạp được bất cứ dòng dữ liệu nào từ cả 2 nguồn TopCV và VietnamWorks.")
  }

  df_all <- bind_rows(df_topcv, df_vnw)
  n_before <- nrow(df_all)
  
  df_all <- df_all %>%
    filter(!is.na(job_id), !is.na(url)) %>%
    # Làm sạch cột bắt buộc NOT NULL
    mutate(
      title = ifelse(is.na(title) | !nzchar(trimws(title)), "Không có tiêu đề", title),
      company = ifelse(is.na(company) | !nzchar(trimws(company)), "Không có tên công ty", company)
    ) %>%
    distinct(job_id, .keep_all = TRUE) %>%
    distinct(url, .keep_all = TRUE)
  
  n_dup <- n_before - nrow(df_all)
  message(sprintf("\n[html_to_db] Tổng hợp dữ liệu: %d dòng. Loại bỏ trùng lặp: %d dòng. Còn lại: %d dòng.", 
                  n_before, n_dup, nrow(df_all)))

  # Lưu CSV trung gian
  write_csv(df_all, csv_output)
  message(sprintf("[html_to_db] Đã xuất CSV trung gian: %s", csv_output))

  # -----------------------------------------------------------
  # BƯỚC D: Trích xuất kỹ năng (job_skills)
  # -----------------------------------------------------------
  message("[html_to_db] Đang phân tích và tách các kỹ năng IT từ văn bản...")
  
  skills_list <- lapply(seq_len(nrow(df_all)), function(i) {
    text_to_search <- paste(df_all$job_description[i], df_all$requirements[i], sep = " ")
    text_to_search <- str_to_lower(text_to_search)
    
    found_skills <- c()
    for (s in IT_SKILLS_DICT) {
      if (s %in% c("c++", "c#", ".net")) next
      if (str_detect(text_to_search, regex(paste0("\\b", s, "\\b"), ignore_case = TRUE))) {
        found_skills <- c(found_skills, s)
      }
    }
    
    if (str_detect(text_to_search, fixed("c++"))) found_skills <- c(found_skills, "c++")
    if (str_detect(text_to_search, fixed("c#"))) found_skills <- c(found_skills, "c#")
    if (str_detect(text_to_search, fixed(".net"))) found_skills <- c(found_skills, ".net")
    
    found_skills <- unique(found_skills)
    
    if (length(found_skills) > 0) {
      tibble(job_id = df_all$job_id[i], skill_name = found_skills)
    } else {
      NULL
    }
  })
  
  df_skills <- bind_rows(skills_list)
  message("[html_to_db] Trích xuất thành công: ", nrow(df_skills), " cặp job-skill.")

  # -----------------------------------------------------------
  # BƯỚC E: Ghi dữ liệu vào SQLite sử dụng Transaction
  # -----------------------------------------------------------
  source(file.path(root_dir, "r_processing", "00_db_config.R"), encoding = "UTF-8")
  
  message("\n[html_to_db] Đang kết nối tới SQLite và cập nhật bảng...")
  con <- get_db_connection()
  on.exit(close_db_connection(con), add = TRUE)
  
  dbExecute(con, "BEGIN TRANSACTION;")
  tryCatch({
    sources_to_clear <- unique(df_all$source)
    for (src in sources_to_clear) {
      dbExecute(con, "DELETE FROM jobs WHERE source = ?", params = list(src))
    }
    
    insert_sql <- "
      INSERT OR REPLACE INTO jobs 
      (job_id, title, company, url, salary_text, salary_currency, salary_min, salary_max,
       experience_years_min, experience_level, location, job_description, requirements,
       benefits, date_posted, deadline, level, scraped_at, source, source_file, raw_text_for_matching)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
      
    stmt <- dbSendStatement(con, insert_sql)
    for (i in seq_len(nrow(df_all))) {
      row <- df_all[i, ]
      dbBind(stmt, list(
        row$job_id, row$title, row$company, row$url, row$salary_text, row$salary_currency,
        as.numeric(row$salary_min), as.numeric(row$salary_max),
        as.numeric(row$experience_years_min), row$experience_level, row$location,
        row$job_description, row$requirements, row$benefits,
        row$date_posted, row$deadline, row$level, row$scraped_at,
        row$source, row$source_file, row$raw_text_for_matching
      ))
    }
    dbClearResult(stmt)
    message("[html_to_db] Đã ghi ", nrow(df_all), " tin tuyển dụng vào bảng [jobs].")
    
    affected_job_ids <- unique(df_skills$job_id)
    if (length(affected_job_ids) > 0) {
      chunk_size <- 500
      chunks <- split(affected_job_ids, ceiling(seq_along(affected_job_ids) / chunk_size))
      for (chunk in chunks) {
        placeholders <- paste(rep("?", length(chunk)), collapse = ",")
        dbExecute(con, paste0("DELETE FROM job_skills WHERE job_id IN (", placeholders, ")"), params = as.list(chunk))
      }
    }
    
    skill_sql <- "INSERT OR IGNORE INTO job_skills (job_id, skill_name) VALUES (?, ?)"
    skill_stmt <- dbSendStatement(con, skill_sql)
    for (i in seq_len(nrow(df_skills))) {
      dbBind(skill_stmt, list(df_skills$job_id[i], df_skills$skill_name[i]))
    }
    dbClearResult(skill_stmt)
    message("[html_to_db] Đã ghi ", nrow(df_skills), " dòng vào bảng [job_skills].")
    
    dbExecute(con, "COMMIT;")
    message("[html_to_db] Transaction thành công! Đã ghi hoàn tất.")
    
  }, error = function(e) {
    dbExecute(con, "ROLLBACK;")
    message("[html_to_db] LỖI: Transaction thất bại, đã rollback: ", e$message)
    stop(e)
  })

  total_in_db <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM jobs")$n
  total_skills_in_db <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM job_skills")$n
  message(sprintf("[html_to_db] Tổng số trong DB: %d jobs, %d job_skills.", total_in_db, total_skills_in_db))
  
  message("[html_to_db] Hoàn tất pipeline nạp dữ liệu.")
  invisible(df_all)
}

# Chỉ tự động chạy nếu gọi trực tiếp từ dòng lệnh Rscript
initial_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", initial_args, value = TRUE)
if (length(file_arg) > 0 && grepl("01_html_to_db\\.R$", file_arg[1])) {
  html_to_db()
}
