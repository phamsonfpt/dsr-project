
import sys
sys.stdout.reconfigure(encoding='utf-8')
from DrissionPage import ChromiumPage, ChromiumOptions
import time

co = ChromiumOptions()
co.headless(True)
page = ChromiumPage(co)
page.get('file:///D:/dsr-project/scratch/vnw_full.html')
time.sleep(2)
cards = page.eles('css:div[data-job-card-version]')
if cards:
    card = cards[0]
    els = card.eles('css:label[name=\'label\']')
    for c in els:
        print('html:', c.html)
        print('text:', repr(c.text))
page.quit()

