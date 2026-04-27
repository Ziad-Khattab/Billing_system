package com.billing.automation;

import com.billing.db.DB;
import net.sf.jasperreports.engine.*;
import org.postgresql.PGConnection;
import org.postgresql.PGNotification;

import java.io.File;
import java.io.InputStream;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.Statement;
import java.util.HashMap;
import java.util.Map;

/**
 * BillAutomationWorker listens for PostgreSQL notifications and automatically
 * generates JasperReport PDFs for new bills.
 * 
 * Integrated from R0qiia's logic with production path fixes.
 */
public class BillAutomationWorker implements Runnable {

    // Use environment variable for output path, default to /app/processed/invoices
    private static final String OUTPUT_FOLDER = System.getenv("CDR_PROCESSED_PATH") != null 
            ? System.getenv("CDR_PROCESSED_PATH") + "/invoices" 
            : "processed/invoices";

    private static final String REPORT_TEMPLATE = "invoice.jrxml";

    @Override
    public void run() {
        System.out.println("🚀 [Automation] Starting BillAutomationWorker...");
        
        // Ensure output directory exists
        new File(OUTPUT_FOLDER).mkdirs();

        // For LISTEN/NOTIFY, we should ideally use a dedicated non-pooled connection.
        // We'll fetch the credentials from the environment.
        String url = System.getenv("DB_URL");
        if (url != null && url.contains("-pooler")) {
            url = url.replace("-pooler", "");
            System.out.println("ℹ [Automation] Using direct connection (no-pooler) for LISTEN/NOTIFY.");
        }
        String user = System.getenv("DB_USER");
        String pass = System.getenv("DB_PASSWORD");

        try (Connection conn = java.sql.DriverManager.getConnection(url, user, pass)) {
            // Unwrap PostgreSQL connection to access LISTEN/NOTIFY features
            PGConnection pgConn = conn.unwrap(PGConnection.class);

            try (Statement stmt = conn.createStatement()) {
                stmt.execute("LISTEN generate_bill_event");
                System.out.println("✔ [Automation] Listening for 'generate_bill_event' (Direct Connection)...");
            }

            int heartbeatCount = 0;
            while (!Thread.currentThread().isInterrupted()) {
                // Poll for notifications every 5 seconds
                PGNotification[] notifications = pgConn.getNotifications(5000);

                if (heartbeatCount++ % 12 == 0) { // Every minute
                    System.out.println("💓 [Automation] Heartbeat: Worker is still listening...");
                }

                if (notifications != null) {
                    for (PGNotification notification : notifications) {
                        handleNotification(notification, conn);
                    }
                }
            }
        } catch (Exception e) {
            System.err.println("❌ [Automation] Worker crashed: " + e.getMessage());
            e.printStackTrace();
        }
    }

    private void handleNotification(PGNotification notification, Connection conn) {
        try {
            int billId = Integer.parseInt(notification.getParameter());
            System.out.println("📩 [Automation] New Bill Event: ID " + billId);
            
            generatePdf(billId, conn);
            
        } catch (NumberFormatException e) {
            System.err.println("⚠️ [Automation] Invalid notification parameter: " + notification.getParameter());
        } catch (Exception e) {
            System.err.println("❌ [Automation] Error handling notification: " + e.getMessage());
        }
    }

    private void generatePdf(int billId, Connection conn) {
        try {
            String pdfPath = OUTPUT_FOLDER + "/Bill_" + billId + ".pdf";
            
            // Load template from classpath (src/main/resources)
            InputStream reportStream = getClass().getClassLoader().getResourceAsStream(REPORT_TEMPLATE);
            if (reportStream == null) {
                throw new RuntimeException("Report template " + REPORT_TEMPLATE + " not found in classpath!");
            }

            // Compile on the fly (Integrated with USER's theme)
            JasperReport jasperReport = JasperCompileManager.compileReport(reportStream);

            // Set parameters
            Map<String, Object> params = new HashMap<>();
            params.put("BILL_ID", billId);

            // Fill report
            JasperPrint print = JasperFillManager.fillReport(jasperReport, params, conn);

            // Export to PDF
            JasperExportManager.exportReportToPdfFile(print, pdfPath);
            System.out.println("✅ [Automation] PDF generated: " + pdfPath);

            // Optional: Register the generated file path back to the DB
            try (PreparedStatement pstmt = conn.prepareStatement(
                    "UPDATE bill SET invoice_path = ? WHERE id = ?")) {
                pstmt.setString(1, pdfPath);
                pstmt.setInt(2, billId);
                pstmt.executeUpdate();
                System.out.println("💾 [Automation] DB updated with invoice path for Bill " + billId);
            }

        } catch (Exception e) {
            System.err.println("❌ [Automation] Jasper generation failed for Bill " + billId + ": " + e.getMessage());
            e.printStackTrace();
        }
    }
}
