import os
import csv

# Source and Destination
source_dir = "processed"
target_dir = "input"

# Ensure target exists
if not os.path.exists(target_dir):
    os.makedirs(target_dir)

processed_files = [f for f in os.listdir(source_dir) if f.endswith(".csv") and f.startswith("CDR")]

if not processed_files:
    print("No processed CDR files found to repair.")
    exit(0)

for filename in processed_files:
    print(f"Repairing {filename}...")
    input_path = os.path.join(source_dir, filename)
    output_path = os.path.join(target_dir, filename)
    
    with open(input_path, 'r') as f_in, open(output_path, 'w', newline='') as f_out:
        writer = csv.writer(f_out)
        for line in csv.reader(f_in):
            # Format: DialA, DialB, ServiceID, Usage, Time, External
            if len(line) >= 4:
                dialB = line[1].lower()
                service_id = line[2]
                usage_str = line[3].strip()
                usage = int(usage_str) if usage_str.isdigit() else 0
                
                # Fix: If it's a URL but labeled as SMS (3), change to Data (2)
                if service_id == "3" and usage > 100:
                    if "://" in dialB or ".com" in dialB or ".net" in dialB or ".org" in dialB:
                        line[2] = "2"
                        print(f"  [FIXED] URL detected: {dialB} -> Moved to Data (ID 2)")
            
            writer.writerow(line)

print("\n--- Repair Complete ---")
print(f"Fixed files have been moved to: {target_dir}")
print("You can now safely delete the files in 'processed/' after verifying the input folder.")
