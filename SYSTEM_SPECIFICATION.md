# FMRZ Billing System: System Specification (Constitutional Rules)

> [!IMPORTANT]
> This document serves as the **"System Constitution."** All AI agents and human developers MUST adhere to these immutable protocols to maintain the architectural integrity, performance, and financial accuracy of the FMRZ Telecom Billing System.

---

## 1. Architectural "Golden Laws" (Immutable)

### 1.1 Data Precision & Types (STRICT)
*   **Currency**: All monetary values MUST be stored as `NUMERIC(12,2)`.
    *   *Rationale*: Prevents rounding errors in telecom billing. AI agents must NEVER downgrade to INT or FLOAT.
*   **Usage Volume**: All usage counts (Data Bytes, Voice Seconds, SMS counts) MUST be stored as `BIGINT`. 
    *   *Rationale*: Prevents overflow in high-density enterprise environments.
*   **MSISDN**: Must be stored as `VARCHAR(20)` and normalized (removing leading `00` or `+`) before processing.

### 1.2 The "Database-First" Logic Mandate (STRICT)
*   **Single Source of Truth**: All Rating, Overage, Roaming, and **Tax (14% VAT)** calculations MUST reside in **PostgreSQL Stored Procedures** (PL/pgSQL).
*   **Orchestration**: Java Servlets are strictly for request handling and calling DB functions. Business logic duplication in Java is **FORBIDDEN**.
*   **Enforcement**: The `generate_bill()` stored procedure MUST apply 14% VAT: `taxes := 0.14 * subtotal`

### 1.3 Ingestion Performance Protocol (STRICT)
*   **JDBC Batching**: Any CDR ingestion MUST use **JDBC Batching** with **1,000 records per packet** and `try-with-resources`.
*   **Archive Protocol**: Processed files MUST be moved from `/input` to `/processed` with UUID prefix (`uuid-originalname.csv`).
*   **Rejection Audit**: Invalid/suspended CDRs MUST be logged to `rejected_cdr` table (NOT silently dropped).

---

## 2. Operational Efficiency Laws

### 2.1 Tool Hierarchy (CLI > GUI)
*   **Verification**: Use `ripgrep` (or grep) to search source code, not browser search.
*   **API Testing**: Use `curl -f` against running container API.
*   **Monitoring**: Use `podman logs` for background workers and ingestion errors.
*   **Browser Use**: Only for visual CSS debugging.

### 2.2 Ingestion Workflow
1.  **Stage**: Place CSV in `/app/input`
2.  **Trigger**: Call `POST /api/admin/cdr/upload`
3.  **Batch**: CDRParser uses JDBC batch (1,000/batch)
4.  **Verify**: Check `rejected_cdr` table for failed records

---

## 3. Container & Security Laws

### 3.1 Ownership (STRICT)
*   **Container Volumes**: All `/app` directories MUST be owned by `javauser:javauser`
*   **Non-root Execution**: Container MUST run as non-root user (javauser)
*   **File Operations**: All write operations must respect javauser ownership

### 3.2 Secrets Management (STRICT)
*   **Zero Hardcoded Credentials**: DB credentials MUST be read from Environment Variables (`DB_URL`, `DB_USER`, `DB_PASSWORD`)
*   **Property Files**: `db.properties` MUST NOT contain actual credentials (only placeholders)
*   **ENV Priority**: Java DB class must check ENV vars before properties

---

## 4. Frontend Standards

### 4.1 Triple-Lane Grid (STRICT)
*   **Pattern**: Usage display MUST follow **Voice | Data | SMS** lane pattern
*   **Iconography**:
    *   **Voice**: `Phone` icon
    *   **Data**: `Wifi/Wireless` icon
    *   **SMS**: `Mail/Envelope` icon

### 4.2 Financial Scannability (STRICT)
*   **Label**: Total column MUST read **"Total (Inc. Tax)"**
*   **Confirmation**: Must explicitly confirm 14% VAT is included

---

## 5. JasperReports 7 Compliance

### 5.1 XML Schema (STRICT)
*   **element-kind Attributes**: All JRXML elements MUST include proper `element-kind` attribute
    *   `<image element-kind="Graphic">`
    *   `<textField element-kind="Text">`
    *   `<line element-kind="Graphic">`
*   **Implementation**: Use `JasperLoader` class with in-memory template caching

### 5.2 Font Handling
*   **Maven AppendingTransformer**: Prevents font file overwrites during build
*   **JIT Compilation Avoidance**: Templates cached in memory (compiled once, used many times)

---

## 6. Billing Cycle Aggregation Logic

### 6.1 "Run Billing Cycle Now" Button Flow

```
Admin Dashboard → POST /api/admin/bills/generate
                         ↓
              generate_all_bills(CURRENT_DATE)
                         ↓
         ┌───────────────┼───────────────┐
         ↓               ↓               ↓
    expire_addons()  For each active   Mark processed
    (previous period)  contract        CDRs as billed
                         ↓
              generate_bill(contract_id, period)
                         ↓
         ┌───────────────┴───────────────┐
         ↓                               ↓
    contract_consumption          ror_contract
    (Voice/Data/SMS usage)        (Overage charges)
         ↓               ↓               ↓
    BIGINT amounts           units * rates
         ↓                               ↓
    subtotal = recurring_fees + overage + roaming
         ↓
    taxes = 0.14 * subtotal  ← 14% VAT IN STORED PROCEDURE
         ↓
    total = subtotal + taxes
         ↓
    Insert into bill table (NUMERIC(12,2))
         ↓
    Update ror_contract SET bill_id = X
    Update contract_consumption SET is_billed = TRUE
```

### 6.2 Aggregation Rules
- **Recurring Fees**: From `rateplan.price`
- **Overage Charges**: From `ror_contract` (voice × ROR_voice + data × ROR_data + sms × ROR_sms)
- **Roaming Charges**: Separate calculation in `ror_contract`
- **Tax**: **14% VAT** applied in stored procedure (NOT in Java code)
- **Precision**: All amounts as `NUMERIC(12,2)`, all usage as `BIGINT`

---

## 7. Pre-Flight Checklist (Definition of Done)

Before marking a task as complete, the agent must verify:
- [ ] **Type Check**: Are usage columns still `BIGINT`?
- [ ] **Tax Check**: Does the total reflect the **14% VAT** in stored procedure?
- [ ] **Batch Check**: Is CDR ingestion using **JDBC Batching (1,000 records)**?
- [ ] **Permission Check**: Is container volume owned by `javauser:javauser`?
- [ ] **Secrets Check**: Are credentials from Environment Variables only?
- [ ] **Rejection Check**: Are invalid CDRs logged to `rejected_cdr` table?
- [ ] **Doc Check**: Are new DB functions reflected in `TECHNICAL_DESIGN_DOCUMENT.md`?

---

## 8. Strict Constraints Summary

| Law | Constraint | Enforcement |
|-----|------------|-------------|
| **Numerical Precision** | `NUMERIC(12,2)` for currency | AI must never downgrade |
| **Usage Types** | `BIGINT` for Voice/Data/SMS | AI must never downgrade to INT |
| **Database-First** | 14% VAT in `generate_bill()` | Logic forbidden in Java |
| **Ingestion Speed** | JDBC Batch 1,000 records | No row-by-row inserts |
| **Archiving** | UUID prefix in `/processed` | Mandatory |
| **Security** | javauser ownership | Container volumes |
| **Secrets** | ENV variables only | Zero hardcoded credentials |
| **UI Pattern** | Triple-Lane (Voice/Data/SMS) | Zero deviation |
| **Jasper 7** | element-kind attributes | Strict XML schema |

---

> [!CAUTION]
> Deviating from these specs without an architectural review will lead to technical debt and financial discrepancy.
> 
> **Legal Warning**: Violation of Numerical Precision Law or Database-First Logic Rule may result in:
> - Revenue leakage (rounding errors)
> - Billing disputes (incorrect VAT calculation)
> - System overflow (INT vs BIGINT)
