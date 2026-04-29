import random
import datetime
import os
import subprocess

def get_env_config():
    # Detect root directory
    base_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Priority: Env Var > Default
    input_dir = os.getenv("CDR_INPUT_PATH", os.path.join(base_dir, "input"))
    db_host = os.getenv("DB_HOST", "localhost")
    db_user = os.getenv("DB_USER", "zkhattab")
    db_pass = os.getenv("DB_PASSWORD", "kh007")
    db_name = os.getenv("DB_NAME", "billing_db")
    
    # Handle DB_URL parsing if present (common in Railway/Docker)
    db_url = os.getenv("DB_URL")
    if db_url and "://" in db_url:
        # Simple parsing for postgresql://user:pass@host:port/db
        try:
            parts = db_url.split("://")[1]
            if "@" in parts:
                creds, host_part = parts.split("@")
                db_user = creds.split(":")[0]
                db_pass = creds.split(":")[1]
                host_db = host_part.split("/")
                db_host = host_db[0].split(":")[0]
                db_name = host_db[1].split("?")[0]
        except:
            pass

    return {
        "input_dir": input_dir,
        "db_host": db_host,
        "db_user": db_user,
        "db_pass": db_pass,
        "db_name": db_name
    }

def get_billable_msisdns(config):
    # Use psql to get MSISDNs
    cmd = ["psql", "-h", config["db_host"], "-U", config["db_user"], "-d", config["db_name"], "-t", "-c", "SELECT msisdn FROM contract WHERE status IN ('active', 'suspended', 'suspended_debt')"]
    env = os.environ.copy()
    env["PGPASSWORD"] = config["db_pass"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, env=env, check=True)
        return [line.strip() for line in result.stdout.splitlines() if line.strip()]
    except Exception as e:
        print(f"Error fetching MSISDNs: {e}")
        return []

def generate_cdrs(msisdns, count=100):
    cdrs = []
    # Destinations for variety (mix of numbers and URLs)
    phone_destinations = ["201090000001", "201090000002", "201090000003", "201000000008", "201223344556"]
    url_destinations = ["google.com", "facebook.com", "youtube.com", "fmrz-telecom.net", "whatsapp.net"]
    
    now = datetime.datetime.now()
    
    for i in range(count):
        # 10% Chance of a "Ghost" MSISDN (not in database) to test auditing
        if random.random() < 0.10:
            dial_a = "2019" + str(random.randint(10000000, 99999999))
        else:
            dial_a = random.choice(msisdns)
            
        # Randomly choose service: 1=Voice, 2=Data, 3=SMS
        service_id = random.choice([1, 2, 3])
        
        if service_id == 1: # Voice
            dial_b = random.choice(phone_destinations)
            duration = random.randint(30, 3600) # seconds (30s to 1 hour)
        elif service_id == 2: # Data
            dial_b = random.choice(url_destinations)
            # Duration is in MB for the 9-column format (converted to bytes by Parser if needed)
            duration = random.randint(1, 500) # 1MB to 500MB
        else: # SMS
            dial_b = random.choice(phone_destinations)
            duration = 1 # count
            
        # Distribute over the last 30 days
        start_time = now - datetime.timedelta(days=random.randint(0, 30), hours=random.randint(0, 23), minutes=random.randint(0, 59))
        time_str = start_time.strftime("%Y-%m-%d %H:%M:%S")
        
        # 9 columns: file_id, dial_a, dial_b, start_time, duration, service_id, hplmn, vplmn, external_charges
        cdrs.append(f"1,{dial_a},{dial_b},{time_str},{duration},{service_id},EGYVO,,0")
        
    return cdrs

def main():
    print("🚀 FMRZ CDR Generator - Simulating real-world traffic...")
    
    config = get_env_config()
    msisdns = get_billable_msisdns(config)
    
    if not msisdns:
        print("❌ No active MSISDNs found in the database. Please ensure you have active contracts.")
        return
        
    print(f"✅ Found {len(msisdns)} active subscribers.")
    
    count = 150 # Number of CDRs to generate
    cdrs = generate_cdrs(msisdns, count=count)
    
    # Filename format: CDRYYYYMMDDHHMMSS_mmm.csv
    timestamp = datetime.datetime.now().strftime("%Y%m%d%H%M%S_%f")[:-3]
    filename = f"CDR{timestamp}.csv"
    
    # Ensure input directory exists
    input_dir = config["input_dir"]
    os.makedirs(input_dir, exist_ok=True)
    
    filepath = os.path.join(input_dir, filename)
    
    with open(filepath, "w") as f:
        f.write("file_id,dial_a,dial_b,start_time,duration,service_id,hplmn,vplmn,external_charges\n")
        for cdr in cdrs:
            f.write(cdr + "\n")
            
    print(f"✨ Successfully generated {len(cdrs)} realistic CDRs.")
    print(f"📂 Location: {filepath}")
    print("\nNext Steps:")
    print("1. Go to http://billing.local/admin/cdr/")
    print("2. Click 'Import & Rate New CDRs'")
    print("3. Watch the Call Explorer populate with rated usage!")

if __name__ == "__main__":
    main()
