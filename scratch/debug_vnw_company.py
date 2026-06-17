import sys
sys.stdout.reconfigure(encoding='utf-8')
from DrissionPage import ChromiumPage, ChromiumOptions
import time
import os

co = ChromiumOptions()
chrome_path = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
if os.path.exists(chrome_path):
    co.set_browser_path(chrome_path)
    debug_dir = os.path.join(os.getcwd(), 'chrome_debug_profile')
    co.set_user_data_path(debug_dir)
co.set_argument("--disable-blink-features=AutomationControlled")
co.set_pref('profile.default_content_setting_values.geolocation', 2)
co.set_pref('profile.default_content_setting_values.notifications', 2)

page = ChromiumPage(co)
page.get('https://www.vietnamworks.com/viec-lam?q=it-software')
time.sleep(10)

cards = page.eles('css:div[data-job-card-version]', timeout=10)
print(f'Found {len(cards)} cards')
if cards:
    card = cards[0]
    # Save full HTML
    with open('scratch/vnw_card_full.html', 'w', encoding='utf-8') as f:
        f.write(card.html)
    print('Saved card HTML to scratch/vnw_card_full.html')
    
    # Find company
    for sel in ['css:img[alt]', 'css:div[class*="company"]', 'css:span[class*="company"]',
                'css:p[class*="company"]', 'css:a[class*="company"]',
                'css:div[class*="employer"]', 'css:span[data-tooltip]']:
        els = card.eles(sel, timeout=0)
        if els:
            print(f'  {sel}: {[e.text[:30] or e.attr("alt") for e in els[:2]]}')

page.quit()
