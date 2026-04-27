package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import java.util.Map;

// Public endpoints — no auth required. For browsing packages before signing up.
@WebServlet("/api/public/*")
public class PublicServlet extends BaseServlet {

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        String path = req.getPathInfo();

        if (path == null || "/".equals(path) || path.startsWith("/rateplans")) {
            // GET /api/public/rateplans
            String sub = path != null ? path.replace("/rateplans", "") : "";
            if (sub.isEmpty() || "/".equals(sub)) {
                handle(res, () -> DB.executeSelect("SELECT * FROM get_all_rateplans()"));
            } else {
                // GET /api/public/rateplans/3
                handle(res, () -> {
                    int id = Integer.parseInt(sub.substring(1));
                    List<Map<String, Object>> plan = DB.executeSelect("SELECT * FROM get_rateplan_by_id(?)", id);
                    if (plan.isEmpty()) throw new RuntimeException("Rate plan not found");
                    return plan.get(0);
                });
            }
        } else if (path.startsWith("/service-packages")) {
            // GET /api/public/service-packages
            handle(res, () -> DB.executeSelect("SELECT * FROM get_all_service_packages()"));
        } else {
            sendError(res, 404, "Not found");
        }
    }
}
