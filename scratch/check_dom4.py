
import sys
sys.stdout.reconfigure(encoding='utf-8')
from bs4 import BeautifulSoup

def analyze(filepath):
    print(f'=== {filepath} ===')
    with open(filepath, 'r', encoding='utf-8') as f:
        html = f.read()
    soup = BeautifulSoup(html, 'html.parser')
    
    # TopCV check
    if 'topcv' in filepath:
        h3s = soup.find_all('h3', class_='title')
        print('Found', len(h3s), 'h3.title')
        for h3 in h3s[:2]:
            parent_div = h3.find_parent('div', class_=lambda c: c and 'job' in c)
            if parent_div:
                print('Parent classes:', parent_div.get('class'))
                
    if 'vnw' in filepath:
        cards = soup.find_all('div', class_=lambda c: c and 'view_job_item' in c)
        print('Found', len(cards), 'view_job_item')
        if cards:
            print('Classes:', cards[0].get('class'))

analyze('scratch/topcv.html')
analyze('scratch/vnw.html')

