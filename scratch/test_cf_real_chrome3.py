
import sys
sys.stdout.reconfigure(encoding='utf-8')
from DrissionPage import ChromiumPage, ChromiumOptions
import time
import os

def test_cf():
    co = ChromiumOptions()
    chrome_path = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
    if os.path.exists(chrome_path):
        co.set_browser_path(chrome_path)
    co.set_user_data_path(r'C:\chrome_debug')
    
    page = ChromiumPage(co)
    page.get('https://www.topcv.vn/tim-viec-lam-it-phan-mem-c10026')
    time.sleep(5)
    print('Title:', page.title)
    if 'Cloudflare' not in page.title:
        print('SUCCESS!')
    page.quit()

test_cf()

