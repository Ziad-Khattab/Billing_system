package com.billing.servlet;

import com.billing.dao.RatePlanDAO;
import com.billing.model.RatePlan;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;

@WebServlet("/api/admin/rateplans/*")
public class AdminRatePlanServlet extends BaseServlet {

    private final RatePlanDAO ratePlanDAO = new RatePlanDAO();

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        String pathParam = getPathParam(req);
        if (pathParam == null) {
            sendJson(res, ratePlanDAO.findAll());
        } else {
            try {
                RatePlan r = ratePlanDAO.findById(Integer.parseInt(pathParam));
                if (r == null) sendError(res, 404, "Rate plan not found");
                else sendJson(res, r);
            } catch (NumberFormatException e) { sendError(res, 400, "Invalid ID"); }
        }
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        RatePlan r = readJson(req, RatePlan.class);
        res.setStatus(201);
        sendJson(res, ratePlanDAO.create(r));
    }
}
