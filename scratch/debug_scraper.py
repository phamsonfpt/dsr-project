
from DrissionPage import ChromiumPage, ChromiumOptions
import time

co = ChromiumOptions()
co.set_argument('--disable-blink-features=AutomationControlled')
co.set_argument('--no-first-run')
co.set_argument('--no-default-browser-check')
co.set_user_agent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36')
page = ChromiumPage(co)

print('Visiting TopCV...')
page.get('https://www.topcv.vn/tim-viec-lam-moi-nhat')
time.sleep(5)
with open('scratch/topcv_debug.html', 'w', encoding='utf-8') as f:
    f.write(page.html)
print('Saved topcv_debug.html')
page.quit()

