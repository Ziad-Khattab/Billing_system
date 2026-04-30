
import csv
import os
import subprocess

def main():
    db_host = os.getenv("DB_HOST", "ep-misty-queen-al6p4067-pooler.c-3.eu-central-1.aws.neon.tech")
    db_user = os.getenv("DB_USER", "neondb_owner")
    db_pass = os.getenv("DB_PASSWORD", "npg_nYZFS7m1NUPg")
    db_name = os.getenv("DB_NAME", "neondb")
    
    input_file = os.getenv("INPUT_FILE")
    if not input_file:
        print("INPUT_FILE env var required")
        return

    print(f"Importing {input_file}...")
    
    with open(input_file, mode='r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # dial_a,dial_b,start_time,duration,service_id,hplmn,vplmn,external_charges
            sql = f"SELECT insert_cdr(1, '{row['dial_a']}', '{row['dial_b']}', '{row['start_time']}', {row['duration']}, {row['service_id']}, '{row['hplmn']}', '{row['vplmn']}', {row['external_charges']});"
            cmd = ["psql", "-h", db_host, "-U", db_user, "-d", db_name, "-c", sql]
            env = os.environ.copy()
            env["PGPASSWORD"] = db_pass
            subprocess.run(cmd, env=env, capture_output=True)

    print("Import complete. Rating CDRs...")
    rate_sql = "SELECT rate_cdr(id) FROM cdr WHERE rated_flag = FALSE;"
    cmd = ["psql", "-h", db_host, "-U", db_user, "-d", db_name, "-c", rate_sql]
    env = os.environ.copy()
    env["PGPASSWORD"] = db_pass
    subprocess.run(cmd, env=env, capture_output=True)
    print("Rating complete.")

if __name__ == "__main__":
    main()
