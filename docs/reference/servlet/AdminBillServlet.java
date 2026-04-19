package com.billing.servlet;

import com.billing.dao.BillDAO;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;

@WebServlet("/api/admin/bills/*")
public class AdminBillServlet extends BaseServlet {

    private final BillDAO billDAO = new BillDAO();

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        String pathParam = getPathParam(req);
        if (pathParam != null) {
            try {
                var bill = billDAO.findById(Integer.parseInt(pathParam));
                if (bill == null) sendError(res, 404, "Bill not found");
                else sendJson(res, bill);
            } catch (NumberFormatException e) { sendError(res, 400, "Invalid ID"); }
        } else {
            String contractId = req.getParameter("contract_id");
            if (contractId != null) {
                sendJson(res, billDAO.findByContractId(Integer.parseInt(contractId)));
            } else {
                sendError(res, 400, "contract_id parameter required");
            }
        }
    }
}
