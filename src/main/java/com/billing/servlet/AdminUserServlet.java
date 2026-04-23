package com.billing.servlet;

import com.billing.dao.UserAccountDAO;
import com.billing.model.UserAccount;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;

@WebServlet("/api/admin/users/*")
public class AdminUserServlet extends BaseServlet {

    private final UserAccountDAO userDAO = new UserAccountDAO();

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        String pathParam = req.getPathInfo();
        
        try {
            if (pathParam == null || "/".equals(pathParam)) {
                // Return all users (this is a simplified example)
                sendJson(res, "[]"); 
            } else {
                int id = Integer.parseInt(pathParam.substring(1));
                UserAccount user = userDAO.getById(id);
                if (user == null) sendError(res, 404, "User not found");
                else sendJson(res, user);
            }
        } catch (Exception e) {
            sendError(res, 500, e.getMessage());
        }
    }
}
