package com.billing.servlet;

import com.billing.dao.UserAccountDAO;
import com.billing.model.UserAccount;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;

@WebServlet("/api/customer/profile")
public class CustomerProfileServlet extends BaseServlet {

    private final UserAccountDAO userDAO = new UserAccountDAO();

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        UserAccount user = (UserAccount) req.getSession().getAttribute("user");
        if (user == null) {
            sendError(res, 401, "Not logged in");
            return;
        }
        
        try {
            UserAccount profile = userDAO.getById(user.getId());
            sendJson(res, profile);
        } catch (Exception e) {
            sendError(res, 500, e.getMessage());
        }
    }
}
