package com.billing.test;

import net.sf.jasperreports.engine.*;
import net.sf.jasperreports.engine.xml.JRXmlLoader;
import java.io.*;

public class TestInvoice {
    public static void main(String[] args) throws Exception {
        System.out.println("Testing invoice.jrxml parsing...");
        try (FileInputStream fis = new FileInputStream("invoice.jrxml")) {
            JasperDesign design = JRXmlLoader.load(fis);
            System.out.println("✓ XML loaded successfully: " + design.getName());
            System.out.println("  Title bands: " + design.getTitle().getHeight());
            System.out.println("  Fields: " + design.getFields().length);
            System.out.println("  Parameters: " + design.getParameters().length);
        }
        System.out.println("Testing compilation...");
        try (FileInputStream fis = new FileInputStream("invoice.jrxml")) {
            JasperReport report = JasperCompileManager.compileReport(fis);
            System.out.println("✓ Compiled successfully: " + report.getName());
        }
        System.out.println("ALL TESTS PASSED");
    }
}