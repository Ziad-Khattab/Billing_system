package com.billing.servlet;

import com.google.gson.Gson;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Map;

// Abstract base class — all servlets extend this for shared JSON helpers.
// "abstract" means you can't create a BaseServlet directly; only subclasses.
public abstract class BaseServlet extends HttpServlet {

    protected final Gson gson = new Gson();

    protected void sendJson(HttpServletResponse res, Object data) throws IOException {
        res.setContentType("application/json");
        res.setCharacterEncoding("UTF-8");
        res.getWriter().print(gson.toJson(data));
    }

    protected <T> T readJson(HttpServletRequest req, Class<T> clazz) throws IOException {
        return gson.fromJson(req.getReader(), clazz);
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
