package com.billing;

import org.apache.catalina.LifecycleException;
import org.apache.catalina.WebResourceRoot;
import org.apache.catalina.core.StandardContext;
import org.apache.catalina.startup.Tomcat;
import org.apache.catalina.valves.RemoteIpValve;
import org.apache.catalina.webresources.DirResourceSet;
import org.apache.catalina.webresources.JarResourceSet;
import org.apache.catalina.webresources.StandardRoot;

import java.io.File;

public class Main {
    public static void main(String[] args) throws LifecycleException {
        Tomcat tomcat = new Tomcat();
        
        // Use port from environment variable or default to 8080
        String webPort = System.getenv("PORT");
        if (webPort == null || webPort.isEmpty()) {
            webPort = "8080";
        }
        tomcat.setPort(Integer.parseInt(webPort));

        // FIX: In a hardened container, we use /tmp for Tomcat's internal files.
        // This avoids "Permission Denied" errors when running as a non-root user.
        String baseDir = System.getProperty("java.io.tmpdir") + "/tomcat-base." + webPort;
        new File(baseDir).mkdirs();
        tomcat.setBaseDir(baseDir);

        // FIX: The docBase must exist for Tomcat to start. If the source folder is missing (production),
        // we create an empty placeholder directory.
        // UNIVERSAL PATH FIX: Check for production static folder first
        File webappFile = new File("webapp_static");
        if (!webappFile.exists()) {
            webappFile = new File("src/main/webapp");
        }
        
        if (!webappFile.exists()) {
            webappFile = new File(baseDir, "docbase");
            webappFile.mkdirs();
        }
        
        StandardContext ctx = (StandardContext) tomcat.addWebapp("", webappFile.getAbsolutePath());
        
        // 3. Best Practice: RemoteIpValve for Nginx Reverse Proxy
        RemoteIpValve valve = new RemoteIpValve();
        valve.setRemoteIpHeader("X-Forwarded-For");
        valve.setProtocolHeader("X-Forwarded-Proto");
        ctx.getPipeline().addValve(valve);

        // FIX: Shaded JAR Support
        // Tomcat 11 doesn't scan inside a Fat JAR by default. We must manually map the JAR 
        // as a JarResourceSet so that @WebServlet and @WebFilter annotations are discovered.
        File additionWebInfClasses = new File("target/classes");
        
        // Dynamic JAR Detection: Find the path of the currently executing JAR
        String jarPath = Main.class.getProtectionDomain().getCodeSource().getLocation().getPath();
        File jarFile = new File(jarPath);
        
        WebResourceRoot resources = new StandardRoot(ctx);
        if (additionWebInfClasses.exists()) {
            // IDE Mode: Classes are in target/classes
            resources.addPreResources(new DirResourceSet(resources, "/WEB-INF/classes",
                    additionWebInfClasses.getAbsolutePath(), "/"));
            
            System.out.println("Mapping resources from IDE path: " + additionWebInfClasses.getAbsolutePath());
        } else if (jarFile.isFile() && jarFile.getName().endsWith(".jar")) {
            // Production Mode: Classes are inside the JAR. We map the JAR dynamically.
            resources.addJarResources(new JarResourceSet(resources, "/WEB-INF/classes",
                    jarFile.getAbsolutePath(), "/"));
            
            System.out.println("Mapping resources from Dynamic JAR: " + jarFile.getAbsolutePath());
        }

        // UNIVERSAL FIX: Always prioritize the filesystem 'webapp' folder if it exists
        // This ensures Docker containers with externalized webapp folders (via COPY) work correctly.
        if (webappFile.exists() && webappFile.isDirectory()) {
            resources.addPreResources(new DirResourceSet(resources, "/",
                    webappFile.getAbsolutePath(), "/"));
            System.out.println("✔ Prioritizing filesystem webapp: " + webappFile.getAbsolutePath());
        }
        ctx.setResources(resources);

        System.out.println("Configuring app with docbase: " + webappFile.getAbsolutePath());

        tomcat.getConnector(); // Initialize the connector
        tomcat.start();

        // 6. AUTOMATION: Start Billing Automation Worker
        // This listens for DB events to generate invoices in the background.
        new Thread(new com.billing.automation.BillAutomationWorker()).start();

        // 4. PRODUCTION: Graceful Shutdown Hook
        // Ensures the DB pool is closed and Tomcat stops cleanly.
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            System.out.println("SHUTDOWN: Stopping FMRZ Billing System...");
            try {
                com.billing.db.DB.closePool();
                tomcat.stop();
                System.out.println("SHUTDOWN: System stopped gracefully.");
            } catch (Exception e) {
                e.printStackTrace();
            }
        }));

        // 5. OBSERVABILITY: Health Check Endpoint
        // Used by Railway/Podman to monitor if the app and DB are alive.
        Tomcat.addServlet(ctx, "HealthCheck", new jakarta.servlet.http.HttpServlet() {
            @Override
            protected void doGet(jakarta.servlet.http.HttpServletRequest req, 
                                jakarta.servlet.http.HttpServletResponse resp) throws java.io.IOException {
                resp.setContentType("application/json");
                resp.setCharacterEncoding("UTF-8");
                try (java.sql.Connection conn = com.billing.db.DB.getConnection()) {
                    resp.setStatus(200);
                    resp.getWriter().write("{\"status\":\"UP\", \"database\":\"CONNECTED\"}");
                } catch (Exception e) {
                    resp.setStatus(503);
                    resp.getWriter().write("{\"status\":\"DOWN\", \"error\":\"" + e.getMessage() + "\"}");
                }
            }
        });
        ctx.addServletMappingDecoded("/health", "HealthCheck");
        ctx.addServletMappingDecoded("/health/*", "HealthCheck");

        System.out.println("FMRZ Billing System started on port " + webPort);
        System.out.println("Health Check: http://localhost:" + webPort + "/health");
        tomcat.getServer().await();
    }
}
