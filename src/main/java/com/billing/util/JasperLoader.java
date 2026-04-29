package com.billing.util;

import net.sf.jasperreports.engine.*;
import net.sf.jasperreports.engine.util.JRLoader;
import net.sf.jasperreports.engine.DefaultJasperReportsContext;
import java.io.InputStream;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * JasperLoader: Optimizes report loading and compilation.
 * Compiles JRXML at runtime in the container to avoid classpath/version issues.
 */
public class JasperLoader {

    private static final Map<String, JasperReport> cache = new ConcurrentHashMap<>();
    
    static {
        // Ensure no display is required for PDF generation
        System.setProperty("java.awt.headless", "true");
    }

    public static JasperReport getReport(String name) throws JRException {
        if (cache.containsKey(name)) return cache.get(name);
        
        // Use Thread Context ClassLoader to ensure extensions are discovered correctly
        ClassLoader originalClassLoader = Thread.currentThread().getContextClassLoader();
        try {
            Thread.currentThread().setContextClassLoader(JasperLoader.class.getClassLoader());
            JasperReport report = loadAndCompile(name);
            cache.put(name, report);
            return report;
        } finally {
            Thread.currentThread().setContextClassLoader(originalClassLoader);
        }
    }

    private static JasperReport loadAndCompile(String name) throws JRException {
        System.out.println("⏳ JasperLoader: Attempting to load " + name);
        
        InputStream is = getResourceStream(name);
        if (is == null) throw new JRException("Report template not found: " + name);

        try {
            if (name.endsWith(".jasper")) {
                return (JasperReport) JRLoader.loadObject(is);
            } else {
                System.out.println("✔ JasperLoader: Compiling .jrxml from stream: " + name);
                return JasperCompileManager.compileReport(is);
            }
        } finally {
            try { is.close(); } catch (Exception e) {}
        }
    }

    public static InputStream getResourceStream(String name) {
        // Try absolute path first (container)
        java.io.File file = new java.io.File("/app/" + name);
        if (file.exists()) {
            try { return new java.io.FileInputStream(file); } catch (Exception e) {}
        }
        
        // Fallback to classpath
        return JasperLoader.class.getClassLoader().getResourceAsStream(name);
    }
}
