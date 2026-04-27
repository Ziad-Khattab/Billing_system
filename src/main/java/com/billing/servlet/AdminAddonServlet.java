package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import java.util.Map;

@WebServlet("/api/admin/addons/*")
public class AdminAddonServlet extends BaseServlet {

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            String path = req.getPathInfo();

            // Get available service packages: GET /api/admin/addons
            if (path == null || "/".equals(path)) {
                return DB.executeSelect("SELECT * FROM service_package ORDER BY name ASC");
            }

            // Get addons for a specific contract: GET /api/admin/addons/{contractId}
            try {
                int contractId = Integer.parseInt(path.substring(1));
                return DB.executeSelect("SELECT * FROM get_contract_addons(?)", contractId);
            } catch (NumberFormatException e) {
                throw new RuntimeException("Invalid contract ID format");
            }
        });
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            Map<String, Object> body = readJson(req);
            
            // Expected body: { contractId, servicePackageId }
            if (!body.containsKey("contractId") || !body.containsKey("servicePackageId")) {
                throw new RuntimeException("Missing contractId or servicePackageId");
            }

            int contractId = ((Number) body.get("contractId")).intValue();
            int servicePackageId = ((Number) body.get("servicePackageId")).intValue();

            // Admins use the same purchase_addon function but we call it on behalf of the customer
            List<Map<String, Object>> result = DB.executeSelect(
                "SELECT purchase_addon(?, ?) AS id",
                contractId, servicePackageId
            );

            int addonId = ((Number) result.get(0).get("id")).intValue();
            return Map.of(
                "success", true,
                "addonId", addonId,
                "message", "Add-on provisioned successfully by Admin."
            );
        });
    }

    @Override
    protected void doDelete(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            String path = req.getPathInfo();
            if (path == null || path.length() < 2) throw new RuntimeException("Add-on ID required");
            
            int addonId = Integer.parseInt(path.substring(1));
            DB.executeUpdate("SELECT cancel_addon(?)", addonId);
            
            return Map.of("success", true, "message", "Add-on terminated by Admin.");
        });
    }
}
