package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@WebServlet("/api/admin/contracts/*")
public class AdminContractServlet extends BaseServlet {

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            String path = req.getPathInfo();
            
            if ("/available-msisdn".equals(path)) {
                String search = req.getParameter("search");
                String msisdn = req.getParameter("msisdn");
                String query = "SELECT msisdn FROM msisdn_pool WHERE is_available = TRUE";
                List<Object> params = new ArrayList<>();
                
                if (search != null && !search.trim().isEmpty()) {
                    query += " AND msisdn ILIKE ?";
                    params.add("%" + search.trim() + "%");
                } else if (msisdn != null && !msisdn.trim().isEmpty()) {
                    query += " AND msisdn = ?";
                    params.add(msisdn.trim());
                }
                
                query += " ORDER BY msisdn LIMIT 50";
                return DB.executeSelect(query, params.toArray());
            }

            if (path == null || "/".equals(path)) {
                String msisdn = req.getParameter("msisdn");
                String search = req.getParameter("search");

                if (msisdn != null && !msisdn.trim().isEmpty()) {
                    String sql = "SELECT c.id, c.msisdn, c.status, c.available_credit as \"availableCredit\", " +
                                 "ua.name as \"customerName\", r.name as \"rateplanName\" " +
                                 "FROM contract c " +
                                 "JOIN user_account ua ON c.user_account_id = ua.id " +
                                 "LEFT JOIN rateplan r ON c.rateplan_id = r.id " +
                                 "WHERE c.msisdn = ? " +
                                 "ORDER BY c.id DESC";
                    return DB.executeSelect(sql, msisdn);
                }
                
                if (search != null && !search.trim().isEmpty()) {
                    String pattern = "%" + search.trim() + "%";
                    String sql = "SELECT c.id, c.msisdn, c.status, " +
                                 "ua.name as \"customerName\", r.name as \"rateplanName\" " +
                                 "FROM contract c " +
                                 "JOIN user_account ua ON c.user_account_id = ua.id " +
                                 "LEFT JOIN rateplan r ON c.rateplan_id = r.id " +
                                 "WHERE c.msisdn ILIKE ? OR ua.name ILIKE ? " +
                                 "ORDER BY ua.name ASC LIMIT 20";
                    return DB.executeSelect(sql, pattern, pattern);
                }
                
                String sql = "SELECT c.id, c.msisdn, c.status, c.available_credit as \"availableCredit\", " +
                             "ua.name as \"customerName\", r.name as \"rateplanName\" " +
                             "FROM contract c " +
                             "JOIN user_account ua ON c.user_account_id = ua.id " +
                             "LEFT JOIN rateplan r ON c.rateplan_id = r.id " +
                             "ORDER BY c.id DESC";
                return DB.executeSelect(sql);
            }
 else {
                int id = Integer.parseInt(path.substring(1));
                String sql = "SELECT c.*, ua.name as \"customerName\", r.name as \"rateplanName\", " +
                             "c.available_credit as \"availableCredit\" " +
                             "FROM contract c " +
                             "JOIN user_account ua ON c.user_account_id = ua.id " +
                             "LEFT JOIN rateplan r ON c.rateplan_id = r.id " +
                             "WHERE c.id = ?";
                List<Map<String, Object>> list = DB.executeSelect(sql, id);
                if (list.isEmpty()) throw new RuntimeException("Contract not found");
                return list.get(0);
            }
        });
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            Map<String, Object> body = readJson(req);
            String msisdn = (String) body.get("msisdn");
            Object userId = body.get("userId");
            Object planId = body.get("planId");
            
            if (msisdn == null || userId == null || planId == null) {
                throw new RuntimeException("Missing required fields: msisdn, userId, or planId");
            }

            Object creditLimit = body.getOrDefault("creditLimit", 1000.0);
            
            // Using teammate's stored function to ensure proper initialization
            DB.executeSelect(
                "SELECT create_contract(?::INT, ?::INT, ?, ?::NUMERIC) as id",
                userId, planId, msisdn, creditLimit
            );
            return Map.of("success", true, "message", "Line provisioned for " + msisdn);
        });
    }
}
