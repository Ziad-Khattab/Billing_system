package com.billing.servlet;

import com.billing.dao.CustomerDAO;
import com.billing.dao.UserDAO;
import com.billing.model.AppUser;
import com.billing.model.Customer;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import org.mindrot.jbcrypt.BCrypt;
import java.io.IOException;
import java.util.Map;

@WebServlet("/api/auth/*")
public class AuthServlet extends BaseServlet {

    private final UserDAO userDAO = new UserDAO();
    private final CustomerDAO customerDAO = new CustomerDAO();

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
        // GET /api/auth/me — return current user
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

        if (username == null || password == null) {
            sendError(res, 400, "Username and password required");
            return;
        }

        AppUser user = userDAO.findByUsername(username);
        if (user == null || !BCrypt.checkpw(password, user.getPasswordHash())) {
            sendError(res, 401, "Invalid username or password");
            return;
        }

        HttpSession session = req.getSession(true);
        user.setPasswordHash(null); // never expose hash to client
        session.setAttribute("user", user);
        sendJson(res, user);
    }

    private void handleRegister(HttpServletRequest req, HttpServletResponse res) throws IOException {
        Map body = readJson(req, Map.class);
        String username = (String) body.get("username");
        String password = (String) body.get("password");
        String fullName = (String) body.get("fullName");
        String address  = (String) body.get("address");

        if (username == null || password == null || fullName == null) {
            sendError(res, 400, "username, password, and fullName required");
            return;
        }

        // Check if username taken
        if (userDAO.findByUsername(username) != null) {
            sendError(res, 409, "Username already exists");
            return;
        }

        // Create app_user with hashed password
        AppUser user = new AppUser();
        user.setUsername(username);
        user.setPasswordHash(BCrypt.hashpw(password, BCrypt.gensalt()));
        user.setFullName(fullName);
        user.setRole("customer");
        user = userDAO.create(user);

        // Create linked customer profile
        Customer customer = new Customer();
        customer.setName(fullName);
        customer.setAddress(address);
        customer.setUserId(user.getId());
        customerDAO.create(customer);

        // Auto-login after registration
        HttpSession session = req.getSession(true);
        user.setPasswordHash(null);
        session.setAttribute("user", user);

        res.setStatus(201);
        sendJson(res, user);
    }

    private void handleLogout(HttpServletRequest req, HttpServletResponse res) throws IOException {
        HttpSession session = req.getSession(false);
        if (session != null) session.invalidate();
        sendJson(res, Map.of("message", "Logged out"));
    }
}
