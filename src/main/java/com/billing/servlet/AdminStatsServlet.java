package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@WebServlet("/api/admin/stats")
public class AdminStatsServlet extends BaseServlet {

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            List<Map<String, Object>> stats = DB.executeSelect(
                    "SELECT * FROM get_dashboard_stats()");
            Map<String, Object> result = stats.get(0);

            // Rename fields to match frontend expectations
            Map<String, Object> formatted = new HashMap<>();
            formatted.put("customers", result.get("total_customers"));
            formatted.put("contracts", result.get("active_contracts"));
            formatted.put("cdrs", result.get("total_cdrs"));
            formatted.put("revenue", result.get("total_revenue"));
            formatted.put("pending_bills", result.get("pending_bills"));

            return formatted;
        });
    }
}
