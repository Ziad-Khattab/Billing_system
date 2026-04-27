# Telecom Billing System 🚀

A modular Telecom Billing System built with a Java-based backend and a reactive frontend.

---

## 🏗️ Architecture Stack
- **Backend**: Java (Jakarta EE 11) on Apache Tomcat 11.
- **Frontend**: SvelteKit 5 (Static Adapter) featuring an **AMOLED Obsidian** dark-mode interface.
- **Database**: PostgreSQL (**Neon DB**) with HikariCP connection pooling.
- **Reporting**: **JasperReports 7.0.1** (element kind schema) for PDF invoice generation.
- **Security**: Unified `AppFilter` for session management and path normalization.

---

## ✨ Key Features
- **Administrative Control Panel**: A central dashboard for managing the telecom lifecycle: Customers, Contracts, Service Packages, and Rateplans.
- **CDR Engine**: A Java-based parser (`CDRParser`) that validates, rates, and transforms raw CSV data into financial records.
- **Jasper 7 Invoicing**: PDF generation using the **7.0.1 element-kind schema**, featuring custom SVG iconography.
- **Automated Billing**: Server-side logic for 10% tax calculation, recurring service assignment, and one-time fee processing.
- **SPA Path Resilience**: A robust `AppFilter` that manages path normalization for SvelteKit client-side routing within a Jakarta EE container.
- **Unified Security Model**: Multi-layered authentication with session-based enforcement and HTTP-only cookie security.
- **Cloud Database (NeonDB)**: Distributed PostgreSQL architecture with **HikariCP** for connection pooling.

---

## 🚀 Deployment & Execution

### Prerequisites
- Java 21+
- Maven 3.9+
- Node.js 20+

### Primary Execution Command
The project utilizes the Maven Cargo plugin for a seamless deployment experience:
```bash
./mvnw clean package cargo:run
```
*Access the application at: http://localhost:8080*

### Standard Administrative Credentials
- **Username**: `admin`
- **Password**: `admin123`

## 🔄 System Core & Data Flow

Understanding the lifecycle of a transaction in FMRZ:

1.  **Ingestion Phase**: Raw CDR (Call Detail Record) files are placed in the `input/` directory.
2.  **Rating Phase**: The `AdminCDRServlet` triggers the `CDRParser`. The system identifies the `MSISDN`, lookups the active `RatePlan`, and calculates costs for Voice (Mins), Data (GB), and SMS.
3.  **Persistence Phase**: Rated records are committed to the `cdr` table in NeonDB, and the raw file is archived to `processed/`.
4.  **Billing Cycle**: The system aggregates rated CDRs, applies `Recurring Services` (from `contract_service`), adds `One-time Fees`, and calculates a **10% Government Tax** on the subtotal.
5.  **Rendering Phase**: When a user requests an invoice, the `CustomerProfileServlet` passes the `BILL_ID` to the Jasper engine. The `invoice.jrxml` template is populated via a direct JDBC sub-query and rendered into a PDF document.

## 🧱 Core Component Breakdown

### 🟢 Backend (The Engine)
- **`com.billing.servlet.*`**: The API layer. Each servlet is specialized for a resource (e.g., `AdminUserServlet` for identity, `AdminBillServlet` for finance).
- **`com.billing.filter.AppFilter`**: The "Traffic Controller". It intercepts all requests to handle path normalization—this allows SvelteKit's deep links (like `/profile/invoices`) to work without triggering a Tomcat 404.
- **`com.billing.db.DB`**: A thread-safe Singleton managing the HikariCP pool. It ensures the application can handle hundreds of concurrent database connections to NeonDB efficiently.

### 🔴 Frontend Implementation
- **Design Philosophy**: Built on an "Obsidian Dark" foundation (`#000000`) with high-contrast crimson accents (`#E00800`).
- **SvelteKit 5**: Utilizes Svelte components for reactive updates in the Admin dashboard.
- **Static Integration**: The frontend is pre-built and served as optimized static assets from `src/main/webapp`, allowing for zero-overhead delivery by Tomcat.

### 📊 Database Schema & Financial Integrity
- **`user_account`**: Identity provider with hashed credentials and role-based permissions (`admin` vs `customer`).
- **`contract`**: The central pivot point. Holds `msisdn`, links to `rateplan`, and tracks `billing_cycle` status.
- **`bill`**: Immutable financial snapshots. Each record stores the exact state of usage at the time of generation, including the **10% tax** stamp.
- **`cdr`**: Raw event logs. Includes `source_msisdn`, `destination_msisdn`, `duration`, and `cost`.

---

## 📡 API Architecture & Endpoints

The system exposes a unified REST-like API via Jakarta Servlets. Each endpoint is protected by the `AuthFilter`.

### 🛡️ Administrative Endpoints (`/api/admin/*`)
- **`/customers`**: Full CRUD for user accounts.
- **`/contracts`**: Management of MSISDN assignments and rateplan links.
- **`/cdr/rate`**: The entry point for the **Rating Engine**. Ingests CSV data and performs real-time cost calculation.
- **`/billing/generate`**: Triggers the end-of-month aggregation and PDF invoice creation.
- **`/stats`**: Provides high-performance aggregation for the dashboard charts.

### 👤 Customer Endpoints (`/api/customer/*`)
- **`/profile`**: Retrieves account details and active service packages.
- **`/invoices`**: Lists historical billing records with secure ownership verification.
- **`/invoices/download`**: Streams the Jasper-rendered PDF with `Content-Disposition: attachment`.

---

## 🔒 Security & Path Engineering

### 1. The `AppFilter` (SPA Routing Fix)
In a standard Tomcat setup, navigating directly to a SvelteKit route like `/profile/invoices` would cause a 404. Our `AppFilter` detects if a request is for a frontend route (vs an API or static file) and transparently serves `index.html`. This enables **true SPA capability** within a legacy Java container.

### 2. Multi-Layered Authentication
1. **Filter Level**: `AuthFilter` checks session existence before any servlet logic executes.
2. **Role Level**: Servlets verify the `role` attribute to prevent customers from accessing administrative billing triggers.
3. **Data Level**: Invoices are queried using both `BILL_ID` and `USER_ID` to prevent ID-enumeration attacks.

---

## 🛠️ Interface Design
The interface is optimized for dark-mode environments:
- **Static Tables**: Custom CSS overrides (`.card-static`) to ensure data remains stationary.
- **Iconography**: Optimized, stroke-based SVGs (`voice.svg`, `data.svg`, `sms.svg`) ensure a consistent look across the web and PDF.
- **Visual Depth**: Uses `backdrop-filter: blur(25px)` to provide depth without distracting from the data.

---

## 🔧 Troubleshooting & Common Issues

### 1. Frontend Changes Not Appearing
**Issue**: You edited a Svelte file but the browser shows the old version.
**Fix**: SvelteKit must be recompiled into static assets. Run:
```bash
npm run build --prefix frontend
```
Then, perform a **Hard Refresh** (`Ctrl + F5`) in your browser to bypass the cache.

### 2. Jasper Font/Image Errors
**Issue**: PDF generation fails or icons are missing in the invoice.
**Fix**: JasperReports 7 is strict about resource paths. Ensure ` Pictures/` is inside `src/main/resources` and your `jasperreports.properties` is correctly pointing to the classpath.

### 3. NeonDB Connection Timeouts
**Issue**: "Connection refused" or slow queries.
**Fix**: Ensure your IP is whitelisted in the Neon Console. The system uses **HikariCP** to maintain warm connections; check `DB.java` to adjust `maximumPoolSize` if under heavy load.

---

## 📂 Project Structure

```text
├── frontend/               # SvelteKit 5 source code (UI/UX)
│   ├── src/routes/         # App pages (Dashboard, Invoices, Login)
│   └── svelte.config.js    # Adapter-static config for Tomcat deployment
├── src/main/java/          # Backend Java source (Jakarta EE)
│   └── com/billing/
│       ├── servlet/        # API Endpoints (Billing, Customer, Profile)
│       ├── model/          # POJOs (Bill, Contract, CDR, Invoice)
│       ├── db/             # NeonDB Connection Management (HikariCP)
│       ├── filter/         # Security & Path Normalization logic
│       └── cdr/            # CDR Ingestion & Rating Engine
├── src/main/resources/     # Resource Assets
│   ├── invoice.jrxml       # JasperReports 7.0.1 Invoice Template
│   ├── Pictures/           # SVG icons and logos
│   └── jasperreports.prop  # Reporting engine configuration
├── src/main/webapp/        # Compiled frontend assets (SvelteKit output)
├── whole_billing.sql       # Database schema & NeonDB initialization
└── pom.xml                 # Maven build & Dependency management
```

## 🛠️ Development & Database
- **NeonDB Integration**: The system connects to a PostgreSQL instance on Neon. Ensure your environment variables or `DB.java` are updated with the correct `DSN`.
- **Billing Logic**: Tax is calculated at a fixed **10%** rate as per pre-production requirements, handled via PostgreSQL triggers and Jasper expressions.
- **Iconography**: The project uses a custom set of Lucide-style **Red Accent SVGs** for a clean, consistent look across the web and PDF.

---

## 🧪 Operational Validation (CDR Rating Pipeline)

To verify the integrity of the call detail record (CDR) rating and billing lifecycle:

### 1. Provision a Test Contract
1. Authenticate as an **Administrator**.
2. Navigate to **Customers** -> **Add Customer**.
3. Navigate to **Contracts** -> **Add Contract** for the newly created customer.
4. Record the **MSISDN** (Phone Number) assigned to the contract (e.g., `01011223344`).

### 2. Prepare Mock CDR Data (CSV)
1. Edit any `.csv` file within the `input/` directory.
2. Insert a record utilizing the previously recorded MSISDN:
   `FILE_ID, 01011223344, 0123456789, 2026-04-24 10:00:00, 120, 1, VOICE, LOCAL, 0.0`

### 3. Execute the Rating Engine
1. From the Administrative Dashboard, access the **Call Explorer**.
2. Select **"Import & Rate New CDRs"**.
3. The system will ingest the file, move it to the `processed/` directory, and calculate the cost based on the active rate plan.

### 4. Data Verification
- **Administrative View**: Confirm the record appears in the **Call Explorer** with the calculated cost and 'Rated' status.
- **Customer View**: Authenticate as the customer to verify updated billing totals and invoice accessibility.

---

**Last Updated:** April 2026
**Release Status:** Production Stable