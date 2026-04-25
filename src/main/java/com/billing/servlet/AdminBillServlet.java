package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import java.util.Map;

// Maps this servlet to /api/admin/bills and any sub-paths (like /api/admin/bills/5)
@WebServlet("/api/admin/bills/*")
public class AdminBillServlet extends BaseServlet {

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            String pathParam = getPathParam(req);
            if (pathParam != null) {
                return DB.executeSelect("SELECT * FROM bill WHERE id = ?", Integer.parseInt(pathParam)).get(0);
            }

            String contractId = req.getParameter("contractId") != null ? req.getParameter("contractId") : req.getParameter("contract_id");
            
            String sql = "SELECT b.*, u.name as customer_name, c.msisdn " +
                         "FROM bill b " +
                         "JOIN contract c ON b.contract_id = c.id " +
                         "JOIN user_account u ON c.user_account_id = u.id ";

            if (contractId != null) {
                return DB.executeSelect(sql + " WHERE b.contract_id = ? ORDER BY b.billing_period_start DESC", Integer.parseInt(contractId));
            } else {
                return DB.executeSelect(sql + " ORDER BY b.billing_date DESC LIMIT 50");
            }
        });
    }
}
