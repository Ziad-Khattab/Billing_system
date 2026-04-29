package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import java.util.Map;

@WebServlet("/api/admin/service-packages/*")
public class AdminServicePkgServlet extends BaseServlet {

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        String pathParam = getPathParam(req);
        handle(res, () -> {
            if (pathParam == null) {
                return DB.executeSelect("SELECT * FROM get_all_service_packages()");
            } else {
                int id = Integer.parseInt(pathParam);
                List<Map<String, Object>> list = DB.executeSelect("SELECT * FROM get_service_package_by_id(?)", id);
                if (list.isEmpty()) throw new RuntimeException("Service package not found");
                return list.get(0);
            }
        });
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            Map body = readJson(req, Map.class);

            // Explicitly cast numbers because Gson parses them as Double
            String name = (String) body.get("name");
            String type = (String) body.get("type");
            Number amount = (Number) body.get("amount");
            Number priority = (Number) body.get("priority");
            Number price = (Number) body.get("price");
            String description = (String) body.get("description");
            Boolean isRoaming = (Boolean) body.get("is_roaming");

            List<Map<String, Object>> result = DB.executeSelect(
                "SELECT * FROM add_new_service_package(?, ?::service_type, ?::numeric, ?::integer, ?::numeric, ?, ?)",
                name, type, 
                amount != null ? amount.doubleValue() : 0, 
                priority != null ? priority.intValue() : 0, 
                price != null ? price.doubleValue() : 0, 
                description, isRoaming != null ? isRoaming : false
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

            // Explicitly cast numbers because Gson parses them as Double
            String name = (String) body.get("name");
            String type = (String) body.get("type");
            Number amount = (Number) body.get("amount");
            Number priority = (Number) body.get("priority");
            Number price = (Number) body.get("price");
            String description = (String) body.get("description");
            Boolean isRoaming = (Boolean) body.get("is_roaming");

            List<Map<String, Object>> result = DB.executeSelect(
                "SELECT * FROM update_service_package(?, ?, ?::service_type, ?::numeric, ?::integer, ?::numeric, ?, ?)",
                id, name, type, 
                amount != null ? amount.doubleValue() : 0, 
                priority != null ? priority.intValue() : 0, 
                price != null ? price.doubleValue() : 0, 
                description, isRoaming != null ? isRoaming : false
            );
            return result.get(0);
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
            DB.executeSelect("SELECT delete_service_package(?)", id);
            return Map.of("message", "Service package deleted successfully");
        });
    }
}
