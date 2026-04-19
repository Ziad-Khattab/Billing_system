# ⌨️ Type-Along Coding Guide — Java Servlets

> **How to use this**: Don't copy-paste. Type each file yourself. Read every comment. When you type `import jakarta.servlet...`, say to yourself: "I'm importing the servlet library." This builds real understanding.

## Learning-While-Typing Tips

1. **Type imports manually** — don't auto-import. Ask yourself: "Why do I need this class?"
2. **Read each comment before typing the line** — understand, then type
3. **After finishing a file**, close it and try to rewrite `doGet` from memory
4. **Test immediately** — deploy, hit with curl, see the response. Don't batch.
5. **Break things on purpose** — remove `@WebServlet`, see what happens. Remove `chain.doFilter()`, see what happens.

---

## File 1: BaseServlet.java (Write This First)

### Steps to write it yourself:
1. Create package folder: `src/main/java/com/billing/servlet/`
2. Create `BaseServlet.java`
3. Think: "What do ALL my servlets need?" → JSON in/out, error handling
4. Type the code below

```java
// ─── PACKAGE ───────────────────────────────────────────────
// Package = folder structure. All servlets live here.
// Java convention: reverse domain name → com.billing.servlet
package com.billing.servlet;

// ─── IMPORTS ───────────────────────────────────────────────
// Gson: Google's JSON library. Converts Java objects ↔ JSON strings
// Example: gson.toJson(customer) → {"name":"Ahmed","address":"Cairo"}
import com.google.gson.Gson;

// jakarta.servlet: The servlet API. "jakarta" replaced "javax" in newer versions.
// HttpServlet: The base class ALL servlets extend
import jakarta.servlet.http.HttpServlet;
// HttpServletRequest: Represents the incoming HTTP request (URL, headers, body)
import jakarta.servlet.http.HttpServletRequest;
// HttpServletResponse: Represents the outgoing HTTP response (status, body)
import jakarta.servlet.http.HttpServletResponse;

// java.io: For reading/writing text streams
// IOException: Must be declared because network I/O can fail
import java.io.IOException;

// java.util.Map: Used for building simple JSON error responses
// Map.of("key", "value") creates an immutable map
import java.util.Map;

// ─── CLASS ─────────────────────────────────────────────────
// "abstract" = can't create an instance directly. Other servlets EXTEND this.
// "extends HttpServlet" = this IS a servlet, inherits doGet/doPost/etc.
public abstract class BaseServlet extends HttpServlet {

    // Gson instance shared by all methods in this servlet.
    // "protected" = accessible by child classes (CustomerServlet, etc.)
    // Only ONE instance needed — Gson is thread-safe.
    protected final Gson gson = new Gson();

    // ─── HELPER: Send any Java object as JSON ──────────────
    // Called like: sendJson(res, customerList);
    // Output: HTTP 200, Content-Type: application/json, body: [{"name":"Ahmed"}, ...]
    protected void sendJson(HttpServletResponse res, Object data) throws IOException {
        // Tell the browser: "this response is JSON, not HTML"
        res.setContentType("application/json");
        // UTF-8: supports Arabic, emoji, special characters
        res.setCharacterEncoding("UTF-8");
        // gson.toJson() converts ANY Java object to a JSON string
        // getWriter() gets the output stream to write the response body
        res.getWriter().print(gson.toJson(data));
    }

    // ─── HELPER: Read JSON from request body into a Java object ─
    // Called like: Customer c = readJson(req, Customer.class);
    // Input body: {"name":"Ahmed"} → creates Customer object with name="Ahmed"
    protected <T> T readJson(HttpServletRequest req, Class<T> clazz) throws IOException {
        // <T> = generic type. clazz tells Gson WHAT class to create.
        // req.getReader() reads the raw text body of the HTTP request.
        // gson.fromJson() parses JSON text → Java object
        return gson.fromJson(req.getReader(), clazz);
    }

    // ─── HELPER: Send an error response ────────────────────
    // Called like: sendError(res, 404, "Customer not found");
    // Output: HTTP 404, body: {"error": "Customer not found"}
    protected void sendError(HttpServletResponse res, int status, String message)
            throws IOException {
        res.setStatus(status);
        // Map.of() creates a quick key-value pair for the JSON body
        sendJson(res, Map.of("error", message));
    }

    // ─── HELPER: Extract path parameter ────────────────────
    // URL: /api/customers/42 → returns "42"
    // URL: /api/customers    → returns null
    protected String getPathParam(HttpServletRequest req) {
        // getPathInfo() returns everything AFTER the servlet mapping
        // @WebServlet("/api/customers/*") + URL "/api/customers/42" → pathInfo = "/42"
        String pathInfo = req.getPathInfo();
        // No path after the base URL
        if (pathInfo == null || pathInfo.equals("/")) {
            return null;
        }
        // Remove leading "/" → "42"
        return pathInfo.substring(1);
    }
}
```

---

## File 2: CorsFilter.java (Write This Second)

### Steps:
1. Create folder: `src/main/java/com/billing/filter/`
2. Think: "SvelteKit runs on :5173, Tomcat on :8080. Browser blocks cross-port requests by default. CORS headers tell the browser it's OK."
3. Type the code

```java
package com.billing.filter;

// ─── IMPORTS ───────────────────────────────────────────────
// Filter: Interface for "middleware" — code that runs BEFORE your servlet
import jakarta.servlet.Filter;
// FilterChain: The chain of filters. You call chain.doFilter() to pass
// the request to the next filter, or to the servlet if you're the last filter.
import jakarta.servlet.FilterChain;
// ServletException: Checked exception that filters/servlets can throw
import jakarta.servlet.ServletException;
// ServletRequest/Response: Generic versions. We cast to Http* versions.
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletResponse;
// @WebFilter: Annotation that tells Tomcat "run this filter for matching URLs"
import jakarta.servlet.annotation.WebFilter;
// Http versions give us headers, methods, status codes
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;

// ─── FILTER ────────────────────────────────────────────────
// "/*" = run this filter for ALL requests
// This MUST run before AuthFilter, so we set a low order
@WebFilter("/*")
public class CorsFilter implements Filter {

    @Override
    public void doFilter(ServletRequest request, ServletResponse response,
                         FilterChain chain) throws IOException, ServletException {

        // Cast generic types to HTTP-specific types
        // (filters use generic types for historical reasons)
        HttpServletResponse res = (HttpServletResponse) response;
        HttpServletRequest req = (HttpServletRequest) request;

        // ─── CORS HEADERS ──────────────────────────────────
        // "Allow requests from SvelteKit dev server"
        res.setHeader("Access-Control-Allow-Origin", "http://localhost:5173");
        // "Allow these HTTP methods"
        res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        // "Allow these headers in the request"
        res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
        // "Allow cookies/sessions to be sent cross-origin"
        res.setHeader("Access-Control-Allow-Credentials", "true");

        // ─── PREFLIGHT HANDLING ────────────────────────────
        // Browsers send an OPTIONS request BEFORE the real request
        // to ask "is this cross-origin request allowed?"
        // We respond with 200 and the headers above. No further processing.
        if ("OPTIONS".equalsIgnoreCase(req.getMethod())) {
            res.setStatus(200);
            return;  // Stop here. Don't call chain.doFilter().
        }

        // ─── PASS TO NEXT FILTER / SERVLET ─────────────────
        // If not OPTIONS, continue the request chain
        chain.doFilter(request, response);
    }
}
```

---

## File 3: AuthFilter.java (Write This Third)

### Steps:
1. Think: "Which URLs need protection? All `/api/*` EXCEPT `/api/auth/login`"
2. Think: "How do I check login? `HttpSession` — Tomcat manages it for me"
3. Type the code

```java
package com.billing.filter;

import jakarta.servlet.Filter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletResponse;
import jakarta.servlet.annotation.WebFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
// HttpSession: Server-side storage tied to a browser session via cookie
// Tomcat auto-manages the JSESSIONID cookie
import jakarta.servlet.http.HttpSession;

import java.io.IOException;

// Only filter /api/* paths — static files and frontend don't need auth
@WebFilter("/api/*")
public class AuthFilter implements Filter {

    @Override
    public void doFilter(ServletRequest request, ServletResponse response,
                         FilterChain chain) throws IOException, ServletException {

        HttpServletRequest req = (HttpServletRequest) request;
        HttpServletResponse res = (HttpServletResponse) response;

        String path = req.getRequestURI();

        // ─── SKIP AUTH FOR LOGIN ENDPOINT ──────────────────
        // Can't require login to... log in. That would be circular.
        if (path.endsWith("/auth/login")) {
            chain.doFilter(request, response);
            return;
        }

        // ─── CHECK SESSION ─────────────────────────────────
        // getSession(false) = get existing session, DON'T create new one
        // If user never logged in, session is null
        HttpSession session = req.getSession(false);

        if (session != null && session.getAttribute("user") != null) {
            // ✅ User is logged in — let the request through
            chain.doFilter(request, response);
        } else {
            // ❌ Not logged in — block with 401
            res.setStatus(401);
            res.setContentType("application/json");
            res.getWriter().print("{\"error\": \"Not authenticated\"}");
            // Note: we do NOT call chain.doFilter() — request stops here
        }
    }
}
```

---

## File 4: AuthServlet.java (Login/Logout)

### Steps:
1. Think: "Login = verify password, create session. Logout = destroy session."
2. Think: "Password stored as bcrypt hash. Never compare plain text."
3. Type the code

```java
package com.billing.servlet;

// ─── IMPORTS ───────────────────────────────────────────────
import com.billing.dao.UserDAO;
import com.billing.model.AppUser;

import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

import java.io.IOException;
import java.util.Map;

// BCrypt: Password hashing library. One-way hash — can verify but never decrypt.
// checkpw("plain", "$2a$10$hash...") returns true/false
import org.mindrot.jbcrypt.BCrypt;

// ─── SERVLET ───────────────────────────────────────────────
@WebServlet("/api/auth/*")
public class AuthServlet extends BaseServlet {

    // DAO = Data Access Object. Talks to the database.
    // Created once, reused for all requests.
    private final UserDAO userDAO = new UserDAO();

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res)
            throws IOException {

        String path = req.getPathInfo();  // "/login" or "/logout"

        if ("/login".equals(path)) {
            handleLogin(req, res);
        } else if ("/logout".equals(path)) {
            handleLogout(req, res);
        } else {
            sendError(res, 404, "Not found");
        }
    }

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res)
            throws IOException {
        // GET /api/auth/me → return current user info
        HttpSession session = req.getSession(false);
        if (session == null || session.getAttribute("user") == null) {
            sendError(res, 401, "Not logged in");
            return;
        }
        // Send back the user object stored in session
        sendJson(res, session.getAttribute("user"));
    }

    private void handleLogin(HttpServletRequest req, HttpServletResponse res)
            throws IOException {
        // ─── Step 1: Read credentials from request body ────
        // Body: {"username": "admin", "password": "admin123"}
        Map<String, String> body = readJson(req, Map.class);
        String username = body.get("username");
        String password = body.get("password");

        // ─── Step 2: Look up user in database ──────────────
        AppUser user = userDAO.findByUsername(username);
        if (user == null) {
            sendError(res, 401, "Invalid username or password");
            return;
        }

        // ─── Step 3: Verify password with bcrypt ───────────
        // BCrypt.checkpw compares plain password against stored hash
        // NEVER do: password.equals(user.getPasswordHash())
        if (!BCrypt.checkpw(password, user.getPasswordHash())) {
            sendError(res, 401, "Invalid username or password");
            return;
        }

        // ─── Step 4: Create session ────────────────────────
        // getSession(true) = create new session
        // Tomcat will automatically set a JSESSIONID cookie in the response
        HttpSession session = req.getSession(true);
        // Don't store the password hash in session!
        user.setPasswordHash(null);
        session.setAttribute("user", user);

        // ─── Step 5: Respond with user info ────────────────
        res.setStatus(200);
        sendJson(res, user);
    }

    private void handleLogout(HttpServletRequest req, HttpServletResponse res)
            throws IOException {
        HttpSession session = req.getSession(false);
        if (session != null) {
            session.invalidate();  // Destroy session + cookie
        }
        sendJson(res, Map.of("message", "Logged out"));
    }
}
```

---

## File 5: CustomerServlet.java (Your First CRUD Servlet)

### Steps:
1. Think: "What operations? List, Search, Get by ID, Create, Update"
2. Think: "GET = read data. POST = create. PUT = update."
3. Think: "How do I tell list vs get-by-id? Check if path param exists."

```java
package com.billing.servlet;

import com.billing.dao.CustomerDAO;
import com.billing.model.Customer;

import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.util.List;

@WebServlet("/api/customers/*")
public class CustomerServlet extends BaseServlet {

    private final CustomerDAO customerDAO = new CustomerDAO();

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res)
            throws IOException {

        String pathParam = getPathParam(req);  // null or "5" or "5/invoices"

        if (pathParam == null) {
            // ─── LIST / SEARCH ─────────────────────────────
            // GET /api/customers         → list all
            // GET /api/customers?q=Ahmed → search by name
            String query = req.getParameter("q");
            List<Customer> customers;

            if (query != null && !query.isEmpty()) {
                customers = customerDAO.search(query);
            } else {
                customers = customerDAO.findAll();
            }
            sendJson(res, customers);

        } else if (pathParam.contains("/")) {
            // ─── SUB-RESOURCE ──────────────────────────────
            // GET /api/customers/5/invoices
            // TODO: implement after InvoiceDAO is ready
            sendError(res, 501, "Not implemented yet");

        } else {
            // ─── GET BY ID ─────────────────────────────────
            // GET /api/customers/5
            try {
                int id = Integer.parseInt(pathParam);
                Customer customer = customerDAO.findById(id);
                if (customer == null) {
                    sendError(res, 404, "Customer not found");
                } else {
                    sendJson(res, customer);
                }
            } catch (NumberFormatException e) {
                sendError(res, 400, "Invalid customer ID");
            }
        }
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res)
            throws IOException {
        // ─── CREATE ────────────────────────────────────────
        // POST /api/customers  body: {"name":"Ahmed","address":"Cairo"}
        Customer customer = readJson(req, Customer.class);
        Customer created = customerDAO.create(customer);
        res.setStatus(201);  // 201 = Created (not 200!)
        sendJson(res, created);
    }

    @Override
    protected void doPut(HttpServletRequest req, HttpServletResponse res)
            throws IOException {
        // ─── UPDATE ────────────────────────────────────────
        // PUT /api/customers/5  body: {"name":"Ahmed Updated"}
        String pathParam = getPathParam(req);
        if (pathParam == null) {
            sendError(res, 400, "Customer ID required");
            return;
        }
        try {
            int id = Integer.parseInt(pathParam);
            Customer customer = readJson(req, Customer.class);
            customer.setId(id);
            Customer updated = customerDAO.update(customer);
            if (updated == null) {
                sendError(res, 404, "Customer not found");
            } else {
                sendJson(res, updated);
            }
        } catch (NumberFormatException e) {
            sendError(res, 400, "Invalid customer ID");
        }
    }
}
```

---

## Writing Order (Type These In This Sequence)

| # | File | Why This Order |
|---|------|---------------|
| 1 | `BaseServlet.java` | Foundation — all servlets use this |
| 2 | `CorsFilter.java` | Needed before any frontend testing |
| 3 | `AuthFilter.java` | Security gate for all `/api/*` |
| 4 | Models (`Customer.java`, etc.) | POJOs — just fields + getters/setters |
| 5 | DAOs (`CustomerDAO.java`, etc.) | DB access — uses JDBC you learned |
| 6 | `AuthServlet.java` | Login must work before testing others |
| 7 | `CustomerServlet.java` | First CRUD — pattern for all others |
| 8 | Remaining servlets | Copy pattern from CustomerServlet |

---

## File 6: Database Connection (DB.java)

### Steps:
1. Think: "I need a single place to handle connections so I don't repeat the URL/User/Pass everywhere."
2. Create `src/main/java/com/billing/db/DB.java`.

```java
package com.billing.db;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.Properties;
import java.io.InputStream;

public class DB {
    private static final Properties props = new Properties();

    static {
        // Load db.properties from the classpath (src/main/resources)
        try (InputStream in = DB.class.getClassLoader().getResourceAsStream("db.properties")) {
            props.load(in);
            Class.forName("org.postgresql.Driver");
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public static Connection getConnection() throws SQLException {
        // DriverManager opens the real connection
        return DriverManager.getConnection(
            props.getProperty("db.url"),
            props.getProperty("db.user"),
            props.getProperty("db.password")
        );
    }
}
```

---

## File 7: The Modern Frontend (SvelteKit)

### Key Concept: The `fetch` flow
When you click "Login" in Svelte:
1. `+page.svelte` script runs.
2. It calls `fetch('http://localhost:8080/api/auth/login')`.
3. Tomcat receives the request, `AuthServlet` runs.
4. Servlet returns JSON: `{"username": "admin"}`.
5. Svelte receives the JSON and updates the UI (e.g., `goto('/dashboard')`).

### Example: Login logic in Svelte
```javascript
let username = $state('');
let password = $state('');

async function login() {
    const res = await fetch('/api/auth/login', {
        method: 'POST',
        body: JSON.stringify({ username, password })
    });
    
    if (res.ok) {
        window.location.href = '/dashboard';
    } else {
        alert('Login failed!');
    }
}
```

> [!TIP]
> **Learning Strategy**: Start by making a tiny change in the Java code (like changing an error message), redeploy, and see it show up in the browser. This confirms you understand the "Full Stack" connection!
