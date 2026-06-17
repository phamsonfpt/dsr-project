
import json

with open('python_scraper/config.json', 'r', encoding='utf-8') as f:
    config = json.load(f)

# Ensure CSS prefix for job_card
config['topcv']['selectors']['job_card'] = 'css:.job-item-search-result, .job-item-default'
config['vietnamworks']['selectors']['job_card'] = 'css:.job-item, .view_job_item, div[class*=''JobCard'']'

with open('python_scraper/config.json', 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=4, ensure_ascii=False)

