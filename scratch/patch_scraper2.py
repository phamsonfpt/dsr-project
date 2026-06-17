# -*- coding: utf-8 -*-
import os
import json
import re

def patch_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 1. Add imports
    if 'from datetime import datetime' not in content:
        content = content.replace('import random', 'import random\nfrom datetime import datetime, timedelta\nimport re')
    else:
        content = content.replace('from datetime import datetime', 'from datetime import datetime, timedelta\nimport re')

    # 2. Add parse_relative_date
    if 'def parse_relative_date' not in content:
        util_code = '''
def parse_relative_date(date_str: str) -> datetime:
    if not date_str:
        return datetime.now()
    date_str = str(date_str).lower().strip()
    now = datetime.now()
    if 'vừa xong' in date_str or 'hôm nay' in date_str or 'giờ trước' in date_str or 'phút trước' in date_str:
        return now
    match_day = re.search(r'(\\d+)\\s*ngày', date_str)
    if match_day:
        return now - timedelta(days=int(match_day.group(1)))
    match_week = re.search(r'(\\d+)\\s*tuần', date_str)
    if match_week:
        return now - timedelta(weeks=int(match_week.group(1)))
    match_month = re.search(r'(\\d+)\\s*tháng', date_str)
    if match_month:
        return now - timedelta(days=int(match_month.group(1))*30)
    match_abs = re.search(r'(\\d{1,2})[-/](\\d{1,2})[-/](\\d{4})', date_str)
    if match_abs:
        try:
            return datetime.strptime(match_abs.group(0).replace('-', '/'), '%d/%m/%Y')
        except:
            pass
    return now

'''
        content = content.replace('def load_config(', util_code + 'def load_config(')

    # 3. Patch load_config
    if 'user_settings.json' not in content:
        user_config_patch = '''
        user_cfg_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'user_settings.json')
        try:
            with open(user_cfg_path, 'r', encoding='utf-8') as uf:
                user_cfg = json.load(uf)
                if 'max_pages' in user_cfg:
                    cfg['topcv'] = cfg.get('topcv', {})
                    cfg['topcv']['max_pages'] = user_cfg['max_pages']
                    cfg['vietnamworks'] = cfg.get('vietnamworks', {})
                    cfg['vietnamworks']['max_pages'] = user_cfg['max_pages']
                cfg['user_settings'] = user_cfg
                logger.info('✅ Đã ghi đè cấu hình từ user_settings.json')
        except FileNotFoundError:
            pass
        return cfg'''
        content = content.replace('return cfg', user_config_patch, 1)

    # 4. Patch __init__ to read date filters
    if 'self.date_filter_enabled' not in content:
        init_patch = '''
        user_settings = config.get('user_settings', {})
        date_filter = user_settings.get('date_filter', {})
        self.date_filter_enabled = date_filter.get('enabled', False)
        try:
            self.start_date = datetime.strptime(date_filter.get('start_date', '2000-01-01'), '%Y-%m-%d')
            self.end_date = datetime.strptime(date_filter.get('end_date', '2100-01-01'), '%Y-%m-%d')
        except Exception:
            self.date_filter_enabled = False
            
        self.jobs: list[dict] = []'''
        content = content.replace('self.jobs: list[dict] = []', init_patch, 1)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

patch_file('python_scraper/scraper_topcv.py')
patch_file('python_scraper/scraper_vnw.py')
