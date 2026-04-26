package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;
import java.util.List;
import java.util.Map;

@WebServlet("/api/auth/*")
public class AuthServlet extends BaseServlet {

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
            List<Map<String, Object>> users = DB.executeSelect(
                "SELECT * FROM login(?, ?)",
                username, password
            );

            if (users.isEmpty()) {
                sendError(res, 401, "Invalid credentials");
                return;
            }

            Map<String, Object> user = users.get(0);
            HttpSession session = req.getSession(true);
            session.setAttribute("user", user);
            sendJson(res, user);
        } catch (Exception e) {
            e.printStackTrace();  // Log to server console
            System.err.println("Login error for user: " + username);
            System.err.println("Error details: " + e.getMessage());
            sendError(res, 500, "Authentication error: " + e.getMessage());
        }
    }

    private void handleRegister(HttpServletRequest req, HttpServletResponse res) throws IOException {
        Map body = readJson(req, Map.class);
        String username  = (String) body.get("username");
        String password  = (String) body.get("password");
        String name      = (String) body.get("name");
        String email     = (String) body.get("email");
        String address   = (String) body.get("address");
        String birthdate = (String) body.get("birthdate");

        try {
            List<Map<String, Object>> result = DB.executeSelect(
                    "SELECT create_customer(?, ?, ?, ?, ?, ?::DATE) AS id",
                    username, password, name, email, address, birthdate
            );

            // ← get the real id back from DB, not from Java
            int newId = ((Number) result.get(0).get("id")).intValue();

            System.out.println("[Register] New user id: " + newId);


            List<Map<String, Object>> users = DB.executeSelect(
                    "SELECT * FROM login(?, ?)", username, password
            );

            if (users.isEmpty()) {
                sendError(res, 500, "User created but login failed");
                return;
            }

            Map<String, Object> user = users.get(0);
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
