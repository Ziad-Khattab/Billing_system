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
                String search = req.getParameter("search");
                int limit = getIntParam(req, "limit", 50);
                int offset = getIntParam(req, "offset", 0);
                
                List<Map<String, Object>> list = DB.executeSelect("SELECT * FROM get_missing_bills(?, ?, ?)", search, limit, offset);
                long total = 0;
                if (!list.isEmpty()) {
                    total = ((Number) list.get(0).get("total_count")).longValue();
                }
                return Map.of("data", list, "total", total);
            }
            if (pathParam != null && pathParam.matches("\\d+")) {
                return DB.executeSelect("SELECT * FROM bill WHERE id = ?", Integer.parseInt(pathParam)).get(0);
            }

            String contractId = req.getParameter("contractId") != null ? req.getParameter("contractId") : req.getParameter("contract_id");
            String search = req.getParameter("search");
            int limit = getIntParam(req, "limit", 50);
            int offset = getIntParam(req, "offset", 0);

            if (contractId != null) {
                // If filtering by contract, we can still use get_all_bills logic or specific contract search
                // For simplicity and consistency, let's use a search filter on the msisdn or contract_id if possible
                // But get_all_bills is more robust for general list.
                // Let's use get_all_bills with the contractId as search or specific query
                return DB.executeSelect("SELECT b.*, ua.name as customer_name, c.msisdn FROM bill b JOIN contract c ON b.contract_id = c.id JOIN user_account ua ON c.user_account_id = ua.id WHERE b.contract_id = ? ORDER BY b.billing_period_start DESC", Integer.parseInt(contractId));
            } else {
                List<Map<String, Object>> list = DB.executeSelect("SELECT * FROM get_all_bills(?, ?, ?)", search, limit, offset);
                long total = 0;
                if (!list.isEmpty()) {
                    total = ((Number) list.get(0).get("total_count")).longValue();
                }
                return Map.of("data", list, "total", total);
            }
        });
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            String pathParam = getPathParam(req);
            if ("generate".equals(pathParam)) {
                String contractIdStr = req.getParameter("contractId");
                if (contractIdStr != null) {
                    DB.executeSelect("SELECT generate_bill(?::INT, DATE_TRUNC('month', CURRENT_DATE)::DATE)", Integer.parseInt(contractIdStr));
                    return Map.of("success", true, "message", "Bill generated for contract #" + contractIdStr);
                }
                DB.executeSelect("SELECT generate_all_bills(DATE_TRUNC('month', CURRENT_DATE)::DATE)");
                return Map.of("success", true, "message", "Billing cycle generated successfully.");
            }
            if ("generate-bulk".equals(pathParam)) {
                String global = req.getParameter("global");
                String search = req.getParameter("search");
                if ("true".equals(global)) {
                    // This uses the same search logic as get_missing_bills but triggers generation
                    // We can call a stored procedure or just loop (sp is safer for performance)
                    DB.executeCall("generate_bulk_missing", search);
                    return Map.of("success", true, "message", "Global generation triggered.");
                }
                return Map.of("success", false, "message", "Only global bulk generation supported via this endpoint currently.");
            }
            if ("pay".equals(pathParam)) {
                String billId = req.getParameter("billId");
                DB.executeUpdate("UPDATE bill SET is_paid = true, status = 'paid' WHERE id = ?", Integer.parseInt(billId));
                return Map.of("success", true, "message", "Bill #" + billId + " marked as paid.");
            }
            if ("pay-bulk".equals(pathParam)) {
                String global = req.getParameter("global");
                String search = req.getParameter("search");
                
                if ("true".equals(global)) {
                    // Optimized Global Update: Direct join to avoid subquery issues
                    String sql = "UPDATE bill b SET is_paid = true, status = 'paid' " +
                                 "FROM contract c JOIN user_account ua ON c.user_account_id = ua.id " +
                                 "WHERE b.contract_id = c.id AND b.status != 'paid' " +
                                 "AND (? IS NULL OR ? = '' OR ua.name ILIKE ? OR c.msisdn ILIKE ? OR b.status::text ILIKE ?)";
                    
                    String searchPattern = "%" + (search != null ? search : "") + "%";
                    int count = DB.executeUpdate(sql, search, search, searchPattern, searchPattern, searchPattern);
                    return Map.of("success", true, "message", "Global payment completed for " + count + " bills.", "count", count);
                } else {
                    String ids = req.getParameter("ids");
                    if (ids != null && !ids.isEmpty()) {
                        String[] idArray = ids.split(",");
                        for (String id : idArray) {
                            DB.executeUpdate("UPDATE bill SET is_paid = true, status = 'paid' WHERE id = ?", Integer.parseInt(id));
                        }
                        return Map.of("success", true, "message", "Bulk payment completed for " + idArray.length + " bills.");
                    }
                    return Map.of("success", false, "message", "No IDs provided.");
                }
            }
            throw new RuntimeException("Invalid action: " + pathParam);
        });
    }
}
