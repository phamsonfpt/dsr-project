# ==============================================================================
# 02_market_analysis.R — Phân tích thị trường lao động
# Job Recommendation & Market Analysis Platform
# ==============================================================================
# Module cung cấp:
#   - run_market_analysis() : Tính toán thống kê → ghi vào market_trends
# ==============================================================================

# --- Nạp module cấu hình DB -------------------------------------------------
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
    config_path <- file.path(getwd(), "r_processing", "00_db_config.R")
  }
  if (file.exists(config_path)) source(config_path, encoding = "UTF-8")
  else stop("[MARKET] Kh\u00f4ng t\u00ecm th\u1ea5y 00_db_config.R")
})

# --- Nạp thư viện -----------------------------------------------------------
for (pkg in c("dplyr", "jsonlite")) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg)
}
library(dplyr)
library(jsonlite)

# ==============================================================================
# Hàm phụ: UPSERT vào market_trends
# Xóa các bản ghi cũ theo category, rồi INSERT mới
# ==============================================================================
.upsert_trends <- function(con, category, trend_df) {
  # trend_df phải có cột: key_name, value_metric, (tùy chọn: extra_json)
  if (nrow(trend_df) == 0) {
    message("[MARKET]   Kh\u00f4ng c\u00f3 d\u1eef li\u1ec7u cho category: ", category)
    return(invisible(0))
  }

  # Xóa dữ liệu cũ
  dbExecute(con, "DELETE FROM market_trends WHERE category = ?", params = list(category))

  # Chuẩn bị dữ liệu INSERT
  trend_df$category    <- category
  trend_df$computed_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  # Đảm bảo có cột extra_json

  if (!"extra_json" %in% names(trend_df)) {
    trend_df$extra_json <- NA_character_
  }

  insert_sql <- paste0(
    "INSERT INTO market_trends (category, key_name, value_metric, extra_json, computed_at) ",
    "VALUES (?, ?, ?, ?, ?)"
  )

  stmt <- dbSendStatement(con, insert_sql)
  n <- 0
  for (i in seq_len(nrow(trend_df))) {
    tryCatch({
      dbBind(stmt, list(
        trend_df$category[i],
        trend_df$key_name[i],
        as.numeric(trend_df$value_metric[i]),
        if (is.na(trend_df$extra_json[i])) NA_character_ else trend_df$extra_json[i],
        trend_df$computed_at[i]
      ))
      n <- n + 1
    }, error = function(e) {
      message("[MARKET]   L\u1ed7i INSERT: ", conditionMessage(e))
    })
  }
  dbClearResult(stmt)

  message("[MARKET]   \u0110\u00e3 ghi ", n, " b\u1ea3n ghi cho [", category, "]")
  return(invisible(n))
}

# ==============================================================================
# run_market_analysis()
# Hàm chính: truy vấn DB → tính toán thống kê → ghi market_trends
# ==============================================================================
run_market_analysis <- function() {
  message("\n", strrep("=", 60))
  message("[MARKET] B\u1eaft \u0111\u1ea7u ph\u00e2n t\u00edch th\u1ecb tr\u01b0\u1eddng lao \u0111\u1ed9ng...")
  message(strrep("=", 60))

  con <- get_db_connection()

  tryCatch({
    # -----------------------------------------------------------------------
    # Đọc dữ liệu từ DB
    # -----------------------------------------------------------------------
    message("\n[MARKET] \u0110ang truy v\u1ea5n d\u1eef li\u1ec7u t\u1eeb DB...")

    jobs_df <- dbGetQuery(con, "SELECT * FROM jobs_clean")
    skills_df <- dbGetQuery(con, "SELECT * FROM job_skills")

    if (nrow(jobs_df) == 0) {
      message("[MARKET] \u274c B\u1ea3ng jobs_clean r\u1ed7ng. H\u00e3y ch\u1ea1y 01_data_cleaning.R tr\u01b0\u1edbc.")
      return(invisible(NULL))
    }

    message("[MARKET]   jobs_clean : ", nrow(jobs_df), " b\u1ea3n ghi")
    message("[MARKET]   job_skills : ", nrow(skills_df), " b\u1ea3n ghi")

    # Bắt đầu transaction
    dbBegin(con)

    # =====================================================================
    # a) top_skills: Tần suất xuất hiện của mỗi kỹ năng
    # =====================================================================
    message("\n[MARKET] (a) Ph\u00e2n t\u00edch top_skills...")
    if (nrow(skills_df) > 0) {
      top_skills <- skills_df %>%
        group_by(skill_name) %>%
        summarise(value_metric = n(), .groups = "drop") %>%
        arrange(desc(value_metric)) %>%
        rename(key_name = skill_name)

      .upsert_trends(con, "top_skills", top_skills)
    } else {
      message("[MARKET]   Kh\u00f4ng c\u00f3 d\u1eef li\u1ec7u skills.")
    }

    # =====================================================================
    # b) salary_by_role: Lương trung vị theo vị trí công việc
    # =====================================================================
    message("\n[MARKET] (b) Ph\u00e2n t\u00edch salary_by_role...")

    # Tính salary trung bình cho mỗi job (trung bình của min và max)
    salary_jobs <- jobs_df %>%
      filter(!is.na(salary_min) | !is.na(salary_max)) %>%
      mutate(
        salary_avg = case_when(
          !is.na(salary_min) & !is.na(salary_max) ~ (salary_min + salary_max) / 2,
          !is.na(salary_min) ~ salary_min,
          TRUE ~ salary_max
        )
      )

    if (nrow(salary_jobs) > 0) {
      salary_by_role <- salary_jobs %>%
        group_by(title) %>%
        # Bỏ điều kiện filter(n() >= 2) để hiển thị được biểu đồ ngay cả khi dữ liệu mỏng (chỉ cào 1 trang)
        summarise(
          value_metric = median(salary_avg, na.rm = TRUE),
          q1           = quantile(salary_avg, 0.25, na.rm = TRUE),
          q3           = quantile(salary_avg, 0.75, na.rm = TRUE),
          sal_min      = min(salary_avg, na.rm = TRUE),
          sal_max      = max(salary_avg, na.rm = TRUE),
          n_jobs       = n(),
          .groups      = "drop"
        ) %>%
        arrange(desc(value_metric)) %>%
        rename(key_name = title) %>%
        rowwise() %>%
        mutate(
          extra_json = toJSON(
            list(q1 = q1, q3 = q3, min = sal_min, max = sal_max, n = n_jobs),
            auto_unbox = TRUE
          )
        ) %>%
        ungroup() %>%
        select(key_name, value_metric, extra_json) %>%
        head(15) # Giới hạn hiển thị 15 vị trí có lương cao nhất để biểu đồ không quá tải

      .upsert_trends(con, "salary_by_role", salary_by_role)
    } else {
      message("[MARKET]   Kh\u00f4ng \u0111\u1ee7 d\u1eef li\u1ec7u l\u01b0\u01a1ng.")
    }

    # =====================================================================
    # c) jobs_by_location: Số lượng việc làm theo địa điểm
    # =====================================================================
    message("\n[MARKET] (c) Ph\u00e2n t\u00edch jobs_by_location...")

    jobs_by_loc <- jobs_df %>%
      filter(!is.na(location), nchar(location) > 0) %>%
      group_by(location) %>%
      summarise(value_metric = n(), .groups = "drop") %>%
      arrange(desc(value_metric)) %>%
      rename(key_name = location)

    .upsert_trends(con, "jobs_by_location", jobs_by_loc)

    # =====================================================================
    # d) jobs_by_experience: Số lượng việc làm theo cấp kinh nghiệm
    # =====================================================================
    message("\n[MARKET] (d) Ph\u00e2n t\u00edch jobs_by_experience...")

    jobs_by_exp <- jobs_df %>%
      filter(!is.na(experience_level), nchar(experience_level) > 0) %>%
      group_by(experience_level) %>%
      summarise(value_metric = n(), .groups = "drop") %>%
      arrange(desc(value_metric)) %>%
      rename(key_name = experience_level)

    .upsert_trends(con, "jobs_by_experience", jobs_by_exp)

    # =====================================================================
    # e) salary_by_location: Lương trung vị theo địa điểm
    # =====================================================================
    message("\n[MARKET] (e) Ph\u00e2n t\u00edch salary_by_location...")

    if (nrow(salary_jobs) > 0) {
      salary_by_loc <- salary_jobs %>%
        filter(!is.na(location), nchar(location) > 0) %>%
        group_by(location) %>%
        filter(n() >= 2) %>%  # Chỉ tính cho thành phố có ≥ 2 bài đăng
        summarise(
          value_metric = median(salary_avg, na.rm = TRUE),
          q1           = quantile(salary_avg, 0.25, na.rm = TRUE),
          q3           = quantile(salary_avg, 0.75, na.rm = TRUE),
          sal_min      = min(salary_avg, na.rm = TRUE),
          sal_max      = max(salary_avg, na.rm = TRUE),
          n_jobs       = n(),
          .groups      = "drop"
        ) %>%
        arrange(desc(value_metric)) %>%
        rename(key_name = location) %>%
        rowwise() %>%
        mutate(
          extra_json = toJSON(
            list(q1 = q1, q3 = q3, min = sal_min, max = sal_max, n = n_jobs),
            auto_unbox = TRUE
          )
        ) %>%
        ungroup() %>%
        select(key_name, value_metric, extra_json)

      .upsert_trends(con, "salary_by_location", salary_by_loc)
    } else {
      message("[MARKET]   Kh\u00f4ng \u0111\u1ee7 d\u1eef li\u1ec7u l\u01b0\u01a1ng theo \u0111\u1ecba \u0111i\u1ec3m.")
    }

    # Commit transaction
    dbCommit(con)

    # -----------------------------------------------------------------------
    # Tổng kết
    # -----------------------------------------------------------------------
    total <- dbGetQuery(con, "SELECT category, COUNT(*) as n FROM market_trends GROUP BY category")
    message("\n", strrep("-", 40))
    message("[MARKET] \u2705 Ph\u00e2n t\u00edch ho\u00e0n t\u1ea5t! T\u1ed5ng k\u1ebft:")
    for (i in seq_len(nrow(total))) {
      message("  \u2022 ", total$category[i], ": ", total$n[i], " b\u1ea3n ghi")
    }
    message(strrep("=", 60))

    invisible(total)

  }, error = function(e) {
    tryCatch(dbRollback(con), error = function(e2) NULL)
    message("[MARKET] \u274c L\u1ed7i: ", conditionMessage(e))
    stop(e)
  }, finally = {
    close_db_connection(con)
  })
}

message("[MARKET] Module 02_market_analysis.R \u0111\u00e3 s\u1eb5n s\u00e0ng.")
message("  G\u1ecdi run_market_analysis() \u0111\u1ec3 ch\u1ea1y ph\u00e2n t\u00edch.")
