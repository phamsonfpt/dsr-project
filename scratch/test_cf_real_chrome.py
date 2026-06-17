
from DrissionPage import ChromiumPage, ChromiumOptions
import time
import os

def test_cf():
    co = ChromiumOptions()
    chrome_path = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
    if os.path.exists(chrome_path):
        co.set_browser_path(chrome_path)
    
    # We remove AutomationControlled flag to see if that helps with real chrome
    # co.set_argument('--disable-blink-features=AutomationControlled')
    page = ChromiumPage(co)
    page.get('https://www.topcv.vn/tim-viec-lam-it-phan-mem-c10026')
    time.sleep(5)
    print('Title:', page.title)
    page.quit()

test_cf()

