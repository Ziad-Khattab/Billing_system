# Telecom Billing System 🚀

A high-performance, enterprise-grade Telecom Billing System built with a robust full-stack architecture.

---

## 🏗️ Architecture Stack
- **Backend**: Java (Jakarta EE 11) on Apache Tomcat 11.
- **Frontend**: SvelteKit 5 (Static Adapter) with a high-fidelity glassmorphic interface.
- **Database**: PostgreSQL (Neon DB) featuring HikariCP connection pooling.
- **Security**: Unified `AppFilter` for session management, path normalization, and dynamic asset delivery.

---

## ✨ Key Features
- **Administrative Control Panel**: Real-time analytics for Customers, Contracts, and CDRs with dynamic visualization.
- **Optimized CDR Engine**: Engineered for high-throughput processing and automated call rating.
- **Unified Security Model**: Session-based authentication with secure, HTTP-only cookie enforcement.
- **Path Resilience**: Global path normalization to ensure zero routing latency in SPA environments.
- **Automated Build Synchronization**: Integrated build process to unify frontend assets with the Java deployment archive.

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

---

## 🛠️ Development Workflow
- **Frontend Engineering**: Assets are located in `frontend/src/`. Execute `npm run build` within the frontend directory to synchronize assets with the Java web application.
- **Backend Engineering**: Servlets and business logic are maintained in `src/main/java/com/billing/`.
- **Database Management**: The system utilizes a centralized cloud database. Connection parameters are managed within `DB.java`.

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