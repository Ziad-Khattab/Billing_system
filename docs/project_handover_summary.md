# 💎 FMRZ TELECOM BILLING: SOTA PROJECT HANDOVER

## 🏗️ 0. THE DIRECTORY RULEBOOK (READ THIS FIRST)
- **Learning Workspace (WRITE HERE)**:
  - `/home/zkhattab/Billing_system/src/`: Your Java source code area.
  - `/home/zkhattab/Billing_system/frontend/`: Your SvelteKit UI area.
- **Solution Reference (READ ONLY)**:
  - `/home/zkhattab/Billing_system/backend_reference/`: The completed Java solution.
  - `/home/zkhattab/Billing_system/frontend_reference/`: The completed Svelte solution.
- **Note**: The reference folders are in `.gitignore` and should **not** be modified.

---

## 🔒 0.1 SECURITY GUARDS (SOTA Best Practice)
- **Frontend Guard**: In `admin/+page.svelte`, always check for the `.nav-user` and `.badge-admin` classes before loading data to prevent unauthorized UI viewing.
- **Backend Guard**: The `AuthFilter` protects all `/api/*` routes. Ensure `PublicServlet` routes are explicitly allowed to show packages without a login.
- **DB Seeding**: Use `psql` to seed the `rateplan` table so the "Packages" page isn't empty during your demos.


---

## 🏗️ 1. INTEGRATION & PROXY (The "Glue")
- **Frontend Port**: `5173` (Vite).
- **Backend Port**: `8080` (Tomcat).
- **Proxy Config**: Ensure your `vite.config.js` has the following block:
```javascript
server: {
    proxy: {
        '/api': {
            target: 'http://localhost:8080',
            changeOrigin: true
        }
    }
}
```

---

## 🗄️ 2. DATABASE SCHEMA (The "Foundation")
Execute this in your `psql` terminal to set up the structure:
```sql
CREATE TABLE app_user (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255),
    role VARCHAR(50) DEFAULT 'customer',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE customer (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    address TEXT,
    email VARCHAR(255),
    birthdate DATE,
    user_id INTEGER REFERENCES app_user(id)
);
```
*(Full backup: `docs/schema_backup.sql`)*

---

## 🐛 3. THE "JAVA 21" VACCINE
You MUST register custom adapters in `BaseServlet.java` to prevent Gson reflection crashes:
```java
protected static final Gson gson = new GsonBuilder()
    .registerTypeAdapter(LocalDate.class, new GsonTypeAdapters.LocalDateAdapter())
    .registerTypeAdapter(LocalDateTime.class, new GsonTypeAdapters.LocalDateTimeAdapter())
    .create();
```

---

## 🚀 4. THE SOTA BUILD PIPELINE
Build, deploy, and restart Tomcat:
```bash
./mvnw clean package -DskipTests -q && cp target/*.war /home/zkhattab/portable/tomcat11/webapps/ROOT.war && /home/zkhattab/portable/tomcat11/bin/shutdown.sh; sleep 2; /home/zkhattab/portable/tomcat11/bin/startup.sh
```

---

**Everything is tracked, ignored, and documented. See you in the next chat!** 🥂💎🚀🎓
