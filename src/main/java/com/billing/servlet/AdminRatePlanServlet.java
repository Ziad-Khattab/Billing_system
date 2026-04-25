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
        if (pathParam == null) {
            try {
                sendJson(res, DB.executeSelect("SELECT * FROM rateplan ORDER BY id"));
            } catch (Exception e) {
                sendError(res, 500, e.getMessage());
            }
        } else {
            try {
                int id = Integer.parseInt(pathParam);
                List<Map<String, Object>> list = DB.executeSelect("SELECT * FROM rateplan WHERE id = ?", id);
                if (list.isEmpty()) sendError(res, 404, "Rate plan not found");
                else sendJson(res, list.get(0));
            } catch (NumberFormatException e) {
                sendError(res, 400, "Invalid ID");
            } catch (Exception e) {
                sendError(res, 500, e.getMessage());
            }
        }
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
