package com.billing.cdr;

import com.billing.db.DB;
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.sql.SQLException;
import java.text.SimpleDateFormat;
import java.util.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class CDRGenerator {
    private static final Logger logger = LoggerFactory.getLogger(CDRGenerator.class);

    public static String generateSamples(int count) throws SQLException, IOException {
        logger.info("Generating {} high-quality sample CDRs...", count);

        // 1. Fetch ALL MSISDNs from DB to ensure no one is at 0
        List<Map<String, Object>> subscribers = DB.executeSelect(
            "SELECT msisdn, status FROM contract WHERE status IN ('active', 'suspended', 'suspended_debt')"
        );

        if (subscribers.isEmpty()) {
            throw new RuntimeException("No MSISDNs found in database.");
        }

        List<String> pool = new ArrayList<>();
        for (Map<String, Object> s : subscribers) {
            pool.add((String) s.get("msisdn"));
        }

        // 2. Setup realistic destinations
        String[] phoneDestinations = {
            "201090000001", "201090000002", "201090000003", "201000000008", 
            "201223344556", "201556677889", "201112223334", "201288899900"
        };
        String[] urlDestinations = {
            "google.com", "facebook.com", "youtube.com", "netflix.com", 
            "whatsapp.net", "instagram.com", "github.com", "fmrz-telecom.net"
        };
        
        // 3. Roaming configuration
        String[] vplmns = {"EGYVO", "FRANC", "DEUTS"};
        
        Random rand = new Random();
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
        
        // 4. Generate data
        List<String> lines = new ArrayList<>();
        lines.add("file_id,dial_a,dial_b,start_time,duration,service_id,hplmn,vplmn,external_charges");

        Calendar cal = Calendar.getInstance();

        for (int i = 0; i < count; i++) {
            String dialA = pool.get(rand.nextInt(pool.size()));
            boolean isRoaming = rand.nextDouble() < 0.20; // 20% Roaming
            String vplmn = isRoaming ? vplmns[1 + rand.nextInt(2)] : "EGYVO";
            
            // Map service IDs based on domestic vs roaming
            // 1=Voice, 2=Data, 3=SMS (Domestic)
            // 5=Voice, 6=Data, 7=SMS (Roaming)
            int baseType = rand.nextInt(3); // 0=Voice, 1=Data, 2=SMS
            int serviceId = (baseType == 0 ? 1 : (baseType == 1 ? 2 : 3));
            if (isRoaming) serviceId += 4; 

            long duration;

            if (baseType == 0) { // Voice
                dialB = phoneDestinations[rand.nextInt(phoneDestinations.length)];
                // 1 minute to 180 minutes
                duration = 60 + rand.nextInt(10800); 
            } else if (baseType == 1) { // Data
                dialB = urlDestinations[rand.nextInt(urlDestinations.length)];
                // 10MB to 15GB (Converted to BYTES for the Parser)
                duration = (10 + rand.nextInt(15360)) * 1024L * 1024L;
            } else { // SMS
                dialB = phoneDestinations[rand.nextInt(phoneDestinations.length)];
                duration = 1;
            }

            cal.setTime(new Date());
            cal.add(Calendar.DAY_OF_YEAR, -rand.nextInt(30));
            cal.add(Calendar.HOUR_OF_DAY, -rand.nextInt(24));
            String timeStr = sdf.format(cal.getTime());

            lines.add(String.format("1,%s,%s,%s,%d,%d,EGYVO,%s,0", dialA, dialB, timeStr, duration, serviceId, isRoaming ? vplmn : ""));
        }

        // 4. Save to file
        String timestamp = new SimpleDateFormat("yyyyMMddHHmmss").format(new Date());
        String filename = "CDR" + timestamp + "_" + System.currentTimeMillis() % 1000 + ".csv";
        
        String inputPath = DB.getProperty("cdr.input.path");
        if (inputPath == null || inputPath.isEmpty()) inputPath = "input";
        
        File inputDir = new File(inputPath);
        if (!inputDir.exists()) inputDir.mkdirs();
        
        File targetFile = new File(inputDir, filename);
        try (FileWriter fw = new FileWriter(targetFile)) {
            for (String line : lines) {
                fw.write(line + "\n");
            }
        }

        logger.info("Generated sample file: {}", targetFile.getAbsolutePath());
        return targetFile.getAbsolutePath();
    }
}
