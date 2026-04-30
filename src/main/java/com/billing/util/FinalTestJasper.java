package com.billing.util;
import net.sf.jasperreports.engine.*;
import com.billing.db.DB;
import java.io.*;
import java.sql.Connection;
import java.util.HashMap;
import java.util.Map;

public class FinalTestJasper {
    public static void main(String[] args) {
        if (args.length < 1) {
            System.out.println("Usage: FinalTestJasper <bill_id>");
            return;
        }
        int billId = Integer.parseInt(args[0]);
        
        // Apply TCCL Hack
        ClassLoader originalClassLoader = Thread.currentThread().getContextClassLoader();
        Thread.currentThread().setContextClassLoader(FinalTestJasper.class.getClassLoader());
        
        try (Connection conn = DB.getConnection()) {
            System.out.println("🚀 Generating Invoice for Bill ID: " + billId);
            
            // Load JRXML from resources
            InputStream jrxml = FinalTestJasper.class.getResourceAsStream("/invoice.jrxml");
            if (jrxml == null) throw new RuntimeException("invoice.jrxml not found!");
            
            JasperReport report = JasperCompileManager.compileReport(jrxml);
            
            Map<String, Object> params = new HashMap<>();
            params.put("BILL_ID", billId);
            params.put("GROUP_NAME", "FMRZ Telecom Group");
            params.put("COMPANY_CARE", "+20 101 234 5678");
            params.put("COMPANY_WEB", "www.fmrz-telecom.com");
            params.put("COMPANY_EMAIL", "support@fmrz.com");
            
            // Logo
            InputStream logo = FinalTestJasper.class.getResourceAsStream("/red-logo.png");
            if (logo != null) params.put("LOGO_PATH", logo);
            
            JasperPrint print = JasperFillManager.fillReport(report, params, conn);
            JasperExportManager.exportReportToPdfFile(print, "Invoice_" + billId + ".pdf");
            
            System.out.println("✅ SUCCESS: Invoice_" + billId + ".pdf generated!");
            System.out.println("📄 SIZE: " + new File("Invoice_" + billId + ".pdf").length() + " bytes");
            
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
            Thread.currentThread().setContextClassLoader(originalClassLoader);
        }
    }
}
