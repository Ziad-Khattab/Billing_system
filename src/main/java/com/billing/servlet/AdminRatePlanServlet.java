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
                return list.get(0);
            }
        });
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        try {
            Map body = readJson(req, Map.class);
            String name = (String) body.get("name");
            Number price = (Number) body.get("price");

            List<Map<String, Object>> result = DB.executeSelect(
                "INSERT INTO rateplan (name, price) VALUES (?, ?) RETURNING *",
                name, price
            );

            res.setStatus(201);
            sendJson(res, result.get(0));
        } catch (Exception e) {
            sendError(res, 500, e.getMessage());
        }
    }
}
