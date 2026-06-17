
from DrissionPage import ChromiumPage, ChromiumOptions
import time

def check(url):
    co = ChromiumOptions()
    co.headless()
    page = ChromiumPage(co)
    page.get(url)
    time.sleep(2)
    print(url, '-> Title:', page.title)
    page.quit()

check('https://www.topcv.vn/tim-viec-lam-it-phan-mem-c10026')
check('https://www.vietnamworks.com/tim-viec-lam?q=IT')
check('https://www.vietnamworks.com/it-software-jobs-i35-vi')

