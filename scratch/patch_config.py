
import json
with open('python_scraper/config.json', 'r', encoding='utf-8') as f:
    config = json.load(f)

# Update TopCV
config['topcv']['selectors']['job_card'] = '.body-content'

# Update VNW
config['vietnamworks']['base_url'] = 'https://www.vietnamworks.com/it-phan-mem-cv18'

with open('python_scraper/config.json', 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=4, ensure_ascii=False)

