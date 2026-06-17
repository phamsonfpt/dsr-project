import sys
sys.stdout.reconfigure(encoding='utf-8')
from DrissionPage import ChromiumPage, ChromiumOptions
import time
import os

co = ChromiumOptions()
co.headless(True)
chrome_path = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
if os.path.exists(chrome_path):
    co.set_browser_path(chrome_path)
    debug_dir = os.path.join(os.getcwd(), 'chrome_debug_profile2')
    co.set_user_data_path(debug_dir)
co.set_argument("--disable-blink-features=AutomationControlled")

page = ChromiumPage(co)
page.get('https://www.topcv.vn/tim-viec-lam-it-phan-mem-c10026')
time.sleep(8)
print('URL:', page.url)

# Try all possible card selectors
selectors = [
    '.job-item-search-result',
    '.job-item-default',
    '.job-item',
    'div[class*="job-item"]',
    'div[data-job-id]',
    'article',
    'div[class*="job"]',
]
for sel in selectors:
    try:
        els = page.eles(f'css:{sel}', timeout=2)
        if els:
            print(f'Found {len(els)} cards with: {sel}')
            # Look inside the first card for skill-related elements
            card = els[0]
            print('Card HTML snippet:', card.html[:400])
            break
    except:
        pass
page.quit()
