package com.billing.servlet;

import java.io.IOException;
import java.util.List;
import java.util.Map;
import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import com.billing.db.DB;

@WebServlet("/api/admin/audit")
public class AdminAuditServlet extends BaseServlet {
    
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        if (!isAdmin(req)) {
            sendError(resp, 403, "Admin access required");
            return;
        }

        try {
            // Fetch the last 50 rejected CDRs
            String sql = "SELECT r.*, s.name as service_name " +
                        "FROM rejected_cdr r " +
                        "LEFT JOIN service_package s ON r.service_id = s.id " +
                        "ORDER BY r.rejected_at DESC LIMIT 50";
            
            List<Map<String, Object>> rejections = DB.executeSelect(sql);
            sendJson(resp, rejections);
            
        } catch (Exception e) {
            sendError(resp, 500, "Failed to fetch audit log: " + e.getMessage());
        }
    }
}
