
def patch_file(filepath):
    print(f'Patching {filepath}')
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    content = content.replace('timeout=1', 'timeout=0')
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print('Patched successfully!')

patch_file('python_scraper/scraper_topcv.py')
patch_file('python_scraper/scraper_vnw.py')

