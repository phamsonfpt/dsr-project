
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

body_content = page.ele('.body-content')
p1 = body_content.parent()
p2 = p1.parent()
p3 = p2.parent()
print('Parent 3 classes:', repr(p3.attr('class')))
print('Parent 3 tag:', p3.tag)
print('Parent 3 innerHTML len:', len(p3.inner_html))

page.quit()

