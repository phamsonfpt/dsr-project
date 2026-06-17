
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
    print('Title:', page.title)
    
    cards = page.eles('.job-item-search-result')
    print('Found .job-item-search-result:', len(cards))
    if not cards:
        cards2 = page.eles('.job-item-default')
        print('Found .job-item-default:', len(cards2))
        cards3 = page.eles('.job-item')
        print('Found .job-item:', len(cards3))
        # Print out some classes of divs
        divs = page.eles('tag:div')
        print('Total divs:', len(divs))
        
    page.quit()

test_cf()

