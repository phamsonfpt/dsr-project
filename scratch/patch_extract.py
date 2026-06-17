# -*- coding: utf-8 -*-
import os

def patch_extract_and_scrape(filepath, source):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # 1. Patch _extract_job
    extract_target = '''        # Lấy URL từ thẻ link tiêu đề'''
    
    if source == 'topcv':
        extract_replacement = '''
        date_str = safe_text(card, 'label.label-update')
        if not date_str:
            date_str = safe_text(card, '.time')
        job_date = parse_relative_date(date_str)

        # Lấy URL từ thẻ link tiêu đề'''
    else: # vnw
        extract_replacement = '''
        date_str = safe_text(card, '.posted-date')
        if not date_str:
            date_str = safe_text(card, '[class*="date"]')
        job_date = parse_relative_date(date_str)

        # Lấy URL từ thẻ link tiêu đề'''

    if 'job_date = parse_relative_date' not in content:
        content = content.replace(extract_target, extract_replacement, 1)

    # 2. Patch return dict in _extract_job
    dict_target = '''            "url": url,
            "source": '''
    dict_replacement = '''            "url": url,
            "job_date": job_date,
            "source": '''
    if '"job_date": job_date,' not in content:
        content = content.replace(dict_target, dict_replacement, 1)

    # 3. Patch _scrape_page
    scrape_target = '''        page_jobs = 0
        for idx, card in enumerate(cards, 1):'''
    scrape_replacement = '''        page_jobs = 0
        should_stop = False
        for idx, card in enumerate(cards, 1):'''
    if 'should_stop = False' not in content:
        content = content.replace(scrape_target, scrape_replacement, 1)

    # 4. Patch loop body
    loop_target = '''                # Chỉ lưu nếu có ít nhất tiêu đề hoặc URL'''
    loop_replacement = '''
                if self.date_filter_enabled:
                    job_date = job.get("job_date")
                    if job_date:
                        # Cẩn thận datetime không có giờ
                        if job_date.date() > self.end_date.date():
                            logger.debug("  ⏭️  [%d/%d] Bỏ qua vì mới hơn %s", idx, len(cards), self.end_date.strftime('%Y-%m-%d'))
                            continue
                        if job_date.date() < self.start_date.date():
                            logger.info("  🛑 Đã gặp tin đăng ngày %s (cũ hơn %s). Dừng cào.", job_date.strftime('%Y-%m-%d'), self.start_date.strftime('%Y-%m-%d'))
                            should_stop = True
                            break

                # Chỉ lưu nếu có ít nhất tiêu đề hoặc URL'''
    if 'if self.date_filter_enabled:' not in content:
        content = content.replace(loop_target, loop_replacement, 1)

    # 5. Patch job append
    append_target = '''                    self.jobs.append(job)'''
    append_replacement = '''                    job["job_date_str"] = job.get("job_date").strftime("%Y-%m-%d") if job.get("job_date") else ""
                    job.pop("job_date", None)
                    self.jobs.append(job)'''
    if 'job["job_date_str"] =' not in content:
        content = content.replace(append_target, append_replacement, 1)

    # 6. Patch _scrape_page return
    ret_target = '''        return page_jobs'''
    ret_replacement = '''        return page_jobs, should_stop'''
    if 'return page_jobs, should_stop' not in content:
        content = content.replace(ret_target, ret_replacement, 1)

    # 7. Patch run() method
    run_target = '''            new_jobs = self._scrape_page(page_num)'''
    run_replacement = '''            new_jobs, should_stop = self._scrape_page(page_num)'''
    if 'new_jobs, should_stop =' not in content:
        content = content.replace(run_target, run_replacement, 1)

    stop_target = '''            if new_jobs == 0:'''
    stop_replacement = '''            if should_stop:
                logger.info("⛔ Đã đạt mốc thời gian start_date. Dừng thu thập.")
                break
            if new_jobs == 0:'''
    if 'if should_stop:' not in content:
        content = content.replace(stop_target, stop_replacement, 1)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

patch_extract_and_scrape('python_scraper/scraper_topcv.py', 'topcv')
patch_extract_and_scrape('python_scraper/scraper_vnw.py', 'vnw')
