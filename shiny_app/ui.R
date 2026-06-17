# ==============================================================
# Job Market Intelligence — UI Definition
# Premium dark theme with glassmorphism & gradient accents
# ==============================================================

library(shiny)
library(shinydashboard)
library(shinyWidgets)
library(plotly)
library(DT)

# --- UI Definition ---
ui <- fluidPage(

  # ----- Head: Google Fonts + Custom CSS -----
  tags$head(
    tags$link(
      rel  = "preconnect",
      href = "https://fonts.googleapis.com"
    ),
    tags$link(
      rel         = "preconnect",
      href        = "https://fonts.gstatic.com",
      crossorigin = NA
    ),
    tags$link(
      rel  = "stylesheet",
      href = "https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&display=swap"
    ),
    # Font Awesome 6 for icons
    tags$link(
      rel  = "stylesheet",
      href = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css"
    ),
    # Custom premium CSS
    tags$link(
      rel  = "stylesheet",
      href = "custom.css"
    ),
    # Viewport meta for responsive
    tags$meta(
      name    = "viewport",
      content = "width=device-width, initial-scale=1"
    )
  ),

  # ----- App Header -----
  tags$header(
    class = "app-header",
    tags$h1(class = "app-title", "Job Market Intelligence"),
    tags$p(class = "app-subtitle", "Nền tảng phân tích & gợi ý việc làm thông minh"),
    tags$hr(class = "header-divider")
  ),

  # ----- Tab Navigation -----
  tabsetPanel(
    id   = "main_tabs",
    type = "tabs",

    # =============================================
    # TAB 1 — Tổng quan thị trường (Market Dashboard)
    # =============================================
    tabPanel(
      title = tagList(icon("chart-line"), "Tổng quan thị trường"),
      value = "dashboard",

      # Row 1: Value Boxes
      tags$div(
        class = "value-box-grid",
        style = "margin-top: 8px;",

        # Total Jobs
        tags$div(
          class = "value-box vb-purple animate-in animate-delay-1",
          tags$div(class = "vb-icon", tags$i(class = "fas fa-briefcase")),
          tags$div(class = "vb-value", textOutput("vb_total_jobs", inline = TRUE)),
          tags$div(class = "vb-label", "Tổng việc làm")
        ),

        # Average Salary
        tags$div(
          class = "value-box vb-green animate-in animate-delay-2",
          tags$div(class = "vb-icon", tags$i(class = "fas fa-coins")),
          tags$div(class = "vb-value", textOutput("vb_avg_salary", inline = TRUE)),
          tags$div(class = "vb-label", "Lương trung bình")
        ),

        # Top Skill
        tags$div(
          class = "value-box vb-pink animate-in animate-delay-3",
          tags$div(class = "vb-icon", tags$i(class = "fas fa-star")),
          tags$div(class = "vb-value", textOutput("vb_top_skill", inline = TRUE)),
          tags$div(class = "vb-label", "Kỹ năng hot nhất")
        ),

        # Top Location
        tags$div(
          class = "value-box vb-orange animate-in animate-delay-4",
          tags$div(class = "vb-icon", tags$i(class = "fas fa-map-marker-alt")),
          tags$div(class = "vb-value", textOutput("vb_top_location", inline = TRUE)),
          tags$div(class = "vb-label", "Địa điểm hàng đầu")
        )
      ),

      # Row 2: Top Skills + Salary by Role
      tags$div(
        class = "chart-grid",

        # Top 15 Skills
        tags$div(
          class = "glass-card animate-in animate-delay-1",
          tags$div(
            class = "card-title",
            tags$i(class = "fas fa-code"),
            "Top 15 kỹ năng được yêu cầu nhiều nhất"
          ),
          plotlyOutput("chart_top_skills", height = "420px") |>
            shinycssloaders::withSpinner(type = 8, color = "#667eea", size = 0.5)
        ),

        # Salary by Role
        tags$div(
          class = "glass-card animate-in animate-delay-2",
          tags$div(
            class = "card-title",
            tags$i(class = "fas fa-money-bill-trend-up"),
            "Phân bố lương theo vị trí"
          ),
          plotlyOutput("chart_salary_role", height = "420px") |>
            shinycssloaders::withSpinner(type = 8, color = "#667eea", size = 0.5)
        )
      ),

      # Row 3: Location + Experience
      tags$div(
        class = "chart-grid",

        # Jobs by Location (Donut)
        tags$div(
          class = "glass-card animate-in animate-delay-3",
          tags$div(
            class = "card-title",
            tags$i(class = "fas fa-location-dot"),
            "Phân bố việc làm theo địa điểm"
          ),
          plotlyOutput("chart_location", height = "400px") |>
            shinycssloaders::withSpinner(type = 8, color = "#667eea", size = 0.5)
        ),

        # Jobs by Experience Level
        tags$div(
          class = "glass-card animate-in animate-delay-4",
          tags$div(
            class = "card-title",
            tags$i(class = "fas fa-layer-group"),
            "Việc làm theo cấp độ kinh nghiệm"
          ),
          plotlyOutput("chart_experience", height = "400px") |>
            shinycssloaders::withSpinner(type = 8, color = "#667eea", size = 0.5)
        )
      )
    ), # end tabPanel Dashboard

    # =============================================
    # TAB 2 — Gợi ý việc làm (Job Recommendation)
    # =============================================
    tabPanel(
      title = tagList(icon("wand-magic-sparkles"), "Gợi ý việc làm"),
      value = "recommendation",

      tags$div(
        class = "reco-layout",
        style = "margin-top: 8px;",

        # ----- Left: Input Panel -----
        tags$div(
          class = "input-panel",
          tags$div(
            class = "glass-card",
            tags$div(
              class = "card-title",
              tags$i(class = "fas fa-user-pen"),
              "Hồ sơ ứng viên"
            ),

            # Skills input (multi-select with autocomplete)
            tags$div(
              class = "form-group",
              tags$label(`for` = "user_skills", "Kỹ năng của bạn"),
              selectizeInput(
                inputId  = "user_skills",
                label    = NULL,
                choices  = NULL, # populated from server
                multiple = TRUE,
                options  = list(
                  placeholder  = "Gõ để tìm kỹ năng (Python, SQL, ...)",
                  maxItems     = 20,
                  plugins      = list("remove_button"),
                  openOnFocus  = FALSE
                )
              )
            ),

            # Experience Level
            tags$div(
              class = "form-group",
              tags$label(`for` = "user_exp", "Cấp độ kinh nghiệm"),
              selectInput(
                inputId  = "user_exp",
                label    = NULL,
                choices  = c(
                  "Chọn cấp độ..."  = "",
                  "Fresher (0-1 năm)" = "Fresher",
                  "Junior (1-3 năm)"  = "Junior",
                  "Mid (3-5 năm)"     = "Mid",
                  "Senior (5+ năm)"   = "Senior"
                ),
                selected = ""
              )
            ),

            # Target Position
            tags$div(
              class = "form-group",
              tags$label(`for` = "user_position", "Vị trí mong muốn"),
              selectizeInput(
                inputId  = "user_position",
                label    = NULL,
                choices  = NULL, # populated from server
                multiple = FALSE,
                options  = list(
                  placeholder = "Ví dụ: Data Analyst, AI Engineer...",
                  create      = TRUE,
                  maxItems    = 1
                )
              )
            ),

            # Expected Salary
            tags$div(
              class = "form-group",
              tags$label(`for` = "user_salary", "Mức lương kỳ vọng (triệu VND)"),
              numericInput(
                inputId = "user_salary",
                label   = NULL,
                value   = NULL,
                min     = 1,
                max     = 200,
                step    = 1
              )
            ),

            tags$hr(class = "section-divider"),

            # Analyze Button
            actionButton(
              inputId = "btn_analyze",
              label   = tagList(icon("bolt"), "Phân tích hồ sơ"),
              class   = "btn-gradient"
            )
          )
        ), # end input-panel

        # ----- Right: Results Panel -----
        tags$div(
          class = "results-panel",

          # Placeholder (shown before analysis)
          conditionalPanel(
            condition = "output.analysis_done == false",
            tags$div(
              class = "results-placeholder",
              tags$div(class = "placeholder-icon", tags$i(class = "fas fa-compass")),
              tags$p("Nhập thông tin hồ sơ và nhấn 'Phân tích hồ sơ' để nhận gợi ý việc làm phù hợp với bạn")
            )
          ),

          # Results (shown after analysis)
          conditionalPanel(
            condition = "output.analysis_done == true",

            # Gauge Chart — Fit Score
            tags$div(
              class = "glass-card animate-in",
              tags$div(
                class = "card-title",
                tags$i(class = "fas fa-gauge-high"),
                "Điểm phù hợp tổng thể"
              ),
              tags$div(
                class = "gauge-section",
                plotlyOutput("gauge_fit_score", height = "280px")
              )
            ),

            # Skill Gap
            tags$div(
              class = "glass-card animate-in",
              style = "margin-top: 24px;",
              tags$div(
                class = "card-title",
                tags$i(class = "fas fa-puzzle-piece"),
                "Phân tích kỹ năng"
              ),
              uiOutput("skill_gap_ui")
            ),

            # Salary Comparison
            tags$div(
              class = "glass-card animate-in",
              style = "margin-top: 24px;",
              tags$div(
                class = "card-title",
                tags$i(class = "fas fa-scale-balanced"),
                "So sánh mức lương"
              ),
              plotlyOutput("chart_salary_compare", height = "200px")
            ),

            # Job Matches Table
            tags$div(
              class = "glass-card animate-in job-table-wrapper",
              style = "margin-top: 24px;",
              tags$div(
                class = "card-title",
                tags$i(class = "fas fa-list-check"),
                "Việc làm phù hợp nhất"
              ),
              DT::dataTableOutput("table_job_matches")
            ),

            # Alternative Jobs (if fit score < 50%)
            uiOutput("alt_jobs_ui")
          )
        ) # end results-panel
      ) # end reco-layout
    ) # end tabPanel Recommendation
  ) # end tabsetPanel
) # end fluidPage
