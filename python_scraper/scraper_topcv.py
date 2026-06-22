"""
scraper_topcv.py - Thu thập dữ liệu việc làm từ TopCV.vn
=========================================================

Sử dụng DrissionPage (ChromiumPage) với chế độ stealth để vượt qua
cơ chế chống bot. Mô phỏng hành vi người dùng thực: cuộn trang ngẫu nhiên,
thời gian chờ ngẫu nhiên, và xử lý phân trang tự động.

Cách chạy:
    python scraper_topcv.py
    python scraper_topcv.py --max-pages 10
    python scraper_topcv.py --headless
"""

import json
import logging
import os
import random
import sys
import time
import argparse
from datetime import datetime, timedelta
import re
from pathlib import Path
from typing import Optional

import pandas as pd
from DrissionPage import ChromiumPage, ChromiumOptions
from DrissionPage.errors import ElementNotFoundError

# ─────────────────────────── CẤU HÌNH LOGGING ───────────────────────────
if sys.stdout.encoding.lower() != 'utf-8':
    sys.stdout.reconfigure(encoding='utf-8')

log_file_path = os.path.join(os.path.dirname(__file__), "scraper_topcv.log")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s │ %(levelname)-8s │ %(message)s",
    datefmt="%H:%M:%S",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(log_file_path, encoding="utf-8"),
    ],
)
logger = logging.getLogger(__name__)


# ═══════════════════════════ HÀM TIỆN ÍCH ═══════════════════════════════


def parse_relative_date(date_str: str) -> datetime:
    if not date_str:
        return datetime.now()
    date_str = str(date_str).lower().strip()
    now = datetime.now()
    if 'vừa xong' in date_str or 'hôm nay' in date_str or 'giờ trước' in date_str or 'phút trước' in date_str:
        return now
    match_day = re.search(r'(\d+)\s*ngày', date_str)
    if match_day:
        return now - timedelta(days=int(match_day.group(1)))
    match_week = re.search(r'(\d+)\s*tuần', date_str)
    if match_week:
        return now - timedelta(weeks=int(match_week.group(1)))
    match_month = re.search(r'(\d+)\s*tháng', date_str)
    if match_month:
        return now - timedelta(days=int(match_month.group(1))*30)
    match_abs = re.search(r'(\d{1,2})[-/](\d{1,2})[-/](\d{4})', date_str)
    if match_abs:
        try:
            return datetime.strptime(match_abs.group(0).replace('-', '/'), '%d/%m/%Y')
        except:
            pass
    return now

def load_config(config_path: str = None) -> dict:
    """Đọc file cấu hình JSON. Trả về dict rỗng nếu lỗi."""
    if config_path is None:
        config_path = os.path.join(os.path.dirname(__file__), "config.json")
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        logger.info("✅ Đọc cấu hình từ %s thành công", config_path)
        
        user_cfg_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'user_settings.json')
        try:
            with open(user_cfg_path, 'r', encoding='utf-8') as uf:
                user_cfg = json.load(uf)
                if 'max_pages' in user_cfg:
                    cfg['topcv'] = cfg.get('topcv', {})
                    cfg['topcv']['max_pages'] = user_cfg['max_pages']
                    cfg['vietnamworks'] = cfg.get('vietnamworks', {})
                    cfg['vietnamworks']['max_pages'] = user_cfg['max_pages']
                
                # Update individually for topcv and vietnamworks if present
                if 'topcv' in user_cfg and isinstance(user_cfg['topcv'], dict):
                    cfg.setdefault('topcv', {}).update(user_cfg['topcv'])
                if 'vietnamworks' in user_cfg and isinstance(user_cfg['vietnamworks'], dict):
                    cfg.setdefault('vietnamworks', {}).update(user_cfg['vietnamworks'])
                cfg['user_settings'] = user_cfg
                logger.info('✅ Đã ghi đè cấu hình từ user_settings.json')
        except FileNotFoundError:
            pass
        return cfg
    except (FileNotFoundError, json.JSONDecodeError) as e:
        logger.error("❌ Không đọc được config: %s", e)
        return {}


def random_delay(delay_range: list[float]) -> None:
    """Tạm dừng ngẫu nhiên trong khoảng [min, max] giây — mô phỏng người dùng."""
    lo, hi = delay_range
    wait = round(random.uniform(lo, hi), 2)
    logger.debug("⏳ Chờ %.2f giây...", wait)
    time.sleep(wait)


def simulate_human_scroll(page: ChromiumPage) -> None:
    """
    Cuộn trang ngẫu nhiên để kích hoạt lazy-load và giảm phát hiện bot.
    Cuộn từ 2-5 lần, mỗi lần cuộn một đoạn ngẫu nhiên rồi dừng lại.
    """
    scroll_count = random.randint(2, 5)
    for i in range(scroll_count):
        # Cuộn xuống một đoạn ngẫu nhiên từ 300-800 pixel
        scroll_px = random.randint(300, 800)
        page.scroll.down(scroll_px)
        time.sleep(random.uniform(0.3, 1.0))
    # Cuộn lại lên đầu trang để đảm bảo nhìn thấy toàn bộ nội dung
    page.scroll.to_top()
    time.sleep(random.uniform(0.5, 1.0))


def safe_text(element, selector: str, attr: Optional[str] = None) -> str:
    """
    Trích xuất text hoặc attribute từ element con một cách an toàn.
    Trả về chuỗi rỗng nếu không tìm thấy phần tử.
    """
    try:
        if selector and not selector.startswith(('css:', 'xpath:', 'tag:', '@')):
            selector = 'css:' + selector
        child = element.ele(selector, timeout=0)
        if child is None:
            return ""
        if attr:
            return (child.attr(attr) or "").strip()
        return (child.text or "").strip()
    except Exception:
        return ""


def safe_texts(element, selector: str) -> str:
    """
    Lấy text từ nhiều element con, nối bằng dấu phẩy.
    Dùng cho trường hợp skill tags (có nhiều thẻ).
    Với TopCV: lấy thêm skills ẩn từ data-original-title của .remaining-items.
    """
    try:
        if selector and not selector.startswith(('css:', 'xpath:', 'tag:', '@')):
            selector = 'css:' + selector
        children = element.eles(selector, timeout=0)
        if not children:
            return ""
        texts = []
        for c in children:
            txt = c.text.strip() if c.text else ""
            # Bỏ qua các text bị cắt ngắn (kết thúc bằng "...")
            if txt and not txt.endswith("..."):
                texts.append(txt)

        # Lấy thêm skills từ .remaining-items[data-original-title]
        try:
            remaining = element.eles('css:.remaining-items', timeout=0)
            for r in remaining:
                title_attr = r.attr("data-original-title") or ""
                if title_attr:
                    extra = [s.strip() for s in title_attr.split(",") if s.strip()]
                    texts.extend(extra)
        except Exception:
            pass

        return ", ".join(dict.fromkeys(texts))  # unique, preserve order
    except Exception:
        return ""


# ═══════════════════════════ LỚP SCRAPER CHÍNH ══════════════════════════

class TopCVScraper:
    """
    Bộ thu thập dữ liệu việc làm từ TopCV.vn.

    Sử dụng DrissionPage với ChromiumPage ở chế độ stealth để:
    - Vượt qua Cloudflare và các cơ chế chống bot
    - Mô phỏng hành vi duyệt web của người dùng thực
    - Tự động phân trang và thu thập nhiều trang kết quả

    Attributes:
        config (dict): Cấu hình từ config.json
        selectors (dict): CSS selectors chính
        fallback (dict): CSS selectors dự phòng
        jobs (list[dict]): Danh sách việc làm đã thu thập
    """

    def __init__(self, config: dict, headless: bool = False):
        """
        Khởi tạo scraper với cấu hình cho trước.

        Args:
            config: Dict cấu hình chứa URL, selectors, delay_range, v.v.
            headless: True = chạy nền (không hiện trình duyệt).
        """
        topcv_cfg = config.get("topcv", {})
        self.base_url = topcv_cfg.get(
            "base_url", "https://www.topcv.vn/tim-viec-lam-moi-nhat"
        )
        self.max_pages = topcv_cfg.get("max_pages", 5)
        self.delay_range = topcv_cfg.get("delay_range", [1.5, 4.5])
        self.selectors = topcv_cfg.get("selectors", {})
        self.fallback = topcv_cfg.get("fallback_selectors", {})
        self.output_dir = config.get("output_dir", "../data/raw")
        self.proxy = config.get("proxy", "")
        self.headless = headless
        self.detail_selectors = topcv_cfg.get("detail_selectors", {})

        
        user_settings = config.get('user_settings', {})
        date_filter = config.get('topcv', {}).get('date_filter', user_settings.get('date_filter', {}))
        self.date_filter_enabled = date_filter.get('enabled', False)
        try:
            self.start_date = datetime.strptime(date_filter.get('start_date', '2000-01-01'), '%Y-%m-%d')
            self.end_date = datetime.strptime(date_filter.get('end_date', '2100-01-01'), '%Y-%m-%d')
        except Exception:
            self.date_filter_enabled = False
            
        self.jobs: list[dict] = []
        self.page: Optional[ChromiumPage] = None

    # ─────────────────── KHỞI TẠO TRÌNH DUYỆT ───────────────────────
    def _init_browser(self) -> ChromiumPage:
        """
        Tạo ChromiumPage với các thiết lập stealth:
        - User-Agent thực tế
        - Tắt flag tự động hoá để tránh phát hiện bot
        - Cấu hình proxy nếu có
        """
        co = ChromiumOptions()
        
        # SỬ DỤNG TRÌNH DUYỆT CHROME THẬT ĐỂ VƯỢT CLOUDFLARE
        import os as _os
        chrome_path = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
        if _os.path.exists(chrome_path):
            co.set_browser_path(chrome_path)
            # Tạo thư mục user data giả để không đụng độ Chrome đang mở
            debug_dir = _os.path.join(_os.getcwd(), 'chrome_debug_profile')
            co.set_user_data_path(debug_dir)

        # Chặn hoàn toàn bảng thông báo xin quyền Vị trí (Location) và Thông báo (Notifications)
        co.set_pref('profile.default_content_setting_values.geolocation', 2)
        co.set_pref('profile.default_content_setting_values.notifications', 2)

        if self.headless:
            co.headless()

        # Thiết lập stealth: tắt các dấu hiệu tự động hoá
        co.set_argument("--disable-blink-features=AutomationControlled")
        co.set_argument("--no-first-run")
        co.set_argument("--no-default-browser-check")
        co.set_argument("--disable-infobars")
        co.set_argument("--disable-popup-blocking")

        # Cấu hình proxy (nếu được cung cấp)
        if self.proxy:
            co.set_proxy(self.proxy)
            logger.info("🌐 Proxy: %s", self.proxy)

        page = ChromiumPage(co)
        logger.info("🚀 Trình duyệt đã khởi tạo (headless=%s)", self.headless)
        return page

    # ─────────────── TÌM PHẦN TỬ VỚI FALLBACK ──────────────────────
    def _find_elements(self, selector_key: str):
        """
        Tìm các phần tử bằng selector chính. Nếu không tìm thấy,
        tự động thử selector dự phòng. Trả về danh sách elements.
        """
        primary = self.selectors.get(selector_key, "")
        fallback = self.fallback.get(selector_key, "")

        # Thử selector chính
        if primary:
            try:
                elements = self.page.eles(primary, timeout=5)
                if elements:
                    logger.debug(
                        "Tìm thấy %d phần tử với selector chính '%s'",
                        len(elements), primary,
                    )
                    return elements
            except Exception:
                pass

        # Thử selector dự phòng
        if fallback:
            try:
                elements = self.page.eles(fallback, timeout=5)
                if elements:
                    logger.info(
                        "⚠️  Dùng selector dự phòng '%s' — tìm thấy %d phần tử",
                        fallback, len(elements),
                    )
                    return elements
            except Exception:
                pass

        logger.warning("❌ Không tìm thấy phần tử nào cho '%s'", selector_key)
        return []

    # ─────────────── TRÍCH XUẤT DỮ LIỆU TỪ 1 THẺ ──────────────────
    def _extract_job(self, card) -> dict:
        """
        Trích xuất thông tin việc làm từ một thẻ (job card).

        Thứ tự ưu tiên:
        1. Dùng selector chính
        2. Nếu thất bại → dùng selector dự phòng
        3. Nếu vẫn thất bại → trả về chuỗi rỗng

        Returns:
            dict chứa các trường: title, company, salary, experience,
            location, skills, url
        """
        def _get(key: str, attr: Optional[str] = None) -> str:
            """Thử selector chính rồi fallback cho một trường cụ thể."""
            val = safe_text(card, self.selectors.get(key, ""), attr)
            if not val and self.fallback.get(key):
                val = safe_text(card, self.fallback[key], attr)
            return val

        def _get_multi(key: str) -> str:
            """Lấy nhiều phần tử (skills/tags) từ card."""
            val = safe_texts(card, self.selectors.get(key, ""))
            if not val and self.fallback.get(key):
                val = safe_texts(card, self.fallback[key])
            return val


        date_str = safe_text(card, 'label.label-update')
        if not date_str:
            date_str = safe_text(card, '.time')
        job_date = parse_relative_date(date_str)

        # Lấy URL từ thẻ link tiêu đề
        url = _get("url", attr="href")
        # Đảm bảo URL đầy đủ
        if url and not url.startswith("http"):
            url = "https://www.topcv.vn" + url

        return {
            "title": _get("title"),
            "company": _get("company"),
            "salary": _get("salary"),
            "location": _get("location"),
            "url": url,
            "job_date": job_date,
            "source": "topcv",
            "scraped_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "job_description": "",
            "requirements": "",
            "benefits": ""
        }

    def _extract_job_details(self, url: str) -> dict:
        """
        Mở tab mới, cào chi tiết Job Description và Experience từ trang chi tiết.
        """
        result = {"job_description": "", "requirements": "", "benefits": "", "experience": ""}
        if not url: return result
        
        jd_selector = "css:.job-detail__information-detail, .job-description, .box-info-job"
        exp_selector = self.detail_selectors.get("experience", "css:.job-detail__box--left, .job-detail-info")
        
        tab = None
        try:
            tab = self.page.new_tab(url)
            time.sleep(random.uniform(0.5, 1.5))
            
            # 1. Lấy Job Description (Bao phủ cả trang chuẩn và trang Brand)
            jd_ele = tab.ele(jd_selector, timeout=3)
            if not jd_ele:
                # Cứu cánh cho trang Brand TopCV có HTML tuỳ biến: Lấy toàn bộ văn bản của trang
                jd_ele = tab.ele('tag:body', timeout=1)
                
            if jd_ele:
                full_text = jd_ele.text
                import re
                
                # Lọc bỏ rác UI của TopCV
                full_text = re.sub(r'(?i)Chi tiết tuyển dụng.*?Gửi cho tôi việc làm tương tự', '', full_text, flags=re.DOTALL).strip()
                full_text = re.sub(r'(?i)^(Chi tiết tuyển dụng)', '', full_text).strip()
                
                req_match = re.search(r'(?i)(?:yêu cầu ứng viên|yêu cầu[:\s]?)(.*?)(?=(?:quyền lợi|phúc lợi|những lợi ích|chuyên môn|địa điểm làm việc|$))', full_text, re.DOTALL)
                ben_match = re.search(r'(?i)(?:quyền lợi|phúc lợi|những lợi ích)[:\s]?(.*?)(?=(?:địa điểm làm việc|chuyên môn|cách thức|$))', full_text, re.DOTALL)
                jd_match = re.search(r'(?i)(?:mô tả công việc[:\s]?)?(.*?)(?=(?:yêu cầu|quyền lợi|chuyên môn|$))', full_text, re.DOTALL)
                
                jd_text = jd_match.group(1).strip() if jd_match else full_text.strip()
                jd_text = re.sub(r'(?i)^mô tả công việc[:\s]*', '', jd_text).strip()
                
                result["job_description"] = jd_text
                result["requirements"] = req_match.group(1).strip() if req_match else ""
                result["benefits"] = ben_match.group(1).strip() if ben_match else ""
                
            # 2. Lấy Experience (TopCV hiển thị "Kinh nghiệm\nDưới 1 năm")
            box = tab.ele(exp_selector, timeout=1)
            if box:
                lines = box.text.split('\n')
                for i, line in enumerate(lines):
                    if "Kinh nghiệm" in line and i + 1 < len(lines):
                        result["experience"] = lines[i+1].strip()
                        break
        except Exception as e:
            logger.debug(f"  ⚠️ Lỗi lấy detail: {e}")
        finally:
            if tab:
                tab.close()
                
        return result

    # ─────────────── THU THẬP MỘT TRANG ────────────────────────────
    def _scrape_page(self, page_num: int) -> int:
        """
        Thu thập tất cả việc làm trên trang hiện tại.

        Args:
            page_num: Số thứ tự trang (bắt đầu từ 1).

        Returns:
            Số lượng việc làm mới thu thập được từ trang này.
        """
        # Mô phỏng hành vi cuộn trang
        simulate_human_scroll(self.page)
        random_delay([0.5, 1.5])

        # Chờ phần tử đầu tiên xuất hiện (tối đa 10s)
        try:
            self.page.wait.ele_loaded(self.selectors.get("job_card", ".job-item"), timeout=00)
        except Exception:
            pass

        # Tìm tất cả job cards trên trang
        cards = self._find_elements("job_card")
        if not cards:
            logger.warning("⚠️  Trang %d: Không tìm thấy job card nào", page_num)
            return 0

        page_jobs = 0
        should_stop = False
        for idx, card in enumerate(cards, 1):
            try:
                
                job = self._extract_job(card)



                if self.date_filter_enabled:
                    job_date = job.get("job_date")
                    if job_date:
                        # Cẩn thận datetime không có giờ
                        if job_date.date() > self.end_date.date():
                            logger.debug("  ⏭️  [%d/%d] Bỏ qua vì mới hơn %s", idx, len(cards), self.end_date.strftime('%Y-%m-%d'))
                            continue
                        if job_date.date() < self.start_date.date():
                            logger.info("  🛑 Đã gặp tin đăng ngày %s (cũ hơn %s). Dừng cào.", job_date.strftime('%Y-%m-%d'), self.start_date.strftime('%Y-%m-%d'))
                            should_stop = True
                            break

                # Chỉ lưu nếu có ít nhất tiêu đề hoặc URL
                if job["title"] or job["url"]:
                    logger.debug("  🔍 Đang cào chi tiết JD cho: %s", job["url"])
                    details = self._extract_job_details(job["url"])
                    job["job_description"] = details["job_description"]
                    job["requirements"] = details.get("requirements", "")
                    job["benefits"] = details.get("benefits", "")
                        
                    job["job_date_str"] = job.get("job_date").strftime("%Y-%m-%d") if job.get("job_date") else ""
                    job.pop("job_date", None)
                    self.jobs.append(job)
                    page_jobs += 1
                    logger.debug(
                        "  📋 [%d/%d] %s — %s (JD: %s chars)",
                        idx, len(cards), job["title"][:50], job["company"][:30], len(job["job_description"])
                    )
                else:
                    logger.debug("  ⏭️  [%d/%d] Bỏ qua card trống", idx, len(cards))

            except Exception as e:
                logger.warning("  ⚠️  [%d/%d] Lỗi trích xuất: %s", idx, len(cards), e)
                continue

        logger.info(
            "📄 Trang %d/%d: Thu thập %d/%d việc làm (tổng cộng: %d)",
            page_num, self.max_pages, page_jobs, len(cards), len(self.jobs),
        )
        return page_jobs, should_stop

    # ─────────────── CHUYỂN TRANG ───────────────────────────────────
    def _go_next_page(self, current_page: int) -> bool:
        """
        Chuyển sang trang tiếp theo bằng cách:
        1. Thử click nút next page
        2. Nếu thất bại, thử thay đổi URL parameter

        Returns:
            True nếu chuyển trang thành công, False nếu hết trang.
        """
        # Cách 1: Click nút phân trang
        next_sel = self.selectors.get("next_page", "")
        fallback_next = self.fallback.get("next_page", "")

        for selector in [next_sel, fallback_next]:
            if not selector:
                continue
            try:
                next_btn = self.page.ele(selector, timeout=3)
                if next_btn:
                    next_btn.click()
                    # Chờ trang tải xong
                    self.page.wait.load_start()
                    random_delay(self.delay_range)
                    logger.info("➡️  Đã chuyển sang trang %d", current_page + 1)
                    return True
            except Exception:
                continue

        # Cách 2: Thay đổi URL thủ công (TopCV dùng ?page=N)
        try:
            next_url = f"{self.base_url}?page={current_page + 1}"
            self.page.get(next_url)
            random_delay(self.delay_range)
            logger.info("➡️  Chuyển trang qua URL: %s", next_url)
            return True
        except Exception as e:
            logger.warning("❌ Không thể chuyển trang: %s", e)
            return False

    # ─────────────── LƯU KẾT QUẢ ───────────────────────────────────
    def _save_results(self) -> str:
        """
        Lưu danh sách việc làm ra file CSV.

        Returns:
            Đường dẫn tuyệt đối của file CSV đã lưu.
        """
        if not self.jobs:
            logger.warning("⚠️  Không có dữ liệu để lưu")
            return ""

        # Tạo thư mục output nếu chưa tồn tại
        script_dir = Path(__file__).parent
        output_path = (script_dir / self.output_dir).resolve()
        output_path.mkdir(parents=True, exist_ok=True)

        filepath = output_path / "topcv_jobs_raw.csv"
        df = pd.DataFrame(self.jobs)

        # Loại bỏ các dòng trùng lặp theo URL
        before = len(df)
        df.drop_duplicates(subset=["url"], keep="first", inplace=True)
        after = len(df)
        if before > after:
            logger.info("🔄 Loại bỏ %d bản ghi trùng lặp", before - after)

        df.to_csv(filepath, index=False, encoding="utf-8-sig")
        logger.info("💾 Đã lưu %d việc làm → %s", len(df), filepath)
        return str(filepath)

    # ─────────────── CHẠY TOÀN BỘ QUY TRÌNH ────────────────────────
    def run(self) -> str:
        """
        Thực thi toàn bộ quy trình thu thập dữ liệu:
        1. Khởi tạo trình duyệt stealth
        2. Truy cập trang đầu tiên
        3. Thu thập dữ liệu trên mỗi trang
        4. Phân trang đến hết hoặc đạt max_pages
        5. Lưu kết quả CSV

        Returns:
            Đường dẫn file CSV kết quả.
        """
        logger.info("═" * 60)
        logger.info("🏁 BẮT ĐẦU THU THẬP DỮ LIỆU TỪ TOPCV.VN")
        logger.info("   URL: %s", self.base_url)
        logger.info("   Số trang tối đa: %d", self.max_pages)
        logger.info("═" * 60)

        start_time = time.time()

        try:
            # Bước 1: Khởi tạo trình duyệt
            self.page = self._init_browser()

            # Bước 2: Truy cập trang đầu tiên
            logger.info("🌐 Đang truy cập %s ...", self.base_url)
            self.page.get(self.base_url)

            # Chờ trang tải hoàn toàn và vượt qua Cloudflare
            self.page.wait.load_start()
            random_delay(self.delay_range)

            # Bước 3: Lặp qua từng trang
            for page_num in range(1, self.max_pages + 1):
                logger.info("─" * 40)
                logger.info("📖 Đang xử lý trang %d/%d ...", page_num, self.max_pages)

                jobs_found = self._scrape_page(page_num)

                # Nếu không tìm thấy việc nào → có thể đã hết kết quả
                if jobs_found == 0:
                    logger.info("⛔ Không còn kết quả. Dừng phân trang.")
                    break

                # Chuyển trang (trừ trang cuối cùng)
                if page_num < self.max_pages:
                    if not self._go_next_page(page_num):
                        logger.info("⛔ Không thể chuyển trang. Dừng lại.")
                        break

            # Bước 4: Lưu kết quả
            result_path = self._save_results()

        except Exception as e:
            logger.error("💥 Lỗi nghiêm trọng: %s", e, exc_info=True)
            # Vẫn cố gắng lưu những gì đã thu thập được
            result_path = self._save_results()

        finally:
            # Đóng trình duyệt an toàn
            if self.page:
                try:
                    self.page.quit()
                    logger.info("🔒 Trình duyệt đã đóng")
                except Exception:
                    pass

        elapsed = round(time.time() - start_time, 1)
        logger.info("═" * 60)
        logger.info(
            "✅ HOÀN THÀNH: %d việc làm trong %.1f giây", len(self.jobs), elapsed
        )
        logger.info("═" * 60)

        return result_path


# ═══════════════════════════ ENTRY POINT ═════════════════════════════════

def parse_args() -> argparse.Namespace:
    """Xử lý tham số dòng lệnh."""
    parser = argparse.ArgumentParser(
        description="Thu thập dữ liệu việc làm từ TopCV.vn"
    )
    parser.add_argument(
        "--config", default=None,
        help="Đường dẫn file cấu hình (mặc định: config.json trong cùng thư mục)",
    )
    parser.add_argument(
        "--max-pages", type=int, default=None,
        help="Ghi đè số trang tối đa từ config",
    )
    parser.add_argument(
        "--headless", action="store_true",
        help="Chạy trình duyệt ở chế độ nền (không hiện giao diện)",
    )
    parser.add_argument(
        "--debug", action="store_true",
        help="Bật chế độ gỡ lỗi (hiển thị log chi tiết)",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()

    # Bật debug logging nếu cần
    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    # Đọc cấu hình
    config = load_config(args.config)
    if not config:
        logger.error("Không thể khởi chạy do thiếu cấu hình. Thoát.")
        sys.exit(1)

    # Ghi đè max_pages nếu có tham số dòng lệnh
    if args.max_pages is not None:
        config.setdefault("topcv", {})["max_pages"] = args.max_pages

    # Chạy scraper
    scraper = TopCVScraper(config, headless=args.headless)
    output_file = scraper.run()

    if output_file:
        print(f"\n📁 Kết quả đã lưu tại: {output_file}")
    else:
        print("\n⚠️  Không thu thập được dữ liệu nào.")
        sys.exit(1)
