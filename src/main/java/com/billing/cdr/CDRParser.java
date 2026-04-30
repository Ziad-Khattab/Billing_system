package com.billing.cdr;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.math.BigDecimal;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.sql.Types;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.billing.db.DB;

public class CDRParser {
    private static final Logger logger = LoggerFactory.getLogger(CDRParser.class);
    private static java.util.Map<String, Integer> serviceMap = new java.util.HashMap<>();
    private static java.util.Map<Integer, String> typeMap = new java.util.HashMap<>();

    private static void loadServiceConfig() {
        try (Connection conn = DB.getConnection()) {
            List<Map<String, Object>> services = DB.executeSelect("SELECT id, name, type FROM service_package");
            for (Map<String, Object> s : services) {
                String name = (String) s.get("name");
                String type = (String) s.get("type");
                Integer id = (Integer) s.get("id");
                serviceMap.put(name, id);
                typeMap.put(id, type);
            }
            logger.info("Loaded {} services from database.", serviceMap.size());
        } catch (Exception e) {
            logger.warn("Failed to load services from database. Using safe defaults.");
            serviceMap.put("Voice Pack", 1); typeMap.put(1, "voice");
            serviceMap.put("Data Pack", 2);  typeMap.put(2, "data");
            serviceMap.put("SMS Pack", 3);   typeMap.put(3, "sms");
        }
    }

    private static int getServiceId(String name) {
        return serviceMap.getOrDefault(name, -1);
    }

    public static void main(String[] args) {
        String input = args.length > 0 ? args[0] : "input";
        String processed = args.length > 1 ? args[1] : "processed";
        loadServiceConfig();
        processAll(input, processed);
    }

    public static void processAll(String sourceDir, String destDir) {
        loadServiceConfig();
        File source = new File(sourceDir);
        File dest = new File(destDir);

        if (!dest.exists()) {
            if (!dest.mkdirs()) {
                logger.warn("Failed to create destination directory: {}", destDir);
            }
        }

        File[] csvFiles = source.listFiles((dir, name) -> name.toLowerCase().endsWith(".csv"));

        if (csvFiles == null || csvFiles.length == 0) {
            System.out.println("No CDR files found in " + sourceDir);
            return;
        }

        for (File file : csvFiles) {
            try {
                logger.info("Parsing CDR: {}", file.getName());
                parseAndInsert(file);
                moveFile(file, dest);
                logger.info("Successfully processed: {}", file.getName());
            } catch (Exception e) {
                logger.error("Error processing {}: {}", file.getName(), e.getMessage());
            }
        }
    }

    private static void parseAndInsert(File file) throws IOException, SQLException {
        // Extract date from filename: CDRYYYYMMDDHHMMSS.csv
        String fileName = file.getName();
        String fileDateStr = "2024-01-01"; // Default fallback
        try {
            if (fileName.startsWith("CDR") && fileName.length() >= 11) {
                String yyyy = fileName.substring(3, 7);
                String mm = fileName.substring(7, 9);
                String dd = fileName.substring(9, 11);
                fileDateStr = yyyy + "-" + mm + "-" + dd;
            }
        } catch (Exception e) {
            logger.warn("Could not parse date from filename {}. Using fallback.", fileName);
        }

        try (Connection conn = DB.getConnection()) {
            conn.setAutoCommit(false);
            Integer fileId = -1;

            // Register file in database
            String createFile = "{ ? = call create_file_record(?) }";
            try (CallableStatement cs = conn.prepareCall(createFile)) {
                cs.registerOutParameter(1, Types.INTEGER);
                cs.setString(2, file.getName());
                cs.execute();
                fileId = cs.getInt(1);
            }

            // Using SELECT for batching (more efficient for PostgreSQL function calls without OUT params)
            String sql = "SELECT insert_cdr(?,?,?,?,?,?,?,?,?)";
            try (java.sql.PreparedStatement ps = conn.prepareStatement(sql);
                 BufferedReader br = new BufferedReader(new FileReader(file))) {

                String line;
                boolean isHeader = true;
                int batchCount = 0;
                final int BATCH_SIZE = 1000;

                while ((line = br.readLine()) != null) {
                    if (line.trim().isEmpty()) continue;
                    String[] p = line.split(",", -1);
                    
                    if (isHeader && (p[0].equalsIgnoreCase("file_id") || p[0].equalsIgnoreCase("dial_a"))) {
                        isHeader = false;
                        continue;
                    }
                    isHeader = false;

                    try {
                        String dialA, dialB, timeStr;
                        int serviceId, usage;
                        double externalPiasters = 0;
                        Timestamp ts;

                        if (p.length >= 9) {
                            dialA = p[1].trim();
                            dialB = p[2].trim();
                            timeStr = p[3].trim(); 
                            serviceId = Integer.parseInt(p[5].trim());
                            double rawUsage = Double.parseDouble(p[4].trim());
                            if ("data".equals(typeMap.get(serviceId))) {
                                usage = (int) Math.ceil(rawUsage / (1024.0 * 1024.0));
                            } else {
                                usage = (int) rawUsage;
                            }
                            externalPiasters = Double.parseDouble(p[8].trim()) * 100.0;
                            ts = Timestamp.valueOf(timeStr);
                        } else if (p.length >= 6) {
                            dialA = p[0].trim();
                            dialB = p[1].trim();
                            serviceId = Integer.parseInt(p[2].trim());
                            double rawUsage = Double.parseDouble(p[3].trim());
                            if (serviceId == getServiceId("Data Pack")) {
                                usage = (int) Math.ceil(rawUsage / (1024.0 * 1024.0));
                            } else {
                                usage = (int) rawUsage;
                            }
                            timeStr = p[4].trim();
                            externalPiasters = Double.parseDouble(p[5].trim());
                            ts = Timestamp.valueOf(fileDateStr + " " + timeStr);
                        } else {
                            continue;
                        }

                        // Normalize
                        if (dialA.startsWith("00")) dialA = dialA.substring(2);
                        if (dialB.startsWith("00")) dialB = dialB.substring(2);

                        // Set parameters for SELECT insert_cdr(...)
                        ps.setInt(1, fileId);
                        ps.setString(2, dialA);
                        ps.setString(3, dialB);
                        ps.setTimestamp(4, ts);
                        ps.setInt(5, usage);
                        ps.setInt(6, serviceId);
                        ps.setNull(7, Types.VARCHAR);
                        ps.setNull(8, Types.VARCHAR);
                        ps.setBigDecimal(9, BigDecimal.valueOf(externalPiasters / 100.0));

                        ps.addBatch();
                        batchCount++;

                        if (batchCount % BATCH_SIZE == 0) {
                            ps.executeBatch();
                            batchCount = 0;
                        }
                    } catch (Exception e) {
                        logger.warn("Skipping malformed row in {}: {}", file.getName(), e.getMessage());
                    }
                }
                if (batchCount > 0) ps.executeBatch();
            }

            // Mark file as parsed
            String markParsed = "{ call set_file_parsed(?) }";
            try (CallableStatement cs = conn.prepareCall(markParsed)) {
                cs.setInt(1, fileId);
                cs.execute();
            }
            conn.commit();
        } catch (Exception e) {
            logger.error("FATAL ERROR in parseAndInsert for {}: {}", file.getName(), e.getMessage());
            throw e;
        }
    }

    private static void moveFile(File file, File destPath) throws IOException {
        String originalName = file.getName();
        String uniqueId = java.util.UUID.randomUUID().toString().substring(0, 8);
        String finalName = uniqueId + "_" + originalName;
        Path target = destPath.toPath().resolve(finalName);
        
        logger.info("Moving {} to {}", originalName, target.toAbsolutePath());
        try {
            Files.move(file.toPath(), target, StandardCopyOption.REPLACE_EXISTING);
        } catch (Exception e) {
            // Fallback for cross-device moves
            Files.copy(file.toPath(), target, StandardCopyOption.REPLACE_EXISTING);
            Files.delete(file.toPath());
        }
    }
}
