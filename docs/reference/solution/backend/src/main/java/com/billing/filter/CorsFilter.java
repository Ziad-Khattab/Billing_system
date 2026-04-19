package com.billing.filter;

import jakarta.servlet.*;
import jakarta.servlet.annotation.WebFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;

/**
 * CORS = Cross-Origin Resource Sharing
 * 
 * Why do we need this?
 * Your frontend runs on localhost:5173 and your backend on localhost:8080.
 * Browsers block requests between different ports for security UNLESS the server
 * explicitly says "It's okay!" via these headers.
 */
@WebFilter("/*")
public class CorsFilter implements Filter {

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {
        
        HttpServletResponse res = (HttpServletResponse) response;
        HttpServletRequest req = (HttpServletRequest) request;

        // Allow our SvelteKit frontend to talk to us
        res.setHeader("Access-Control-Allow-Origin", "http://localhost:5173");
        // Allow common HTTP methods
        res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        // Allow the frontend to send JSON and Auth headers
        res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
        // Essential for keeping the Session (Cookie) working across different ports
        res.setHeader("Access-Control-Allow-Credentials", "true");

        // Browsers send a "preflight" OPTIONS request to check permissions.
        // If it's an OPTIONS request, we respond 200 OK immediately.
        if ("OPTIONS".equalsIgnoreCase(req.getMethod())) {
            res.setStatus(HttpServletResponse.SC_OK);
            return;
        }

        chain.doFilter(request, response);
    }
}
