# -*- coding: utf-8 -*-
from bs4 import BeautifulSoup
import re
import sys
sys.stdout.reconfigure(encoding='utf-8')

with open('scratch/topcv_debug.html', 'r', encoding='utf-8') as f:
    soup = BeautifulSoup(f.read(), 'html.parser')

cards = soup.select('.job-item-search-result')
if cards:
    card = cards[0]
    date_els = card.find_all(string=re.compile('trước|hôm nay|vừa xong', re.I))
    for text in date_els:
        parent = text.parent
        print(f'Text: {text.strip()}')
        print(f'Tag: {parent.name}')
        print(f'Classes: {parent.get("class")}')
