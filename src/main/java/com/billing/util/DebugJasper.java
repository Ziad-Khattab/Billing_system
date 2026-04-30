package com.billing.util;

import net.sf.jasperreports.engine.JasperCompileManager;
import java.io.File;
import java.io.FileInputStream;

public class DebugJasper {
    public static void main(String[] args) {
        String fileName = (args.length > 0) ? args[0] : "invoice.jrxml";
        String filePath = "/app/" + fileName;
        System.out.println("🚀 DEBUG: Attempting to compile " + filePath);
        
        File f = new File(filePath);
        if (!f.exists()) {
            System.err.println("❌ ERROR: File not found at " + filePath);
            System.exit(1);
        }
        
        try (FileInputStream is = new FileInputStream(f)) {
            byte[] bytes = is.readAllBytes();
            String content = new String(bytes, java.nio.charset.StandardCharsets.UTF_8);
            System.out.println("📜 FILE CONTENT START:\n" + content + "\n📜 FILE CONTENT END");
            
            try (java.io.ByteArrayInputStream bais = new java.io.ByteArrayInputStream(bytes)) {
                JasperCompileManager.compileReport(bais);
                System.out.println("✅ SUCCESS: Report compiled successfully!");
            }
        } catch (Exception e) {
            System.err.println("❌ FAILED: Compilation failed!");
            e.printStackTrace();
            System.exit(1);
        }
    }
}
