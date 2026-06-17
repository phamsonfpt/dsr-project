import sys
sys.stdout.reconfigure(encoding='utf-8')
from bs4 import BeautifulSoup
html = open('scratch/vnw_full.html', encoding='utf-8').read()
soup = BeautifulSoup(html, 'html.parser')
card = soup.select_one('div[data-job-card-version]')
for e in card.find_all(['div', 'span', 'a', 'label']):
    if e.text.strip():
        print(f"{e.name}.{e.get('class', [])}: {e.text.strip()}")
