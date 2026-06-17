
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
    
    card = page.ele('.body-content')
    if card:
        with open('scratch/card_topcv.html', 'w', encoding='utf-8') as f:
            f.write(card.html)
        print('Dumped TopCV card to scratch/card_topcv.html')
        
    page.get('https://www.vietnamworks.com/it-phan-mem-cv18')
    time.sleep(5)
    
    card = page.ele('.job-item')
    if card:
        with open('scratch/card_vnw.html', 'w', encoding='utf-8') as f:
            f.write(card.html)
        print('Dumped VNW card to scratch/card_vnw.html')
            
    page.quit()

test_cf()

