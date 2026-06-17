
from DrissionPage import ChromiumPage, ChromiumOptions
import time

co = ChromiumOptions()
co.headless(False)
page = ChromiumPage(co)
page.get('https://www.topcv.vn/tim-viec-lam-it-phan-mem-c10026')
time.sleep(10)
with open('scratch/topcv_local.html', 'w', encoding='utf-8') as f:
    f.write(page.html)
page.quit()

