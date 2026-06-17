import sys
sys.stdout.reconfigure(encoding='utf-8')
from bs4 import BeautifulSoup
html = open('scratch/topcv_full.html', encoding='utf-8').read()
soup = BeautifulSoup(html, 'html.parser')
card = soup.select_one('.job-item-search-result, .job-item-default')
if card:
    for e in card.find_all(['div', 'span', 'a', 'label']):
        if e.text.strip():
            print(f"{e.name}.{e.get('class', [])}: {e.text.strip()}")
else:
    print('No card found in TopCV HTML')
