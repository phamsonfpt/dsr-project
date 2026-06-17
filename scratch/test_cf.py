
from DrissionPage import ChromiumPage, ChromiumOptions
import time

def test_cf():
    co = ChromiumOptions()
    # Try using default system browser profile
    # co.use_system_user_path()
    page = ChromiumPage(co)
    page.get('https://www.topcv.vn/tim-viec-lam-it-phan-mem-c10026')
    time.sleep(5)
    print('Title:', page.title)
    page.quit()

test_cf()

