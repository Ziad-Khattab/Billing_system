package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import java.util.Map;

@WebServlet("/api/admin/stats")
public class AdminStatsServlet extends BaseServlet {

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            List<Map<String, Object>> stats = DB.executeSelect("SELECT * FROM get_admin_stats()");
            if (stats.isEmpty()) return Map.of("customers", 0, "contracts", 0, "cdrs", 0, "revenue", 0, "pending_bills", 0);
            return stats.get(0);
        });
    }
}
