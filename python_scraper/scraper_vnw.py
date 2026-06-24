"""
scraper_vnw.py - Thu thập dữ liệu việc làm từ VietnamWorks.com
===============================================================

Sử dụng DrissionPage (ChromiumPage) với chế độ stealth để vượt qua
cơ chế chống bot. VietnamWorks sử dụng React/SPA nên cần chờ JavaScript
render xong trước khi trích xuất dữ liệu.

VietnamWorks thường xuyên thay đổi class names → script sử dụng chiến lược
selector kết hợp: attribute-contains [class*='...'] + fallback selectors.

Cách chạy:
    python scraper_vnw.py
    python scraper_vnw.py --max-pages 10
    python scraper_vnw.py --headless
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

log_file_path = os.path.join(os.path.dirname(__file__), "scraper_vnw.log")
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
    Cuộn trang ngẫu nhiên — rất quan trọng cho VietnamWorks vì trang
    sử dụng lazy-loading. Cần cuộn để kích hoạt tải dữ liệu.
    """
    scroll_count = random.randint(3, 6)
    for _ in range(scroll_count):
        scroll_px = random.randint(250, 700)
        page.scroll.down(scroll_px)
        time.sleep(random.uniform(0.4, 1.2))

    # Cuộn xuống cuối trang để đảm bảo tải hết nội dung
    page.scroll.to_bottom()
    time.sleep(random.uniform(0.8, 1.5))

    # Cuộn lại lên đầu
    page.scroll.to_top()
    time.sleep(random.uniform(0.3, 0.8))


def safe_text(element, selector: str, attr: Optional[str] = None) -> str:
    """
    Trích xuất text/attribute từ element con một cách an toàn.

    VietnamWorks dùng CSS selector phức tạp nên hàm này hỗ trợ
    selector chứa dấu phẩy (multiple selectors) — thử từng cái.
    """
    # Tách multiple selectors (phân cách bởi dấu phẩy)
    selectors = [s.strip() for s in selector.split(",") if s.strip()]

    for sel in selectors:
        try:
            child = element.ele(sel, timeout=0)
            if child is None:
                continue
            if attr:
                result = (child.attr(attr) or "").strip()
            else:
                result = (child.text or "").strip()
            if result:
                return result
        except Exception:
            continue
    return ""


def safe_texts(element, selector: str) -> str:
    """
    Lấy text từ nhiều element con, nối bằng dấu phẩy.
    Hỗ trợ multiple selectors cho VietnamWorks.
    VNW dùng label[name='label'] với title attribute chứa skill thật.
    Các "+N" là placeholder bị cắt ngắn, cần lấy từ title của chúng.
    """
    selectors = [s.strip() for s in selector.split(",") if s.strip()]

    for sel in selectors:
        try:
            children = element.eles(sel, timeout=0)
            if children:
                texts = []
                for c in children:
                    txt = c.text.strip() if c.text else ""
                    # "+N" là placeholder, skip
                    if txt.startswith("+") and txt[1:].isdigit():
                        continue
                    # Lấy từ title attribute nếu text rỗng hoặc bị cắt
                    if not txt:
                        title_attr = c.attr("title") or ""
                        if title_attr:
                            txt = title_attr.strip()
                    if txt:
                        texts.append(txt)
                if texts:
                    return ", ".join(texts)
        except Exception:
            continue
    return ""


# ═══════════════════════════ LỚP SCRAPER CHÍNH ══════════════════════════

class VietnamWorksScraper:
    """
    Bộ thu thập dữ liệu việc làm từ VietnamWorks.com.

    VietnamWorks là trang SPA (Single Page Application) sử dụng React,
    do đó cần phải:
    - Chờ JavaScript render hoàn tất
    - Cuộn trang để kích hoạt lazy-loading
    - Sử dụng selector linh hoạt vì class names thay đổi thường xuyên

    Attributes:
        config (dict): Cấu hình từ config.json
        selectors (dict): CSS selectors chính (dùng attribute-contains)
        fallback (dict): CSS selectors dự phòng
        jobs (list[dict]): Danh sách việc làm đã thu thập
    """

    def __init__(self, config: dict, headless: bool = False):
        """
        Khởi tạo scraper với cấu hình VietnamWorks.

        Args:
            config: Dict cấu hình đầy đủ (lấy key 'vietnamworks').
            headless: Chạy trình duyệt ẩn nếu True.
        """
        vnw_cfg = config.get("vietnamworks", {})
        self.base_url = vnw_cfg.get(
            "base_url",
            "https://www.vietnamworks.com/tim-viec-lam/tat-ca-viec-lam",
        )
        self.max_pages = vnw_cfg.get("max_pages", 5)
        self.delay_range = vnw_cfg.get("delay_range", [2.0, 5.0])
        self.selectors = vnw_cfg.get("selectors", {})
        self.fallback = vnw_cfg.get("fallback_selectors", {})
        self.output_dir = config.get("output_dir", "../data/raw")
        self.proxy = config.get("proxy", "")
        self.headless = headless
        self.detail_selectors = vnw_cfg.get("detail_selectors", {})

        
        user_settings = config.get('user_settings', {})
        date_filter = config.get('vietnamworks', {}).get('date_filter', user_settings.get('date_filter', {}))
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
        Tạo ChromiumPage stealth cho VietnamWorks.

        VietnamWorks có cơ chế phát hiện bot mạnh hơn TopCV,
        nên cần thêm một số thiết lập bảo mật:
        - Giả lập kích thước cửa sổ thực tế
        - Tắt WebDriver detection
        - Thiết lập ngôn ngữ tiếng Việt
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

        # Stealth settings — vượt qua phát hiện bot
        co.set_argument("--disable-blink-features=AutomationControlled")
        co.set_argument("--no-first-run")
        co.set_argument("--no-default-browser-check")
        co.set_argument("--disable-infobars")
        co.set_argument("--disable-popup-blocking")
        co.set_argument("--lang=vi-VN")
        co.set_argument("--window-size=1920,1080")

        # User-Agent giống Chrome thật trên Windows
        co.set_user_agent(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/131.0.0.0 Safari/537.36"
        )

        if self.proxy:
            co.set_proxy(self.proxy)
            logger.info("🌐 Proxy: %s", self.proxy)

        page = ChromiumPage(co)
        logger.info("🚀 Trình duyệt đã khởi tạo (headless=%s)", self.headless)
        return page

    # ─────────────── TÌM JOB CARDS LINH HOẠT ────────────────────────
    def _find_job_cards(self):
        """
        Tìm tất cả job cards trên trang VietnamWorks.

        Do VietnamWorks thường xuyên thay đổi cấu trúc HTML,
        hàm này thử nhiều chiến lược:
        1. Selector chính từ config
        2. Selector dự phòng từ config
        3. Tìm tự động bằng các pattern phổ biến
        """
        # Chiến lược 1: Selector chính (hỗ trợ multiple selectors)
        primary = self.selectors.get("job_card", "")
        for sel in [s.strip() for s in primary.split(",") if s.strip()]:
            try:
                cards = self.page.eles(sel, timeout=5)
                if cards and len(cards) >= 2:
                    logger.info(
                        "Tìm thấy %d job cards với selector '%s'",
                        len(cards), sel,
                    )
                    return cards
            except Exception:
                continue

        # Chiến lược 2: Selector dự phòng
        fallback = self.fallback.get("job_card", "")
        for sel in [s.strip() for s in fallback.split(",") if s.strip()]:
            try:
                cards = self.page.eles(sel, timeout=5)
                if cards and len(cards) >= 2:
                    logger.info(
                        "⚠️  Dùng selector dự phòng '%s' — %d cards",
                        sel, len(cards),
                    )
                    return cards
            except Exception:
                continue

        # Chiến lược 3: Quét tự động — tìm các thẻ chứa link đến trang chi tiết
        auto_selectors = [
            "div[class*='job']",
            "div[class*='Job']",
            "article",
            "li[class*='job']",
            "div[data-job-id]",
        ]
        for sel in auto_selectors:
            try:
                cards = self.page.eles(sel, timeout=3)
                if cards and len(cards) >= 3:
                    logger.info(
                        "🔍 Tự động phát hiện %d cards với '%s'",
                        len(cards), sel,
                    )
                    return cards
            except Exception:
                continue

        logger.warning("❌ Không tìm thấy job card nào trên trang")
        return []

    # ─────────────── TRÍCH XUẤT DỮ LIỆU ────────────────────────────
    def _extract_job(self, card) -> dict:
        """
        Trích xuất thông tin từ một job card của VietnamWorks.

        VietnamWorks có cấu trúc phức tạp hơn TopCV nên cần
        xử lý nhiều trường hợp đặc biệt:
        - URL có thể là relative hoặc absolute
        - Salary có thể hiển thị "Thương lượng" hoặc khoảng lương
        - Skills thường nằm trong tags hoặc badges
        """
        def _get(key: str, attr: Optional[str] = None) -> str:
            """Thử selector chính → fallback cho một trường."""
            val = safe_text(card, self.selectors.get(key, ""), attr)
            if not val and self.fallback.get(key):
                val = safe_text(card, self.fallback[key], attr)
            return val

        def _get_multi(key: str) -> str:
            """Lấy nhiều phần tử (skills/tags)."""
            val = safe_texts(card, self.selectors.get(key, ""))
            if not val and self.fallback.get(key):
                val = safe_texts(card, self.fallback[key])
            return val

        # Lấy URL — VietnamWorks dùng cả relative và absolute URL
        url = _get("url", attr="href")
        if url:
            if url.startswith("/"):
                url = "https://www.vietnamworks.com" + url
            elif not url.startswith("http"):
                url = "https://www.vietnamworks.com/" + url

        job_date = None
        return {
            "title": _get("title", attr="title") or _get("title"),
            "company": _get("company"),
            "salary": _get("salary"),
            "location": _get("location"),
            "url": url,
            "job_date": job_date,
            "source": "vnw",
            "scraped_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "job_description": "",
            "requirements": "",
            "benefits": "",
            "level": ""
        }

    def _extract_job_details(self, url: str) -> dict:
        """
        Mở tab mới, cào chi tiết Job Description, Requirements, Benefits
        và Experience từ trang chi tiết VietnamWorks.

        Strategy ưu tiên:
          1. Tìm heading h2/h3 theo text của từng section, lấy sibling content
          2. Container fallback + regex
        """
        result = {"job_description": "", "requirements": "", "benefits": "", "experience": "", "level": ""}
        if not url:
            return result

        exp_selector = self.detail_selectors.get("experience", "css:.summary-item")

        tab = None
        try:
            tab = self.page.new_tab(url)
            # Chờ trang load xong nội dung (đợi thẻ h2 xuất hiện)
            try:
                tab.wait.eles_loaded('tag:h2', timeout=5)
            except Exception:
                time.sleep(2)
            time.sleep(random.uniform(1.0, 2.0)) # Thêm một chút delay tự nhiên

            # ── Helper: Tìm nội dung section theo heading text ──
            def _find_section(heading_keywords):
                """Tìm heading h2/h3 chứa keyword, trả về text nội dung kế tiếp."""
                for kw in heading_keywords:
                    for tag in ['h2', 'h3']:
                        try:
                            # Dùng xpath tìm tag chứa text (tương đối mạnh mẽ và chính xác)
                            heading = tab.ele(f"xpath://{tag}[contains(., '{kw}')]", timeout=1)
                            if not heading:
                                continue
                            heading_text = (heading.text or "").strip()

                            # ── Helper: Cắt bỏ AI matching junk ──
                            def _clean_content(c):
                                import re
                                if not c: return ""
                                c = re.sub(r'(?i)mức độ phù hợp.*?(?:như thế nào\??|NULL)', '', c, flags=re.DOTALL).strip()
                                return c if len(c) > 10 else ""

                            # Cách 1: Lấy sibling element kế tiếp
                            nxt = heading.next()
                            if nxt:
                                c1 = _clean_content(nxt.text)
                                if c1: return c1

                            # Cách 2: Heading nằm trong wrapper div → lấy sibling của parent
                            parent = heading.parent()
                            if parent:
                                parent_nxt = parent.next()
                                if parent_nxt:
                                    c2 = _clean_content(parent_nxt.text)
                                    if c2: return c2

                            # Cách 3: Lấy text của parent trừ heading
                            if parent:
                                parent_text = (parent.text or "").strip()
                                content = parent_text.replace(heading_text, "", 1).strip()
                                if content and len(content) > 10:
                                    return content
                        except Exception:
                            continue
                return ""

            # 1. Job Description
            result["job_description"] = _find_section([
                'Mô tả công việc', 'Job Description', 'Mô tả'
            ])

            # 2. Requirements
            result["requirements"] = _find_section([
                'Yêu cầu công việc', 'Yêu cầu ứng viên',
                'Job Requirements', 'Requirements', 'Yêu cầu'
            ])

            # 3. Benefits
            result["benefits"] = _find_section([
                'Các phúc lợi dành cho bạn', 'Phúc lợi', 'Quyền lợi', 'Những lợi ích', 'Lợi ích',
                'Benefits', 'Tại sao bạn sẽ yêu thích', 'Why You Will Love'
            ])

            # ── Fallback: container + regex nếu chưa có job_description ──
            if not result["job_description"] or not result["requirements"] or not result["benefits"]:
                for sel in ['css:.job-detail__body', 'css:.description', 'css:.job-detail-content', 'css:.job-description', 'css:.brand-job-detail', 'css:.premium-job']:
                    container = tab.ele(sel, timeout=1)
                    if container and container.text and len(container.text.strip()) > 50:
                        full_text = container.text.strip()
                        # Loại bỏ rác UI (AI matching)
                        full_text = re.sub(
                            r'(?i)mức độ phù hợp.*?(?:như thế nào\??|NULL)', '', full_text, flags=re.DOTALL
                        ).strip()

                        jd_m = re.search(
                            r'(?:mô tả công việc|job description)\s*(.*?)(?=yêu cầu|requirement|$)',
                            full_text, re.DOTALL | re.IGNORECASE
                        )
                        req_m = re.search(
                            r'(?:yêu cầu công việc|yêu cầu ứng viên|requirement)\s*(.*?)(?=phúc lợi|quyền lợi|lợi ích|benefit|$)',
                            full_text, re.DOTALL | re.IGNORECASE
                        )
                        ben_m = re.search(
                            r'(?:phúc lợi|quyền lợi|lợi ích|benefit)\s*(.*?)(?=địa điểm|thông tin|cách thức|$)',
                            full_text, re.DOTALL | re.IGNORECASE
                        )

                        if not result["job_description"] and jd_m: result["job_description"] = jd_m.group(1).strip()
                        if not result["requirements"] and req_m: result["requirements"] = req_m.group(1).strip()
                        if not result["benefits"] and ben_m: result["benefits"] = ben_m.group(1).strip()
                        ben_m = re.search(
                            r'(?:phúc lợi|quyền lợi|lợi ích|benefit)\s*(.*)',
                            full_text, re.DOTALL | re.IGNORECASE
                        )

                        if jd_m:
                            result["job_description"] = jd_m.group(1).strip()
                        if req_m and not result["requirements"]:
                            result["requirements"] = req_m.group(1).strip()
                        if ben_m and not result["benefits"]:
                            result["benefits"] = ben_m.group(1).strip()
                        break

            # ── Lấy Experience và Level ──
            exp_ele = tab.ele(exp_selector, timeout=1)
            if exp_ele:
                parent = exp_ele.parent() if ("Năm Kinh Nghiệm" in (exp_ele.text or "") or "Cấp bậc" in (exp_ele.text or "")) else exp_ele
                lines = (parent.text or "").split('\n')
                for i, line in enumerate(lines):
                    if "Kinh nghiệm" in line or "Năm Kinh Nghiệm" in line:
                        if i + 1 < len(lines):
                            result["experience"] = lines[i + 1].strip()
                        else:
                            result["experience"] = line.strip()
                    if "Cấp Bậc" in line or "Cấp bậc" in line or "Level" in line:
                        if i + 1 < len(lines):
                            result["level"] = lines[i + 1].strip()
                        else:
                            result["level"] = line.strip()

        except Exception as e:
            logger.debug("  ⚠️ Lỗi lấy detail: %s", e)
        finally:
            if tab:
                tab.close()

        return result

    # ─────────────── ĐÓNG POPUP/BANNER ──────────────────────────────
    def _dismiss_popups(self) -> None:
        """
        Đóng các popup quảng cáo, banner cookie, hoặc modal đăng nhập
        thường xuất hiện trên VietnamWorks khi truy cập lần đầu.
        """
        popup_selectors = [
            "button[class*='close']",
            "[class*='modal'] button[class*='close']",
            "[class*='popup'] [class*='close']",
            "[class*='cookie'] button",
            "[class*='Cookie'] button",
            "button[aria-label='Close']",
            "button[aria-label='close']",
            ".btn-close",
        ]
        for sel in popup_selectors:
            try:
                btn = self.page.ele(sel, timeout=0)
                if btn:
                    btn.click()
                    logger.debug("🗙 Đã đóng popup: %s", sel)
                    time.sleep(0.5)
            except Exception:
                continue

    # ─────────────── THU THẬP MỘT TRANG ────────────────────────────
    def _scrape_page(self, page_num: int) -> int:
        """
        Thu thập tất cả việc làm trên trang hiện tại.

        Args:
            page_num: Số thứ tự trang hiện tại.

        Returns:
            Số lượng việc làm mới thu thập từ trang này.
        """
        # Đóng popup nếu có (thường xuất hiện ở trang 1)
        if page_num <= 2:
            self._dismiss_popups()

        # Cuộn trang để kích hoạt lazy-loading (quan trọng với SPA)
        simulate_human_scroll(self.page)
        random_delay([1.0, 2.0])

        # Chờ phần tử đầu tiên xuất hiện (tối đa 10s)
        try:
            self.page.wait.ele_loaded(self.selectors.get("job_card", ".job-item"), timeout=00)
        except Exception:
            pass

        # Tìm job cards
        cards = self._find_job_cards()
        if not cards:
            logger.warning("⚠️  Trang %d: Không tìm thấy job card nào", page_num)
            return 0

        page_jobs = 0
        should_stop = False
        for idx, card in enumerate(cards, 1):
            try:
                job = self._extract_job(card)

                # Chỉ lưu nếu có thông tin hữu ích
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
                        idx, len(cards),
                        job["title"][:50] if job["title"] else "(no title)",
                        job["company"][:30] if job["company"] else "(no company)",
                        len(job["job_description"])
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
        Chuyển sang trang tiếp theo.

        VietnamWorks phân trang bằng nhiều cách:
        1. Nút "Next" hoặc nút số trang
        2. URL parameter ?page=N
        3. Infinite scroll (cần cuộn xuống cuối trang)

        Returns:
            True nếu chuyển trang thành công.
        """
        # Cách 1: Click nút phân trang
        next_sel = self.selectors.get("next_page", "")
        fallback_next = self.fallback.get("next_page", "")

        for selector in [s.strip() for sel_group in [next_sel, fallback_next]
                         for s in sel_group.split(",") if s.strip()]:
            try:
                btn = self.page.ele(selector, timeout=3)
                if btn:
                    # Cuộn đến nút trước khi click (tránh lỗi click ngoài viewport)
                    btn.scroll.to_see()
                    time.sleep(0.5)
                    btn.click()
                    self.page.wait.load_start()
                    random_delay(self.delay_range)
                    logger.info("➡️  Đã chuyển sang trang %d", current_page + 1)
                    return True
            except Exception:
                continue

        # Cách 2: Thay đổi URL thủ công
        # VietnamWorks sử dụng nhiều URL pattern khác nhau
        url_patterns = [
            f"{self.base_url}?page={current_page + 1}",
            f"{self.base_url}&page={current_page + 1}",
        ]
        # Xử lý trường hợp URL đã có query string
        if "?" in self.base_url:
            url_patterns.insert(0, f"{self.base_url}&page={current_page + 1}")
        else:
            url_patterns.insert(0, f"{self.base_url}?page={current_page + 1}")

        for url in url_patterns:
            try:
                self.page.get(url)
                random_delay(self.delay_range)
                # Kiểm tra xem trang mới có job cards không
                test_cards = self._find_job_cards()
                if test_cards:
                    logger.info("➡️  Chuyển trang qua URL: page=%d", current_page + 1)
                    return True
            except Exception:
                continue

        logger.warning("❌ Không thể chuyển sang trang tiếp theo")
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

        # Tạo thư mục output
        script_dir = Path(__file__).parent
        output_path = (script_dir / self.output_dir).resolve()
        output_path.mkdir(parents=True, exist_ok=True)

        filepath = output_path / "vnw_jobs_raw.csv"
        df = pd.DataFrame(self.jobs)

        # Loại bỏ trùng lặp theo URL
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
        Thực thi toàn bộ quy trình thu thập dữ liệu từ VietnamWorks:
        1. Khởi tạo trình duyệt stealth
        2. Truy cập trang tìm kiếm
        3. Đóng popup quảng cáo (nếu có)
        4. Thu thập dữ liệu trên mỗi trang
        5. Phân trang đến max_pages
        6. Lưu kết quả CSV

        Returns:
            Đường dẫn file CSV kết quả.
        """
        logger.info("═" * 60)
        logger.info("🏁 BẮT ĐẦU THU THẬP DỮ LIỆU TỪ VIETNAMWORKS.COM")
        logger.info("   URL: %s", self.base_url)
        logger.info("   Số trang tối đa: %d", self.max_pages)
        logger.info("═" * 60)

        start_time = time.time()

        try:
            # Bước 1: Khởi tạo trình duyệt
            self.page = self._init_browser()

            # Bước 2: Truy cập trang tìm kiếm
            logger.info("🌐 Đang truy cập %s ...", self.base_url)
            self.page.get(self.base_url)

            # Chờ SPA render xong — VietnamWorks cần nhiều thời gian hơn
            self.page.wait.load_start()
            random_delay([3.0, 5.0])  # Chờ lâu hơn cho SPA render

            # Bước 3: Lặp qua từng trang
            for page_num in range(1, self.max_pages + 1):
                logger.info("─" * 40)
                logger.info("📖 Đang xử lý trang %d/%d ...", page_num, self.max_pages)

                jobs_found = self._scrape_page(page_num)

                if jobs_found == 0:
                    logger.info("⛔ Không còn kết quả. Dừng phân trang.")
                    break

                # Chuyển trang
                if page_num < self.max_pages:
                    if not self._go_next_page(page_num):
                        logger.info("⛔ Không thể chuyển trang. Dừng lại.")
                        break

            # Bước 4: Lưu kết quả
            result_path = self._save_results()

        except Exception as e:
            logger.error("💥 Lỗi nghiêm trọng: %s", e, exc_info=True)
            result_path = self._save_results()

        finally:
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
        description="Thu thập dữ liệu việc làm từ VietnamWorks.com"
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
        help="Chạy trình duyệt ở chế độ nền",
    )
    parser.add_argument(
        "--debug", action="store_true",
        help="Bật chế độ gỡ lỗi",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    config = load_config(args.config)
    if not config:
        logger.error("Không thể khởi chạy do thiếu cấu hình. Thoát.")
        sys.exit(1)

    if args.max_pages is not None:
        config.setdefault("vietnamworks", {})["max_pages"] = args.max_pages

    scraper = VietnamWorksScraper(config, headless=args.headless)
    output_file = scraper.run()

    if output_file:
        print(f"\n📁 Kết quả đã lưu tại: {output_file}")
    else:
        print("\n⚠️  Không thu thập được dữ liệu nào.")
        sys.exit(1)
