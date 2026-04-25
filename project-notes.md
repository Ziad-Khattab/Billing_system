# 📝 FMRZ Telecom Billing System - Project Notes

This document serves as the technical audit, roadmap, and integration guide for the FMRZ Telecom Billing System.

---

## 🛠️ Environment Setup

You must have the following versions installed. Use these commands to set up a fresh Linux environment:

### 1. Java 21 (OpenJDK)
We recommend **SDKMAN!** as it is the universal best practice for any Linux distribution (Fedora, Ubuntu, etc.) and avoids permission issues:
```bash
# Install SDKMAN!
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"

# Install Java 21
sdk install java 21.0.2-tem
```
*Alternatively, use your system package manager:*
*   **Fedora/RedHat**: `sudo dnf install java-21-openjdk-devel`
*   **Ubuntu/Debian**: `sudo apt install openjdk-21-jdk`

### 2. Node.js (v18+)
Use **NVM** (Node Version Manager) to ensure compatibility across different Fedora/Ubuntu versions:
```bash
# Install NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc

# Install Node.js LTS
nvm install --lts
nvm use --lts
```

### 3. PostgreSQL
Ensure you have access to the **Neon DB** credentials located in `src/main/resources/db.properties`.

---

## 🏗️ Technical Architecture Standards

To maintain a consistent and scalable deployment, the team must adhere to the following principles:

### 1. The DAO Pattern (Data Access Object)
We have centralized all database operations into the `com.billing.dao` package. 

> [!IMPORTANT]
> **Rationale for DAO:**
> *   **Separation of Concerns**: Servlets handle HTTP request/response logic; DAOs handle SQL logic.
> *   **Decoupling**: Migration to another database provider (e.g., from Neon to on-premise Postgres) only requires editing DAOs.
> *   **Maintainability**: Centralized SQL prevents duplicate queries across the project.
> *   **Security**: DAOs enforce `PreparedStatement` usage, providing built-in protection against SQL Injection.

### 2. SvelteKit + Java Integration
*   **Build Process**: The frontend is built using `adapter-static` and outputted directly to `src/main/webapp`.
*   **Packaging**: A `ROOT.war` is generated via Maven, containing both the compiled UI and the Jakarta backend.
*   **Dynamic CSS Injection**: We use `HtmlInjectionFilter.java` to manage SvelteKit's hashed filename randomization. This ensures styles (rounded corners, dark mode) are correctly loaded regardless of build-time hashes.

---

## ⚡ Performance & Optimization (Special Issue)

> [!NOTE]
> **Issue**: Noticeable delay when navigating to the "Packages" page.
>
> **Explanation**:
> *   When a user clicks "Packages", the frontend sends a request to the backend at `/api/public/rateplans`.
> *   The backend then queries the Neon DB to fetch the latest prices and plans (including the newly added "Gold" package).
>
> **Solution**: We implemented **HikariCP (Connection Pool)**. Without this, the backend would have to establish a brand-new TLS handshake with the Neon servers (located in Europe) every time the page is clicked, causing a ~0.5-second delay. The pool keeps connections "warm" for near-instant responses (<20ms).

---

## 🔄 Integration Between Our Work

We have successfully integrated the latest **Roaming Support** from the upstream repository:

| Component | Change Description |
| :--- | :--- |
| **Logic** | `rate_cdr` and `generate_bill` SQL functions now detect roaming (HPLMN vs VPLMN) and apply a `v_roaming_multiplier`. |
| **Schema** | Added `is_roaming` to `service_package` and roaming overage columns to `ror_contract`. |
| **Public API** | Updated the service packages API to include `price` and `description` fields for a modern user experience. |

---

## 🛠️ Safe Git Integration Workflow

Before pushing changes to the upstream repository, follow these steps to avoid overwriting teammate work:

1.  **Branching**: Create a fresh integration branch: `git checkout -b feature/integrated-production`.
2.  **Merging**: Pull latest changes: `git pull upstream main`.
3.  **Conflict Resolution**:
    *   **`DB.java`**: Always keep our HikariCP pool configuration.
    *   **Models**: Manually merge `price` and `description` with teammate's `is_roaming` fields.
    *   **SQL**: Prefer upstream functions for roaming math, but verify schema compatibility.
4.  **Verification**: Run `./mvnw clean package` to ensure the merge is stable.
5.  **Push**: Push to a new remote branch for review: `git push upstream feature/integrated-production`.

---

## 📝 Team Discussion Points (Action Items)

| Priority | Task | Description |
| :--- | :--- | :--- |
| 🔴 **High** | **Password Security** | Transition from plain-text passwords to **BCrypt** hashing in the `user_account` table. |
| 🟠 **Medium** | **Bill Adjustment** | Implement a `modify_bill` SQL function for partial adjustments to avoid full deletion. |
| 🟠 **Medium** | **Dynamic Config** | Migrate the 15% tax rate from hardcoded SQL to a `system_config` database table. |
| 🔵 **Low** | **Roaming Bundles** | Create specific "Roaming Bundles" in `service_package` where `is_roaming = TRUE`. |
| 🔵 **Low** | **CDR Parser** | Update `CDRParser.java` to handle new roaming fields in incoming CSV files. |

---

##  Build & Run Command

Use this unified command to build the entire stack and launch the server:

```bash
fuser -k 8080/tcp || true && (cd frontend && npm install && npm run build) && ./mvnw clean package && ./mvnw cargo:run
```

---
*Last updated on 2026-04-23*
