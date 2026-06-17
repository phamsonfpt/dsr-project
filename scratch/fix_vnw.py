with open('python_scraper/scraper_vnw.py', 'r', encoding='utf-8') as f:
    content = f.read()
content = content.replace(
    "date_filter = self.cfg.get('date_filter', user_settings.get('date_filter', {}))",
    "date_filter = config.get('vietnamworks', {}).get('date_filter', user_settings.get('date_filter', {}))"
)
with open('python_scraper/scraper_vnw.py', 'w', encoding='utf-8') as f:
    f.write(content)
