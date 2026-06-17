with open('python_scraper/scraper_vnw.py', 'r', encoding='utf-8') as f:
    content = f.read()
import re
content = content.replace(
    '"skills": _get_multi("skills"),',
    '"skills": (lambda x: print("\\n---SKILLS EXTRACTED:", repr(x)) or x)(_get_multi("skills")),'
)
with open('python_scraper/scraper_vnw_debug.py', 'w', encoding='utf-8') as f:
    f.write(content)
