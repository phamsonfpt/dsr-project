with open('python_scraper/scraper_vnw.py', 'r', encoding='utf-8') as f:
    content = f.read()
import re
content = content.replace(
    '"skills": _get_multi("skills"),',
    '"skills": (lambda x: print("\\n---CARD HTML:", card.html[:800], "\\n---SKILLS:", repr(x)) or x)(_get_multi("skills")),'
)
with open('python_scraper/scraper_vnw_debug2.py', 'w', encoding='utf-8') as f:
    f.write(content)
