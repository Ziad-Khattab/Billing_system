package com.billing.servlet;

import com.billing.dao.ContractDAO;
import com.billing.dao.CustomerDAO;
import com.billing.dao.InvoiceDAO;
import com.billing.model.AppUser;
import com.billing.model.Customer;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Map;

// Customer self-service: view/edit own profile, view own invoices/contracts
@WebServlet("/api/customer/*")
public class CustomerProfileServlet extends BaseServlet {

    private final CustomerDAO customerDAO = new CustomerDAO();
    private final ContractDAO contractDAO = new ContractDAO();
    private final InvoiceDAO invoiceDAO = new InvoiceDAO();

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        AppUser user = (AppUser) req.getSession().getAttribute("user");
        Customer customer = customerDAO.findByUserId(user.getId());

        if (customer == null) {
            sendError(res, 404, "Customer profile not found");
            return;
        }

        String path = req.getPathInfo();
        if (path == null || "/profile".equals(path) || "/".equals(path)) {
            sendJson(res, customer);
        } else if ("/contracts".equals(path)) {
            sendJson(res, contractDAO.findByCustomerId(customer.getId()));
        } else if ("/invoices".equals(path)) {
            sendJson(res, invoiceDAO.findByCustomerId(customer.getId()));
        } else {
            sendError(res, 404, "Not found");
        }
    }

    @Override
    protected void doPut(HttpServletRequest req, HttpServletResponse res) throws IOException {
        AppUser user = (AppUser) req.getSession().getAttribute("user");
        Customer existing = customerDAO.findByUserId(user.getId());

        if (existing == null) {
            sendError(res, 404, "Customer profile not found");
            return;
        }

        // Only allow updating name, address, and email
        Map body = readJson(req, Map.class);
        if (body.get("name") != null) existing.setName((String) body.get("name"));
        if (body.get("address") != null) existing.setAddress((String) body.get("address"));
        if (body.get("email") != null) existing.setEmail((String) body.get("email"));

        customerDAO.update(existing);
        sendJson(res, existing);
    }
}
