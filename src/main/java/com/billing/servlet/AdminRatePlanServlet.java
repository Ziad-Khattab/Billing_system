package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import java.util.Map;

@WebServlet("/api/admin/rateplans/*")
public class AdminRatePlanServlet extends BaseServlet {

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        String pathParam = getPathParam(req);
        handle(res, () -> {
            if (pathParam == null) {
                return DB.executeSelect("SELECT * FROM get_all_rateplans()");
            } else {
                int id = Integer.parseInt(pathParam);
                List<Map<String, Object>> list = DB.executeSelect("SELECT * FROM get_rateplan_by_id(?)", id);
                if (list.isEmpty()) throw new RuntimeException("Rate plan not found");
                
                Map<String, Object> plan = list.get(0);
                List<Map<String, Object>> pkgs = DB.executeSelect(
                    "SELECT service_package_id FROM rateplan_service_package WHERE rateplan_id = ?", id
                );

                List<Integer> pkgIds = pkgs.stream()
                    .map(m -> {
                        Object val = m.get("service_package_id");
                        return val != null ? ((Number) val).intValue() : null;
                    })
                    .filter(v -> v != null)
                    .toList();

                plan.put("servicePackageIds", pkgIds);
                return plan;
            }
        });
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            Map body = readJson(req, Map.class);
            List<Object> packageIdsList = (List<Object>) body.get("servicePackageIds");
            Object[] packageIds = packageIdsList != null ? packageIdsList.stream().map(n -> ((Number)n).intValue()).toArray() : new Object[0];

            String name = (String) body.get("name");
            Number rorVoice = (Number) body.get("ror_voice");
            Number rorData = (Number) body.get("ror_data");
            Number rorSms = (Number) body.get("ror_sms");
            Number price = (Number) body.get("price");

            List<Map<String, Object>> result = DB.executeSelect(
                "SELECT * FROM create_rateplan_with_packages(?, ?::numeric, ?::numeric, ?::numeric, ?::numeric, ?)",
                name, 
                rorVoice != null ? rorVoice.doubleValue() : 0, 
                rorData != null ? rorData.doubleValue() : 0, 
                rorSms != null ? rorSms.doubleValue() : 0, 
                price != null ? price.doubleValue() : 0, 
                DB.createSqlArray("integer", packageIds)
            );

            res.setStatus(201);
            return result.get(0);
        });
    }

    @Override
    protected void doPut(HttpServletRequest req, HttpServletResponse res) throws IOException {
        String pathParam = getPathParam(req);
        if (pathParam == null) {
            sendError(res, 400, "Missing ID");
            return;
        }
        handle(res, () -> {
            int id = Integer.parseInt(pathParam);
            Map body = readJson(req, Map.class);
            List<Object> packageIdsList = (List<Object>) body.get("servicePackageIds");

            java.sql.Array sqlArray = null;
            if (packageIdsList != null) {
                Object[] packageIds = packageIdsList.stream().map(n -> ((Number)n).intValue()).toArray();
                sqlArray = DB.createSqlArray("integer", packageIds);
            }

            String name = (String) body.get("name");
            Number rorVoice = (Number) body.get("ror_voice");
            Number rorData = (Number) body.get("ror_data");
            Number rorSms = (Number) body.get("ror_sms");
            Number price = (Number) body.get("price");

            DB.executeSelect(
                "SELECT update_rateplan(?, ?, ?::numeric, ?::numeric, ?::numeric, ?::numeric, ?)",
                id, name, 
                rorVoice != null ? rorVoice.doubleValue() : null, 
                rorData != null ? rorData.doubleValue() : null, 
                rorSms != null ? rorSms.doubleValue() : null, 
                price != null ? price.doubleValue() : null, 
                sqlArray
            );

            return Map.of("message", "Rate plan updated successfully");
        });
    }

    @Override
    protected void doDelete(HttpServletRequest req, HttpServletResponse res) throws IOException {
        String pathParam = getPathParam(req);
        if (pathParam == null) {
            sendError(res, 400, "Missing ID");
            return;
        }
        handle(res, () -> {
            int id = Integer.parseInt(pathParam);
            DB.executeSelect("SELECT delete_rateplan(?)", id);
            return Map.of("message", "Rate plan deleted successfully");
        });
    }
}
