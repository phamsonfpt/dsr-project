# Job Recommendation & Market Analysis Platform

Hệ thống phân tích thị trường tuyển dụng và gợi ý việc làm dựa trên Machine Learning, kết hợp Python (Web Scraping) và R (Data Processing, Analytics & Shiny Web App).

## 📋 Tổng quan hệ thống

```
┌─────────────────┐     ┌──────────────────┐     ┌────────────────────┐
│  Python Scraper  │────▶│  R Processing    │────▶│   R Shiny App      │
│  (TopCV + VNW)   │     │  (Clean + ML)    │     │  (Dashboard + AI)  │
└─────────────────┘     └──────────────────┘     └────────────────────┘
         │                       │                        │
         ▼                       ▼                        ▼
    data/raw/*.csv         SQLite Database          localhost:3838
```

## 🛠 Yêu cầu hệ thống & Cài đặt

Dự án sử dụng môi trường ảo độc lập cho cả Python và R để tránh xung đột thư viện.

### Python (>= 3.9) - Môi trường `.venv`
Bạn cần tạo và kích hoạt môi trường ảo (Virtual Environment) trước khi cài đặt:

**Trên Windows (PowerShell):**
```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r python_scraper/requirements.txt
```

### R (>= 4.2) - Môi trường `renv`
Dự án sử dụng `renv` để quản lý package R. Mở R hoặc RStudio và chạy lệnh sau để khôi phục (restore) toàn bộ thư viện:

```R
install.packages("renv")
renv::restore()
```

### Trình duyệt Chrome/Chromium
DrissionPage cần Chrome/Chromium để chạy scraper ở chế độ stealth.

## 🚀 Cách sử dụng

Dự án hỗ trợ chạy toàn bộ quy trình từ A-Z chỉ với 1 lệnh, hoặc chạy rời rạc từng công đoạn tùy nhu cầu test của bạn.

### 1. Chạy toàn bộ dự án (All-in-one)
Lệnh này sẽ tự động gọi Python cào dữ liệu → Dùng R làm sạch → Đổ vào SQLite → Bật Web App.
```powershell
Rscript main.R
```

### 2. Chạy riêng từng Module bằng cờ (Flags)
Nếu bạn chỉ muốn chạy một đoạn cụ thể trong luồng (ví dụ: cào xong rồi, giờ chỉ muốn phân tích và bật web):

```powershell
# Chỉ chạy Python Scraper (Cào dữ liệu thô)
Rscript main.R --scrape-only

# Chỉ chạy R Processing (Làm sạch & Phân tích vào SQLite)
Rscript main.R --process-only

# Chỉ bật Shiny Web App (Đòi hỏi đã có dữ liệu trong SQLite)
Rscript main.R --app-only
```

### 3. Chạy riêng rẽ từng file gốc (Dành cho Debug)

**A. Đối với Python Scraper:**
Yêu cầu phải bật môi trường ảo trước khi chạy:
```powershell
.\.venv\Scripts\Activate.ps1
python python_scraper\scraper_topcv.py      # Cào TopCV
python python_scraper\scraper_vnw.py        # Cào VietnamWorks
```

**B. Đối với R Processing:**
Các file R trong `r_processing/` đều chứa hàm (function) chứ không chạy trực tiếp khi gọi. Cách chuẩn nhất để test chúng là thông qua cờ `--process-only` ở trên.

---

## ⚙️ Cấu hình người dùng (User Settings)

Bạn không cần sửa code để đổi tham số! Hệ thống hỗ trợ một file cấu hình riêng cho bạn có tên `user_settings.json` tại thư mục gốc. Bạn có thể tạo/sửa file này để điều khiển tool cào dữ liệu:

```json
{
  "max_pages": 5,
  "date_filter": {
    "enabled": true,
    "start_date": "2026-06-01",
    "end_date": "2026-06-17"
  }
}
```
- `max_pages`: Giới hạn số trang tối đa (Cầu chì an toàn).
- `date_filter`: Lọc tin tức đăng từ khoảng thời gian X đến Y. Bot sẽ cào từ hiện tại lùi về quá khứ và ngắt khi gặp `start_date`.

## 📁 Cấu trúc thư mục

```
job_recommendation_system/
│
├── database/                   # Quản lý Database
│   ├── job_market.sqlite       # File SQLite (tự tạo khi chạy)
│   └── init_db.sql             # Script khởi tạo Schema
│
├── data/
│   └── raw/                    # Dữ liệu thô do Python scraper tạo
│
├── python_scraper/             # Module 1: Thu thập dữ liệu
│   ├── requirements.txt
│   ├── config.json             # Cấu hình URL, selectors, proxy
│   ├── scraper_topcv.py        # Scraper TopCV
│   └── scraper_vnw.py          # Scraper VietnamWorks
│
├── r_processing/               # Module 2 & 4: Xử lý dữ liệu & ML
│   ├── 00_db_config.R          # Kết nối Database
│   ├── 01_data_cleaning.R      # Làm sạch & chuẩn hóa
│   ├── 02_market_analysis.R    # Phân tích xu hướng
│   └── 03_recommendation.R    # Thuật toán NLP + Recommendation
│
├── shiny_app/                  # Module 3 & 5: Giao diện Web
│   ├── ui.R                    # Thiết kế giao diện
│   ├── server.R                # Logic nghiệp vụ
│   └── www/custom.css          # Styling tùy chỉnh
│
├── main.R                      # Entry Point
└── README.md                   # Tài liệu này
```

## 🗄 Database Schema

Hệ thống sử dụng **SQLite** với 3 bảng chính:

| Bảng | Mô tả | Cột chính |
|------|--------|-----------|
| `jobs_clean` | Thông tin việc làm | title, company, salary_min/max, experience_level, location, url |
| `job_skills` | Quan hệ Job ↔ Skill | job_id (FK), skill_name |
| `market_trends` | Kết quả phân tích | category, key_name, value_metric, extra_json |

## 🧠 Thuật toán Recommendation

1. **TF-IDF Vectorization**: Chuyển đổi JD và hồ sơ ứng viên sang không gian vector
2. **Cosine Similarity**: Tính độ tương đồng → Fit Score (%)
3. **K-Means Clustering**: Phân cụm công việc → Gợi ý vị trí thay thế
4. **Skill Gap Analysis**: Phép trừ tập hợp → Kỹ năng cần bổ sung

## 📊 Tính năng Dashboard

- **Tổng quan thị trường**: Top Skills, Salary by Role, Jobs by Location
- **Gợi ý việc làm**: Nhập skills + kinh nghiệm → Nhận Fit Score, Skill Gap, Job list
- **Interactive charts**: Tất cả biểu đồ dùng Plotly (hover, zoom, filter)

## ⚠️ Lưu ý

- TopCV và VietnamWorks có thể thay đổi cấu trúc HTML. Nếu scraper không hoạt động, cập nhật CSS selectors trong `python_scraper/config.json`
- Scraper giả lập hành vi người dùng với delay ngẫu nhiên 1.5–4.5 giây để tránh bị chặn
- Nên chạy scraper vào giờ thấp tải và giới hạn số trang hợp lý

## 📝 License

MIT License
