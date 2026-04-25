package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Map;

@WebServlet("/api/admin/stats")
public class AdminStatsServlet extends BaseServlet {

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            long totalCustomers = (long) DB.executeSelect("SELECT COUNT(*) as count FROM user_account WHERE role = 'customer'").get(0).get("count");
            long totalContracts = (long) DB.executeSelect("SELECT COUNT(*) as count FROM contract").get(0).get("count");
            long totalCdrs = (long) DB.executeSelect("SELECT COUNT(*) as count FROM cdr").get(0).get("count");
            
            return Map.of(
                "customers", totalCustomers,
                "contracts", totalContracts,
                "cdrs", totalCdrs
            );
        });
    }
}
