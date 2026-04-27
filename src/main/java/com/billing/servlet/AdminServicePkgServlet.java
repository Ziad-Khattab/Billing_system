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
        try {
            Map body = readJson(req, Map.class);
            List<Map<String, Object>> result = DB.executeSelect(
                "SELECT * FROM create_service_package(?, ?::service_type, ?, ?, ?, ?, ?)",
                body.get("name"), body.get("type"), body.get("amount"), 
                body.get("priority"), body.get("price"), body.get("description"), body.get("is_roaming")
            );
            res.setStatus(201);
            sendJson(res, result.get(0));
        } catch (Exception e) {
            sendError(res, 500, e.getMessage());
        }
    }
}
