
import sys
sys.stdout.reconfigure(encoding='utf-8')
from bs4 import BeautifulSoup

def analyze(filepath):
    print(f'=== {filepath} ===')
    with open(filepath, 'r', encoding='utf-8') as f:
        html = f.read()
    soup = BeautifulSoup(html, 'html.parser')
    
    # Try to find common job card patterns
    for div in soup.find_all('div'):
        classes = div.get('class', [])
        class_str = ' '.join(classes)
        
        # Check if it contains a title link
        h3 = div.find('h3')
        a_tag = div.find('a')
        
        if h3 and a_tag and ('job' in class_str.lower() or 'item' in class_str.lower()):
            print('Found potential card:', class_str)
            print('Title class:', h3.get('class'))
            break

analyze('scratch/topcv.html')
analyze('scratch/vnw.html')

