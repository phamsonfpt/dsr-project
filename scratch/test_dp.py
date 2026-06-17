
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
    print('Card found!')
    # Try different selectors
    print('1:', card.eles('label[name=\'label\']'))
    print('2:', card.eles('css:label[name=\'label\']'))
    print('3:', card.eles('css:label'))
    print('4:', card.eles('.sc-bXWnss'))
page.quit()

