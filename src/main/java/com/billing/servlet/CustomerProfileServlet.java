package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import net.sf.jasperreports.engine.*;
import java.io.IOException;
import java.io.InputStream;
import java.sql.Connection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;

@WebServlet("/api/customer/*")
public class CustomerProfileServlet extends BaseServlet {
    
    private static final Properties config = new Properties();

    static {
        try (InputStream is = CustomerProfileServlet.class.getResourceAsStream("/config.properties")) {
            if (is != null) config.load(is);
        } catch (IOException e) {
            System.err.println("WARNING: Could not load config.properties");
        }
    }

    private static JasperReport cachedReport = null;

    private JasperReport getCachedReport() throws JRException {
        if (cachedReport == null) {
            synchronized (CustomerProfileServlet.class) {
                if (cachedReport == null) {
                    try (InputStream is = getClass().getResourceAsStream("/invoice.jrxml")) {
                        net.sf.jasperreports.engine.JasperReportsContext context = net.sf.jasperreports.engine.DefaultJasperReportsContext.getInstance();
                        net.sf.jasperreports.engine.design.JasperDesign design = net.sf.jasperreports.jackson.util.JacksonUtil.getInstance(context).loadXml(is, net.sf.jasperreports.engine.design.JasperDesign.class);
                        cachedReport = JasperCompileManager.compileReport(design);
                    } catch (IOException e) {
                        throw new JRException("Failed to load invoice.jrxml", e);
                    }
                }
            }
        }
        return cachedReport;
    }

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        String path = req.getPathInfo();
        Map<String, Object> user = (Map<String, Object>) req.getSession().getAttribute("user");
        
        if (user == null) {
            sendError(res, 401, "Not logged in");
            return;
        }
        
        Integer userId = ((Number) user.get("id")).intValue();

        try {
            if ("/profile".equals(path)) {
                List<Map<String, Object>> profile = DB.executeSelect(
                    "SELECT id, username, name, email, address " +
                    "FROM user_account " +
                    "WHERE id = ?", userId);
                if (profile.isEmpty()) sendError(res, 404, "User not found");
                else sendJson(res, profile.get(0));
            } 
            else if ("/contracts".equals(path)) {
                List<Map<String, Object>> list = DB.executeSelect(
                    "SELECT c.msisdn, c.status, c.available_credit as \"availableCredit\", r.name as \"rateplanName\" " +
                    "FROM contract c " +
                    "LEFT JOIN rateplan r ON c.rateplan_id = r.id " +
                    "WHERE c.user_account_id = ?", userId);
                sendJson(res, list);
            }
            else if ("/invoices".equals(path)) {
                List<Map<String, Object>> list = DB.executeSelect(
                    "SELECT b.id, CAST(b.billing_date AS VARCHAR) as \"generationDate\", c.msisdn, " +
                    "b.taxes, b.recurring_fees as \"recurringFees\", b.one_time_fees as \"oneTimeFees\", " +
                    "b.total_amount as \"totalAmount\", b.status " +
                    "FROM bill b " +
                    "JOIN contract c ON b.contract_id = c.id " +
                    "WHERE c.user_account_id = ? ORDER BY b.billing_date DESC", userId);
                sendJson(res, list);
            }
            else if ("/invoices/download".equals(path)) {
                String idParam = req.getParameter("id");
                if (idParam == null) throw new RuntimeException("Invoice ID required");
                int billId = Integer.parseInt(idParam);

                // Verify ownership and get data
                List<Map<String, Object>> bills = DB.executeSelect(
                    "SELECT b.*, ua.name as customer_name, c.msisdn " +
                    "FROM bill b " +
                    "JOIN contract c ON b.contract_id = c.id " +
                    "JOIN user_account ua ON c.user_account_id = ua.id " +
                    "WHERE b.id = ? AND c.user_account_id = ?", billId, userId);

                if (bills.isEmpty()) {
                    sendError(res, 403, "Access denied or invoice not found");
                    return;
                }

                Map<String, Object> bill = bills.get(0);

                // Generate PDF using official template and live DB connection
                res.setContentType("application/pdf");
                res.setHeader("Content-Disposition", "attachment; filename=Invoice_" + billId + ".pdf");

                try (Connection conn = DB.getConnection()) {
                    
                    Map<String, Object> params = new HashMap<>();
                    params.put("BILL_ID", billId);
                    
                    // Safe Stream-based logo loading (Fixed NPE)
                    InputStream logoStream = getClass().getResourceAsStream("/logo.svg");
                    params.put("LOGO_PATH", logoStream);
                    
                    // --- HARDENING: Inject Company Info as Parameters (Loaded from config.properties) ---
                    params.put("GROUP_NAME", config.getProperty("company.name", "FMRZ Telecom Group"));
                    params.put("COMPANY_CARE", config.getProperty("company.care", "+20 101 234 5678"));
                    params.put("COMPANY_WEB", config.getProperty("company.web", "www.fmrz-telecom.com"));
                    params.put("COMPANY_EMAIL", config.getProperty("company.email", "support@fmrz.com"));
                    
                    params.put(JRParameter.REPORT_CLASS_LOADER, getClass().getClassLoader());

                    // --- PERFORMANCE: Use cached report to avoid 2-second compilation delay ---
                    JasperReport jasperReport = getCachedReport();
                    JasperPrint jasperPrint = JasperFillManager.fillReport(jasperReport, params, conn);
                    JasperExportManager.exportReportToPdfStream(jasperPrint, res.getOutputStream());
                }
            }
            else {
                sendError(res, 404, "Unknown customer endpoint: " + path);
            }
        } catch (Throwable e) {
            e.printStackTrace();
            // ... rest of the catch block
            // Clear response and send JSON error
            try {
                if (!res.isCommitted()) {
                    res.reset();
                    sendError(res, 500, "Jasper Error: " + e.getClass().getSimpleName() + " - " + e.getMessage());
                }
            } catch (IOException ex) {
                ex.printStackTrace();
            }
        }
    }
}
