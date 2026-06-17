
import sys
sys.stdout.reconfigure(encoding='utf-8')
from DrissionPage import ChromiumPage, ChromiumOptions
import os

co = ChromiumOptions()
chrome_path = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
if os.path.exists(chrome_path):
    co.set_browser_path(chrome_path)
debug_dir = os.path.join(os.getcwd(), 'chrome_debug_profile')
co.set_user_data_path(debug_dir)

page = ChromiumPage(co)
page.get('https://www.vietnamworks.com/viec-lam?q=it-software')
import time
time.sleep(5)

cards = page.eles('css:.job-item, .view_job_item, div[class*=''JobCard'']', timeout=3)
if not cards:
    print('Trying fallback')
    cards = page.eles('css:[data-job-id], .search-result-item, [class*=''listing'']', timeout=3)
    
print('Found cards:', len(cards))
if cards:
    card = cards[0]
    print('Card classes:', card.attr('class'))

page.quit()

