
import json

with open('python_scraper/config.json', 'r', encoding='utf-8') as f:
    config = json.load(f)

# Use structural selectors since VNW uses hashed classes
config['vietnamworks']['selectors']['title'] = 'css:a[title]'
config['vietnamworks']['selectors']['url'] = 'css:a[title]'
config['vietnamworks']['selectors']['company'] = 'css:a[title] + div'
config['vietnamworks']['selectors']['location'] = 'css:a[title] + div + div'
config['vietnamworks']['selectors']['salary'] = 'css:a[title] + div + div + div'
config['vietnamworks']['selectors']['experience'] = 'css:a[title] + div + div + div + div'

with open('python_scraper/config.json', 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=4, ensure_ascii=False)

