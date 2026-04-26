package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
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
                    "SELECT u.id, u.username, c.name, c.email, c.address " +
                    "FROM user_account u " +
                    "LEFT JOIN customer c ON u.customer_id = c.id " +
                    "WHERE u.id = ?", userId);
                if (profile.isEmpty()) sendError(res, 404, "User not found");
                else sendJson(res, profile.get(0));
            } 
            else if ("/contracts".equals(path)) {
                List<Map<String, Object>> list = DB.executeSelect(
                    "SELECT c.msisdn, c.status, c.available_credit as \"availableCredit\", r.name as \"rateplanName\" " +
                    "FROM contract c " +
                    "LEFT JOIN rateplan r ON c.rateplan_id = r.id " +
                    "JOIN user_account u ON c.customer_id = u.customer_id " +
                    "WHERE u.id = ?", userId);
                sendJson(res, list);
            }
            else if ("/invoices".equals(path)) {
                List<Map<String, Object>> list = DB.executeSelect(
                    "SELECT b.id, b.billing_date as \"billingDate\", b.taxes, b.recurring_fees as \"recurringFees\", b.one_time_fees as \"oneTimeFees\" " +
                    "FROM bill b " +
                    "JOIN contract c ON b.contract_id = c.id " +
                    "JOIN user_account u ON c.customer_id = u.customer_id " +
                    "WHERE u.id = ? ORDER BY b.billing_date DESC", userId);
                sendJson(res, list);
            }
            else {
                sendError(res, 404, "Unknown customer endpoint: " + path);
            }
        } catch (Exception e) {
            sendError(res, 500, e.getMessage());
        }
    }
}
