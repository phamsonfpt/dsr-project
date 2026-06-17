import sys
sys.stdout.reconfigure(encoding='utf-8')
from DrissionPage import ChromiumPage, ChromiumOptions
import time

co = ChromiumOptions()
co.headless(True)
page = ChromiumPage(co)
page.get('https://www.topcv.vn/tim-viec-lam-it-phan-mem-c10026')
time.sleep(6)
cards = page.eles('css:.job-item-search-result')
if not cards:
    cards = page.eles('css:.job-item-default')
if cards:
    card = cards[0]
    print('Card HTML snippet:', card.html[:600])
    els = card.eles('css:.job-info-skill-label')
    print('skill els (job-info-skill-label):', els)
    els2 = card.eles('css:.tag-list a.tag')
    print('skill els (tag-list):', els2)
    els3 = card.eles('css:span[class*="tag"], span[class*="skill"]')
    print('skill span:', els3)
else:
    print('No cards found')
    cards2 = page.eles('css:div[class*="job"]')
    if cards2:
        print('Found fallback cards:', len(cards2))
        print(cards2[0].html[:300])
page.quit()
