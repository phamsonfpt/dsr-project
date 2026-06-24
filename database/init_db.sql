-- ============================================================
-- Job Recommendation & Market Analysis Platform
-- Database Schema — SQLite (Thống nhất & Hợp nhất phiên bản)
-- ============================================================

-- Bật Foreign Key enforcement
PRAGMA foreign_keys = ON;

-- -----------------------------------------------------------
-- 1. Bảng jobs: Thông tin tuyển dụng hợp nhất từ TopCV và VietnamWorks
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS jobs (
    job_id               TEXT    PRIMARY KEY,           -- ID duy nhất (TopCV ID hoặc VietnamWorks ID/Hash)
    title                TEXT    NOT NULL,              -- Tiêu đề công việc (Data Scientist, v.v.)
    company              TEXT    NOT NULL,              -- Tên công ty tuyển dụng
    url                  TEXT    UNIQUE NOT NULL,       -- Link canonical tuyển dụng
    salary_text          TEXT    DEFAULT NULL,          -- Lương dạng chữ gốc (VD: "15 - 20 triệu", "Thỏa thuận")
    salary_currency      TEXT    DEFAULT NULL,          -- Đơn vị tiền tệ ("VND" / "USD" / NULL)
    salary_min           REAL    DEFAULT NULL,          -- Lương tối thiểu (triệu VND)
    salary_max           REAL    DEFAULT NULL,          -- Lương tối đa (triệu VND)
    experience_years_min REAL    DEFAULT NULL,          -- Số năm kinh nghiệm tối thiểu dạng số (VD: 2.0)
    experience_level     TEXT    DEFAULT NULL,          -- Cấp độ kinh nghiệm ("Fresher", "Junior", "Mid", "Senior")
    location             TEXT    DEFAULT NULL,          -- Địa điểm làm việc đã chuẩn hóa (VD: "Hà Nội", "TP.HCM")
    job_description      TEXT    DEFAULT NULL,          -- Mô tả công việc chi tiết
    requirements         TEXT    DEFAULT NULL,          -- Yêu cầu ứng viên
    benefits             TEXT    DEFAULT NULL,          -- Quyền lợi được hưởng
    date_posted          TEXT    DEFAULT NULL,          -- Ngày đăng tin (YYYY-MM-DD)
    deadline             TEXT    DEFAULT NULL,          -- Hạn nộp hồ sơ (YYYY-MM-DD)
    level                TEXT    DEFAULT NULL,          -- Cấp bậc công việc ("Nhân viên", "Trưởng nhóm", v.v.)
    scraped_at           TEXT    DEFAULT NULL,          -- Thời điểm cào/xử lý tin
    source               TEXT    DEFAULT NULL,          -- Nguồn dữ liệu ("TopCV" / "VietnamWorks")
    source_file          TEXT    DEFAULT NULL,          -- File dữ liệu gốc
    raw_text_for_matching TEXT   DEFAULT NULL           -- Text tổng hợp để chạy recommendation engine
);

-- -----------------------------------------------------------
-- 2. Bảng job_skills: Liên kết giữa công việc và kỹ năng IT
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS job_skills (
    job_id      TEXT    NOT NULL,
    skill_name  TEXT    NOT NULL,
    PRIMARY KEY (job_id, skill_name),
    FOREIGN KEY (job_id) REFERENCES jobs(job_id) ON DELETE CASCADE
);

-- -----------------------------------------------------------
-- 3. Bảng market_trends: Kết quả phân tích thống kê thị trường
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS market_trends (
    trend_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    category        TEXT    NOT NULL,                -- top_skills, salary_by_role, jobs_by_location, jobs_by_experience, salary_by_location
    key_name        TEXT    NOT NULL,                -- "Python", "Hà Nội", "Senior"
    value_metric    REAL    NOT NULL,                -- Giá trị số liệu
    extra_json      TEXT    DEFAULT NULL,            -- Dữ liệu mở rộng dạng JSON (q1, q3, min, max, n)
    computed_at     TEXT    DEFAULT (datetime('now')),
    UNIQUE(category, key_name)
);

-- -----------------------------------------------------------
-- INDEXES — Tối ưu tốc độ truy vấn cho Shiny App và Rec Engine
-- -----------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_jobs_title            ON jobs(title);
CREATE INDEX IF NOT EXISTS idx_jobs_location         ON jobs(location);
CREATE INDEX IF NOT EXISTS idx_jobs_experience_level ON jobs(experience_level);
CREATE INDEX IF NOT EXISTS idx_jobs_date_posted      ON jobs(date_posted);
CREATE INDEX IF NOT EXISTS idx_jobs_source           ON jobs(source);
CREATE INDEX IF NOT EXISTS idx_job_skills_name       ON job_skills(skill_name);
CREATE INDEX IF NOT EXISTS idx_trends_category       ON market_trends(category);
