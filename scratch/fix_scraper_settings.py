
def update_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    old_load = '''                if 'max_pages' in user_cfg:
                    cfg['topcv'] = cfg.get('topcv', {})
                    cfg['topcv']['max_pages'] = user_cfg['max_pages']
                    cfg['vietnamworks'] = cfg.get('vietnamworks', {})
                    cfg['vietnamworks']['max_pages'] = user_cfg['max_pages']'''
    
    new_load = '''                if 'max_pages' in user_cfg:
                    cfg['topcv'] = cfg.get('topcv', {})
                    cfg['topcv']['max_pages'] = user_cfg['max_pages']
                    cfg['vietnamworks'] = cfg.get('vietnamworks', {})
                    cfg['vietnamworks']['max_pages'] = user_cfg['max_pages']
                
                # Update individually for topcv and vietnamworks if present
                if 'topcv' in user_cfg and isinstance(user_cfg['topcv'], dict):
                    cfg.setdefault('topcv', {}).update(user_cfg['topcv'])
                if 'vietnamworks' in user_cfg and isinstance(user_cfg['vietnamworks'], dict):
                    cfg.setdefault('vietnamworks', {}).update(user_cfg['vietnamworks'])'''
    content = content.replace(old_load, new_load)

    old_df = '''        user_settings = config.get('user_settings', {})
        date_filter = user_settings.get('date_filter', {})'''
    
    new_df = '''        user_settings = config.get('user_settings', {})
        date_filter = self.cfg.get('date_filter', user_settings.get('date_filter', {}))'''
    content = content.replace(old_df, new_df)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f'Updated {filepath}')

update_file('python_scraper/scraper_topcv.py')
update_file('python_scraper/scraper_vnw.py')

