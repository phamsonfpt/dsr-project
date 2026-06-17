import os

def patch_file(filepath):
    print(f'Patching {filepath}')
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    target = '''        co = ChromiumOptions()

        if self.headless:
            co.headless()

        # Stealth settings — vượt qua phát hiện bot
        co.set_argument("--disable-blink-features=AutomationControlled")
        co.set_argument("--no-first-run")'''
        
    replacement = '''        co = ChromiumOptions()
        
        # SỬ DỤNG TRÌNH DUYỆT CHROME THẬT ĐỂ VƯỢT CLOUDFLARE
        import os as _os
        chrome_path = r'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe'
        if _os.path.exists(chrome_path):
            co.set_browser_path(chrome_path)
            # Tạo thư mục user data giả để không đụng độ Chrome đang mở
            debug_dir = _os.path.join(_os.getcwd(), 'chrome_debug_profile')
            co.set_user_data_path(debug_dir)

        if self.headless:
            co.headless()

        # Stealth settings — vượt qua phát hiện bot
        co.set_argument("--disable-blink-features=AutomationControlled")
        co.set_argument("--no-first-run")'''
    
    if target in content:
        content = content.replace(target, replacement)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print('Patched successfully!')
    else:
        print('Target not found in file!')

patch_file('python_scraper/scraper_vnw.py')
