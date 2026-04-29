package com.billing.servlet;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.MultipartConfig;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.Part;
import java.io.File;
import java.io.IOException;
import java.util.Map;
import com.billing.db.DB;

@WebServlet("/api/admin/cdr/upload")
@MultipartConfig(
    fileSizeThreshold = 1024 * 1024 * 2, // 2MB
    maxFileSize = 1024 * 1024 * 10,      // 10MB
    maxRequestSize = 1024 * 1024 * 50   // 50MB
)
public class AdminCDRUploadServlet extends BaseServlet {

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws ServletException, IOException {
        if (!isAdmin(req)) {
            sendError(res, 403, "Admin privileges required");
            return;
        }

        try {
            Part filePart = req.getPart("file");
            if (filePart == null) {
                sendError(res, 400, "No file part found in request");
                return;
            }

            String fileName = filePart.getSubmittedFileName();
            if (fileName == null || !fileName.toLowerCase().endsWith(".csv")) {
                sendError(res, 400, "Only CSV files are allowed");
                return;
            }

            // Get the input path from DB/Environment
            String inputPath = DB.getProperty("cdr.input.path");
            if (inputPath == null || inputPath.isEmpty()) {
                inputPath = "input"; // Fallback to local 'input' folder
            }

            File inputDir = new File(inputPath);
            if (!inputDir.exists()) {
                inputDir.mkdirs();
            }

            // Save the file
            File targetFile = new File(inputDir, fileName);
            filePart.write(targetFile.getAbsolutePath());

            logger.info("Uploaded CDR file: {} to {}", fileName, targetFile.getAbsolutePath());

            sendJson(res, Map.of(
                "success", true,
                "message", "File uploaded successfully: " + fileName,
                "path", targetFile.getAbsolutePath()
            ));

        } catch (Exception e) {
            logger.error("Upload failed", e);
            sendError(res, 500, "Upload failed: " + e.getMessage());
        }
    }
}
