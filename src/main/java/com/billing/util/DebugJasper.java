package com.billing.util;

import net.sf.jasperreports.engine.JasperCompileManager;
import java.io.File;
import java.io.FileInputStream;

public class DebugJasper {
    public static void main(String[] args) {
        String filePath = "/app/invoice.jrxml";
        System.out.println("🚀 DEBUG: Attempting to compile " + filePath);
        
        File f = new File(filePath);
        if (!f.exists()) {
            System.err.println("❌ ERROR: File not found at " + filePath);
            System.exit(1);
        }
        
        try (FileInputStream is = new FileInputStream(f)) {
            JasperCompileManager.compileReport(is);
            System.out.println("✅ SUCCESS: Report compiled successfully!");
        } catch (Exception e) {
            System.err.println("❌ FAILED: Compilation failed!");
            e.printStackTrace();
            System.exit(1);
        }
    }
}
