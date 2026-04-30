package com.billing.test;

import net.sf.jasperreports.engine.*;
import com.billing.db.DB;
import java.io.*;
import java.sql.Connection;
import java.util.HashMap;
import java.util.Map;

public class TestJasper {
    public static void main(String[] args) {
        try {
            System.out.println("🚀 Starting Jasper Test with invoice.jrxml...");
            int billId = (args.length > 0) ? Integer.parseInt(args[0]) : 1;
            System.out.println("📄 Testing with Bill ID: " + billId);
            
            InputStream stream = TestJasper.class.getResourceAsStream("/invoice.jrxml");
            if (stream == null) throw new RuntimeException("Resource not found: /invoice.jrxml");

            JasperReport report;
            try {
                report = JasperCompileManager.compileReport(stream);
                System.out.println("✔ Report compiled successfully!");
            } catch (Exception e) {
                System.err.println("❌ Compilation Error: " + e.getMessage());
                e.printStackTrace();
                return;
            }

            InputStream logoStream = TestJasper.class.getResourceAsStream("/red-logo.png");
            if (logoStream != null) {
                System.out.println("✔ red-logo.png found successfully.");
            }

            Map<String, Object> params = new HashMap<>();
            params.put("BILL_ID", billId);
            params.put("LOGO_PATH", logoStream);
            params.put("GROUP_NAME", "FMRZ Telecom Group");

            System.out.println("⏳ Filling report...");
            try (Connection conn = DB.getConnection()) {
                JasperPrint print = JasperFillManager.fillReport(report, params, conn);
                System.out.println("✔ Report filled successfully!");

                System.out.println("💾 Exporting to PDF...");
                JasperExportManager.exportReportToPdfFile(print, "test_invoice.pdf");
                System.out.println("🎉 PDF generated: test_invoice.pdf");
            }

        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
