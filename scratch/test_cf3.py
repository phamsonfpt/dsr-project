
from DrissionPage import ChromiumPage, ChromiumOptions
import time

def test_cf():
    co = ChromiumOptions()
    # DO NOT disable AutomationControlled
    page = ChromiumPage(co)
    page.get('https://www.topcv.vn/tim-viec-lam-it-phan-mem-c10026')
    time.sleep(5)
    print('Title:', page.title)
    page.quit()

test_cf()

