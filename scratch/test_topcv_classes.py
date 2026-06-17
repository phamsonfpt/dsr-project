
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
    debug_dir = os.path.join(os.getcwd(), 'chrome_debug_profile')
    co.set_user_data_path(debug_dir)
    
    page = ChromiumPage(co)
    page.get('https://www.topcv.vn/tim-viec-lam-it-phan-mem-c10026')
    time.sleep(5)
    
    # Try finding job titles
    print('Looking for h3.title...')
    titles = page.eles('tag:h3')
    for t in titles[:5]:
        print('H3 text:', t.text)
        print('H3 class:', t.attr('class'))
        parent = t.parent(3)
        if parent:
            print('Parent(3) class:', parent.attr('class'))
            
    page.quit()

test_cf()

