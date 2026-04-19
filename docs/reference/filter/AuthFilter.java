package com.billing.filter;

import com.billing.model.AppUser;
import jakarta.servlet.*;
import jakarta.servlet.annotation.WebFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;

// Three-zone auth filter:
//   /api/public/*   → no auth
//   /api/auth/*     → no auth (login/register endpoints)
//   /api/customer/* → customer or admin
//   /api/admin/*    → admin only
@WebFilter("/api/*")
public class AuthFilter implements Filter {

    @Override
    public void doFilter(ServletRequest request, ServletResponse response,
                         FilterChain chain) throws IOException, ServletException {

        HttpServletRequest req = (HttpServletRequest) request;
        HttpServletResponse res = (HttpServletResponse) response;
        String path = req.getRequestURI();

        // Zone 1: Public + Auth endpoints — no login needed
        if (path.contains("/api/public") || path.contains("/api/auth")) {
            chain.doFilter(request, response);
            return;
        }

        // Get session (don't create new one)
        HttpSession session = req.getSession(false);
        AppUser user = null;
        if (session != null) {
            user = (AppUser) session.getAttribute("user");
        }

        // Not logged in at all
        if (user == null) {
            res.setStatus(401);
            res.setContentType("application/json");
            res.getWriter().print("{\"error\":\"Not authenticated\"}");
            return;
        }

        // Zone 2: Admin-only endpoints
        if (path.contains("/api/admin") && !"admin".equals(user.getRole())) {
            res.setStatus(403);
            res.setContentType("application/json");
            res.getWriter().print("{\"error\":\"Admin access required\"}");
            return;
        }

        // Zone 3: Customer endpoints — any logged-in user (customer or admin)
        chain.doFilter(request, response);
    }
}
