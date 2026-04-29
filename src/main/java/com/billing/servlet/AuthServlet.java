package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;
import java.util.List;
import java.util.Map;

@SuppressWarnings("unused")
@WebServlet("/api/auth/*")
public class AuthServlet extends BaseServlet {

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        String path = req.getPathInfo();
        switch (path) {
            case "/login" -> handleLogin(req, res);
            case "/register" -> handleRegister(req, res);
            case "/logout" -> handleLogout(req, res);
            default -> sendError(res, 404, "Not found");
        }
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

    @SuppressWarnings("unchecked")
    private void handleLogin(HttpServletRequest req, HttpServletResponse res) throws IOException {
        Map<String, String> body = readJson(req, Map.class);
        String username = body.get("username");
        String password = body.get("password");

        try {
            List<Map<String, Object>> users = DB.executeSelect(
                "SELECT * FROM login(?, ?)",
                username, password
            );

            if (users.isEmpty()) {
                sendError(res, 401, "Invalid credentials");
                return;
            }

            Map<String, Object> user = users.getFirst();
            HttpSession session = req.getSession(true);
            session.setAttribute("user", user);
            sendJson(res, user);
        } catch (Exception e) {
            logger.error("Login error for user: {}", username, e);
            sendError(res, 500, "Authentication error: " + e.getMessage());
        }
    }

    @SuppressWarnings("unchecked")
    private void handleRegister(HttpServletRequest req, HttpServletResponse res) throws IOException {
        Map<String, String> body = readJson(req, Map.class);
        String username  = body.get("username");
        String password  = body.get("password");
        String name      = body.get("name");
        String email     = body.get("email");
        String address   = body.get("address");
        String birthdate = body.get("birthdate");

        try {
            List<Map<String, Object>> result = DB.executeSelect(
                    "SELECT create_customer(?, ?, ?, ?, ?, ?::DATE) AS id",
                    username, password, name, email, address, birthdate
            );

            // ← get the real id back from DB, not from Java
            int newId = ((Number) result.getFirst().get("id")).intValue();

            System.out.println("[Register] New user id: " + newId);


            List<Map<String, Object>> users = DB.executeSelect(
                    "SELECT * FROM login(?, ?)", username, password
            );

            if (users.isEmpty()) {
                sendError(res, 500, "User created but login failed");
                return;
            }

            Map<String, Object> user = users.getFirst();
            System.out.println("[Register] Session user: " + user); // debug

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
