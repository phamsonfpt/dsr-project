
import sys
import os
sys.stdout.reconfigure(encoding='utf-8')
sys.path.append(os.getcwd())
import logging
logging.basicConfig(level=logging.DEBUG)

from python_scraper.scraper_topcv import TopCVScraper
import json

with open('python_scraper/config.json', 'r', encoding='utf-8') as f:
    config = json.load(f)

scraper = TopCVScraper(config)
scraper.run()

