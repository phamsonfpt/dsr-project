
import sys
sys.stdout.reconfigure(encoding='utf-8')
from DrissionPage import ChromiumPage, ChromiumOptions
import time
import os

def test_vnw():
    co = ChromiumOptions()
    chrome_path = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
    if os.path.exists(chrome_path):
        co.set_browser_path(chrome_path)
    debug_dir = os.path.join(os.getcwd(), 'chrome_debug_profile')
    co.set_user_data_path(debug_dir)
    
    # Block prompts
    co.set_pref('profile.default_content_setting_values.geolocation', 2)
    co.set_pref('profile.default_content_setting_values.notifications', 2)
    
    page = ChromiumPage(co)
    page.get('https://www.vietnamworks.com/tim-viec-lam?q=IT')
    time.sleep(5)
    print('Title:', page.title)
    
    # Check if job cards exist
    cards = page.eles('.view_job_item')
    print('Found view_job_item cards:', len(cards))
    if not cards:
        cards2 = page.eles('.job-item')
        print('Found .job-item cards:', len(cards2))
        
    page.quit()

test_vnw()

