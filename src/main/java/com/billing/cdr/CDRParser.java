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

import com.billing.db.DB;

public class CDRParser {
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
            System.out.println("[CONFIG] Loaded " + serviceMap.size() + " services from database.");
        } catch (Exception e) {
            System.err.println("[CONFIG] Failed to load services from database. Using safe defaults.");
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

        if (!dest.exists()) dest.mkdirs();

        File[] csvFiles = source.listFiles((dir, name) -> name.toLowerCase().endsWith(".csv"));

        if (csvFiles == null || csvFiles.length == 0) {
            System.out.println("No CDR files found in " + sourceDir);
            return;
        }

        for (File file : csvFiles) {
            try {
                System.out.println("Parsing CDR: " + file.getName());
                parseAndInsert(file);
                moveFile(file, dest);
                System.out.println("Successfully processed: " + file.getName());
            } catch (Exception e) {
                System.err.println("Error processing " + file.getName() + ": " + e.getMessage());
                e.printStackTrace();
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
            System.err.println("Warning: Could not parse date from filename " + fileName + ". Using fallback.");
        }

        Connection conn = DB.getConnection();
        conn.setAutoCommit(false);
        Integer fileId = -1;

        try {
            // Register file in database
            String createFile = "{ ? = call create_file_record(?) }";
            try (CallableStatement cs = conn.prepareCall(createFile)) {
                cs.registerOutParameter(1, Types.INTEGER);
                cs.setString(2, file.getName());
                cs.execute();
                fileId = cs.getInt(1);
            }

            String sql = "{ ? = call insert_cdr(?,?,?,?,?,?,?,?,?) }";
            try (CallableStatement cs = conn.prepareCall(sql);
                 BufferedReader br = new BufferedReader(new FileReader(file))) {

                String line;
                boolean isHeader = true;
                while ((line = br.readLine()) != null) {
                    if (line.trim().isEmpty()) continue;
                    
                    String[] p = line.split(",", -1);
                    
                    // Skip header if present (common in 9-column files)
                    if (isHeader && p[0].equalsIgnoreCase("file_id")) {
                        isHeader = false;
                        continue;
                    }
                    isHeader = false;

                    String dialA, dialB, timeStr;
                    int serviceId, usage;
                    double externalPiasters = 0;
                    Timestamp ts;

                    if (p.length >= 9) {
                        // 9-Column Format: file_id, dial_a, dial_b, start_time, duration, service_id, hplmn, vplmn, external_charges
                        dialA = p[1].trim();
                        dialB = p[2].trim();
                        timeStr = p[3].trim(); 
                        serviceId = Integer.parseInt(p[5].trim());
                        
                        double rawUsage = Double.parseDouble(p[4].trim());
                        // Convert Bytes to MB for data services in 9-column format
                        if ("data".equals(typeMap.get(serviceId))) {
                            usage = (int) Math.ceil(rawUsage / (1024.0 * 1024.0));
                        } else {
                            usage = (int) rawUsage;
                        }

                        externalPiasters = Double.parseDouble(p[8].trim()) * 100.0;
                        ts = Timestamp.valueOf(timeStr);
                    } else if (p.length >= 6) {
                        // 6-Column Format: Dial A, Dial B, Service ID, Usage, Time, External charges
                        dialA = p[0].trim();
                        dialB = p[1].trim();
                        serviceId = Integer.parseInt(p[2].trim());
                        
                        // Detect unit: 6-column data usage is usually in Bytes
                        int dataId = getServiceId("Data Pack");
                        double rawUsage = Double.parseDouble(p[3].trim());
                        if (serviceId == dataId) {
                            usage = (int) Math.ceil(rawUsage / (1024.0 * 1024.0)); // Convert Bytes to MB
                        } else {
                            usage = (int) rawUsage; // Voice is usually in seconds
                        }
                        
                        timeStr = p[4].trim(); // HH:MM:SS
                        externalPiasters = Double.parseDouble(p[5].trim());

                        ts = Timestamp.valueOf(fileDateStr + " " + timeStr);
                    } else {
                        continue; // Invalid format
                    }

                    // Normalize MSISDNs
                    if (dialA.startsWith("00")) dialA = dialA.substring(2);
                    if (dialB.startsWith("00")) dialB = dialB.substring(2);

                    // Fetch dynamic configuration for smart correction
                    int voiceId = getServiceId("Voice Pack");
                    int dataId = getServiceId("Data Pack");
                    int smsId = getServiceId("SMS Pack");
                    
                    String urlMarkers = DB.getProperty("cdr.url.markers");
                    if (urlMarkers == null) urlMarkers = "://,.com,.net,.org,.gov";
                    String[] markers = urlMarkers.split(",");

                    // SMART CORRECTION: Detect "Data Leakage" where URLs are labeled as SMS
                    if (serviceId == smsId && usage > 100) {
                        String lowerDest = dialB.toLowerCase();
                        boolean matches = false;
                        for (String m : markers) if (lowerDest.contains(m.trim())) { matches = true; break; }
                        if (matches) serviceId = dataId;
                    }

                    // SMART CORRECTION 2: Detect "SMS Leakage" where SMS are labeled as Data
                    if (serviceId == dataId && usage == 1) {
                        String lowerDest = dialB.toLowerCase();
                        boolean isUrl = false;
                        for (String m : markers) if (lowerDest.contains(m.trim())) { isUrl = true; break; }
                        if (!isUrl) serviceId = smsId;
                    }

                    // Insert via SQL function
                    cs.registerOutParameter(1, Types.INTEGER);
                    cs.setInt(2, fileId);
                    cs.setString(3, dialA);
                    cs.setString(4, dialB);
                    cs.setTimestamp(5, ts);
                    cs.setInt(6, usage);
                    cs.setInt(7, serviceId);
                    cs.setNull(8, Types.VARCHAR); // p_hplmn
                    cs.setNull(9, Types.VARCHAR); // p_vplmn
                    cs.setBigDecimal(10, BigDecimal.valueOf(externalPiasters / 100.0));

                    cs.execute();
                }
            }

            // Mark file as parsed
            String markParsed = "{ call set_file_parsed(?) }";
            try (CallableStatement cs = conn.prepareCall(markParsed)) {
                cs.setInt(1, fileId);
                cs.execute();
            }

            conn.commit();
        } catch (Exception e) {
            conn.rollback();
            throw e;
        } finally {
            conn.close();
        }
    }

    private static void moveFile(File file, File destPath) throws IOException {
        String originalName = file.getName();
        String uniqueId = java.util.UUID.randomUUID().toString().substring(0, 8);
        String finalName = uniqueId + "_" + originalName;
        Path target = destPath.toPath().resolve(finalName);
        
        System.out.println("[AUDIT] Moving " + originalName + " to " + target.toAbsolutePath());
        try {
            Files.move(file.toPath(), target, StandardCopyOption.REPLACE_EXISTING);
        } catch (Exception e) {
            // Fallback for cross-device moves
            Files.copy(file.toPath(), target, StandardCopyOption.REPLACE_EXISTING);
            Files.delete(file.toPath());
        }
    }
}
