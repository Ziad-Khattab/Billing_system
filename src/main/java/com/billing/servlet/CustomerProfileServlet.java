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

@WebServlet("/api/customer/*")
public class CustomerProfileServlet extends BaseServlet {

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
                    "SELECT b.id, b.billing_date as \"generationDate\", c.msisdn, b.taxes, b.recurring_fees as \"recurringFees\", b.one_time_fees as \"oneTimeFees\" " +
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

                try (InputStream reportStream = getClass().getResourceAsStream("/invoice.jrxml");
                     Connection conn = DB.getConnection()) {
                    
                    Map<String, Object> params = new HashMap<>();
                    params.put("BILL_ID", billId);

                    JasperReport jasperReport = JasperCompileManager.compileReport(reportStream);
                    JasperPrint jasperPrint = JasperFillManager.fillReport(jasperReport, params, conn);
                    JasperExportManager.exportReportToPdfStream(jasperPrint, res.getOutputStream());
                }
            }
            else {
                sendError(res, 404, "Unknown customer endpoint: " + path);
            }
        } catch (Exception e) {
            e.printStackTrace(); // Print to IntelliJ console for you to see
            sendError(res, 500, "Jasper Error: " + e.getMessage() + " (Check console for full trace)");
        }
    }
}
