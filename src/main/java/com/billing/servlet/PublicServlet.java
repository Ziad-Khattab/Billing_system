package com.billing.servlet;

import com.billing.dao.RatePlanDAO;
import com.billing.dao.ServicePackageDAO;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;

// Public endpoints — no auth required. For browsing packages before signing up.
@WebServlet("/api/public/*")
public class PublicServlet extends BaseServlet {

    private final RatePlanDAO ratePlanDAO = new RatePlanDAO();
    private final ServicePackageDAO servicePkgDAO = new ServicePackageDAO();

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        String path = req.getPathInfo();

        if (path == null || "/".equals(path) || path.startsWith("/rateplans")) {
            // GET /api/public/rateplans
            String sub = path != null ? path.replace("/rateplans", "") : "";
            if (sub.isEmpty() || "/".equals(sub)) {
                try { sendJson(res, ratePlanDAO.findAll()); }
                catch (Exception e) { sendError(res, 500, e.getMessage()); }
            } else {
                // GET /api/public/rateplans/3
                try {
                    int id = Integer.parseInt(sub.substring(1));
                    var plan = ratePlanDAO.findById(id);
                    if (plan == null) sendError(res, 404, "Rate plan not found");
                    else sendJson(res, plan);
                } catch (NumberFormatException e) {
                    sendError(res, 400, "Invalid ID");
                } catch (Exception e) {
                    sendError(res, 500, e.getMessage());
                }
            }
        } else if (path.startsWith("/service-packages")) {
            // GET /api/public/service-packages
            try { sendJson(res, servicePkgDAO.findAll()); }
            catch (Exception e) { sendError(res, 500, e.getMessage()); }
        } else {
            sendError(res, 404, "Not found");
        }
    }
}
