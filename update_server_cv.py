import re

with open('shiny_app/server.R', 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Add source for 04_cv_parser.R
code = code.replace('source("../r_processing/03_recommendation.R")',
                    'source("../r_processing/03_recommendation.R")\n  source("../r_processing/04_cv_parser.R")')

# 2. Add parsed_cv to reactiveValues
code = code.replace('required_skills    = NULL\n  )',
                    'required_skills    = NULL,\n    parsed_cv          = NULL\n  )')

# 3. Add observeEvent for cv_upload to parse it
parse_logic = """
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
"""

# Insert before btn_analyze
code = re.sub(r'(  # --- Main analysis event ---)', parse_logic + r'\n\1', code)

# 4. Update btn_analyze to use parsed_cv instead of user_skills
btn_analyze_old = """    # Validate inputs
    validate(
      need(length(input$user_skills) > 0, "Vui lòng chọn ít nhất 1 kỹ năng."),
      need(input$user_exp != "",          "Vui lòng chọn cấp độ kinh nghiệm."),
      need(
        !is.null(input$user_position) && nchar(input$user_position) > 0,
        "Vui lòng nhập vị trí mong muốn."
      )
    )

    # Collect user profile
    user_profile <- list(
      skills     = input$user_skills,
      experience = input$user_exp,
      position   = input$user_position
    )"""

btn_analyze_new = """    # Validate inputs
    validate(
      need(!is.null(rv$parsed_cv), "Vui lòng upload file CV (PDF) trước khi phân tích.")
    )

    # Collect user profile
    user_profile <- rv$parsed_cv"""

code = code.replace(btn_analyze_old, btn_analyze_new)

with open('shiny_app/server.R', 'w', encoding='utf-8') as f:
    f.write(code)
