
import json

with open('python_scraper/config.json', 'r', encoding='utf-8') as f:
    config = json.load(f)

config['vietnamworks']['base_url'] = 'https://www.vietnamworks.com/viec-lam?q=it-software'

with open('python_scraper/config.json', 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=4, ensure_ascii=False)

