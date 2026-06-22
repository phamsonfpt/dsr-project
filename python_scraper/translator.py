import pandas as pd
import glob
import time
import sys
from deep_translator import GoogleTranslator
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(message)s")
logger = logging.getLogger(__name__)

sys.stdout.reconfigure(encoding='utf-8')

def translate_text(text, translator, max_retries=3):
    if not isinstance(text, str) or not text.strip():
        return text
    
    # Split text if it's too long (> 4500 chars) since google translate limit is 5000
    if len(text) > 4500:
        chunks = [text[i:i+4500] for i in range(0, len(text), 4500)]
        translated = []
        for chunk in chunks:
            success = False
            for attempt in range(max_retries):
                try:
                    translated.append(translator.translate(chunk))
                    time.sleep(1.0)
                    success = True
                    break
                except Exception as e:
                    logger.error(f"Translation error on chunk (attempt {attempt+1}): {e}")
                    # Làm mới translator object nếu bị block
                    translator = GoogleTranslator(source='auto', target='en')
                    time.sleep(3.0)
            if not success:
                translated.append(chunk)
        return "".join(translated)
    else:
        for attempt in range(max_retries):
            try:
                res = translator.translate(text)
                time.sleep(0.5)
                return res
            except Exception as e:
                logger.error(f"Translation error (attempt {attempt+1}): {e}")
                if attempt == 1:
                    from deep_translator import MyMemoryTranslator
                    logger.warning("Switching to MyMemoryTranslator fallback...")
                    translator = MyMemoryTranslator(source='vi', target='en')
                time.sleep(3.0)
        return text

def translate_csv_files():
    translator = GoogleTranslator(source='auto', target='en')
    csv_files = glob.glob("data/raw/*_jobs_raw.csv")
    
    cols_to_translate = ["title", "job_description", "requirements", "benefits"]
    
    for file in csv_files:
        logger.info(f"Translating {file}...")
        try:
            df = pd.read_csv(file, encoding='utf-8-sig')
            
            for col in cols_to_translate:
                if col in df.columns:
                    logger.info(f"  -> Translating column: {col}")
                    for idx, row in df.iterrows():
                        original_text = df.at[idx, col]
                        if pd.notna(original_text) and str(original_text).strip():
                            # Print progress every 10 rows
                            if idx > 0 and idx % 10 == 0:
                                logger.info(f"     ... translated {idx}/{len(df)} rows")
                                
                            translated_text = translate_text(str(original_text), translator)
                            df.at[idx, col] = translated_text
                            time.sleep(0.1) # tiny delay to avoid rate limits
            
            df.to_csv(file, index=False, encoding='utf-8-sig')
            logger.info(f"✅ Successfully translated and saved: {file}")
            
        except Exception as e:
            logger.error(f"❌ Failed to process {file}: {e}")

if __name__ == "__main__":
    translate_csv_files()
