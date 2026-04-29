package com.billing.servlet;

import com.billing.util.GsonTypeAdapters;
import com.google.gson.Gson;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

// Abstract base class — all servlets extend this for shared JSON helpers.
// "abstract" means you can't instantiate BaseServlet directly using 'new BaseServlet()'. 
// It only serves as a parent template for AuthServlet, AdminBillServlet, etc.
// Extending 'HttpServlet' hooks this class into Tomcat's web request engine.
public abstract class BaseServlet extends HttpServlet {
    protected final Logger logger = LoggerFactory.getLogger(getClass());

    // Gson is a Google library that converts Java Objects to JSON text, and vice versa.
    // Making it 'protected' means child classes can use it.
    // 'final' means the reference to this specific Gson instance cannot be changed.
    protected final Gson gson = GsonTypeAdapters.GSON;

    /**
     * Helper method to send data back to the frontend as a JSON response.
     * @param res The HttpServletResponse object used to talk back to the client.
     * @param data Any Java object (List, Map, custom model) to be converted to JSON.
     */
    protected void sendJson(HttpServletResponse res, Object data) throws IOException {
        res.setContentType("application/json");
        res.setCharacterEncoding("UTF-8");
        res.getWriter().print(gson.toJson(data));
    }

    /**
     * Helper method to read an incoming JSON request body and convert it into a Map.
     * Useful for dynamic or one-off JSON payloads.
     */
    protected Map<String, Object> readJson(HttpServletRequest req) throws IOException {
        return gson.fromJson(req.getReader(), Map.class);
    }

    /**
     * Helper method to read an incoming JSON request body and map it to a specific class.
     */
    protected <T> T readJson(HttpServletRequest req, Class<T> clazz) throws IOException {
        return gson.fromJson(req.getReader(), clazz);
    }

    // --- Functional Helpers for Lean Code ---

    @FunctionalInterface
    public interface Logic<T> { T execute() throws Exception; }

    protected <T> void handle(HttpServletResponse res, Logic<T> logic) {
        try {
            T result = logic.execute();
            sendJson(res, result);
        } catch (Exception e) {
            logger.error("API Logic Error", e);
            try { sendError(res, 500, e.getMessage()); } catch (IOException ignored) {}
        }
    }

    protected void sendError(HttpServletResponse res, int status, String message) throws IOException {
        res.setStatus(status);
        sendJson(res, Map.of(
            "error", message,
            "message", message
        ));
    }

    protected String getPathParam(HttpServletRequest req) {
        String pathInfo = req.getPathInfo();
        if (pathInfo == null || pathInfo.equals("/")) return null;
        return pathInfo.substring(1);
    }

    protected int getIntParam(HttpServletRequest req, String name, int defaultValue) {
        String val = req.getParameter(name);
        if (val == null || val.trim().isEmpty()) return defaultValue;
        try {
            return Integer.parseInt(val);
        } catch (NumberFormatException e) {
            return defaultValue;
        }
    }

    protected boolean isAdmin(HttpServletRequest req) {
        jakarta.servlet.http.HttpSession session = req.getSession(false);
        if (session == null) return false;
        Map<String, Object> user = (Map<String, Object>) session.getAttribute("user");
        return user != null && "admin".equalsIgnoreCase((String) user.get("role"));
    }
}
