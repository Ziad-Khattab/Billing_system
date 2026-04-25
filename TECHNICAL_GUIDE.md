# 📘 FMRZ Telecom Billing System: Technical Guide

This guide provides a deep dive into the architecture, connectivity, and data management of the FMRZ Telecom Billing System. It is designed for developers and teammates to understand how the system operates from frontend to backend.

---

## 🏗️ 1. Architecture Overview

The system follows a classic **Three-Tier Architecture**, modernized with a decoupled frontend:

1.  **Presentation Tier**: Built with **SvelteKit** (Modern JS Framework).
2.  **Logic Tier**: Built with **Jakarta EE (Servlets)** running on **Tomcat 11**.
3.  **Data Tier**: Powered by **PostgreSQL (Neon DB)** with high-performance stored procedures.

---

## 🔗 2. Frontend to Backend Connectivity

### The Bridge: REST APIs
The frontend and backend communicate exclusively through **JSON REST APIs**.
-   **Frontend**: SvelteKit uses the browser's `fetch()` API to call backend endpoints.
-   **Backend**: Java Servlets (extending `BaseServlet`) process requests and return JSON using **Gson**.

### Development vs. Production
| Feature | Development (Local) | Production (Tomcat) |
| :--- | :--- | :--- |
| **Frontend Server** | Vite Dev Server (Port 5173) | Static files in `src/main/webapp` |
| **API Proxy** | `vite.config.js` proxies `/api` to `localhost:8080` | Native Servlet mapping at `/api/*` |
| **Asset Loading** | Hot Module Replacement (HMR) | `HtmlInjectionFilter` handles hashed CSS/JS |

### 🛠️ The `HtmlInjectionFilter` (Technical Magic)
SvelteKit generates randomized filenames for CSS/JS (e.g., `0.DC_ZIXDP.css`). To ensure Tomcat always serves the correct version:
1.  The filter intercepts the initial HTML request.
2.  It scans the `/_app/immutable/assets` directory for the latest CSS/JS files.
3.  It dynamically injects these `<link>` and `<script>` tags into the HTML head before it reaches the user's browser.

---

## 🏛️ 3. The DAO Pattern (Data Access Object)

We use the **DAO Pattern** to centralize all database interactions. This prevents "Spaghetti Code" by ensuring that SQL logic stays out of your Servlets.

### The Flow:
`Browser Request` ➔ `Servlet` ➔ `DAO` ➔ `DB.java (Connection Pool)` ➔ `PostgreSQL`

### Implementation Example: `BillDAO.java`
```java
public class BillDAO {
    public List<Bill> findByContractId(int contractId) throws SQLException {
        String sql = "SELECT * FROM bill WHERE contract_id = ?";
        try (Connection conn = DB.getConnection(); // Gets connection from Pool
             PreparedStatement pstmt = conn.prepareStatement(sql)) {
            // ... Logic to map ResultSet to Bill Objects
        }
    }
}
```

### Why DAOs are Mandatory:
-   **Separation of Concerns**: Servlets handle HTTP; DAOs handle Data.
-   **Reusability**: Multiple Servlets can use the same DAO.
-   **Security**: Centralizes `PreparedStatement` usage to prevent SQL Injection.

---

## ⚡ 4. Database Integration: HikariCP

To reduce latency when talking to **Neon DB** (which is hosted in Europe), we implemented **HikariCP Connection Pooling**.

-   **Problem**: Opening a new TLS connection to Europe on every page load takes **~500ms**.
-   **Solution**: HikariCP keeps a "Warm Pool" of 10 connections open at all times.
-   **Result**: Database queries now take **< 20ms**, making the "Packages" and "Dashboard" pages load near-instantly.

---

## 🌍 5. Teammate Updates: Roaming Support (Fouad's Repo)

We have integrated the latest features from Fouad's repository, which adds **Roaming Logic** to the billing engine.

### Key Additions:
1.  **Roaming Detection**: The `rate_cdr` SQL function now compares `hplmn` (Home PLMN) with `vplmn` (Visited PLMN). If they differ, it flags the CDR as roaming.
2.  **Roaming Multiplier**: International usage is billed at **2x** the standard rate by default.
3.  **`ror_contract` table**: Now tracks `roam_voice`, `roam_data`, and `roam_sms` separately from local usage.
4.  **CDR Parser**: Updated to read roaming-specific fields from CSV files and pass them to the database.

---

## 🚀 6. Full Deployment Guide

### Prerequisites
-   **Java 21** (Use `sdk install java 21.0.2-tem`)
-   **Node.js 18+** (Use `nvm install --lts`)

### Commands (The "Golden Path")
Run these from the project root:

```bash
# 1. Prepare Frontend
cd frontend && npm install && npm run build && cd ..

# 2. Package Backend
./mvnw clean package

# 3. Start Server
./mvnw cargo:run
```

> [!TIP]
> Use `fuser -k 8080/tcp || true` before running the server to kill any "ghost" Tomcat processes that might be holding the port.

---

## 📋 7. Team Discussion Points
1.  **Security**: We need to move from plain-text passwords to **BCrypt** hashing.
2.  **Bill Adjustments**: Implement a `modify_bill` SQL function to handle partial credits without deleting full records.
3.  **PDF Invoicing**: Integrate **JasperReports** to generate professional PDF bills (triggered in `BillDAO.pay`).
