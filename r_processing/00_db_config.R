# ==============================================================================
# 00_db_config.R — Cấu hình kết nối cơ sở dữ liệu SQLite
# Job Recommendation & Market Analysis Platform
# ==============================================================================
# Module cung cấp:
#   - get_project_root()    : Tìm thư mục gốc dự án
#   - get_db_connection()   : Mở kết nối SQLite (tự tạo DB + schema nếu chưa có)
#   - close_db_connection() : Đóng kết nối an toàn
#   - init_database()       : Khởi tạo lại schema (force re-init)
# ==============================================================================

# --- Nạp thư viện cần thiết ------------------------------------------------
if (!requireNamespace("DBI", quietly = TRUE))      install.packages("DBI")
if (!requireNamespace("RSQLite", quietly = TRUE))   install.packages("RSQLite")

library(DBI)
library(RSQLite)

# ==============================================================================
# Hàm tìm thư mục gốc dự án
# Logic: đi ngược từ thư mục chứa script hoặc working directory,
#        tìm folder chứa file init_db.sql ở database/
# ==============================================================================
get_project_root <- function() {
  # Ưu tiên 1: Biến môi trường DSR_PROJECT_ROOT (cho CI/CD hoặc config ngoài)
  env_root <- Sys.getenv("DSR_PROJECT_ROOT", unset = "")
  if (nzchar(env_root) && dir.exists(env_root)) {
    return(normalizePath(env_root, winslash = "/"))
  }

  # Ưu tiên 2: Vị trí file script đang chạy (hỗ trợ source() và Rscript)
  candidates <- c()

  # Trường hợp gọi bằng source()
  if (sys.nframe() > 0) {
    for (i in seq_len(sys.nframe())) {
      env_i <- sys.frame(i)
      if (exists("ofile", envir = env_i, inherits = FALSE)) {
        script_dir <- dirname(normalizePath(get("ofile", envir = env_i), winslash = "/"))
        candidates <- c(candidates, script_dir)
      }
    }
  }

  # Trường hợp gọi bằng Rscript (commandArgs)
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- sub("^--file=", "", file_arg[1])
    if (file.exists(script_path)) {
        candidates <- c(candidates, dirname(normalizePath(script_path, winslash = "/")))
    } else if (file.exists(file.path("..", script_path))) {
        candidates <- c(candidates, dirname(normalizePath(file.path("..", script_path), winslash = "/")))
    }
  }

  # Ưu tiên 3: Dùng working directory hiện tại
  candidates <- c(candidates, normalizePath(getwd(), winslash = "/"))

  # Tìm ngược lên cây thư mục cho từng candidate

  for (start_dir in candidates) {
    current <- start_dir
    repeat {
      # Marker: thư mục database/init_db.sql tồn tại
      marker <- file.path(current, "database", "init_db.sql")
      if (file.exists(marker)) {
        return(normalizePath(current, winslash = "/"))
      }
      parent <- dirname(current)
      if (parent == current) break
      current <- parent
    }
  }

  stop(paste0(
    "[DB_CONFIG] Kh\u00f4ng t\u00ecm th\u1ea5y th\u01b0 m\u1ee5c g\u1ed1c d\u1ef1 \u00e1n.\n",
    "  \u0110\u1ea3m b\u1ea3o r\u1eb1ng database/init_db.sql t\u1ed3n t\u1ea1i ho\u1eb7c set DSR_PROJECT_ROOT."
  ))
}

# ==============================================================================
# Đường dẫn tuyệt đối tới DB file
# ==============================================================================
.db_rel_path <- function() {
  root <- get_project_root()
  file.path(root, "database", "job_market.sqlite")
}

.sql_init_path <- function() {
  root <- get_project_root()
  file.path(root, "database", "init_db.sql")
}

# ==============================================================================
# Đọc và thực thi file init_db.sql
# Tách từng lệnh SQL bằng dấu ;  (bỏ qua comment --)
# ==============================================================================
.execute_init_sql <- function(con) {
  sql_file <- .sql_init_path()
  if (!file.exists(sql_file)) {
    stop("[DB_CONFIG] File init_db.sql kh\u00f4ng t\u1ed3n t\u1ea1i: ", sql_file)
  }

  message("[DB_CONFIG] \u0110\u1ecdc v\u00e0 th\u1ef1c thi schema t\u1eeb: ", sql_file)
  sql_content <- readLines(sql_file, encoding = "UTF-8", warn = FALSE)

  # Loại bỏ dòng comment thuần (bắt đầu bằng --)
  sql_content <- sql_content[!grepl("^\\s*--", sql_content)]
  sql_text <- paste(sql_content, collapse = "\n")

  # Tách thành từng câu lệnh theo dấu ;

  statements <- unlist(strsplit(sql_text, ";"))
  statements <- trimws(statements)
  statements <- statements[nzchar(statements)]

  for (stmt in statements) {
    tryCatch(
      dbExecute(con, paste0(stmt, ";")),
      error = function(e) {
        # PRAGMA và một số lệnh có thể báo lỗi nhẹ → chỉ cảnh báo
        message("[DB_CONFIG] C\u1ea3nh b\u00e1o khi ch\u1ea1y SQL: ", conditionMessage(e))
      }
    )
  }
  message("[DB_CONFIG] Schema \u0111\u00e3 \u0111\u01b0\u1ee3c kh\u1edfi t\u1ea1o th\u00e0nh c\u00f4ng.")
}

# ==============================================================================
# Kiểm tra schema đã tồn tại chưa (kiểm tra 3 bảng chính)
# ==============================================================================
.schema_exists <- function(con) {
  required_tables <- c("jobs_clean", "job_skills", "market_trends")
  existing <- dbListTables(con)
  all(required_tables %in% existing)
}

# ==============================================================================
# get_db_connection()
# Mở kết nối tới SQLite. Tự tạo file DB và schema nếu chưa tồn tại.
# Trả về: đối tượng DBIConnection
# ==============================================================================
get_db_connection <- function() {
  db_path <- .db_rel_path()

  # Tạo thư mục database/ nếu chưa có
  db_dir <- dirname(db_path)
  if (!dir.exists(db_dir)) {
    dir.create(db_dir, recursive = TRUE)
    message("[DB_CONFIG] \u0110\u00e3 t\u1ea1o th\u01b0 m\u1ee5c: ", db_dir)
  }

  is_new_db <- !file.exists(db_path)

  # Mở kết nối (RSQLite tự tạo file nếu chưa có)
  con <- tryCatch(
    dbConnect(RSQLite::SQLite(), dbname = db_path),
    error = function(e) {
      stop("[DB_CONFIG] Kh\u00f4ng th\u1ec3 k\u1ebft n\u1ed1i DB: ", conditionMessage(e))
    }
  )

  # Bật foreign key enforcement
  dbExecute(con, "PRAGMA foreign_keys = ON;")

  # Tự khởi tạo schema nếu DB mới hoặc thiếu bảng
  if (is_new_db || !.schema_exists(con)) {
    message("[DB_CONFIG] DB m\u1edbi ho\u1eb7c thi\u1ebfu b\u1ea3ng \u2014 \u0111ang kh\u1edfi t\u1ea1o schema...")
    .execute_init_sql(con)
  }

  message("[DB_CONFIG] K\u1ebft n\u1ed1i DB th\u00e0nh c\u00f4ng: ", db_path)
  return(con)
}

# ==============================================================================
# close_db_connection(con)
# Đóng kết nối SQLite an toàn
# ==============================================================================
close_db_connection <- function(con) {
  if (!is.null(con) && dbIsValid(con)) {
    dbDisconnect(con)
    message("[DB_CONFIG] \u0110\u00e3 \u0111\u00f3ng k\u1ebft n\u1ed1i DB.")
  } else {
    message("[DB_CONFIG] K\u1ebft n\u1ed1i \u0111\u00e3 \u0111\u00f3ng ho\u1eb7c kh\u00f4ng h\u1ee3p l\u1ec7.")
  }
}

# ==============================================================================
# init_database()
# Xóa DB cũ và khởi tạo lại schema từ đầu
# ==============================================================================
init_database <- function() {
  db_path <- .db_rel_path()

  # Xóa file DB cũ nếu tồn tại
  if (file.exists(db_path)) {
    file.remove(db_path)
    message("[DB_CONFIG] \u0110\u00e3 x\u00f3a DB c\u0169: ", db_path)
  }

  # Tạo DB mới + schema
  con <- get_db_connection()
  message("[DB_CONFIG] Kh\u1edfi t\u1ea1o l\u1ea1i DB ho\u00e0n t\u1ea5t.")
  return(con)
}

message("[DB_CONFIG] Module 00_db_config.R \u0111\u00e3 s\u1eb5n s\u00e0ng.")
