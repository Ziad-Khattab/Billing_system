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
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * BillAutomationWorker listens for PostgreSQL notifications and automatically
 * generates JasperReport PDFs for new bills.
 */
public class BillAutomationWorker implements Runnable {
    private static final Logger logger = LoggerFactory.getLogger(BillAutomationWorker.class);

    private static final String OUTPUT_FOLDER = System.getenv("CDR_PROCESSED_PATH") != null 
            ? System.getenv("CDR_PROCESSED_PATH") + "/invoices" 
            : "processed/invoices";

    private static final String REPORT_TEMPLATE = "invoice.jrxml";

    @Override
    public void run() {
        logger.info("Starting BillAutomationWorker...");
        
        File outDir = new File(OUTPUT_FOLDER);
        if (!outDir.exists()) {
            if (!outDir.mkdirs()) {
                logger.warn("Could not create output folder: {}", OUTPUT_FOLDER);
            }
        }

        String url = DB.getEnvOrProp("DB_URL", "db.url");
        String user = DB.getEnvOrProp("DB_USER", "db.user");
        String pass = DB.getEnvOrProp("DB_PASSWORD", "db.password");

        try (Connection conn = java.sql.DriverManager.getConnection(url, user, pass)) {
            PGConnection pgConn = conn.unwrap(PGConnection.class);

            try (Statement stmt = conn.createStatement()) {
                stmt.execute("LISTEN generate_bill_event");
                logger.info("Listening for 'generate_bill_event' (Direct Connection)...");
            }

            int heartbeatCount = 0;
            while (!Thread.currentThread().isInterrupted()) {
                PGNotification[] notifications = pgConn.getNotifications(5000);

                if (heartbeatCount++ % 12 == 0) {
                    logger.debug("Heartbeat: Worker is still listening...");
                }

                if (notifications != null) {
                    for (PGNotification notification : notifications) {
                        handleNotification(notification, conn);
                    }
                }
            }
            }
        } catch (Exception e) {
            logger.error("Worker crashed: {}", e.getMessage(), e);
        }
    }

    private void handleNotification(PGNotification notification, Connection conn) {
        try {
            int billId = Integer.parseInt(notification.getParameter());
            logger.info("New Bill Event: ID {}", billId);
            generatePdf(billId, conn);
        } catch (Exception e) {
            logger.error("Error handling notification: {}", e.getMessage());
        }
    }

    private void generatePdf(int billId, Connection conn) {
        try {
            String pdfPath = OUTPUT_FOLDER + "/Bill_" + billId + ".pdf";
            
            JasperReport jasperReport = com.billing.util.JasperLoader.getReport(REPORT_TEMPLATE);
            
            Map<String, Object> params = new HashMap<>();
            params.put("BILL_ID", billId);
            
            InputStream logoStream = com.billing.util.JasperLoader.getResourceStream("logo.svg");
            params.put("LOGO_PATH", logoStream);
            
            params.put("GROUP_NAME", "FMRZ Telecom Group");
            params.put("COMPANY_CARE", "111 (Free from FMRZ)");
            params.put("COMPANY_WEB", "www.fmrz-telecom.com");
            params.put("COMPANY_EMAIL", "support@fmrz-telecom.com");

            // Load Icons
            params.put("VOICE_ICON", com.billing.util.JasperLoader.getResourceStream("Pictures/voice.svg"));
            params.put("DATA_ICON", com.billing.util.JasperLoader.getResourceStream("Pictures/data.svg"));
            params.put("SMS_ICON", com.billing.util.JasperLoader.getResourceStream("Pictures/sms.svg"));

            JasperPrint print = JasperFillManager.fillReport(jasperReport, params, conn);
            JasperExportManager.exportReportToPdfFile(print, pdfPath);
            logger.info("PDF generated: {}", pdfPath);

            try (PreparedStatement pstmt = conn.prepareStatement(
                    "INSERT INTO invoice (bill_id, pdf_path) VALUES (?, ?) " +
                    "ON CONFLICT (bill_id) DO UPDATE SET pdf_path = EXCLUDED.pdf_path")) {
                pstmt.setInt(1, billId);
                pstmt.setString(2, pdfPath);
                pstmt.executeUpdate();
                logger.info("Invoice table updated for Bill {}", billId);
            }

        } catch (Exception e) {
            logger.error("Jasper generation failed for Bill {}: {}", billId, e.getMessage(), e);
        }
    }
}
