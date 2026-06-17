
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
print('Card found:', bool(card))

child1 = card.ele('h3.title span, h3.title a span, h3.title a')
print('Without css: prefix:', bool(child1))

child2 = card.ele('css:h3.title span, h3.title a span, h3.title a')
print('With css: prefix:', bool(child2))

child3 = card.ele('h3.title span')
print('Single selector:', bool(child3))

page.quit()

