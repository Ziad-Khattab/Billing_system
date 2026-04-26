package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import java.util.Map;

@WebServlet("/api/admin/bills/*")
public class AdminBillServlet extends BaseServlet {

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            String pathParam = getPathParam(req);
            if ("missing".equals(pathParam)) {
                return DB.executeSelect("SELECT * FROM get_missing_bills()");
            }
            if (pathParam != null) {
                return DB.executeSelect("SELECT * FROM bill WHERE id = ?", Integer.parseInt(pathParam)).get(0);
            }

            String contractId = req.getParameter("contractId") != null ? req.getParameter("contractId") : req.getParameter("contract_id");
            
            String sql = "SELECT b.*, cust.name as customer_name, c.msisdn " +
                         "FROM bill b " +
                         "JOIN contract c ON b.contract_id = c.id " +
                         "JOIN customer cust ON c.customer_id = cust.id ";

            if (contractId != null) {
                return DB.executeSelect(sql + " WHERE b.contract_id = ? ORDER BY b.billing_period_start DESC", Integer.parseInt(contractId));
            } else {
                return DB.executeSelect(sql + " ORDER BY b.billing_date DESC LIMIT 50");
            }
        });
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            String pathParam = getPathParam(req);
            if ("generate".equals(pathParam)) {
                DB.executeSelect("SELECT generate_all_bills(DATE_TRUNC('month', CURRENT_DATE)::DATE)");
                return Map.of("success", true, "message", "Billing cycle generated successfully.");
            }
            throw new RuntimeException("Invalid action: " + pathParam);
        });
    }
}
