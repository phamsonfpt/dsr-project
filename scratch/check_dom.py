
from bs4 import BeautifulSoup

def analyze(filepath):
    print(f'=== Analyzing {filepath} ===')
    with open(filepath, 'r', encoding='utf-8') as f:
        html = f.read()
    soup = BeautifulSoup(html, 'html.parser')
    
    # Check TopCV
    jobs = soup.select('.job-item-search-result, .job-item-default, .job-item, [class*=\'job\']')
    print(f'Found {len(jobs)} potential job items.')
    if jobs:
        for job in jobs[:2]:
            print('Class:', job.get('class'))
            
analyze('scratch/topcv.html')
analyze('scratch/vnw.html')

