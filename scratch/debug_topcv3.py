import sys
sys.stdout.reconfigure(encoding='utf-8')
from DrissionPage import ChromiumPage, ChromiumOptions
import time
import os

co = ChromiumOptions()
# NOT headless, use real Chrome profile
chrome_path = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
if os.path.exists(chrome_path):
    co.set_browser_path(chrome_path)
    debug_dir = os.path.join(os.getcwd(), 'chrome_debug_profile')
    co.set_user_data_path(debug_dir)
co.set_argument("--disable-blink-features=AutomationControlled")
co.set_pref('profile.default_content_setting_values.geolocation', 2)
co.set_pref('profile.default_content_setting_values.notifications', 2)

page = ChromiumPage(co)
page.get('https://www.topcv.vn/tim-viec-lam-it-phan-mem-c10026')
time.sleep(8)

cards = page.eles('css:.job-item-search-result', timeout=5)
if not cards:
    cards = page.eles('css:.job-item-default', timeout=5)
    
print(f'Found {len(cards)} cards')
if cards:
    card = cards[0]
    # Print first card HTML to see what skills look like
    with open('scratch/topcv_card.html', 'w', encoding='utf-8') as f:
        f.write(card.html)
    print('Saved card HTML to scratch/topcv_card.html')
    
    # Try various skill selectors
    for sel in ['.job-info-skill-label', '.tag-list a.tag', '.tag', 'span[class*="skill"]', 'span[class*="tag"]', '[class*="label"]', '.label']:
        try:
            els = card.eles(f'css:{sel}', timeout=0)
            if els:
                print(f'  {sel}: {len(els)} items → {[e.text[:30] for e in els[:3]]}')
        except Exception as e:
            print(f'  {sel}: error {e}')

page.quit()
