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
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class Main {
    private static final Logger logger = LoggerFactory.getLogger(Main.class);
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
        File bDirFile = new File(baseDir);
        if (!bDirFile.exists()) {
            if (!bDirFile.mkdirs()) {
                logger.warn("Could not create Tomcat base directory: {}", baseDir);
            }
        }
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
            if (!webappFile.mkdirs()) {
                logger.warn("Could not create docbase directory: {}", webappFile.getAbsolutePath());
            }
        }
        
        StandardContext ctx = (StandardContext) tomcat.addWebapp("", webappFile.getAbsolutePath());
        
        // 3. Best Practice: RemoteIpValve for Nginx Reverse Proxy
        RemoteIpValve valve = new RemoteIpValve();
        valve.setRemoteIpHeader("X-Forwarded-For");
        valve.setProtocolHeader("X-Forwarded-Proto");
        ctx.getPipeline().addValve(valve);

        // --- WELCOME FILES: Serve index.html for root ---
        ctx.addWelcomeFile("index.html");

        // FIX: Shaded JAR Support
        File additionWebInfClasses = new File("target/classes");
        String jarPath = Main.class.getProtectionDomain().getCodeSource().getLocation().getPath();
        File jarFile = new File(jarPath);
        
        WebResourceRoot resources = new StandardRoot(ctx);
        if (additionWebInfClasses.exists()) {
            resources.addPreResources(new DirResourceSet(resources, "/WEB-INF/classes",
                    additionWebInfClasses.getAbsolutePath(), "/"));
            logger.info("Mapping resources from IDE path: {}", additionWebInfClasses.getAbsolutePath());
        } else if (jarFile.isFile() && jarFile.getName().endsWith(".jar")) {
            resources.addJarResources(new JarResourceSet(resources, "/WEB-INF/classes",
                    jarFile.getAbsolutePath(), "/"));
            logger.info("Mapping resources from Dynamic JAR: {}", jarFile.getAbsolutePath());
        }

        // UNIVERSAL FIX: Always prioritize the filesystem 'webapp' folder if it exists
        if (webappFile.exists() && webappFile.isDirectory()) {
            resources.addPreResources(new DirResourceSet(resources, "/",
                    webappFile.getAbsolutePath(), "/"));
            logger.info("✔ Prioritizing filesystem webapp: {}", webappFile.getAbsolutePath());
        }
        
        // FIX: Increase cache size to avoid "insufficient free space" warnings
        resources.setCacheMaxSize(100 * 1024); // 100MB
        
        // --- SPA FALLBACK: If a file isn't found, serve index.html (for client-side routing) ---
        org.apache.tomcat.util.descriptor.web.ErrorPage spaFallback = new org.apache.tomcat.util.descriptor.web.ErrorPage();
        spaFallback.setErrorCode(404);
        spaFallback.setLocation("/index.html");
        ctx.addErrorPage(spaFallback);

        ctx.setResources(resources);

        logger.info("Configuring app with docbase: {}", webappFile.getAbsolutePath());

        tomcat.getConnector(); // Initialize the connector
        tomcat.start();

        // 6. AUTOMATION: Start Billing Automation Worker
        // This listens for DB events to generate invoices in the background.
        new Thread(new com.billing.automation.BillAutomationWorker()).start();

        // 4. PRODUCTION: Graceful Shutdown Hook
        // Ensures the DB pool is closed and Tomcat stops cleanly.
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            logger.info("SHUTDOWN: Stopping FMRZ Billing System...");
            try {
                com.billing.db.DB.closePool();
                tomcat.stop();
                logger.info("SHUTDOWN: System stopped gracefully.");
            } catch (Exception e) {
                logger.error("Error during graceful shutdown", e);
            }
        }));

        // 5. OBSERVABILITY: Health Check Endpoint
        registerServlet(ctx, "HealthCheck", new jakarta.servlet.http.HttpServlet() {
            @Override
            protected void doGet(jakarta.servlet.http.HttpServletRequest req, 
                                jakarta.servlet.http.HttpServletResponse resp) throws java.io.IOException {
                resp.setContentType("application/json");
                resp.setCharacterEncoding("UTF-8");
                try (java.sql.Connection ignored = com.billing.db.DB.getConnection()) {
                    resp.setStatus(200);
                    resp.getWriter().write("{\"status\":\"UP\", \"database\":\"CONNECTED\"}");
                } catch (Exception e) {
                    resp.setStatus(503);
                    resp.getWriter().write("{\"status\":\"DOWN\", \"error\":\"" + e.getMessage() + "\"}");
                }
            }
        }, "/health", "/health/*");

        // 6. BULLETPROOF REGISTRATION: Manually register all servlets to bypass scanning issues in IDE
        registerServlet(ctx, "AuthServlet", new com.billing.servlet.AuthServlet(), "/api/auth/*");
        registerServlet(ctx, "AdminCDRServlet", new com.billing.servlet.AdminCDRServlet(), "/api/admin/cdr/*");
        registerServlet(ctx, "AdminBillServlet", new com.billing.servlet.AdminBillServlet(), "/api/admin/bills/*");
        registerServlet(ctx, "AdminAuditServlet", new com.billing.servlet.AdminAuditServlet(), "/api/admin/audit/*");
        registerServlet(ctx, "AdminContractServlet", new com.billing.servlet.AdminContractServlet(), "/api/admin/contracts/*");
        registerServlet(ctx, "AdminUserServlet", new com.billing.servlet.AdminUserServlet(), "/api/admin/users/*");
        registerServlet(ctx, "AdminStatsServlet", new com.billing.servlet.AdminStatsServlet(), "/api/admin/stats/*");
        registerServlet(ctx, "AdminRatePlanServlet", new com.billing.servlet.AdminRatePlanServlet(), "/api/admin/rateplans/*");
        registerServlet(ctx, "AdminServicePkgServlet", new com.billing.servlet.AdminServicePkgServlet(), "/api/admin/service-packages/*");
        registerServlet(ctx, "AdminAddonServlet", new com.billing.servlet.AdminAddonServlet(), "/api/admin/addons/*");
        registerServlet(ctx, "PublicServlet", new com.billing.servlet.PublicServlet(), "/api/public/*");
        registerServlet(ctx, "CustomerProfileServlet", new com.billing.servlet.CustomerProfileServlet(), "/api/customer/*");

        logger.info("FMRZ Billing System started on port {}", webPort);
        logger.info("Health Check: http://localhost:{}/health", webPort);
        tomcat.getServer().await();
    }

    private static void registerServlet(StandardContext ctx, String name, jakarta.servlet.Servlet servlet, String... mappings) {
        Tomcat.addServlet(ctx, name, servlet);
        for (String mapping : mappings) {
            ctx.addServletMappingDecoded(mapping, name);
        }
        logger.info("Registered Servlet: {} at {}", name, java.util.Arrays.toString(mappings));
    }
}
