with open('python_scraper/scraper_topcv.py', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('job = self._extract_job(card)', '''
                if i == 0:
                    with open("scratch/topcv_card.html", "w", encoding="utf-8") as h:
                        h.write(card.html)
                job = self._extract_job(card)
''')

with open('python_scraper/scraper_topcv.py', 'w', encoding='utf-8') as f:
    f.write(content)
