# ============================================================
# main.R — Entry Point: Job Recommendation & Market Analysis Platform
# ============================================================
# Tập lệnh chính điều phối toàn bộ hệ thống:
#   1. Thu thập dữ liệu (Python Scraper)
#   2. Làm sạch & lưu trữ vào Database
#   3. Phân tích xu hướng thị trường
#   4. Khởi động Shiny Web App
#
# Cách sử dụng:
#   Rscript main.R                  # Chạy toàn bộ pipeline
#   Rscript main.R --scrape-only    # Chỉ cào dữ liệu
#   Rscript main.R --process-only   # Chỉ xử lý dữ liệu (cleaning + analysis)
#   Rscript main.R --app-only       # Chỉ mở Shiny App
# ============================================================

# --- Xác định thư mục gốc của dự án ---
# Thử lấy đường dẫn file đang chạy; nếu chạy interactive thì dùng getwd()
get_script_dir <- function() {
  # Khi chạy bằng Rscript
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", cmd_args, value = TRUE)
  if (length(file_arg) > 0) {
    return(normalizePath(dirname(sub("^--file=", "", file_arg[1])), winslash = "/"))
  }
  # Khi chạy bằng source()
  if (!is.null(sys.frame(1)$ofile)) {
    return(normalizePath(dirname(sys.frame(1)$ofile), winslash = "/"))
  }
  # Fallback: working directory hiện tại
  return(normalizePath(getwd(), winslash = "/"))
}

PROJECT_ROOT <- get_script_dir()
setwd(PROJECT_ROOT)

cat("============================================================\n")
cat("  Job Recommendation & Market Analysis Platform\n")
cat("============================================================\n")
cat(paste0("  Thời gian: ", Sys.time(), "\n"))
cat(paste0("  Thư mục dự án: ", PROJECT_ROOT, "\n"))
cat("============================================================\n\n")

# --- Đọc tham số dòng lệnh ---
args <- commandArgs(trailingOnly = TRUE)

# Xác định chế độ chạy
# Nếu không có argument nào -> chạy toàn bộ
# Nếu có flag cụ thể -> chỉ chạy module tương ứng
mode_scrape_only  <- "--scrape-only"  %in% args
mode_process_only <- "--process-only" %in% args
mode_app_only     <- "--app-only"     %in% args
mode_all          <- !mode_scrape_only && !mode_process_only && !mode_app_only

run_scrape  <- mode_all || mode_scrape_only
run_process <- mode_all || mode_process_only
run_app     <- mode_all || mode_app_only

# --- Kiểm tra thư viện R cần thiết ---
required_packages <- c(
  "DBI", "RSQLite", "dplyr", "tidyr", "stringr", "readr",
  "jsonlite", "text2vec", "Matrix",
  "shiny", "bslib", "plotly", "DT", "shinyWidgets"
)

cat("[SETUP] Kiểm tra các thư viện R...\n")
missing_pkgs <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  cat(paste0("  -> Cài đặt thư viện thiếu: ", paste(missing_pkgs, collapse = ", "), "\n"))
  install.packages(missing_pkgs, repos = "https://cran.r-project.org", quiet = TRUE)
}
cat("  -> Tất cả thư viện R đã sẵn sàng.\n\n")

# ============================================================
# GIAI ĐOẠN 1: Thu thập dữ liệu (Python Scraper)
# ============================================================
if (run_scrape) {
  cat(paste(rep("=", 60), collapse = ""), "\n")
  cat("[MODULE 1] THU THẬP DỮ LIỆU — Python Scraper\n")
  cat(paste(rep("=", 60), collapse = ""), "\n")

  tryCatch({
    cat("\n  [0/2] Xóa dữ liệu raw và database cũ theo yêu cầu...\n")
    unlink(file.path(PROJECT_ROOT, "data", "raw", "*.csv"), force = TRUE)
    unlink(file.path(PROJECT_ROOT, "database", "job_market.sqlite"), force = TRUE)
    cat("  -> Đã xóa dữ liệu cũ thành công.\n\n")

    # Kiểm tra Python khả dụng (Ưu tiên môi trường ảo .venv nếu có)
    venv_python <- file.path(PROJECT_ROOT, ".venv", "Scripts", "python.exe")
    python_cmd <- if (file.exists(venv_python)) {
      venv_python
    } else {
      if (.Platform$OS.type == "windows") "python" else "python3"
    }
    python_check <- system(paste(python_cmd, "--version"), intern = TRUE, ignore.stderr = TRUE)
    cat(paste0("  Python version: ", python_check, "\n"))

    # Đọc cấu hình user để hiển thị log
    if (file.exists("user_settings.json")) {
      tryCatch({
        user_cfg <- jsonlite::fromJSON("user_settings.json")
        if (isTRUE(user_cfg$date_filter$enabled)) {
          cat(sprintf("  [CONFIG] Kích hoạt lọc thời gian: %s đến %s\n", 
                      user_cfg$date_filter$start_date, 
                      user_cfg$date_filter$end_date))
        }
      }, error = function(e) {})
    }

    # Chạy scraper TopCV
    cat("\n  [1/2] Đang cào dữ liệu TopCV...\n")
    topcv_result <- system(
      paste(python_cmd, shQuote(file.path(PROJECT_ROOT, "python_scraper", "scraper_topcv.py"))),
      intern = FALSE
    )
    if (topcv_result == 0) {
      cat("  -> TopCV: Hoàn thành!\n")
    } else {
      warning("  -> TopCV: Có lỗi xảy ra (exit code ", topcv_result, ")")
    }

    # Chạy scraper VietnamWorks
    cat("\n  [2/2] Đang cào dữ liệu VietnamWorks...\n")
    vnw_result <- system(
      paste(python_cmd, shQuote(file.path(PROJECT_ROOT, "python_scraper", "scraper_vnw.py"))),
      intern = FALSE
    )
    if (vnw_result == 0) {
      cat("  -> VietnamWorks: Hoàn thành!\n")
    } else {
      warning("  -> VietnamWorks: Có lỗi xảy ra (exit code ", vnw_result, ")")
    }

    # Chạy translator
    cat("\n  [3/3] Đang dịch dữ liệu sang tiếng Anh (Vietnamese -> English)...\n")
    trans_result <- system(
      paste(python_cmd, shQuote(file.path(PROJECT_ROOT, "python_scraper", "translator.py"))),
      intern = FALSE
    )
    if (trans_result == 0) {
      cat("  -> Dịch thuật: Hoàn thành!\n")
    } else {
      warning("  -> Dịch thuật: Có lỗi xảy ra (exit code ", trans_result, ")")
    }


  }, error = function(e) {
    cat(paste0("\n  [LỖI] Không thể chạy Python scraper: ", e$message, "\n"))
    cat("  -> Bỏ qua bước cào dữ liệu. Tiếp tục xử lý dữ liệu có sẵn...\n")
  })

  cat("\n")
}

# ============================================================
# GIAI ĐOẠN 2: Xử lý dữ liệu & Phân tích
# ============================================================
if (run_process) {
  cat(paste(rep("=", 60), collapse = ""), "\n")
  cat("[MODULE 2] XỬ LÝ DỮ LIỆU — R Processing Engine\n")
  cat(paste(rep("=", 60), collapse = ""), "\n")

  tryCatch({
    # Bước 2a: Làm sạch & Load vào DB
    cat("\n  [1/2] Làm sạch dữ liệu thô và lưu vào Database...\n")
    source(file.path(PROJECT_ROOT, "r_processing", "01_data_cleaning.R"), local = TRUE)
    clean_and_load_data()
    cat("  -> Data Cleaning: Hoàn thành!\n")

    # Bước 2b: Phân tích xu hướng
    cat("\n  [2/2] Phân tích xu hướng thị trường...\n")
    source(file.path(PROJECT_ROOT, "r_processing", "02_market_analysis.R"), local = TRUE)
    run_market_analysis()
    cat("  -> Market Analysis: Hoàn thành!\n")

  }, error = function(e) {
    cat(paste0("\n  [LỖI] Lỗi xử lý dữ liệu: ", e$message, "\n"))
    cat("  -> Kiểm tra lại file CSV trong data/raw/ và schema Database.\n")
  })

  cat("\n")
}

# ============================================================
# GIAI ĐOẠN 3: Khởi động Shiny Web App
# ============================================================
if (run_app) {
  cat(paste(rep("=", 60), collapse = ""), "\n")
  cat("[MODULE 3] KHỞI ĐỘNG WEB APP — R Shiny\n")
  cat(paste(rep("=", 60), collapse = ""), "\n")
  cat("\n  Đang khởi động Shiny App...\n")
  cat("  Truy cập: http://localhost:3838\n")
  cat("  Nhấn Ctrl+C để dừng.\n\n")

  shiny::runApp(
    appDir = file.path(PROJECT_ROOT, "shiny_app"),
    port = 3838,
    host = "0.0.0.0",
    launch.browser = TRUE
  )
}

cat("\n[DONE] Pipeline hoàn tất.\n")
