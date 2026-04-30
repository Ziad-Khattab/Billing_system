package com.billing.util;

import net.sf.jasperreports.engine.JasperCompileManager;
import java.io.File;
import java.io.FileInputStream;

public class DebugJasper {
    public static void main(String[] args) {
        String fileName = (args.length > 0) ? args[0] : "invoice.jrxml";
        String filePath = "/app/" + fileName;
        System.out.println("🚀 DEBUG (v5): Attempting to compile " + filePath);
        
        File f = new File(filePath);
        if (!f.exists()) {
            System.err.println("❌ ERROR: File not found at " + filePath);
            System.exit(1);
        }
        
        try (FileInputStream is = new FileInputStream(f)) {
            System.out.println("🔍 TESTING: Standard JDK DocumentBuilder parsing...");
            javax.xml.parsers.DocumentBuilderFactory factory = javax.xml.parsers.DocumentBuilderFactory.newInstance();
            factory.setNamespaceAware(true);
            javax.xml.parsers.DocumentBuilder builder = factory.newDocumentBuilder();
            builder.parse(is);
            System.out.println("✅ SUCCESS: Standard JDK parsing works!");
        } catch (Exception e) {
            System.err.println("❌ FAILED: Standard JDK parsing failed!");
            e.printStackTrace();
        }

        try (FileInputStream is = new FileInputStream(f)) {
            byte[] bytes = is.readAllBytes();
            System.out.println("📜 FILE CONTENT LENGTH: " + bytes.length);
            
            try (java.io.ByteArrayInputStream bais = new java.io.ByteArrayInputStream(bytes)) {
                JasperCompileManager.compileReport(bais);
                System.out.println("✅ SUCCESS: Jasper compilation works!");
            }
        } catch (Exception e) {
            System.err.println("❌ FAILED: Compilation failed!");
            e.printStackTrace();
            System.exit(1);
        }
    }
}
