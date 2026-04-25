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
                    "SELECT * FROM get_user_data(?)", userId);
                if (profile.isEmpty()) sendError(res, 404, "User not found");
                else sendJson(res, profile.get(0));
            } 
             else if ("/contracts".equals(path)) {
                 List<Map<String, Object>> list = DB.executeSelect(
                     "SELECT * FROM get_user_contracts(?)", userId);
                 sendJson(res, list);
            }
            else if ("/invoices".equals(path)) {
                List<Map<String, Object>> list = DB.executeSelect(
                    "SELECT * FROM get_user_invoices(?)", userId);
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
