-- ============================================================
-- Job Recommendation & Market Analysis Platform
-- Database Schema — SQLite
-- ============================================================

-- Bật Foreign Key enforcement (SQLite mặc định tắt)
PRAGMA foreign_keys = ON;

-- -----------------------------------------------------------
-- 1. Bảng jobs_clean: Lưu thông tin việc làm cốt lõi
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS jobs_clean (
    job_id          INTEGER PRIMARY KEY AUTOINCREMENT,
    title           TEXT    NOT NULL,                -- Tiêu đề công việc đã chuẩn hóa
    company         TEXT    NOT NULL,                -- Tên công ty tuyển dụng
    salary_min      REAL    DEFAULT NULL,            -- Lương tối thiểu (triệu VND)
    salary_max      REAL    DEFAULT NULL,            -- Lương tối đa (triệu VND)
    experience_level TEXT   DEFAULT NULL,            -- Fresher / Junior / Mid / Senior
    location        TEXT    DEFAULT NULL,            -- Thành phố đã chuẩn hóa
    url             TEXT    UNIQUE NOT NULL,          -- Link gốc bài đăng (dùng làm key chống trùng)
    source          TEXT    DEFAULT NULL,            -- Nguồn dữ liệu: topcv / vietnamworks
    scraped_at      TEXT    DEFAULT (datetime('now')),-- Thời điểm cào dữ liệu
    updated_at      TEXT    DEFAULT (datetime('now')) -- Thời điểm cập nhật gần nhất
);

-- -----------------------------------------------------------
-- 2. Bảng job_skills: Quan hệ Job ↔ Skill (1-N)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS job_skills (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          INTEGER NOT NULL,
    skill_name      TEXT    NOT NULL,                -- Tên kỹ năng (Python, SQL, Git, ...)
    FOREIGN KEY (job_id) REFERENCES jobs_clean(job_id) ON DELETE CASCADE,
    UNIQUE(job_id, skill_name)                       -- Không lưu trùng skill cho 1 job
);

-- -----------------------------------------------------------
-- 3. Bảng market_trends: Kết quả phân tích thống kê
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS market_trends (
    trend_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    category        TEXT    NOT NULL,                -- Loại: top_skills, salary_by_role, jobs_by_location, ...
    key_name        TEXT    NOT NULL,                -- Tên thực thể: "Python", "AI Engineer", "Hà Nội"
    value_metric    REAL    NOT NULL,                -- Giá trị thống kê tương ứng
    extra_json      TEXT    DEFAULT NULL,            -- Dữ liệu mở rộng dạng JSON (Q1, Q3, ...)
    computed_at     TEXT    DEFAULT (datetime('now')),-- Thời điểm tính toán
    UNIQUE(category, key_name)                       -- Mỗi loại + thực thể chỉ 1 bản ghi (UPSERT)
);

-- -----------------------------------------------------------
-- INDEXES — Tối ưu tốc độ truy vấn
-- -----------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_jobs_title       ON jobs_clean(title);
CREATE INDEX IF NOT EXISTS idx_jobs_location    ON jobs_clean(location);
CREATE INDEX IF NOT EXISTS idx_jobs_experience  ON jobs_clean(experience_level);
CREATE INDEX IF NOT EXISTS idx_jobs_source      ON jobs_clean(source);
CREATE INDEX IF NOT EXISTS idx_skills_job_id    ON job_skills(job_id);
CREATE INDEX IF NOT EXISTS idx_skills_name      ON job_skills(skill_name);
CREATE INDEX IF NOT EXISTS idx_trends_category  ON market_trends(category);
