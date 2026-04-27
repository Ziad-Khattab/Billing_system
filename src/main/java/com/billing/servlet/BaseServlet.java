package com.billing.servlet;

import com.billing.util.GsonTypeAdapters;
import com.google.gson.Gson;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Map;

// Abstract base class — all servlets extend this for shared JSON helpers.
// "abstract" means you can't instantiate BaseServlet directly using 'new BaseServlet()'. 
// It only serves as a parent template for AuthServlet, AdminBillServlet, etc.
// Extending 'HttpServlet' hooks this class into Tomcat's web request engine.
public abstract class BaseServlet extends HttpServlet {

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
            e.printStackTrace();
            try { sendError(res, 500, e.getMessage()); } catch (IOException ignored) {}
        }
    }

    protected void sendError(HttpServletResponse res, int status, String message) throws IOException {
        res.setStatus(status);
        sendJson(res, Map.of("error", message));
    }

    protected String getPathParam(HttpServletRequest req) {
        String pathInfo = req.getPathInfo();
        if (pathInfo == null || pathInfo.equals("/")) return null;
        return pathInfo.substring(1);
    }
}
