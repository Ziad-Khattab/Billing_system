package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.File;
import java.io.IOException;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@WebServlet("/api/admin/cdr/*")
public class AdminCDRServlet extends BaseServlet {
    private static final Logger logger = LoggerFactory.getLogger(AdminCDRServlet.class);

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            int limit = req.getParameter("limit") != null ? Integer.parseInt(req.getParameter("limit")) : 50;
            int offset = req.getParameter("offset") != null ? Integer.parseInt(req.getParameter("offset")) : 0;

            String sql = "SELECT * from get_cdrs(?,?)";
            List<Map<String, Object>> data = DB.executeSelect(sql, limit, offset);
            
            // Get total count for pagination
            List<Map<String, Object>> countResult = DB.executeSelect("SELECT count(*) as total FROM cdr");
            long total = countResult.isEmpty() ? 0 : ((Number) countResult.get(0).get("total")).longValue();

            return Map.of(
                "data", data,
                "total", total
            );
        });
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        try {
            logger.info("CDR-IMPORT Triggered via Admin Panel");
            
            String configInput = DB.getProperty("cdr.input.path");
            String configProcessed = DB.getProperty("cdr.processed.path");

            File inputDir;
            File processedDir;

            if (configInput != null && !configInput.isEmpty()) {
                inputDir = new File(configInput);
                processedDir = new File(configProcessed);
            } else {
                String currentDir = System.getProperty("user.dir");
                if (currentDir.contains("target")) {
                    currentDir = currentDir.substring(0, currentDir.indexOf("target") - 1);
                }
                
                inputDir = new File(currentDir, "input");
                processedDir = new File(currentDir, "processed");

                // Hardening: check parent if root 'input' not found (IDE specific)
                if (!inputDir.exists()) {
                    File parentDir = new File(currentDir).getParentFile();
                    if (parentDir != null) {
                        File altInput = new File(parentDir, "input");
                        if (altInput.exists()) {
                            inputDir = altInput;
                            processedDir = new File(parentDir, "processed");
                        }
                    }
                }
            }

            logger.info("Using Input Path: {}", inputDir.getAbsolutePath());

            if (!inputDir.exists()) {
                throw new IOException("Input directory not found at: " + inputDir.getAbsolutePath());
            }
            if (!processedDir.exists() && !processedDir.mkdirs()) {
                logger.warn("Could not create processed directory: {}", processedDir.getAbsolutePath());
            }


            // Capture file count before processing
            File[] files = inputDir.listFiles((dir, name) -> name.toLowerCase().endsWith(".csv"));
            int fileCount = (files != null) ? files.length : 0;

            com.billing.cdr.CDRParser.processAll(inputDir.getAbsolutePath(), processedDir.getAbsolutePath());
            
            System.out.println("[CDR-IMPORT] Success. Processed " + fileCount + " files.");
            sendJson(res, Map.of(
                "success", true, 
                "message", "Import Complete! Processed " + fileCount + " files.",
                "count", fileCount
            ));
        } catch (Exception e) {
            System.err.println("[CDR-IMPORT] Error: " + e.getMessage());
            sendError(res, 500, "Import failed: " + e.getMessage());
        }
    }
}
