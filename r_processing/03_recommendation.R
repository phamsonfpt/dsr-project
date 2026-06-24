# ==============================================================================
# 03_recommendation.R — Hệ thống gợi ý việc làm (TF-IDF + Cosine Similarity)
# Job Recommendation & Market Analysis Platform
# ==============================================================================
# Module cung cấp:
#   - build_tfidf_model(con)             : Xây dựng mô hình TF-IDF từ DB
#   - compute_fit_score(...)             : Tính điểm phù hợp cho ứng viên
#   - find_alternative_jobs(...)         : Gợi ý việc thay thế (K-Means)
#   - analyze_skill_gap(...)             : Phân tích kỹ năng còn thiếu
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
  if (!file.exists(config_path)) {
    config_path <- file.path(getwd(), "..", "r_processing", "00_db_config.R")
  }
  if (file.exists(config_path)) {
      # source only if not already loaded
      if (!exists("get_db_connection", mode="function")) {
          source(config_path, encoding = "UTF-8")
      }
  } else {
      stop("[RECOMMEND] Không tìm thấy 00_db_config.R")
  }
})

# --- Nạp thư viện -----------------------------------------------------------
for (pkg in c("dplyr", "text2vec", "Matrix")) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg)
}
library(dplyr)
library(text2vec)
library(Matrix)

# ==============================================================================
# Hàm phụ: Tokenizer đơn giản cho tiếng Việt + tiếng Anh
# Tách theo khoảng trắng, lowercase, bỏ stop words cơ bản
# ==============================================================================
.simple_tokenizer <- function(texts) {
  # Stop words cơ bản (kết hợp Việt + Anh)
  stop_words <- c(
    # Tiếng Anh
    "and", "or", "the", "a", "an", "in", "on", "at", "to", "for", "of",
    "with", "is", "are", "was", "were", "be", "been", "being",
    # Tiếng Việt
    "va", "hoac", "cua", "cho", "voi", "trong", "tai", "la", "duoc",
    "co", "khong", "den", "tu", "mot", "cac", "nhung", "nhu", "ve"
  )

  lapply(texts, function(txt) {
    tokens <- unlist(strsplit(tolower(txt), "\\s+"))
    tokens <- tokens[nzchar(tokens)]
    tokens <- tokens[!tokens %in% stop_words]
    tokens <- tokens[nchar(tokens) >= 2]  # Bỏ token quá ngắn
    return(tokens)
  })
}

# ==============================================================================
# build_tfidf_model(con)
# Xây dựng mô hình TF-IDF từ tất cả job trong DB
#
# Mỗi job được biểu diễn = paste(title, skills, experience_level)
# Trả về list:
#   $vectorizer  : text2vec vectorizer (dùng lại cho candidate)
#   $tfidf       : TfIdf model object
#   $dtm         : Document-Term Matrix (sparse, các job)
#   $job_ids     : Vector job_id tương ứng với từng hàng của DTM
#   $jobs_meta   : Data frame metadata (job_id, title, company, salary, url, ...)
# ==============================================================================
build_tfidf_model <- function(con) {
  message("\n", strrep("=", 60))
  message("[RECOMMEND] Đang xây dựng mô hình TF-IDF...")
  message(strrep("=", 60))

  # --- 0. Tự động chọn chiến lược mô hình dựa trên số lượng data -----------
  # Ngưỡng: < 5000 jobs → Machine Learning (TF-IDF + Cosine Similarity)
  #         >= 5000 jobs → Deep Learning (Text Embedding + Qdrant Vector Search)
  n_jobs  <- as.integer(dbGetQuery(con, "SELECT COUNT(*) as n FROM jobs")[1, 1])
  n_skills <- as.integer(dbGetQuery(con, "SELECT COUNT(*) as n FROM job_skills")[1, 1])

  ML_THRESHOLD <- 5000L  # Cần >= 5000 jobs để chạy Deep Learning (Embedding + Qdrant)

  model_strategy <- if (n_jobs >= ML_THRESHOLD) {
    message("[RECOMMEND] \u200b Chiến lược: DEEP LEARNING (", n_jobs, " jobs \u2265 ", ML_THRESHOLD,
            ") — Text Embedding + Qdrant Vector Search")
    "deep_learning"
  } else {
    message("[RECOMMEND] \u200b Chiến lược: MACHINE LEARNING (", n_jobs, " jobs < ", ML_THRESHOLD,
            ") — TF-IDF + Cosine Similarity")
    "machine_learning"
  }
  message("[RECOMMEND]   Số skills: ", n_skills)

  # --- 1. Truy vấn dữ liệu jobs + skills ------------------------------------
  jobs_df <- dbGetQuery(con, "SELECT * FROM jobs")
  skills_df <- dbGetQuery(con, "SELECT job_id, skill_name FROM job_skills")

  if (nrow(jobs_df) == 0) {
    stop("[RECOMMEND] B\u1ea3ng jobs r\u1ed7ng. H\u00e3y n\u1ea1p d\u1eef li\u1ec7u tr\u01b0\u1edbc.")
  }

  message("[RECOMMEND]   S\u1ed1 jobs: ", nrow(jobs_df))
  message("[RECOMMEND]   S\u1ed1 skills: ", nrow(skills_df))

  # --- 2. Gộp skills thành chuỗi cho mỗi job --------------------------------
  skills_agg <- skills_df %>%
    group_by(job_id) %>%
    summarise(skills_text = paste(skill_name, collapse = " "), .groups = "drop")

  jobs_corpus <- jobs_df %>%
    left_join(skills_agg, by = "job_id") %>%
    mutate(
      skills_text = ifelse(is.na(skills_text), "", skills_text),
      experience_level = ifelse(is.na(experience_level), "", experience_level),
      # Tạo document: kết hợp title + skills + experience
      document = paste(title, skills_text, experience_level)
    )

  message("[RECOMMEND]   \u0110\u00e3 t\u1ea1o corpus: ", nrow(jobs_corpus), " t\u00e0i li\u1ec7u")

  # --- 3. Xây dựng TF-IDF ---------------------------------------------------
  # Tạo iterator từ corpus
  it <- itoken(
    jobs_corpus$document,
    tokenizer    = .simple_tokenizer,
    ids          = jobs_corpus$job_id,
    progressbar  = FALSE
  )

  # Xây dựng vocabulary (loại bỏ từ quá hiếm hoặc quá phổ biến)
  vocab <- create_vocabulary(it) %>%
    prune_vocabulary(
      term_count_min  = 2,    # Xuất hiện ít nhất 2 lần
      doc_proportion_max = 0.95  # Không xuất hiện trong > 95% documents
    )

  message("[RECOMMEND]   Vocabulary size: ", nrow(vocab))

  # Tạo vectorizer
  vectorizer <- vocab_vectorizer(vocab)

  # Tạo DTM (Document-Term Matrix)
  # Cần tạo lại iterator vì đã bị consume
  it <- itoken(
    jobs_corpus$document,
    tokenizer    = .simple_tokenizer,
    ids          = jobs_corpus$job_id,
    progressbar  = FALSE
  )
  dtm <- create_dtm(it, vectorizer)

  # Áp dụng TF-IDF transformation
  tfidf_model <- TfIdf$new()
  dtm_tfidf <- fit_transform(dtm, tfidf_model)

  message("[RECOMMEND]   DTM dimensions: ", nrow(dtm_tfidf), " x ", ncol(dtm_tfidf))
  message("[RECOMMEND] \u2705 M\u00f4 h\u00ecnh TF-IDF \u0111\u00e3 s\u1eb5n s\u00e0ng!")

  # --- 4. Trả về model object ------------------------------------------------
  model <- list(
    vectorizer     = vectorizer,
    tfidf          = tfidf_model,
    dtm            = dtm_tfidf,
    job_ids        = jobs_corpus$job_id,
    model_strategy = model_strategy,   # "machine_learning" | "deep_learning"
    n_jobs         = n_jobs,
    jobs_meta  = jobs_corpus %>%
      select(job_id, title, company, salary_min, salary_max,
             experience_level, location, url, source)
  )

  return(model)
}

# ==============================================================================
# Hàm phụ: Cosine Similarity giữa 1 vector và ma trận
# candidate_vec: 1 x p sparse vector
# dtm: n x p sparse matrix
# Trả về: vector n giá trị cosine similarity
# ==============================================================================
.cosine_similarity <- function(candidate_vec, dtm) {
  # Đảm bảo candidate_vec là matrix 1 hàng
  if (!is(candidate_vec, "dgCMatrix") && !is(candidate_vec, "dgRMatrix")) {
    candidate_vec <- as(candidate_vec, "dgCMatrix")
  }

  # Tính norm
  candidate_norm <- sqrt(sum(candidate_vec^2))
  if (candidate_norm == 0) return(rep(0, nrow(dtm)))

  # Row norms của DTM
  row_norms <- sqrt(Matrix::rowSums(dtm^2))
  row_norms[row_norms == 0] <- 1  # Tránh chia cho 0

  # Dot product: candidate (1 x p) %*% t(dtm) (p x n) = 1 x n
  dot_products <- as.numeric(dtm %*% Matrix::t(candidate_vec))

  # Cosine similarity
  similarities <- dot_products / (row_norms * candidate_norm)

  return(similarities)
}

# ==============================================================================
# compute_fit_score()
# Tính điểm phù hợp giữa ứng viên và các job trong DB
#
# Tham số:
#   candidate_skills     : vector kỹ năng ứng viên, ví dụ c("python", "sql", "git")
#   candidate_experience : chuỗi kinh nghiệm, ví dụ "3 năm" hoặc "Junior"
#   target_title         : (tùy chọn) lọc theo job title chứa từ khóa này
#   model                : output từ build_tfidf_model()
#   con                  : kết nối DB (dùng nếu cần truy vấn thêm)
#
# Trả về: data.frame với job_id, title, company, fit_score_pct, salary_min,
#         salary_max, url — sắp xếp theo fit_score giảm dần
# ==============================================================================
compute_fit_score <- function(candidate_skills, candidate_experience,
                               target_title = NULL, model, con) {
  message("\n[RECOMMEND] \u0110ang t\u00ednh \u0111i\u1ec3m ph\u00f9 h\u1ee3p...")

  # --- 1. Tạo document cho ứng viên -----------------------------------------
  skills_text <- paste(tolower(candidate_skills), collapse = " ")
  exp_text <- tolower(as.character(candidate_experience))
  title_text <- if (!is.null(target_title)) tolower(target_title) else ""

  candidate_doc <- paste(title_text, skills_text, exp_text)
  message("[RECOMMEND]   Candidate document: '", candidate_doc, "'")

  # --- 2. Transform sang TF-IDF vector cùng vectorizer ----------------------
  it_cand <- itoken(
    candidate_doc,
    tokenizer   = .simple_tokenizer,
    ids         = "candidate",
    progressbar = FALSE
  )
  cand_dtm <- create_dtm(it_cand, model$vectorizer)
  cand_tfidf <- transform(cand_dtm, model$tfidf)

  # --- 3. Tính Cosine Similarity với tất cả jobs ----------------------------
  similarities <- .cosine_similarity(cand_tfidf, model$dtm)

  # Tạo kết quả
  results <- model$jobs_meta %>%
    mutate(
      cosine_sim    = similarities,
      fit_score_pct = round(cosine_sim * 100, 2)
    )

  # --- 4. Lọc theo target_title nếu có --------------------------------------
  if (!is.null(target_title) && nzchar(target_title)) {
    target_lower <- tolower(target_title)
    results <- results %>%
      filter(grepl(target_lower, tolower(title), fixed = TRUE))
    message("[RECOMMEND]   L\u1ecdc theo title '", target_title, "': ", nrow(results), " k\u1ebft qu\u1ea3")
  }

  # --- 5. Sắp xếp và trả về -------------------------------------------------
  results <- results %>%
    arrange(desc(fit_score_pct)) %>%
    select(job_id, title, company, fit_score_pct, salary_min, salary_max, location, url)

  message("[RECOMMEND] \u2705 T\u00ecm th\u1ea5y ", nrow(results), " vi\u1ec7c l\u00e0m ph\u00f9 h\u1ee3p.")

  if (nrow(results) > 0) {
    top5 <- head(results, 5)
    message("[RECOMMEND]   Top 5:")
    for (i in seq_len(nrow(top5))) {
      message("    ", i, ". [", top5$fit_score_pct[i], "%] ",
              top5$title[i], " @ ", top5$company[i])
    }
  }

  return(results)
}

# ==============================================================================
# find_alternative_jobs()
# Gợi ý việc làm thay thế dùng K-Means clustering
#
# Tham số:
#   candidate_vector : TF-IDF vector của ứng viên (1 x p sparse matrix)
#   model           : output từ build_tfidf_model()
#   n_clusters      : số cluster K-Means (mặc định 5)
#   top_n           : số kết quả trả về (mặc định 10)
#
# Trả về: data.frame jobs từ cluster gần nhất + các cluster lân cận
# ==============================================================================
find_alternative_jobs <- function(candidate_vector, model, n_clusters = 5, top_n = 10) {
  message("\n[RECOMMEND] \u0110ang t\u00ecm vi\u1ec7c l\u00e0m thay th\u1ebf b\u1eb1ng K-Means...")

  dtm_dense <- as.matrix(model$dtm)

  # Điều chỉnh n_clusters nếu số job ít hơn
  n_clusters <- min(n_clusters, nrow(dtm_dense))
  if (n_clusters < 2) {
    message("[RECOMMEND]   Kh\u00f4ng \u0111\u1ee7 d\u1eef li\u1ec7u \u0111\u1ec3 clustering. Tr\u1ea3 v\u1ec1 t\u1ea5t c\u1ea3.")
    return(head(model$jobs_meta, top_n))
  }

  # --- 1. K-Means clustering trên tất cả jobs --------------------------------
  set.seed(42)  # Đảm bảo kết quả tái lập
  km <- tryCatch(
    kmeans(dtm_dense, centers = n_clusters, nstart = 10, iter.max = 100),
    error = function(e) {
      message("[RECOMMEND]   L\u1ed7i K-Means: ", conditionMessage(e))
      return(NULL)
    }
  )

  if (is.null(km)) {
    return(head(model$jobs_meta, top_n))
  }

  message("[RECOMMEND]   \u0110\u00e3 t\u1ea1o ", n_clusters, " cluster, size: ",
          paste(km$size, collapse = ", "))

  # --- 2. Tìm cluster gần ứng viên nhất -------------------------------------
  cand_dense <- as.numeric(candidate_vector)
  # Nếu cand_dense ngắn hơn, pad thêm 0
  if (length(cand_dense) < ncol(km$centers)) {
    cand_dense <- c(cand_dense, rep(0, ncol(km$centers) - length(cand_dense)))
  } else if (length(cand_dense) > ncol(km$centers)) {
    cand_dense <- cand_dense[seq_len(ncol(km$centers))]
  }

  # Khoảng cách Euclidean tới từng centroid
  dists <- apply(km$centers, 1, function(center) {
    sqrt(sum((cand_dense - center)^2))
  })

  # Sắp xếp cluster theo khoảng cách
  cluster_order <- order(dists)
  nearest_cluster <- cluster_order[1]
  message("[RECOMMEND]   Cluster g\u1ea7n nh\u1ea5t: ", nearest_cluster,
          " (kho\u1ea3ng c\u00e1ch: ", round(dists[nearest_cluster], 4), ")")

  # --- 3. Lấy jobs từ cluster gần nhất + lân cận ----------------------------
  # Ưu tiên cluster gần nhất, rồi đến các cluster lân cận
  selected_jobs <- c()

  for (cl in cluster_order) {
    cluster_indices <- which(km$cluster == cl)
    selected_jobs <- c(selected_jobs, cluster_indices)
    if (length(selected_jobs) >= top_n * 2) break  # Lấy dư ra để lọc
  }

  # Lấy metadata và trả về
  alt_results <- model$jobs_meta[selected_jobs, ] %>%
    head(top_n)

  message("[RECOMMEND] \u2705 Tr\u1ea3 v\u1ec1 ", nrow(alt_results), " vi\u1ec7c l\u00e0m thay th\u1ebf.")
  return(alt_results)
}

# ==============================================================================
# analyze_skill_gap()
# Phân tích kỹ năng còn thiếu so với yêu cầu của job
#
# Tham số:
#   candidate_skills : vector kỹ năng ứng viên, ví dụ c("python", "sql")
#   job_id           : ID job cần so sánh
#   con              : kết nối DB
#
# Trả về: list với:
#   $required_skills : tất cả kỹ năng yêu cầu
#   $matching_skills : kỹ năng ứng viên khớp
#   $missing_skills  : kỹ năng còn thiếu
#   $match_pct       : phần trăm khớp
# ==============================================================================
analyze_skill_gap <- function(candidate_skills, job_id, con) {
  message("\n[RECOMMEND] Ph\u00e2n t\u00edch skill gap cho job_id = ", job_id, "...")

  # --- 1. Truy vấn kỹ năng yêu cầu -----------------------------------------
  required <- dbGetQuery(
    con,
    "SELECT skill_name FROM job_skills WHERE job_id = ?",
    params = list(job_id)
  )

  if (nrow(required) == 0) {
    message("[RECOMMEND]   Kh\u00f4ng t\u00ecm th\u1ea5y k\u1ef9 n\u0103ng y\u00eau c\u1ea7u cho job_id ", job_id)
    return(list(
      required_skills = character(0),
      matching_skills = character(0),
      missing_skills  = character(0),
      match_pct       = NA_real_
    ))
  }

  required_skills <- tolower(required$skill_name)
  candidate_lower <- tolower(candidate_skills)

  # --- 2. Tính set difference ------------------------------------------------
  matching <- intersect(candidate_lower, required_skills)
  missing  <- setdiff(required_skills, candidate_lower)

  match_pct <- if (length(required_skills) > 0) {
    round(length(matching) / length(required_skills) * 100, 1)
  } else {
    NA_real_
  }

  # --- 3. Lấy thêm thông tin job để hiển thị ---------------------------------
  job_info <- dbGetQuery(
    con,
    "SELECT title, company FROM jobs WHERE job_id = ?",
    params = list(job_id)
  )

  message("[RECOMMEND]   Job: ", job_info$title[1], " @ ", job_info$company[1])
  message("[RECOMMEND]   K\u1ef9 n\u0103ng y\u00eau c\u1ea7u (", length(required_skills), "): ",
          paste(required_skills, collapse = ", "))
  message("[RECOMMEND]   K\u1ef9 n\u0103ng kh\u1edbp   (", length(matching), "): ",
          paste(matching, collapse = ", "))
  message("[RECOMMEND]   K\u1ef9 n\u0103ng thi\u1ebfu  (", length(missing), "): ",
          paste(missing, collapse = ", "))
  message("[RECOMMEND]   \u0110\u1ed9 kh\u1edbp: ", match_pct, "%")

  return(list(
    job_title       = if (nrow(job_info) > 0) job_info$title[1] else NA_character_,
    job_company     = if (nrow(job_info) > 0) job_info$company[1] else NA_character_,
    required_skills = required_skills,
    matching_skills = matching,
    missing_skills  = missing,
    match_pct       = match_pct
  ))
}

# ==============================================================================
# Hàm tiện ích: Pipeline đầy đủ cho 1 ứng viên
# ==============================================================================
recommend_for_candidate <- function(candidate_skills, candidate_experience,
                                     target_title = NULL, top_n = 10) {
  message("\n", strrep("=", 60))
  message("[RECOMMEND] Pipeline g\u1ee3i \u00fd \u0111\u1ea7y \u0111\u1ee7 cho \u1ee9ng vi\u00ean")
  message(strrep("=", 60))
  message("[RECOMMEND]   K\u1ef9 n\u0103ng: ", paste(candidate_skills, collapse = ", "))
  message("[RECOMMEND]   Kinh nghi\u1ec7m: ", candidate_experience)
  if (!is.null(target_title)) message("[RECOMMEND]   V\u1ecb tr\u00ed m\u1ee5c ti\u00eau: ", target_title)

  con <- get_db_connection()

  tryCatch({
    # Bước 1: Xây dựng mô hình
    model <- build_tfidf_model(con)

    # Bước 2: Tính điểm phù hợp
    scores <- compute_fit_score(
      candidate_skills, candidate_experience,
      target_title, model, con
    )

    # Bước 3: Lấy top jobs
    top_jobs <- head(scores, top_n)

    # Bước 4: Phân tích skill gap cho top job
    if (nrow(top_jobs) > 0) {
      message("\n[RECOMMEND] Ph\u00e2n t\u00edch skill gap cho top ", min(3, nrow(top_jobs)), " vi\u1ec7c:")
      gap_analysis <- list()
      for (i in seq_len(min(3, nrow(top_jobs)))) {
        gap_analysis[[i]] <- analyze_skill_gap(
          candidate_skills, top_jobs$job_id[i], con
        )
      }
    } else {
      gap_analysis <- list()
    }

    # Bước 5: Tìm việc thay thế
    it_cand <- itoken(
      paste(target_title, paste(candidate_skills, collapse = " "), candidate_experience),
      tokenizer   = .simple_tokenizer,
      ids         = "candidate",
      progressbar = FALSE
    )
    cand_dtm <- create_dtm(it_cand, model$vectorizer)
    cand_tfidf <- transform(cand_dtm, model$tfidf)

    alternatives <- find_alternative_jobs(cand_tfidf, model, n_clusters = 5, top_n = top_n)

    message("\n", strrep("=", 60))
    message("[RECOMMEND] \u2705 Ho\u00e0n t\u1ea5t pipeline g\u1ee3i \u00fd!")
    message(strrep("=", 60))

    return(list(
      top_matches  = top_jobs,
      alternatives = alternatives,
      skill_gaps   = gap_analysis
    ))

  }, error = function(e) {
    message("[RECOMMEND] \u274c L\u1ed7i: ", conditionMessage(e))
    stop(e)
  }, finally = {
    close_db_connection(con)
  })
}

message("[RECOMMEND] Module 03_recommendation.R \u0111\u00e3 s\u1eb5n s\u00e0ng.")
message("  G\u1ecdi recommend_for_candidate() \u0111\u1ec3 ch\u1ea1y pipeline \u0111\u1ea7y \u0111\u1ee7.")
message("  Ho\u1eb7c g\u1ecdi t\u1eebng h\u00e0m ri\u00eang: build_tfidf_model(), compute_fit_score(), etc.")
