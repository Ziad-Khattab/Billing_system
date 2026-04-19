package com.billing.servlet;

import com.billing.dao.CustomerDAO;
import com.billing.model.Customer;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;

// Admin-only: full CRUD on all customers
@WebServlet("/api/admin/customers/*")
public class AdminCustomerServlet extends BaseServlet {

    private final CustomerDAO customerDAO = new CustomerDAO();

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        String pathParam = getPathParam(req);

        if (pathParam == null) {
            String q = req.getParameter("q");
            List<Customer> customers = (q != null && !q.isEmpty())
                ? customerDAO.search(q)
                : customerDAO.findAll();
            sendJson(res, customers);
        } else {
            try {
                Customer c = customerDAO.findById(Integer.parseInt(pathParam));
                if (c == null) sendError(res, 404, "Customer not found");
                else sendJson(res, c);
            } catch (NumberFormatException e) {
                sendError(res, 400, "Invalid ID");
            }
        }
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        Customer c = readJson(req, Customer.class);
        Customer created = customerDAO.create(c);
        res.setStatus(201);
        sendJson(res, created);
    }

    @Override
    protected void doPut(HttpServletRequest req, HttpServletResponse res) throws IOException {
        String pathParam = getPathParam(req);
        if (pathParam == null) { sendError(res, 400, "ID required"); return; }

        try {
            int id = Integer.parseInt(pathParam);
            Customer c = readJson(req, Customer.class);
            c.setId(id);
            Customer updated = customerDAO.update(c);
            if (updated == null) sendError(res, 404, "Customer not found");
            else sendJson(res, updated);
        } catch (NumberFormatException e) {
            sendError(res, 400, "Invalid ID");
        }
    }
}
