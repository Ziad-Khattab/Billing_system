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

def get_msisdns_with_status(config):
    # Fetch MSISDN and status to allow weighted selection
    cmd = ["psql", "-h", config["db_host"], "-U", config["db_user"], "-d", config["db_name"], "-t", "-c", "SELECT msisdn, status FROM contract WHERE status IN ('active', 'suspended', 'suspended_debt', 'terminated')"]
    env = os.environ.copy()
    env["PGPASSWORD"] = config["db_pass"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, env=env, check=True)
        data = []
        for line in result.stdout.splitlines():
            parts = line.strip().split("|")
            if len(parts) == 2:
                data.append({"msisdn": parts[0].strip(), "status": parts[1].strip()})
        return data
    except Exception as e:
        print(f"Error fetching MSISDNs: {e}")
        return []

def generate_cdrs(subscribers, count=100):
    cdrs = []
    phone_destinations = ["201090000001", "201090000002", "201090000003", "201000000008", "201223344556"]
    url_destinations = ["google.com", "facebook.com", "youtube.com", "fmrz-telecom.net", "whatsapp.net"]
    
    now = datetime.datetime.now()
    
    # Separate for weighting
    active_pool = [s["msisdn"] for s in subscribers if s["status"] == 'active']
    blocked_pool = [s["msisdn"] for s in subscribers if s["status"] != 'active']
    
    for i in range(count):
        roll = random.random()
        
        if roll < 0.05: # 5% Chance of a "Ghost" (Stranger)
            dial_a = "2019" + str(random.randint(10000000, 99999999))
        elif roll < 0.15: # 10% Chance of a "Blocked" subscriber (Suspended/Debt)
            dial_a = random.choice(blocked_pool) if blocked_pool else random.choice(active_pool)
        else: # 85% Chance of a "Healthy" active subscriber
            dial_a = random.choice(active_pool) if active_pool else random.choice(blocked_pool)
            
        service_id = random.choice([1, 2, 3])
        
        if service_id == 1: # Voice
            dial_b = random.choice(phone_destinations)
            duration = random.randint(30, 3600)
        elif service_id == 2: # Data
            dial_b = random.choice(url_destinations)
            duration = random.randint(1, 500)
        else: # SMS
            dial_b = random.choice(phone_destinations)
            duration = 1
            
        start_time = now - datetime.timedelta(days=random.randint(0, 30), hours=random.randint(0, 23), minutes=random.randint(0, 59))
        time_str = start_time.strftime("%Y-%m-%d %H:%M:%S")
        cdrs.append(f"1,{dial_a},{dial_b},{time_str},{duration},{service_id},EGYVO,,0")
        
    return cdrs

def main():
    print("🚀 FMRZ CDR Generator - Simulating real-world traffic...")
    
    config = get_env_config()
    subscribers = get_msisdns_with_status(config)
    
    if not subscribers:
        print("❌ No MSISDNs found in the database.")
        return
        
    print(f"✅ Found {len(subscribers)} subscribers in database.")
    
    count = 150 
    cdrs = generate_cdrs(subscribers, count=count)
    
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
