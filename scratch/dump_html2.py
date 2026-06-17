
from DrissionPage import ChromiumPage, ChromiumOptions
import time

co = ChromiumOptions()
co.headless(True)
page = ChromiumPage(co)

# VietnamWorks
page.get('https://www.vietnamworks.com/viec-lam?q=it-software')
time.sleep(5)
with open('scratch/vnw_full.html', 'w', encoding='utf-8') as f:
    f.write(page.html)

# TopCV
page.get('https://www.topcv.vn/tim-viec-lam-it-phan-mem-c10026')
time.sleep(5)
with open('scratch/topcv_full.html', 'w', encoding='utf-8') as f:
    f.write(page.html)

page.quit()

