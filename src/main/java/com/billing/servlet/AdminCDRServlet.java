package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.File;
import java.io.IOException;
import java.util.List;
import java.util.Map;

@WebServlet("/api/admin/cdr/*")
public class AdminCDRServlet extends BaseServlet {

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            int limit = req.getParameter("limit") != null ? Integer.parseInt(req.getParameter("limit")) : 50;
            int offset = req.getParameter("offset") != null ? Integer.parseInt(req.getParameter("offset")) : 0;

            String sql = "SELECT * from get_cdrs(?,?)";
            
            return DB.executeSelect(sql, limit, offset);
        });
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        try {
            System.out.println("[CDR-IMPORT] Triggered via Admin Panel");
            
            // The most reliable way to find project folders during dev
            String projectRoot = System.getProperty("user.dir");
            File inputDir = new File(projectRoot, "input");
            File processedDir = new File(projectRoot, "processed");

            System.out.println("[CDR-IMPORT] Scanning: " + inputDir.getAbsolutePath());

            if (!inputDir.exists()) {
                throw new IOException("Input directory not found at: " + inputDir.getAbsolutePath());
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
