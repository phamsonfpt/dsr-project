
from bs4 import BeautifulSoup
import re
with open('scratch/topcv_debug.html', 'r', encoding='utf-8') as f:
    html = f.read()
soup = BeautifulSoup(html, 'html.parser')
links = soup.select('a[href*=\'/viec-lam/\']')
print('Found', len(links), 'job links.')
job_divs = set()
for a in links:
    parent = a.find_parent('div', class_=re.compile('job|item', re.I))
    if parent:
        classes = ' '.join(parent.get('class', []))
        if 'job' in classes.lower() or 'item' in classes.lower():
            job_divs.add(classes)

print('Possible job card classes:')
for c in job_divs:
    print(' -', c)

