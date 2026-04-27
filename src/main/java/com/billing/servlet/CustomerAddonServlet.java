package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import java.util.Map;

@WebServlet("/api/customer/addons/*")
public class CustomerAddonServlet extends BaseServlet {

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            Map<String, Object> user = (Map<String, Object>)
                    req.getSession().getAttribute("user");
            if (user == null) throw new RuntimeException("Not logged in");

            int userId = ((Number) user.get("id")).intValue();

            // Get customer's contract id
            List<Map<String, Object>> contracts = DB.executeSelect(
                    "SELECT id FROM contract WHERE user_account_id = ? AND status = 'active'",
                    userId);
            if (contracts.isEmpty()) throw new RuntimeException("No active contract found");

            int contractId = ((Number) contracts.get(0).get("id")).intValue();

            // GET /api/customer/addons/available → packages not yet purchased
            String path = req.getPathInfo();
            if ("/available".equals(path)) {
                return DB.executeSelect(
                        "SELECT sp.* FROM service_package sp " +
                                "WHERE sp.id NOT IN ( " +
                                "    SELECT service_package_id FROM contract_addon " +
                                "    WHERE contract_id = ? AND is_active = TRUE " +
                                ") ORDER BY sp.type, sp.name",
                        contractId);
            }

            // GET /api/customer/addons → active add-ons
            return DB.executeSelect(
                    "SELECT * FROM get_contract_addons(?)", contractId);
        });
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            Map<String, Object> user = (Map<String, Object>)
                    req.getSession().getAttribute("user");
            if (user == null) throw new RuntimeException("Not logged in");

            int userId = ((Number) user.get("id")).intValue();
            Map<String, Object> body = readJson(req);
            String path = req.getPathInfo();

            // POST /api/customer/addons/cancel
            if ("/cancel".equals(path)) {
                int addonId = ((Number) body.get("addonId")).intValue();
                DB.executeUpdate("SELECT cancel_addon(?)", addonId);
                return Map.of("success", true, "message", "Add-on cancelled.");
            }

            // POST /api/customer/addons → purchase
            int servicePackageId = ((Number) body.get("servicePackageId")).intValue();

            // Get customer's active contract
            List<Map<String, Object>> contracts = DB.executeSelect(
                    "SELECT id FROM contract WHERE user_account_id = ? AND status = 'active'",
                    userId);
            if (contracts.isEmpty()) throw new RuntimeException("No active contract found");

            int contractId = ((Number) contracts.get(0).get("id")).intValue();

            List<Map<String, Object>> result = DB.executeSelect(
                    "SELECT purchase_addon(?, ?) AS id",
                    contractId, servicePackageId);

            int addonId = ((Number) result.get(0).get("id")).intValue();
            return Map.of(
                    "success",  true,
                    "addonId",  addonId,
                    "message",  "Add-on purchased successfully."
            );
        });
    }
}