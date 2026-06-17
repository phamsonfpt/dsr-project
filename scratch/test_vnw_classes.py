
import sys
sys.stdout.reconfigure(encoding='utf-8')
from DrissionPage import ChromiumPage, ChromiumOptions
import time
import os

def test_vnw():
    co = ChromiumOptions()
    chrome_path = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
    if os.path.exists(chrome_path):
        co.set_browser_path(chrome_path)
    debug_dir = os.path.join(os.getcwd(), 'chrome_debug_profile')
    co.set_user_data_path(debug_dir)
    
    page = ChromiumPage(co)
    page.get('https://www.vietnamworks.com/it-phan-mem-cv18')
    time.sleep(5)
    
    print('Title:', page.title)
    
    # Try finding job titles
    print('Looking for job cards...')
    titles = page.eles('tag:h3')
    if titles:
        for t in titles[:3]:
            print('H3 text:', t.text)
            for i in range(1, 4):
                try:
                    parent = t.parent(i)
                    print(f'Parent({i}) class:', parent.attr('class'))
                except:
                    pass
    else:
        titles = page.eles('tag:h2')
        for t in titles[:3]:
            print('H2 text:', t.text)
            for i in range(1, 4):
                try:
                    parent = t.parent(i)
                    print(f'Parent({i}) class:', parent.attr('class'))
                except:
                    pass
            
    page.quit()

test_vnw()

