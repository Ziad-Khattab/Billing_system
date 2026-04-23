package com.billing.servlet;

import com.billing.dao.UserAccountDAO;
import com.billing.model.UserAccount;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;
import java.util.Map;

@WebServlet("/api/auth/*")
public class AuthServlet extends BaseServlet {

    private final UserAccountDAO userDAO = new UserAccountDAO();

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        String path = req.getPathInfo();
        if ("/login".equals(path)) handleLogin(req, res);
        else if ("/register".equals(path)) handleRegister(req, res);
        else if ("/logout".equals(path)) handleLogout(req, res);
        else sendError(res, 404, "Not found");
    }

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        HttpSession session = req.getSession(false);
        if (session == null || session.getAttribute("user") == null) {
            sendError(res, 401, "Not logged in");
            return;
        }
        sendJson(res, session.getAttribute("user"));
    }

    private void handleLogin(HttpServletRequest req, HttpServletResponse res) throws IOException {
        Map body = readJson(req, Map.class);
        String username = (String) body.get("username");
        String password = (String) body.get("password");

        try {
            UserAccount user = userDAO.login(username, password);
            if (user == null) {
                sendError(res, 401, "Invalid credentials");
                return;
            }

            HttpSession session = req.getSession(true);
            user.setPassword(null); // Security
            session.setAttribute("user", user);
            sendJson(res, user);
        } catch (Exception e) {
            sendError(res, 500, e.getMessage());
        }
    }

    private void handleRegister(HttpServletRequest req, HttpServletResponse res) throws IOException {
        Map body = readJson(req, Map.class);
        UserAccount user = new UserAccount();
        user.setUsername((String) body.get("username"));
        user.setPassword((String) body.get("password"));
        user.setName((String) body.get("name"));
        user.setEmail((String) body.get("email"));
        user.setRole("customer");

        try {
            userDAO.register(user);
            user.setPassword(null);
            HttpSession session = req.getSession(true);
            session.setAttribute("user", user);
            res.setStatus(201);
            sendJson(res, user);
        } catch (Exception e) {
            sendError(res, 500, e.getMessage());
        }
    }

    private void handleLogout(HttpServletRequest req, HttpServletResponse res) throws IOException {
        HttpSession session = req.getSession(false);
        if (session != null) session.invalidate();
        sendJson(res, Map.of("message", "Logged out"));
    }
}
