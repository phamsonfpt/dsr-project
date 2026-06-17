# -*- coding: utf-8 -*-
import os

def patch_file(filepath):
    print(f'Patching {filepath}')
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    target = 'if self.headless:\n            co.headless()'
    replacement = '''# Chặn hoàn toàn bảng thông báo xin quyền Vị trí (Location) và Thông báo (Notifications)
        co.set_pref('profile.default_content_setting_values.geolocation', 2)
        co.set_pref('profile.default_content_setting_values.notifications', 2)

        if self.headless:
            co.headless()'''
    
    if target in content and 'geolocation' not in content:
        content = content.replace(target, replacement)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print('Patched successfully!')
    else:
        print('Target not found or already patched!')

patch_file('python_scraper/scraper_topcv.py')
patch_file('python_scraper/scraper_vnw.py')
