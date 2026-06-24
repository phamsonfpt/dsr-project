# ==============================================================
# Job Market Intelligence — Server Logic
# Handles DB queries, chart rendering, and recommendation engine
# ==============================================================

library(shiny)
library(DBI)
library(RSQLite)
library(plotly)
library(DT)
library(dplyr)
library(jsonlite)

# --- Server Definition ---
server <- function(input, output, session) {

  # ============================================================
  # 1. STARTUP: Connect DB, source processing scripts, load data
  # ============================================================

  # Database path (SQLite)
  db_path <- file.path("..", "database", "job_market.sqlite")

  # Source R processing scripts (DB config & recommendation engine)
  # These files define: get_db_connection(), compute_fit_score(),
  #   analyze_skill_gap(), find_alternative_jobs(), build_tfidf_model()
  tryCatch({
    source(file.path("..", "r_processing", "00_db_config.R"), local = TRUE)
    source(file.path("..", "r_processing", "03_recommendation.R"), local = TRUE)
  }, error = function(e) {
    message("INFO: R processing scripts not found. Using fallback DB connection.")
    message("Chi tiết lỗi: ", e$message)
  })

  # Fallback DB connection function if 00_db_config.R not available
  get_db <- function() {
    if (exists("get_db_connection", mode = "function")) {
      return(get_db_connection())
    }
    dbConnect(RSQLite::SQLite(), dbname = db_path)
  }

  # Reactive: Load all market trends from DB
  market_data <- reactiveVal(NULL)

  # Reactive: Store distinct skills for autocomplete
  all_skills <- reactiveVal(character(0))

  # Reactive: Store distinct job titles for position suggestions
  all_titles <- reactiveVal(character(0))

  # Reactive values to store analysis results
  rv <- reactiveValues(
    analysis_done      = FALSE,
    fit_score          = NULL,
    matched_jobs       = NULL,
    skill_gap          = NULL,
    user_skills_list   = NULL,
    required_skills    = NULL,
    parsed_cv          = NULL
  )

  # --- Startup data loading ---
  observe({
    tryCatch({
      con <- get_db()
      on.exit(dbDisconnect(con), add = TRUE)

      # Load market trends
      trends <- dbGetQuery(con, "SELECT * FROM market_trends")
      market_data(trends)

      # Load distinct skills for autocomplete
      skills <- dbGetQuery(con, "SELECT DISTINCT skill_name FROM job_skills ORDER BY skill_name")
      all_skills(skills$skill_name)

      # Load distinct job titles for position suggestions
      titles <- dbGetQuery(con, "SELECT DISTINCT title FROM jobs_clean ORDER BY title")
      all_titles(titles$title)

    }, error = function(e) {
      # If DB doesn't exist yet, use empty data
      message("DB connection info: ", e$message)
      market_data(data.frame(
        trend_id = integer(), category = character(),
        key_name = character(), value_metric = numeric(),
        extra_json = character(), computed_at = character()
      ))
    })
  })

  # --- Populate selectize inputs on server side ---
  observe({
    updateSelectizeInput(
      session, "user_skills",
      choices  = all_skills(),
      server   = TRUE # server-side for performance
    )
    updateSelectizeInput(
      session, "user_position",
      choices  = c("", all_titles()),
      server   = TRUE
    )
  })

  # ============================================================
  # 2. DASHBOARD TAB — Value Boxes & Charts
  # ============================================================

  # Helper: filter market data by category
  get_trend <- function(cat) {
    df <- market_data()
    if (is.null(df) || nrow(df) == 0) return(data.frame())
    df %>% filter(category == cat) %>% arrange(desc(value_metric))
  }

  # --- Value Box: Total Jobs ---
  output$vb_total_jobs <- renderText({
    tryCatch({
      con <- get_db()
      on.exit(dbDisconnect(con), add = TRUE)
      n <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM jobs_clean")$n
      format(n, big.mark = ".", decimal.mark = ",")
    }, error = function(e) "—")
  })

  # Removed vb_avg_salary

  # --- Value Box: Top Skill ---
  output$vb_top_skill <- renderText({
    df <- get_trend("top_skills")
    if (nrow(df) == 0) return("—")
    df$key_name[1]
  })

  # --- Value Box: Top Location ---
  output$vb_top_location <- renderText({
    df <- get_trend("jobs_by_location")
    if (nrow(df) == 0) return("—")
    df$key_name[1]
  })

  # --- Chart: Top 15 Skills (Horizontal Bar) ---
  output$chart_top_skills <- renderPlotly({
    df <- get_trend("top_skills")
    validate(need(nrow(df) > 0, "Chưa có dữ liệu kỹ năng. Vui lòng chạy phân tích thị trường trước."))

    # Take top 15 and reverse for horizontal bar
    df <- head(df, 15)
    df <- df[order(df$value_metric), ]
    df$key_name <- factor(df$key_name, levels = df$key_name)

    # Gradient color palette from purple to cyan
    n <- nrow(df)
    colors <- colorRampPalette(c("#667eea", "#764ba2", "#f093fb"))(n)

    plot_ly(
      df,
      x          = ~value_metric,
      y          = ~key_name,
      type       = "bar",
      orientation = "h",
      marker     = list(
        color        = colors,
        line         = list(width = 0),
        cornerradius = 6
      ),
      hovertemplate = paste0(
        "<b>%{y}</b><br>",
        "Số lượng: <b>%{x}</b> tin tuyển dụng",
        "<extra></extra>"
      )
    ) %>%
      layout(
        xaxis = list(
          title      = list(text = "Số lượng tin tuyển dụng", font = list(color = "#a0a0b8", size = 12)),
          color      = "#a0a0b8",
          gridcolor  = "rgba(255,255,255,0.04)",
          zerolinecolor = "rgba(255,255,255,0.04)"
        ),
        yaxis = list(
          title = "",
          color = "#e8e8f0",
          tickfont = list(size = 12)
        ),
        plot_bgcolor  = "rgba(0,0,0,0)",
        paper_bgcolor = "rgba(0,0,0,0)",
        margin        = list(l = 120, r = 20, t = 10, b = 40),
        font          = list(family = "Inter, sans-serif", color = "#e8e8f0"),
        hoverlabel    = list(
          bgcolor = "#1a1a2e",
          bordercolor = "#667eea",
          font = list(family = "Inter", color = "#e8e8f0")
        )
      ) %>%
      config(displayModeBar = FALSE)
  })

  # Removed chart_salary_role

  # --- Chart: Jobs by Location (Donut) ---
  output$chart_location <- renderPlotly({
    df <- get_trend("jobs_by_location")
    validate(need(nrow(df) > 0, "Chưa có dữ liệu địa điểm."))

    # Gradient-inspired color palette
    n <- nrow(df)
    colors <- c(
      "#667eea", "#764ba2", "#f093fb", "#f5576c", "#43e97b",
      "#38f9d7", "#4facfe", "#00f2fe", "#fa8231", "#f7b731",
      "#a55eea", "#778beb", "#e77f67", "#cf6a87", "#786fa6"
    )
    if (n > length(colors)) colors <- colorRampPalette(colors)(n)

    plot_ly(
      df,
      labels       = ~key_name,
      values       = ~value_metric,
      type         = "pie",
      hole         = 0.55,
      textinfo     = "label+percent",
      textposition = "outside",
      textfont     = list(color = "#e8e8f0", size = 12, family = "Inter"),
      marker       = list(
        colors = colors[1:n],
        line   = list(color = "#0f0f23", width = 2)
      ),
      hovertemplate = paste0(
        "<b>%{label}</b><br>",
        "Số việc làm: <b>%{value}</b><br>",
        "Tỷ lệ: <b>%{percent}</b>",
        "<extra></extra>"
      )
    ) %>%
      layout(
        showlegend    = TRUE,
        plot_bgcolor  = "rgba(0,0,0,0)",
        paper_bgcolor = "rgba(0,0,0,0)",
        margin        = list(l = 20, r = 20, t = 20, b = 20),
        font          = list(family = "Inter, sans-serif", color = "#e8e8f0"),
        legend        = list(
          font      = list(color = "#a0a0b8", size = 11),
          bgcolor   = "rgba(0,0,0,0)",
          borderwidth = 0
        ),
        hoverlabel = list(
          bgcolor = "#1a1a2e", bordercolor = "#667eea",
          font = list(family = "Inter", color = "#e8e8f0")
        ),
        # Center text in donut hole
        annotations = list(list(
          text       = "<b>Địa điểm</b>",
          showarrow  = FALSE,
          font       = list(size = 14, color = "#a0a0b8", family = "Inter"),
          x = 0.5, y = 0.5
        ))
      ) %>%
      config(displayModeBar = FALSE)
  })

  # --- Chart: Jobs by Experience Level (Bar) ---
  output$chart_experience <- renderPlotly({
    df <- get_trend("jobs_by_experience")
    validate(need(nrow(df) > 0, "Chưa có dữ liệu kinh nghiệm."))

    # Order experience levels logically
    exp_order <- c("Fresher", "Junior", "Mid", "Senior")
    df$key_name <- factor(df$key_name, levels = intersect(exp_order, df$key_name))
    df <- df[order(df$key_name), ]

    n <- nrow(df)
    colors <- c("#667eea", "#4facfe", "#43e97b", "#764ba2")
    if (n > length(colors)) colors <- colorRampPalette(colors)(n)

    plot_ly(
      df,
      x          = ~key_name,
      y          = ~value_metric,
      type       = "bar",
      marker     = list(
        color        = colors[1:n],
        line         = list(width = 0),
        cornerradius = 8
      ),
      text       = ~paste0(format(value_metric, big.mark = "."), " việc làm"),
      textposition = "outside",
      textfont   = list(color = "#a0a0b8", size = 11, family = "Inter"),
      hovertemplate = paste0(
        "<b>%{x}</b><br>",
        "Số việc làm: <b>%{y}</b>",
        "<extra></extra>"
      )
    ) %>%
      layout(
        xaxis = list(
          title     = "",
          color     = "#e8e8f0",
          tickfont  = list(size = 13),
          gridcolor = "rgba(255,255,255,0.04)"
        ),
        yaxis = list(
          title     = list(text = "Số lượng việc làm", font = list(color = "#a0a0b8", size = 12)),
          color     = "#a0a0b8",
          gridcolor = "rgba(255,255,255,0.04)",
          zerolinecolor = "rgba(255,255,255,0.04)"
        ),
        plot_bgcolor  = "rgba(0,0,0,0)",
        paper_bgcolor = "rgba(0,0,0,0)",
        margin        = list(l = 60, r = 20, t = 20, b = 40),
        font          = list(family = "Inter, sans-serif", color = "#e8e8f0"),
        hoverlabel    = list(
          bgcolor = "#1a1a2e", bordercolor = "#667eea",
          font = list(family = "Inter", color = "#e8e8f0")
        )
      ) %>%
      config(displayModeBar = FALSE)
  })

  # ============================================================
  # 3. RECOMMENDATION TAB — Analysis & Results
  # ============================================================

  # Output flag to control conditionalPanel visibility
  output$analysis_done <- reactive({ rv$analysis_done })
  outputOptions(output, "analysis_done", suspendWhenHidden = FALSE)


  # --- Trích xuất CV khi upload ---
  observeEvent(input$cv_upload, {
    req(input$cv_upload)
    
    withProgress(message = "Đang đọc nội dung CV...", value = 0.5, {
      tryCatch({
        parsed <- parse_cv_features(input$cv_upload$datapath)
        rv$parsed_cv <- parsed
        showNotification("Đọc CV thành công!", type = "message")
      }, error = function(e) {
        showNotification(paste("Lỗi khi đọc file PDF:", conditionMessage(e)), type = "error")
        rv$parsed_cv <- NULL
      })
    })
  })

  # --- Hiển thị Preview CV ---
  output$cv_preview_ui <- renderUI({
    req(rv$parsed_cv)
    p <- rv$parsed_cv
    
    tags$div(
      class = "glass-card animate-in",
      style = "margin-top: 16px; padding: 12px; border-left: 4px solid #667eea; background: rgba(102,126,234,0.05);",
      tags$h5(tags$i(class = "fas fa-check-circle", style = "color: #667eea; margin-right: 8px;"), "Thông tin đã trích xuất"),
      tags$div(
        style = "font-size: 0.9rem;",
        tags$b("Vị trí: "), p$position, tags$br(),
        tags$b("Kinh nghiệm: "), p$experience, tags$br(),
        tags$b("Kỹ năng: "), paste(p$skills, collapse = ", ")
      )
    )
  })

  # --- Main analysis event ---
  observeEvent(input$btn_analyze, {
    # Validate inputs
    validate(
      need(!is.null(rv$parsed_cv), "Vui lòng upload file CV (PDF) trước khi phân tích.")
    )

    # Collect user profile
    user_profile <- rv$parsed_cv

    # Show progress
    withProgress(message = "Đang phân tích hồ sơ...", value = 0, {

      incProgress(0.2, detail = "Truy vấn cơ sở dữ liệu...")

      tryCatch({
        con <- get_db()
        on.exit(dbDisconnect(con), add = TRUE)

        # --------------------------------------------------
        # Step 1: Get matching jobs from DB
        # --------------------------------------------------
        incProgress(0.2, detail = "Tìm kiếm việc làm phù hợp...")

        # Query jobs with their skills
        jobs_query <- "
          SELECT j.job_id, j.title, j.company, j.experience, j.level, j.location, j.url,
                 GROUP_CONCAT(js.skill_name, ', ') AS skills_text
          FROM jobs_clean j
          LEFT JOIN job_skills js ON j.job_id = js.job_id
          GROUP BY j.job_id
        "
        jobs_df <- dbGetQuery(con, jobs_query)

        if (nrow(jobs_df) == 0) {
          showNotification("Không tìm thấy việc làm nào trong cơ sở dữ liệu.",
                           type = "warning", duration = 5)
          return()
        }

        # --------------------------------------------------
        # Step 2: Compute Fit Scores
        # --------------------------------------------------
        incProgress(0.2, detail = "Tính điểm phù hợp (Cosine Similarity)...")

        # Check if compute_fit_score function exists from 03_recommendation.R
        if (exists("compute_fit_score", mode = "function")) {
          results <- compute_fit_score(user_profile, jobs_df)
          matched_jobs  <- results$matched_jobs
          fit_score_val <- results$fit_score
        } else {
          # Fallback: Simple keyword matching algorithm
          matched_jobs <- compute_fit_score_fallback(user_profile, jobs_df)
          fit_score_val <- if (nrow(matched_jobs) > 0) matched_jobs$fit_score[1] else 0
        }

        # --------------------------------------------------
        # Step 3: Analyze Skill Gap
        # --------------------------------------------------
        incProgress(0.2, detail = "Phân tích khoảng cách kỹ năng...")

        if (exists("analyze_skill_gap", mode = "function") && nrow(matched_jobs) > 0) {
          skill_gap_result <- analyze_skill_gap(user_profile$skills, matched_jobs$job_id[1], con)
        } else {
          # Fallback skill gap analysis
          skill_gap_result <- compute_skill_gap_fallback(user_profile, matched_jobs, con)
        }

        # Removed step 4 & 5
        # --------------------------------------------------
        # Store results in reactiveValues
        # --------------------------------------------------
        rv$fit_score        <- fit_score_val
        rv$matched_jobs     <- matched_jobs
        rv$skill_gap        <- skill_gap_result
        rv$user_skills_list <- user_profile$skills
        rv$analysis_done    <- TRUE

        incProgress(0.1, detail = "Hoàn tất!")

      }, error = function(e) {
        showNotification(
          paste("Lỗi phân tích:", e$message),
          type = "error", duration = 8
        )
        message("Analysis error: ", e$message)
      })
    }) # end withProgress
  }) # end observeEvent

  # ============================================================
  # FALLBACK FUNCTIONS (used when 03_recommendation.R not available)
  # ============================================================

  # Simple keyword-matching fit score
  compute_fit_score_fallback <- function(profile, jobs_df) {
    user_skills_lower <- tolower(profile$skills)

    scores <- sapply(seq_len(nrow(jobs_df)), function(i) {
      job_skills_text <- tolower(as.character(jobs_df$skills_text[i]))
      if (is.na(job_skills_text) || nchar(job_skills_text) == 0) return(0)

      job_skills <- trimws(unlist(strsplit(job_skills_text, ",")))
      if (length(job_skills) == 0) return(0)

      # Skill overlap
      skill_match <- sum(user_skills_lower %in% job_skills) / max(length(job_skills), 1)

      # Title similarity (simple)
      title_match <- if (grepl(tolower(profile$position), tolower(jobs_df$title[i]), fixed = TRUE)) 0.3 else 0

      # Experience match
      exp_match <- if (!is.na(jobs_df$experience[i]) &&
                       tolower(jobs_df$experience[i]) == tolower(profile$experience)) 0.2 else 0

      round((skill_match * 0.8 + exp_match * 0.2) * 100, 1)
    })

    jobs_df$fit_score <- pmin(scores, 100) # cap at 100
    jobs_df <- jobs_df[order(-jobs_df$fit_score), ]
    head(jobs_df, 20)
  }

  # Simple skill gap analysis
  compute_skill_gap_fallback <- function(profile, matched_jobs, con) {
    if (nrow(matched_jobs) == 0) {
      return(list(missing = character(0), matched = profile$skills))
    }

    # Get skills of top matched job
    top_job_id <- matched_jobs$job_id[1]
    required <- dbGetQuery(con, sprintf(
      "SELECT skill_name FROM job_skills WHERE job_id = %d", top_job_id
    ))$skill_name

    if (length(required) == 0) {
      # If top job has no skills, aggregate from top 5
      top_ids <- head(matched_jobs$job_id, 5)
      required <- dbGetQuery(con, sprintf(
        "SELECT DISTINCT skill_name FROM job_skills WHERE job_id IN (%s)",
        paste(top_ids, collapse = ",")
      ))$skill_name
    }

    user_lower <- tolower(profile$skills)
    req_lower  <- tolower(required)

    list(
      missing  = required[!req_lower %in% user_lower],
      matched  = profile$skills[user_lower %in% req_lower],
      required = required
    )
  }

  # ============================================================
  # 4. RENDER OUTPUTS — Gauge, Skill Gap, Salary, Table
  # ============================================================

  # --- Gauge Chart: Fit Score ---
  output$gauge_fit_score <- renderPlotly({
    req(rv$analysis_done, rv$fit_score)

    score <- rv$fit_score

    # Dynamic color based on score
    if (score >= 70) {
      gauge_color <- "#43e97b"
      glow_color  <- "rgba(67,233,123,0.3)"
    } else if (score >= 50) {
      gauge_color <- "#4facfe"
      glow_color  <- "rgba(79,172,254,0.3)"
    } else if (score >= 30) {
      gauge_color <- "#fa8231"
      glow_color  <- "rgba(250,130,49,0.3)"
    } else {
      gauge_color <- "#f5576c"
      glow_color  <- "rgba(245,87,108,0.3)"
    }

    plot_ly(
      type    = "indicator",
      mode    = "gauge+number+delta",
      value   = score,
      number  = list(
        suffix = "%",
        font   = list(size = 48, family = "Inter", color = "#e8e8f0", weight = 700)
      ),
      gauge = list(
        axis = list(
          range     = list(0, 100),
          tickwidth = 2,
          tickcolor = "rgba(255,255,255,0.2)",
          dtick     = 20,
          tickfont  = list(color = "#a0a0b8", size = 12, family = "Inter")
        ),
        bar = list(
          color     = gauge_color,
          thickness = 0.75
        ),
        bgcolor     = "rgba(255,255,255,0.05)",
        borderwidth = 0,
        steps = list(
          list(range = c(0, 30),  color = "rgba(245,87,108,0.08)"),
          list(range = c(30, 50), color = "rgba(250,130,49,0.08)"),
          list(range = c(50, 70), color = "rgba(79,172,254,0.08)"),
          list(range = c(70, 100), color = "rgba(67,233,123,0.08)")
        ),
        threshold = list(
          line  = list(color = "#e8e8f0", width = 3),
          thickness = 0.8,
          value     = score
        )
      )
    ) %>%
      layout(
        plot_bgcolor  = "rgba(0,0,0,0)",
        paper_bgcolor = "rgba(0,0,0,0)",
        margin        = list(l = 30, r = 30, t = 50, b = 10),
        font          = list(family = "Inter, sans-serif", color = "#e8e8f0"),
        annotations   = list(list(
          text       = "ĐỘ PHÙ HỢP",
          showarrow  = FALSE,
          x = 0.5, y = -0.05,
          font = list(size = 13, color = "#a0a0b8", family = "Inter", weight = 600),
          xref = "paper", yref = "paper"
        ))
      ) %>%
      config(displayModeBar = FALSE)
  })

  # --- Skill Gap UI ---
  output$skill_gap_ui <- renderUI({
    req(rv$analysis_done, rv$skill_gap)

    gap  <- rv$skill_gap
    missing_skills <- gap$missing
    matched_skills <- gap$matched

    tagList(
      # Matched skills
      if (length(matched_skills) > 0) {
        tags$div(
          tags$h4(
            tags$i(class = "fas fa-check-circle", style = "color: #43e97b;"),
            paste0("Kỹ năng đã có (", length(matched_skills), ")")
          ),
          tags$div(
            class = "skill-badges",
            lapply(matched_skills, function(s) {
              tags$span(
                class = "skill-badge has",
                tags$i(class = "fas fa-check"),
                s
              )
            })
          )
        )
      },

      # Missing skills
      if (length(missing_skills) > 0) {
        tags$div(
          style = "margin-top: 20px;",
          tags$h4(
            tags$i(class = "fas fa-exclamation-triangle", style = "color: #f5576c;"),
            paste0("Kỹ năng cần bổ sung (", length(missing_skills), ")")
          ),
          tags$div(
            class = "skill-badges",
            lapply(missing_skills, function(s) {
              tags$span(
                class = "skill-badge missing",
                tags$i(class = "fas fa-plus"),
                s
              )
            })
          )
        )
      },

      # Summary message
      if (length(missing_skills) == 0 && length(matched_skills) > 0) {
        tags$div(
          style = "margin-top: 16px; padding: 12px 16px; background: rgba(67,233,123,0.1);
                   border-radius: 12px; border: 1px solid rgba(67,233,123,0.2);",
          tags$p(
            style = "margin: 0; color: #43e97b; font-weight: 600;",
            tags$i(class = "fas fa-trophy", style = "margin-right: 8px;"),
            "Tuyệt vời! Bạn đã có đủ kỹ năng yêu cầu."
          )
        )
      }
    )
  })

  # Removed chart_salary_compare

  # --- Job Matches DataTable ---
  output$table_job_matches <- DT::renderDataTable({
    req(rv$analysis_done, rv$matched_jobs)
    df <- rv$matched_jobs

    # Prepare display columns
    display_df <- data.frame(
      `Vị trí`       = df$title,
      `Công ty`       = df$company,
      `Điểm phù hợp` = paste0(round(df$fit_score, 1), "%"),
      `Lương (triệu VND)` = ifelse(
        !is.na(df$salary_min) & !is.na(df$salary_max),
        paste0(df$salary_min, " - ", df$salary_max),
        "Thương lượng"
      ),
      `Kinh nghiệm`  = ifelse(is.na(df$experience), "—", df$experience),
      `Địa điểm`     = ifelse(is.na(df$location), "—", df$location),
      `Ứng tuyển`    = ifelse(
        !is.na(df$url) & nchar(df$url) > 0,
        paste0(
          '<a href="', df$url, '" target="_blank" class="btn-apply-link">',
          '<i class="fas fa-external-link-alt"></i> Ứng tuyển</a>'
        ),
        "—"
      ),
      stringsAsFactors = FALSE,
      check.names      = FALSE
    )

    DT::datatable(
      display_df,
      escape    = FALSE, # allow HTML in Ứng tuyển column
      rownames  = FALSE,
      selection = "none",
      options   = list(
        pageLength   = 10,
        lengthMenu   = c(5, 10, 20),
        dom          = "lfrtip",
        scrollX      = TRUE,
        language     = list(
          search       = "Tìm kiếm:",
          lengthMenu   = "Hiển thị _MENU_ dòng",
          info         = "Hiển thị _START_ - _END_ / _TOTAL_ kết quả",
          paginate     = list(
            `previous` = "Trước",
            `next`     = "Sau"
          ),
          zeroRecords  = "Không tìm thấy kết quả phù hợp",
          emptyTable   = "Không có dữ liệu"
        ),
        columnDefs = list(
          list(className = "dt-center", targets = c(2, 4, 5)),
          list(orderable = FALSE, targets = 6)
        ),
        initComplete = DT::JS(
          "function(settings, json) {",
          "  $(this.api().table().header()).css({'background-color': 'rgba(102,126,234,0.12)', 'color': '#e8e8f0'});",
          "}"
        )
      ),
      class = "display compact"
    )
  })

  # --- Alternative Jobs UI (shown when fit_score < 50%) ---
  output$alt_jobs_ui <- renderUI({
    req(rv$analysis_done)

    if (is.null(rv$fit_score) || rv$fit_score >= 50) return(NULL)
    if (is.null(rv$alternative_jobs) || nrow(rv$alternative_jobs) == 0) return(NULL)

    alt <- rv$alternative_jobs

    tags$div(
      class = "alt-jobs-section animate-in",
      style = "margin-top: 24px;",
      tags$h4(
        tags$i(class = "fas fa-lightbulb"),
        "Vị trí thay thế phù hợp hơn"
      ),
      tags$p(
        style = "color: #a0a0b8; margin-bottom: 16px; font-size: 0.9rem;",
        "Điểm phù hợp của bạn dưới 50%. Dưới đây là các vị trí khác bạn có thể cân nhắc:"
      ),
      tags$div(
        lapply(seq_len(min(nrow(alt), 5)), function(i) {
          tags$div(
            style = "display: flex; align-items: center; justify-content: space-between;
                     padding: 12px 16px; margin-bottom: 8px;
                     background: rgba(255,255,255,0.03); border-radius: 12px;
                     border: 1px solid rgba(255,255,255,0.06);
                     transition: all 0.3s ease;",
            tags$div(
              tags$div(
                style = "font-weight: 600; color: #e8e8f0; font-size: 0.95rem;",
                alt$title[i]
              ),
              tags$div(
                style = "color: #a0a0b8; font-size: 0.82rem; margin-top: 2px;",
                paste0(alt$company[i],
                       ifelse(!is.na(alt$location[i]), paste0(" • ", alt$location[i]), ""))
              )
            ),
            tags$div(
              style = "display: flex; align-items: center; gap: 12px;",
              tags$span(
                style = paste0(
                  "font-weight: 700; font-size: 0.95rem; color: ",
                  ifelse(alt$fit_score[i] >= 50, "#43e97b", "#4facfe"), ";"
                ),
                paste0(round(alt$fit_score[i], 1), "%")
              ),
              if (!is.na(alt$url[i]) && nchar(alt$url[i]) > 0) {
                tags$a(
                  href   = alt$url[i],
                  target = "_blank",
                  class  = "btn-apply-link",
                  style  = "font-size: 0.75rem; padding: 5px 12px;",
                  tags$i(class = "fas fa-external-link-alt"),
                  "Xem"
                )
              }
            )
          )
        })
      )
    )
  })

  # ============================================================
  # 5. SESSION CLEANUP
  # ============================================================
  session$onSessionEnded(function() {
    message("Shiny session ended. Cleaning up...")
  })

} # end server function
