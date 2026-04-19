package com.billing.servlet;

import com.billing.dao.BillDAO;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;

// Maps this servlet to /api/admin/bills and any sub-paths (like /api/admin/bills/5)
@WebServlet("/api/admin/bills/*")
public class AdminBillServlet extends BaseServlet {

    private final BillDAO billDAO = new BillDAO();

    // Handles HTTP GET requests to read data.
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        try {
            // getPathParam() extracts the ID from the URL if present (e.g., returns "5" from /bills/5)
            String pathParam = getPathParam(req);
            if (pathParam != null) {
                // Path: /api/admin/bills/{id}
                try {
                    // Find a specific single bill by its Primary Key
                    var bill = billDAO.findById(Integer.parseInt(pathParam));
                    if (bill == null) sendError(res, 404, "Bill not found");
                    else sendJson(res, bill);
                } catch (NumberFormatException e) { 
                    sendError(res, 400, "Invalid ID format"); 
                }
            } else {
                // Path: /api/admin/bills?contract_id=xyz
                // req.getParameter() reads the query string variables after the '?'
                String contractId = req.getParameter("contract_id");
                if (contractId != null) {
                    // Find all bills belonging to this specific contract
                    sendJson(res, billDAO.findByContractId(Integer.parseInt(contractId)));
                } else {
                    sendError(res, 400, "contract_id parameter required");
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
            sendError(res, 500, "Database error occurred");
        }
    }
}
