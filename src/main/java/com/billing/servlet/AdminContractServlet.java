package com.billing.servlet;

import com.billing.dao.ContractDAO;
import com.billing.model.Contract;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;

@WebServlet("/api/admin/contracts/*")
public class AdminContractServlet extends BaseServlet {

    private final ContractDAO contractDAO = new ContractDAO();

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        String path = req.getPathInfo();
        try {
            if (path == null || "/".equals(path)) {
                sendJson(res, contractDAO.findAll());
            } else {
                int id = Integer.parseInt(path.substring(1));
                Contract c = contractDAO.findById(id);
                if (c == null) sendError(res, 404, "Contract not found");
                else sendJson(res, c);
            }
        } catch (Exception e) {
            sendError(res, 500, e.getMessage());
        }
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        try {
            Contract c = readJson(req, Contract.class);
            contractDAO.create(c);
            res.setStatus(201);
            sendJson(res, c);
        } catch (Exception e) {
            sendError(res, 500, e.getMessage());
        }
    }
}
