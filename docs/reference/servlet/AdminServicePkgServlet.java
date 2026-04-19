package com.billing.servlet;

import com.billing.dao.ServicePackageDAO;
import com.billing.model.ServicePackage;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;

@WebServlet("/api/admin/service-packages/*")
public class AdminServicePkgServlet extends BaseServlet {

    private final ServicePackageDAO dao = new ServicePackageDAO();

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        String pathParam = getPathParam(req);
        if (pathParam == null) {
            sendJson(res, dao.findAll());
        } else {
            try {
                ServicePackage sp = dao.findById(Integer.parseInt(pathParam));
                if (sp == null) sendError(res, 404, "Service package not found");
                else sendJson(res, sp);
            } catch (NumberFormatException e) { sendError(res, 400, "Invalid ID"); }
        }
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        ServicePackage sp = readJson(req, ServicePackage.class);
        res.setStatus(201);
        sendJson(res, dao.create(sp));
    }
}
