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
        String pathParam = getPathParam(req);
        if (pathParam == null) {
            sendJson(res, contractDAO.findAll());
        } else {
            try {
                Contract c = contractDAO.findById(Integer.parseInt(pathParam));
                if (c == null) sendError(res, 404, "Contract not found");
                else sendJson(res, c);
            } catch (NumberFormatException e) { sendError(res, 400, "Invalid ID"); }
        }
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        Contract c = readJson(req, Contract.class);
        res.setStatus(201);
        sendJson(res, contractDAO.create(c));
    }
}
