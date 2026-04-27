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

import com.billing.db.DB;

public class CDRParser {

    public static void main(String[] args) {
        String input = args.length > 0 ? args[0] : "input";
        String processed = args.length > 1 ? args[1] : "processed";
        processAll(input, processed);
    }

    public static void processAll(String sourceDir, String destDir) {
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
                while ((line = br.readLine()) != null) {
                    if (line.trim().isEmpty()) continue;
                    
                    // User Format: Dial A, Dial B, Service ID, Usage, Time, External charges
                    String[] p = line.split(",", -1);
                    if (p.length < 6) continue;

                    String dialA = p[0].trim();
                    String dialB = p[1].trim();
                    int serviceId = Integer.parseInt(p[2].trim());
                    int usage = Integer.parseInt(p[3].trim());
                    String timeStr = p[4].trim(); // HH:MM:SS
                    double externalPiasters = Double.parseDouble(p[5].trim());

                    // Construct full timestamp
                    Timestamp ts = Timestamp.valueOf(fileDateStr + " " + timeStr);

                    // Insert via SQL function (Match exact signature in whole_billing_updated.sql)
                    cs.registerOutParameter(1, Types.INTEGER);
                    cs.setInt(2, fileId);
                    cs.setString(3, dialA);
                    cs.setString(4, dialB);
                    cs.setTimestamp(5, ts);
                    cs.setInt(6, usage);
                    cs.setInt(7, serviceId);
                    cs.setNull(8, Types.VARCHAR); // p_hplmn
                    cs.setNull(9, Types.VARCHAR); // p_vplmn
                    cs.setBigDecimal(10, BigDecimal.valueOf(externalPiasters / 100.0)); // p_external_charges

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
        Path target = destPath.toPath().resolve(file.getName());
        if (Files.exists(target)) {
            String newName = System.currentTimeMillis() + "_" + file.getName();
            target = destPath.toPath().resolve(newName);
        }
        Files.move(file.toPath(), target, StandardCopyOption.REPLACE_EXISTING);
    }
}
