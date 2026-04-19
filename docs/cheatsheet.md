# 🚀 FMRZ Telecom — Development Cheat Sheet

This is your one-page quick reference for the entire tech stack. Keep this open while you code!

---

## 🌐 HTTP Methods & Status Codes
| Method | Purpose | Example URL |
|--------|---------|-------------|
| **GET** | Read/Fetch data | `/api/customers` |
| **POST** | Create new data | `/api/auth/login` |
| **PUT** | Update existing data | `/api/customers/5` |
| **DELETE**| Remove data | `/api/contracts/10` |

| Code | Meaning | What to check? |
|------|---------|----------------|
| **200 OK** | Success! | Everything went fine. |
| **201 Created** | New item made | Usually returned after a `POST`. |
| **400 Bad Req** | Client error | Check your JSON body or parameters. |
| **401 Unauth** | Login required | User needs to log in first. |
| **403 Forbidden**| Not allowed | Admin-only page accessed by customer. |
| **404 Not Found**| URL wrong | Check `@WebServlet` mapping. |
| **500 Error** | Server crashed | Check Tomcat logs (`catalina.out`)! |

---

## ☕ Java JDBC (Database)
**The standard pattern in every DAO method:**
1. Get Connection: `try (Connection conn = DB.getConnection())`
2. Prepare SQL: `PreparedStatement ps = conn.prepareStatement(sql)`
3. Set Params: `ps.setInt(1, id)` (**Starts at 1!**)
4. Run Query: `ResultSet rs = ps.executeQuery()`
5. Map Data: `while (rs.next()) { ... }`

**Key classes:**
- `BigDecimal`: Use this for money! `Double` is for math, `BigDecimal` is for billing.
- `LocalDate`: Modern date handling.
- `try-with-resources`: Auto-closes connections so you don't leak memory.

---

## ⚡ Svelte (Frontend Runes)
| Rune | What it does | Example |
|------|--------------|---------|
| `$state()` | Reactive variable | `let count = $state(0);` |
| `$derived()`| Computed value | `let double = $derived(count * 2);` |
| `$effect()` | Runs on change | ` $effect(() => { console.log(count); });` |
| `$props()` | Component input | `let { name } = $props();` |

**Calling Tomcat from Svelte:**
```javascript
const res = await fetch('http://localhost:8080/api/auth/login', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ username, password })
});
```

---

## 🏗️ Architecture Layers
1. **Frontend (SvelteKit)**: The UI. Talks to the API via `fetch`.
2. **Controller (Servlet)**: The Entry point. Receives HTTP request → Calls DAO.
3. **DAO (Data Access Object)**: The DB Bridge. SQL queries live here.
4. **Model (POJO)**: The Data Container. Simple class with fields + getters/setters.
5. **Database (PostgreSQL)**: The Persistence. Where data lives forever.

---

## 🛠️ Build Tools
- **Maven (`mvn`)**: Handles Java dependencies and building the `.war` file.
- **Tomcat**: The web server that hosts and runs your Java `.war`.
- **Vite**: The dev server that runs your SvelteKit frontend.
- **psql**: Command-line tool to talk to PostgreSQL.
