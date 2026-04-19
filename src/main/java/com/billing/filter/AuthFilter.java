package com.billing.filter;

import jakarta.servlet.*;
import jakarta.servlet.annotation.WebFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;

/**
 * AuthFilter = The Security Gatekeeper
 * 
 * This filter runs before every request to /api/*.
 * It checks if the user has a valid session. If not, it blocks the request.
 */
@WebFilter("/api/*")
public class AuthFilter implements Filter {

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {
        
        HttpServletRequest req = (HttpServletRequest) request;
        HttpServletResponse res = (HttpServletResponse) response;
        String path = req.getRequestURI();

        // 1. We must allow login and registration without a session!
        // Otherwise, no one could ever log in.
        if (path.endsWith("/auth/login") || path.endsWith("/auth/register") || path.contains("/public/")) {
            chain.doFilter(request, response);
            return;
        }

        // 2. Check if a session exists
        HttpSession session = req.getSession(false); // false = don't create a new one
        
        if (session != null && session.getAttribute("user") != null) {
            // User is logged in! Proceed to the servlet.
            chain.doFilter(request, response);
        } else {
            // User is NOT logged in. Block the request with 401 Unauthorized.
            res.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            res.setContentType("application/json");
            res.getWriter().write("{\"error\": \"Not authenticated. Please login.\"}");
        }
    }
}
