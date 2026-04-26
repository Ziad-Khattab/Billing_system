# 🚀 FMRZ Telecom Billing System — Ultimate Project Guide

This is the definitive technical resource for the FMRZ Telecom Billing System. It consolidates all previous guides, deployment steps, and architecture notes into a single source of truth.

---

## 🏛️ 1. System Architecture

The FMRZ platform is a modern, high-performance billing engine built with a **Hybrid SPA + Java Backend** architecture.

### **The Tech Stack**
-   **Frontend**: SvelteKit 5 (Runes-based) + Vanilla CSS (Supreme Obsidian Theme).
-   **Backend**: Jakarta EE (Servlets & Filters) on Apache Tomcat.
-   **Database**: PostgreSQL (Hosted on Neon DB) with HikariCP Connection Pooling.
-   **Language**: Java 21 (Records, Patterns) + Node.js 18+.

### **Architecture: Generic DB Helper (The Pivot)**
We have moved away from the rigid DAO (Data Access Object) pattern. Instead, we use a **Generic DB Helper (`DB.java`)**.
-   **Why?**: This allows the Java backend to instantly support new database columns added by teammates (e.g., Roaming fields) without requiring code changes to Model classes or DAOs.
-   **How it works**: `DB.executeSelect` returns a `List<Map<String, Object>>`, which GSON converts directly to JSON for the frontend.

---

## 📂 2. Project Directory Structure
```text
Billing_system/
├── frontend/                # SvelteKit Source Code
│   ├── src/
│   │   ├── routes/          # UI Pages (Admin, Profile, Login)
│   │   └── app.css          # SOTA Glassmorphism Design System
├── src/main/java/           # Java Backend
│   ├── com/billing/
│   │   ├── cdr/             # Rating Engine & CSV Parser (Roaming Support)
│   │   ├── db/              # HikariCP Connection Pooling & Generic DB Helper
│   │   ├── filter/          # Auth, Security, & Asset Injection Filters
│   │   └── servlet/         # REST API Endpoints
├── src/main/resources/      # Configuration (db.properties)
├── input/                   # Entry point for CDR CSV files
└── pom.xml                  # Maven Configuration
```

---

## 🚀 3. Deployment & Development

### **The "Golden Path" (Full Build)**
To rebuild the entire system and start the server:
```bash
# Clean, Package, and Run
cd frontend && npm install && npm run build && cd ..
./mvnw clean package cargo:run
```

### **Rapid UI Development**
For styling and frontend changes only:
```bash
cd frontend && npm run dev
```
*Note: The frontend dev server proxies `/api` requests to `localhost:8080` automatically.*

### **Troubleshooting: Ghost Processes**
If port 8080 is blocked:
```bash
fuser -k 8080/tcp || true
```

---

## 📡 4. Core Features & Logic

### **Rating Engine (Roaming Support)**
The CDR engine (`CDRParser.java`) and the `rate_cdr` SQL function now support international roaming:
-   **Detection**: Compares `hplmn` vs `vplmn`.
-   **Pricing**: Roaming usage is billed at a **2x multiplier** by default.
-   **Storage**: Usage is aggregated in `contract_consumption` with specific roaming buckets.

### **Security & Asset Injection**
The `AppFilter.java` is the "Brain" of the deployment:
1.  **Auth Guard**: Blocks `/admin/*` and `/api/admin/*` for non-admin users.
2.  **Asset Injector**: Automatically scans the `_app/immutable/assets` folder and injects the latest CSS/JS hashes into the HTML, solving caching issues.
3.  **Anti-Latency**: Sets strict `Cache-Control` headers to ensure "instant" UI updates upon refresh.

---

## 🗄️ 5. Database Schema (Critical Tables)
1.  **`user_account`**: Auth & Roles (Admin vs Customer).
2.  **`contract`**: Links MSISDN to a `rateplan`.
3.  **`cdr`**: Raw call records (rated/unrated status).
4.  **`contract_consumption`**: Real-time usage tracking.
5.  **`bill`**: Monthly invoices generated from consumption.

---

## 📋 6. Future Roadmap
-   **BCrypt Integration**: Moving from plain-text passwords to secure hashing.
-   **JasperReports**: Professional PDF invoice generation.
-   **Real-time Dashboard**: Live usage graphs using Chart.js on the Admin panel.

---

**Last Updated:** April 26, 2026 (Refactored to Generic DB Helper)
