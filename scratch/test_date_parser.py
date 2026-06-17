
import re
from datetime import datetime, timedelta

def parse_relative_date(date_str):
    if not date_str:
        return datetime.now()
    
    date_str = date_str.lower().strip()
    now = datetime.now()
    
    if 'v?a xong' in date_str or 'hôm nay' in date_str or 'gi? tru?c' in date_str or 'phút tru?c' in date_str:
        return now
    
    # x ngày tru?c
    match_day = re.search(r'(\d+)\s*ngày', date_str)
    if match_day:
        days = int(match_day.group(1))
        return now - timedelta(days=days)
        
    # x tu?n tru?c
    match_week = re.search(r'(\d+)\s*tu?n', date_str)
    if match_week:
        weeks = int(match_week.group(1))
        return now - timedelta(weeks=weeks)
        
    # x tháng tru?c
    match_month = re.search(r'(\d+)\s*tháng', date_str)
    if match_month:
        months = int(match_month.group(1))
        return now - timedelta(days=months*30)
        
    # If absolute format like dd/mm/yyyy
    match_abs = re.search(r'(\d{1,2})[-/](\d{1,2})[-/](\d{4})', date_str)
    if match_abs:
        try:
            return datetime.strptime(match_abs.group(0).replace('-', '/'), '%d/%m/%Y')
        except:
            pass
            
    return now

print(parse_relative_date('6 ngày tru?c').strftime('%Y-%m-%d'))
print(parse_relative_date('1 tu?n tru?c').strftime('%Y-%m-%d'))
print(parse_relative_date('v?a xong').strftime('%Y-%m-%d'))

