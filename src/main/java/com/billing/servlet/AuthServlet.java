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

// The @WebServlet annotation tells Tomcat to map this Java class to specific URLs.
// The "/*" means this servlet catches ANY request starting with /api/auth/
@WebServlet("/api/auth/*")
public class AuthServlet extends BaseServlet {

    private final UserDAO userDAO = new UserDAO();
    private final CustomerDAO customerDAO = new CustomerDAO();

    // doPost automatically handles all incoming HTTP POST requests to /api/auth/*
    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        // req.getPathInfo() gets the part of the URL after /api/auth
        // Example: if requested /api/auth/login, path == "/login"
        String path = req.getPathInfo();
        
        // Basic routing logic inside the servlet
        if ("/login".equals(path)) handleLogin(req, res);
        else if ("/register".equals(path)) handleRegister(req, res);
        else if ("/logout".equals(path)) handleLogout(req, res);
        else sendError(res, 404, "Not found");
    }

    // doGet handles all incoming HTTP GET requests.
    // Used here to check if the user is currently logged in (Session check).
    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        // req.getSession(false) returns the current session IF it exists. 
        // passing 'false' means: do NOT create a new session if one doesn't exist.
        HttpSession session = req.getSession(false);
        
        // If no session exists, or the session doesn't contain a "user" object, they aren't logged in.
        if (session == null || session.getAttribute("user") == null) {
            sendError(res, 401, "Not logged in");
            return;
        }
        // If logged in, return the user object as JSON to the frontend
        sendJson(res, session.getAttribute("user"));
    }

    private void handleLogin(HttpServletRequest req, HttpServletResponse res) throws IOException {
        // readJson() is the helper from BaseServlet. It converts the JSON string into a Java Map.
        Map body = readJson(req, Map.class);
        String username = (String) body.get("username");
        String password = (String) body.get("password");

        if (username == null || password == null) {
            sendError(res, 400, "Username and password required");
            return;
        }

        // Fetch user from PostgreSQL database using the DAO (Data Access Object)
        AppUser user = userDAO.findByUsername(username);
        
        // BCrypt.checkpw() is the industry standard for verifying passwords.
        // It hashes the provided 'password' and compares it to the secure hash stored in the DB.
        // We NEVER store or compare plain-text passwords.
        if (user == null || !BCrypt.checkpw(password, user.getPasswordHash())) {
            sendError(res, 401, "Invalid username or password");
            return;
        }

        // req.getSession(true) forces Tomcat to create a new session ID cookie.
        // This is what keeps the user logged in across different page reloads.
        HttpSession session = req.getSession(true);
        
        // SECURITY: Never send the password hash back to the frontend
        user.setPasswordHash(null); 
        
        // Store the user object in Tomcat's server-side memory linked to the user's session cookie.
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
