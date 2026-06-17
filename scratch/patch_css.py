# -*- coding: utf-8 -*-
def patch_file(filepath):
    print(f'Patching {filepath}')
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
        
    old_func1 = '''def safe_text(element, selector: str, attr: Optional[str] = None) -> str:
    """
    Trích xuất text hoặc attribute từ element con một cách an toàn.
    Trả về chuỗi rỗng nếu không tìm thấy phần tử.
    """
    try:
        child = element.ele(selector, timeout=0)'''
        
    new_func1 = '''def safe_text(element, selector: str, attr: Optional[str] = None) -> str:
    """
    Trích xuất text hoặc attribute từ element con một cách an toàn.
    Trả về chuỗi rỗng nếu không tìm thấy phần tử.
    """
    try:
        if selector and not selector.startswith(('css:', 'xpath:', 'tag:', '@')):
            selector = 'css:' + selector
        child = element.ele(selector, timeout=0)'''

    old_func2 = '''def safe_texts(element, selector: str) -> str:
    """
    Lấy text từ nhiều element con, nối bằng dấu phẩy.
    Dùng cho trường hợp skill tags (có nhiều thẻ).
    """
    try:
        children = element.eles(selector, timeout=0)'''
        
    new_func2 = '''def safe_texts(element, selector: str) -> str:
    """
    Lấy text từ nhiều element con, nối bằng dấu phẩy.
    Dùng cho trường hợp skill tags (có nhiều thẻ).
    """
    try:
        if selector and not selector.startswith(('css:', 'xpath:', 'tag:', '@')):
            selector = 'css:' + selector
        children = element.eles(selector, timeout=0)'''
        
    if old_func1 in content:
        content = content.replace(old_func1, new_func1)
    if old_func2 in content:
        content = content.replace(old_func2, new_func2)
        
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print('Patched successfully!')

patch_file('python_scraper/scraper_topcv.py')
patch_file('python_scraper/scraper_vnw.py')
