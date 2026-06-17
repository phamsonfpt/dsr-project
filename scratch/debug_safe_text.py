def patch_file(filepath):
    print(f'Patching {filepath}')
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
        
    old_func = '''def safe_text(element, selector: str, attr: Optional[str] = None) -> str:
    """
    Trích xuất text hoặc attribute từ element con một cách an toàn.
    Trả về chuỗi rỗng nếu không tìm thấy phần tử.
    """
    try:
        if selector and not selector.startswith(('css:', 'xpath:', 'tag:', '@')):
            selector = 'css:' + selector
        child = element.ele(selector, timeout=0)
        if child is None:
            return ""
        if attr:
            return (child.attr(attr) or "").strip()
        return (child.text or "").strip()
    except Exception:
        return ""'''
        
    new_func = '''def safe_text(element, selector: str, attr: Optional[str] = None) -> str:
    """
    Trích xuất text hoặc attribute từ element con một cách an toàn.
    Trả về chuỗi rỗng nếu không tìm thấy phần tử.
    """
    try:
        if selector and not selector.startswith(('css:', 'xpath:', 'tag:', '@')):
            selector = 'css:' + selector
        child = element.ele(selector, timeout=0)
        if child is None:
            # print(f'DEBUG: {selector} -> None')
            return ""
        if attr:
            res = (child.attr(attr) or "").strip()
            # print(f'DEBUG: {selector} -> {res}')
            return res
        res = (child.text or "").strip()
        print(f'DEBUG: {selector} -> {res}')
        return res
    except Exception as e:
        print(f'DEBUG ERROR: {selector} -> {e}')
        return ""'''
        
    if old_func in content:
        content = content.replace(old_func, new_func)
    else:
        print('Could not find old func')
        
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print('Patched successfully!')

patch_file('python_scraper/scraper_topcv.py')
