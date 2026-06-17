
from DrissionPage import ChromiumPage, ChromiumOptions
import time

def dump_topcv():
    co = ChromiumOptions()
    co.headless(True)
    page = ChromiumPage(co)
    page.get('https://www.topcv.vn/tim-viec-lam-it-phan-mem-c10026')
    time.sleep(3)
    card = page.ele('css:.job-item-search-result, .job-item-default')
    if card:
        with open('scratch/topcv_card.html', 'w', encoding='utf-8') as f:
            f.write(card.html)
        print('Saved TopCV card')
    page.quit()

def dump_vnw():
    co = ChromiumOptions()
    co.headless(True)
    page = ChromiumPage(co)
    page.get('https://www.vietnamworks.com/viec-lam?q=it-software')
    time.sleep(3)
    card = page.ele('css:.job-item, .view_job_item, div[class*=JobCard]')
    if card:
        with open('scratch/vnw_card.html', 'w', encoding='utf-8') as f:
            f.write(card.html)
        print('Saved VNW card')
    page.quit()

dump_topcv()
dump_vnw()

