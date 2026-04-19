package com.billing.cdr;

import com.billing.db.DB;

import java.io.*;
import java.math.BigDecimal;
import java.nio.file.*;
import java.sql.*;

public class CDRParser {

    public static void processAll(String sourceDir, String destDir) {
        File source = new File(sourceDir);
        File dest = new File(destDir);

        if (!dest.exists()) dest.mkdirs();

        File[] csvFiles = source.listFiles(
                ((dir, name) -> name.toLowerCase().endsWith(".csv"))
        );

        if (csvFiles == null || csvFiles.length == 0) {
            System.out.println("No CSV files found in " + sourceDir);
            return;
        }
        for (File file : csvFiles) {
            System.out.println("Processing: " + file.getName());
            try {
                parseAndInsert(file);
                moveFile(file,dest);
                System.out.println("Done: " + file.getName());
            } catch (Exception e) {
                System.err.println("Failed on " + file.getName() + ": " + e.getMessage());
            }
        }
            }
    private static void parseAndInsert(File file) throws IOException, SQLException {

        Connection conn = DB.getConnection();
        conn.setAutoCommit(false);

        long fileId = -1;

        try {

            fileId = createFile(conn, file.getName());

            String sql = "{ ? = call insert_cdr(?,?,?,?,?,?,?,?,?) }";

            try (CallableStatement cs = conn.prepareCall(sql);
                 BufferedReader br = new BufferedReader(new FileReader(file))) {

                String line = br.readLine(); // skip header

                while ((line = br.readLine()) != null) {

                    if (line.trim().isEmpty()) continue;

                    String[] p = line.split(",", -1);

                    if (p.length < 7) {
                        throw new IllegalArgumentException("Invalid CSV row: " + line);
                    }

                    // register return value (function return id)
                    cs.registerOutParameter(1, Types.INTEGER);

                    cs.setInt(2, (int) fileId);
                    cs.setString(3, p[0]);
                    cs.setString(4, p[1]);
                    cs.setTimestamp(5, Timestamp.valueOf(p[2]));
                    cs.setInt(6, Integer.parseInt(p[3]));

                    if (p[4].trim().isEmpty())
                        cs.setNull(7, Types.INTEGER);
                    else
                        cs.setInt(7, Integer.parseInt(p[4]));

                    cs.setString(8, p[5]);
                    cs.setString(9, p[6]);

                    if (p.length > 7 && !p[7].trim().isEmpty())
                        cs.setBigDecimal(10, new BigDecimal(p[7]));
                    else
                        cs.setBigDecimal(10, BigDecimal.ZERO);

                    cs.execute();

                    // optional: get inserted id if you need it
                    cs.getInt(1);
                }
            }

            markFileParsed(conn, fileId);

            conn.commit();

        } catch (Exception e) {
            conn.rollback();
            throw e;
        } finally {
            conn.close();
        }
    }
    private static long createFile(Connection conn, String filename) throws SQLException {

        String sql = "INSERT INTO file(filename,parsed_flag) VALUES (?, false) RETURNING id";

        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, filename);

            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                return rs.getLong(1);
            }
        }
    }
    private static void markFileParsed(Connection conn, long fileId) throws SQLException {

        try (PreparedStatement ps = conn.prepareStatement(
                "UPDATE file SET parsed_flag = true WHERE id = ?"
        )) {
            ps.setLong(1, fileId);
            ps.executeUpdate();
        }
    }
        private static void moveFile(File file, File destPath) throws IOException {
                Path sourcePath = file.toPath();
                Path target = destPath.toPath().resolve(file.getName());
                if (Files.exists(target)) {
                    String newName = System.currentTimeMillis() + "_" + file.getName();
                    target = destPath.toPath().resolve(newName);
                }
                Files.move(sourcePath, target, StandardCopyOption.REPLACE_EXISTING);
            System.out.println("Moved to: " + target);
        }
}
