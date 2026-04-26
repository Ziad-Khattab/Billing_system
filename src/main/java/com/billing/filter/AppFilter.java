package com.billing.filter;

import jakarta.servlet.*;
import jakarta.servlet.annotation.WebFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpServletResponseWrapper;
import java.io.*;
import java.util.Optional;

/**
 * High-Performance Unified App Filter
 */
@WebFilter(urlPatterns = "/*")
public class AppFilter implements Filter {

    private String cachedCssTag = null;
    private long lastBuildTime = 0;
    private static final ThreadLocal<Boolean> RECURSION_GUARD = ThreadLocal.withInitial(() -> false);

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {
        
        if (RECURSION_GUARD.get()) {
            chain.doFilter(request, response);
            return;
        }

        try {
            RECURSION_GUARD.set(true);
            handleFilterLogic(request, response, chain);
        } finally {
            RECURSION_GUARD.set(false);
        }
    }

    private void handleFilterLogic(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {
        HttpServletRequest req = (HttpServletRequest) request;
        HttpServletResponse res = (HttpServletResponse) response;
        String path = req.getRequestURI().substring(req.getContextPath().length());

        // Normalization
        if (path.length() > 1 && path.endsWith("/")) path = path.substring(0, path.length() - 1);

        // Security Guard: Strict Role-Based Authorization
        jakarta.servlet.http.HttpSession session = req.getSession(false);
        java.util.Map<String, Object> user = (session != null) ? (java.util.Map<String, Object>) session.getAttribute("user") : null;

        if (path.startsWith("/admin") || path.startsWith("/api/admin")) {
            if (user == null) {
                if (path.startsWith("/api/")) res.sendError(401, "Authentication required");
                else res.sendRedirect(req.getContextPath() + "/login");
                return;
            }
            if (!"admin".equals(user.get("role"))) {
                if (path.startsWith("/api/")) res.sendError(403, "Admin role required");
                else res.sendRedirect(req.getContextPath() + "/dashboard");
                return;
            }
        } else if (path.startsWith("/profile") || path.startsWith("/api/customer")) {
            if (user == null) {
                if (path.startsWith("/api/")) res.sendError(401, "Authentication required");
                else res.sendRedirect(req.getContextPath() + "/login");
                return;
            }
        }

        // Routing
        boolean isApi = path.startsWith("/api/");
        boolean isAsset = path.startsWith("/_app/") || path.contains(".");
        boolean isRoot = path.equals("/") || path.isEmpty() || path.equals("/index.html");

        if (isApi || isAsset) {
            chain.doFilter(request, response);
        } else if (isRoot) {
            handleHtmlInjection(req, res, chain);
        } else {
            System.out.println("[AppFilter] Deep link: " + path + " -> Forwarding to index.html");
            request.getRequestDispatcher("/index.html").forward(request, response);
        }
    }

    private void handleHtmlInjection(HttpServletRequest req, HttpServletResponse res, FilterChain chain) 
            throws IOException, ServletException {
        
        String cssTag = getCssTag(req.getServletContext());
        
        // Anti-Latency: Force browser to re-validate HTML on every request
        res.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
        res.setHeader("Pragma", "no-cache");
        res.setHeader("Expires", "0");

        CharResponseWrapper wrapper = new CharResponseWrapper(res);
        chain.doFilter(req, wrapper);

        byte[] responseBytes = wrapper.getByteArray();
        String html = new String(responseBytes, "UTF-8");
        
        if (html.contains("</head>")) {
            html = html.replace("</head>", cssTag + "\n</head>");
            byte[] finalBytes = html.getBytes("UTF-8");
            res.setContentType("text/html; charset=UTF-8");
            res.setContentLength(finalBytes.length);
            res.getOutputStream().write(finalBytes);
        } else {
            res.getOutputStream().write(responseBytes);
        }
    }

    private synchronized String getCssTag(ServletContext context) {
        String assetPath = context.getRealPath("/_app/immutable/assets/");
        if (assetPath == null) return "";
        
        File assetDir = new File(assetPath);
        long currentDiskTime = assetDir.lastModified();

        // Smart Sync: Only re-scan if the disk has actually changed
        if (cachedCssTag != null && lastBuildTime >= currentDiskTime) {
            return cachedCssTag;
        }
        // If we reach here, we need a fresh scan
        java.util.Set<String> assets = context.getResourcePaths("/_app/immutable/assets/");
        if (assets == null || assets.isEmpty()) return "";

        Optional<String> cssFile = assets.stream()
                .map(p -> p.substring(p.lastIndexOf("/") + 1))
                .filter(name -> name.endsWith(".css"))
                .sorted((a, b) -> a.startsWith("0.") ? -1 : 1)
                .findFirst();

        if (cssFile.isPresent()) {
            cachedCssTag = "<link rel=\"stylesheet\" href=\"/_app/immutable/assets/" + cssFile.get() + "\">";
            lastBuildTime = currentDiskTime; // Lock to current disk state
        }
        
        return cachedCssTag != null ? cachedCssTag : "";
    }

    private static class CharResponseWrapper extends HttpServletResponseWrapper {
        private ByteArrayOutputStream baos = new ByteArrayOutputStream();
        private ServletOutputStream sos = new ServletOutputStream() {
            @Override public boolean isReady() { return true; }
            @Override public void setWriteListener(WriteListener writeListener) {}
            @Override public void write(int b) throws IOException { baos.write(b); }
        };
        private PrintWriter pw;

        public CharResponseWrapper(HttpServletResponse response) throws UnsupportedEncodingException {
            super(response);
            pw = new PrintWriter(new OutputStreamWriter(baos, "UTF-8"));
        }

        @Override public ServletOutputStream getOutputStream() { return sos; }
        @Override public PrintWriter getWriter() { return pw; }
        public byte[] getByteArray() { 
            pw.flush();
            return baos.toByteArray(); 
        }
    }

    @Override public void init(FilterConfig filterConfig) {}
    @Override public void destroy() {}
}
