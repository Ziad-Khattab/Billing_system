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
        try:
            # parsing for postgresql://user:pass@host:port/db or jdbc:postgresql://...
            if db_url.startswith("jdbc:"):
                db_url = db_url.replace("jdbc:", "", 1)
            
            parts = db_url.split("://")[1]
            if "@" in parts:
                creds, host_part = parts.split("@")
                db_user = creds.split(":")[0]
                db_pass = creds.split(":")[1]
                if "/" in host_part:
                    host_port, db_name_part = host_part.split("/")
                    db_host = host_port.split(":")[0]
                    db_name = db_name_part.split("?")[0]
                else:
                    db_host = host_part.split(":")[0]
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

def generate_cdrs(subscribers, count=100, specific_msisdn=None):
    cdrs = []
    phone_destinations = ["201090000001", "201090000002", "201090000003", "201000000008", "201223344556"]
    url_destinations = ["google.com", "facebook.com", "youtube.com", "fmrz-telecom.net", "whatsapp.net"]
    vplmns = ["FRA01", "UK01", "USA01", "UAE01", "GER01"]
    
    now = datetime.datetime.now()
    active_pool = [s["msisdn"] for s in subscribers if s["status"] == 'active']
    blocked_pool = [s["msisdn"] for s in subscribers if s["status"] != 'active']
    
    for i in range(count):
        roll = random.random()
        is_roaming = random.random() < 0.3 # 30% Roaming
        vplmn = random.choice(vplmns) if is_roaming else ""
        
        if specific_msisdn:
            dial_a = specific_msisdn
        elif roll < 0.05: 
            dial_a = "2019" + str(random.randint(10000000, 99999999))
        elif roll < 0.15: 
            dial_a = random.choice(blocked_pool) if blocked_pool else random.choice(active_pool)
        else: 
            dial_a = random.choice(active_pool) if active_pool else random.choice(blocked_pool)
            
        # Domestic IDs: 1, 2, 3; Roaming IDs: 5, 6, 7
        service_base = random.choice([1, 2, 3])
        service_id = service_base + 4 if is_roaming else service_base
        
        external_charges = 0
        if service_base == 1: # Voice
            dial_b = random.choice(phone_destinations)
            duration = random.randint(30, 7200) # Up to 2 hours
        elif service_base == 2: # Data
            dial_b = random.choice(url_destinations)
            # Big data for overage: 500MB to 5GB
            duration = random.randint(524288000, 5368709120) if specific_msisdn else random.randint(1, 52428800)
        else: # SMS
            dial_b = random.choice(phone_destinations)
            duration = 1
            
        start_time = now - datetime.timedelta(days=random.randint(0, 30), hours=random.randint(0, 23), minutes=random.randint(0, 59))
        time_str = start_time.strftime("%Y-%m-%d %H:%M:%S")
        
        cdrs.append(f"1,{dial_a},{dial_b},{time_str},{duration},{service_id},EGYVO,{vplmn},{external_charges}")
        
    return cdrs

def main():
    print("🚀 FMRZ CDR Generator - Simulating real-world traffic...")
    
    config = get_env_config()
    subscribers = get_msisdns_with_status(config)
    
    if not subscribers:
        print("❌ No MSISDNs found in the database.")
        return
        
    print(f"✅ Found {len(subscribers)} subscribers in database.")
    
    count = 100 
    targets = ["201000000001", "201000000002"] # Alice and Bob
    
    cdrs = []
    for msisdn in targets:
        cdrs += generate_cdrs(subscribers, count=count // 2, specific_msisdn=msisdn)
    
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
