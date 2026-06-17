
import json

with open('python_scraper/config.json', 'r', encoding='utf-8') as f:
    config = json.load(f)

config['topcv']['selectors'] = {
    'job_card': '.job-item-search-result, .job-item-default',
    'title': 'h3.title a',
    'company': 'a.company, .company-name',
    'salary': 'label.title-salary, .salary',
    'location': 'label.address, .address',
    'experience': 'label.experience, .experience',
    'skills': '.job-info-skill-label, .tag-list a.tag',
    'url': 'h3.title a',
    'next_page': 'a.next-page, .pagination li.active + li a'
}

# Fix VNW hanging: use exact selectors to avoid expensive search
config['vietnamworks']['selectors'] = {
    'job_card': '.job-item, .view_job_item, div[class*=''JobCard'']',
    'title': 'h3 a, h2 a',
    'company': 'span.company, a.company',
    'salary': 'span.salary, .salary',
    'location': 'span.location, .location',
    'experience': 'span.experience, .experience',
    'skills': 'span.skill, .tag',
    'url': 'h3 a, h2 a',
    'next_page': 'a.next-page, button.next'
}

with open('python_scraper/config.json', 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=4, ensure_ascii=False)

