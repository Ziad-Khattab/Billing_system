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
        logger.info("Generating {} sample CDRs...", count);

        // 1. Fetch MSISDNs from DB
        List<Map<String, Object>> subscribers = DB.executeSelect(
            "SELECT msisdn, status FROM contract WHERE status IN ('active', 'suspended', 'suspended_debt', 'terminated')"
        );

        if (subscribers.isEmpty()) {
            throw new RuntimeException("No MSISDNs found in database. Create some contracts first!");
        }

        List<String> activePool = new ArrayList<>();
        List<String> blockedPool = new ArrayList<>();

        for (Map<String, Object> s : subscribers) {
            String msisdn = (String) s.get("msisdn");
            String status = (String) s.get("status");
            if ("active".equals(status)) activePool.add(msisdn);
            else blockedPool.add(msisdn);
        }

        // 2. Setup destinations
        String[] phoneDestinations = {"201090000001", "201090000002", "201090000003", "201000000008", "201223344556"};
        String[] urlDestinations = {"google.com", "facebook.com", "youtube.com", "fmrz-telecom.net", "whatsapp.net"};
        
        Random rand = new Random();
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
        
        // 3. Generate data
        List<String> lines = new ArrayList<>();
        lines.add("file_id,dial_a,dial_b,start_time,duration,service_id,hplmn,vplmn,external_charges");

        Calendar cal = Calendar.getInstance();

        for (int i = 0; i < count; i++) {
            double roll = rand.nextDouble();
            String dialA;
            
            if (roll < 0.05) { // Ghost
                dialA = "2019" + (10000000 + rand.nextInt(90000000));
            } else if (roll < 0.15 && !blockedPool.isEmpty()) { // Blocked
                dialA = blockedPool.get(rand.nextInt(blockedPool.size()));
            } else { // Healthy
                dialA = activePool.isEmpty() ? blockedPool.get(rand.nextInt(blockedPool.size())) : activePool.get(rand.nextInt(activePool.size()));
            }

            int serviceId = 1 + rand.nextInt(3);
            String dialB;
            int duration;

            if (serviceId == 1) { // Voice
                dialB = phoneDestinations[rand.nextInt(phoneDestinations.length)];
                duration = 30 + rand.nextInt(3570);
            } else if (serviceId == 2) { // Data
                dialB = urlDestinations[rand.nextInt(urlDestinations.length)];
                duration = 1 + rand.nextInt(500);
            } else { // SMS
                dialB = phoneDestinations[rand.nextInt(phoneDestinations.length)];
                duration = 1;
            }

            cal.setTime(new Date());
            cal.add(Calendar.DAY_OF_YEAR, -rand.nextInt(30));
            cal.add(Calendar.HOUR_OF_DAY, -rand.nextInt(24));
            cal.add(Calendar.MINUTE, -rand.nextInt(60));
            String timeStr = sdf.format(cal.getTime());

            lines.add(String.format("1,%s,%s,%s,%d,%d,EGYVO,,0", dialA, dialB, timeStr, duration, serviceId));
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
