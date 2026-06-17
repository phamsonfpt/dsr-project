
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
page.get('https://www.topcv.vn/tim-viec-lam-it-phan-mem-c10026')
import time
time.sleep(3)

card = page.ele('.body-content')
print('Card text:', repr(card.text[:50]))

child = card.ele('css:a.company, .company-name', timeout=0)
print('Company using css:', bool(child), repr(child.text) if child else '')

child3 = card.ele('css:label.title-salary, .salary', timeout=0)
print('Salary using css:', bool(child3), repr(child3.text) if child3 else '')

page.quit()

