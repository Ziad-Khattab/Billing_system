# Telecom Billing System 🚀

A modular Telecom Billing System built with a Java-based backend and a reactive frontend.

---

## 🏗️ Architecture Stack
- **Backend**: Java (Jakarta EE 11) on Apache Tomcat 11.
- **Frontend**: SvelteKit 5 (Static Adapter) featuring an **AMOLED Obsidian** dark-mode interface.
- **Database**: PostgreSQL (**Neon DB**) with HikariCP connection pooling.
- **Reporting**: **JasperReports 7.0.4** (element kind schema) with hardened font merging.
- **Security**: Unified `AppFilter` for session management and path normalization.
- **Observability**: Built-in **Health Check (`/health`)** for real-time monitoring.

---

## ✨ Key Features
- **Administrative Control Panel**: A central dashboard for managing the telecom lifecycle: Customers, Contracts, Service Packages, and Rateplans.
- **CDR Engine**: A Java-based parser (`CDRParser`) that validates, rates, and transforms raw CSV data into financial records.
- **Jasper 7 Invoicing**: PDF generation using the **7.0.4 element-kind schema** with hardened font merging.
- **Automated Billing**: Server-side logic for 10% tax calculation, recurring service assignment, and one-time fee processing.
- **SPA Path Resilience**: A robust `AppFilter` that manages path normalization for SvelteKit client-side routing and system paths like `/health`.
- **Unified Security Model**: Multi-layered authentication with session-based enforcement and HTTP-only cookie security.
- **Cloud Database (NeonDB)**: Distributed PostgreSQL architecture with **HikariCP** for connection pooling.

---

## 🚀 Deployment & Execution

### 1. Development (IDE Mode - IntelliJ / NetBeans)
1.  **Configure Secrets**: Create a `.env` file from `.env.example`. 
2.  **Link to IDE**: In IntelliJ, edit your 'Main' Run Configuration and select the `.env` file (or paste variables).
3.  **Safety Net**: The app will automatically run a **Diagnostic Boot Check** and warn you if credentials are missing.
4.  **Run** `com.billing.Main` class directly.

### 2. Production (Container Mode - Podman)
1.  **Build the Golden JAR**: `./mvnw clean package -DskipTests`
2.  **Launch**: `podman-compose up -d --build`
3.  **Health Check**: Visit `http://localhost:8080/health` to confirm status.

---

## 🛠️ Infrastructure & DevOps (Containerized Architecture)

The system has been upgraded to a **Hardened Standalone JAR** architecture, protected by an **Nginx Edge Gateway** and managed via **Podman Orchestration**.

### 1. The "Nginx Armor" (Synchronized Proxy)
- **Unified Proxying**: Nginx proxies all traffic to the container, ensuring UI and API are always in sync.
- **Security Headers**: Injects `X-Frame-Options`, `X-Content-Type-Options` at the edge.
- **Domain Mapping**: Configured for `http://billing.local`.

### 2. Standalone Engine (Self-Detecting JAR)
- **Dynamic Resource Mapping**: Detects its environment and adjusts resource scanning (`JarResourceSet`).
- **Embedded Tomcat 11**: Self-contained server with optimized connector threads.

### 3. Container Orchestration (Podman)
- **Production Image**: Uses a lightweight JRE and a **non-root user** (`javauser`).
- **Health Check**: Automatic container recovery using the `/health` endpoint.

---

## 🛡️ Security Hardening Audit (April 2026)
| Component | Status | Fix Description |
| :--- | :--- | :--- |
| **Identity** | ✅ Hardened | Running as non-root `javauser` to prevent container escape. |
| **Secrets** | ✅ Secured | Defensive "Safety Net" check prevents boot-up with leaked secrets. |
| **Observability**| ✅ Production | Integrated `/health` endpoint for automated Cloud monitoring. |
| **Build** | ✅ Enterprise | All LICENSE/NOTICE and Jasper properties merged for a Zero-Warning build. |
| **Reporting** | ✅ Optimized | JIT Caching + Fragmented Font merging (Jasper 7 fix). |
| **Assets** | ✅ Synchronized | Atomic UI/API updates via container-native asset serving. |

---

*This architecture ensures that the FMRZ Telecom Billing System is secure, portable, and ready for high-scale production loads.* 🏎️🛡️🚀