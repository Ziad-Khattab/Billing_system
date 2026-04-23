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

        Integer fileId = -1;

        try {

            String createFile ="{ ? = call create_file_record(?)}" ;
                try (CallableStatement cs = conn.prepareCall(createFile)) {
                    cs.registerOutParameter(1, Types.INTEGER);
                    cs.setString(2, file.getPath());
                    cs.execute();
                    fileId = cs.getInt(1);
                }

            String sql = "{ ? = call insert_cdr(?,?,?,?,?,?,?,?,?) }";

            try (CallableStatement cs = conn.prepareCall(sql);
                 BufferedReader br = new BufferedReader(new FileReader(file))) {

                String line = br.readLine(); // skip header

                while ((line = br.readLine()) != null) {

                    if (line.trim().isEmpty()) continue;

                    String[] p = line.split(",", -1);

                    if (p.length < 9) {
                        throw new IllegalArgumentException("Invalid CSV row: " + line);
                    }

                    // register return value (function return id)
                    cs.registerOutParameter(1, Types.INTEGER);

                    cs.setInt(2, (int) fileId);
                    cs.setString(3, p[1]);
                    cs.setString(4, p[2]);
                    cs.setTimestamp(5, Timestamp.valueOf(p[3]));
                    cs.setInt(6, Integer.parseInt(p[4]));

                    if (p[5].trim().isEmpty())
                        cs.setNull(7, Types.INTEGER);
                    else
                        cs.setInt(7, Integer.parseInt(p[5]));

                    cs.setString(8, p[6]);
                    cs.setString(9, p[7]);

                    if (p.length > 8 && !p[8].trim().isEmpty())
                        cs.setBigDecimal(10, new BigDecimal(p[8]));
                    else
                        cs.setBigDecimal(10, BigDecimal.ZERO);

                    cs.execute();

                    // optional: get inserted id if you need it
                    cs.getInt(1);
                }
            }

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
