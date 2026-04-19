# 🚩 Team Discussion Notes — Existing Code Review

Items to discuss with teammates before changing. **I will not modify any of these** — your call after team discussion.

---

## 🔴 Critical Issues

### 1. `DB.java` — Single Static Connection (Thread-Safety Bug)
**File**: [DB.java](file:///home/zkhattab/Billing_system/src/main/java/com/billing/db/DB.java#L9)
```java
static Connection conn;  // ← shared across ALL servlet threads
```
**Problem**: Servlets are multi-threaded. Two requests hitting the DB simultaneously will corrupt each other's queries or crash with "connection already in use."

**Recommendation**: Each call to `getConnection()` should return a **new** connection. Caller closes via try-with-resources. Simple fix, ~5 lines changed.

**Impact if not fixed**: Random failures under any concurrent load (e.g., two browser tabs open).

---

### 2. `DB.java` — Hardcoded Credentials in Source Code
**File**: [DB.java:5-7](file:///home/zkhattab/Billing_system/src/main/java/com/billing/db/DB.java#L5-L7)
```java
private static final String db_url = "jdbc:postgresql://...";
private static final String db_user = "neondb_owner";
private static final String db_password = "npg_eZDj1hp4uUMT";
```
**Problem**: Credentials pushed to GitHub. Anyone with repo access has full DB access. Already in git history — can't be fully undone without history rewrite.

**Recommendation**: Move to `db.properties` (already gitignored) or environment variables. For now, since it's a student project with a free Neon tier, low risk — but worth knowing it's bad practice.

**Discussion point**: Should we rotate the Neon password? Or accept the risk for the 10-day sprint?

---

### 3. `Billing.sql` — Syntax Error in Customer INSERT
**File**: [Billing.sql:257](file:///home/zkhattab/Billing_system/Billing.sql#L256-L260)
```sql
-- INSERT INTO customer (name, address, birthdate)
VALUES-- ============================================================
      ('Ahmed Ali', 'Beni Suef', '1998-05-10'),
```
**Problem**: The `INSERT INTO` is commented out but `VALUES` is not. Also `VALUES` is concatenated with a comment on the same line. This SQL will fail if run as-is.

**Recommendation**: Fix the INSERT or comment out the entire block.

---

### 4. `Billing.sql` — `ALTER TABLE` Inside `CREATE TABLE`
**File**: [Billing.sql:8-12](file:///home/zkhattab/Billing_system/Billing.sql#L8-L12)
```sql
CREATE TABLE file (
    ALTER TABLE file ADD COLUMN filename TEXT;  -- ← this is inside CREATE TABLE
    id          SERIAL PRIMARY KEY,
    parsed_flag BOOLEAN NOT NULL DEFAULT FALSE
);
```
**Problem**: `ALTER TABLE` inside a `CREATE TABLE` block is invalid SQL. Should be `filename TEXT` as a column definition, or the ALTER should be after the CREATE.

---

## 🟡 Minor Issues

### 5. `CDRParser.java` — Connection Not Always Closed on Error
**File**: [CDRParser.java:99-103](file:///home/zkhattab/Billing_system/src/main/java/com/billing/cdr/CDRParser.java#L98-L103)
Connection is closed in `finally` block ✅, but since `DB.getConnection()` returns a shared static connection, calling `conn.close()` kills it for everyone.

**Ties to issue #1** — fixing DB.java fixes this too.

### 6. `HelloServlet.java` — Different Package Than Billing Code
- Billing code: `com.billing.*`
- HelloServlet: `org.example.billing_system`

Not a bug, just inconsistent. New servlets should go under `com.billing.servlet`.

### 7. `.idea/` Files Were Tracked in Git
**Status**: ✅ Already fixed — I untracked them and updated `.gitignore`.

---

## ✅ What Teammates Did Well

- **Database schema** is solid — proper normalization, good use of ENUMs, FK constraints, indexes
- **CDRParser** logic is correct — transaction handling with rollback, file-based tracking
- **Neon PgBouncer endpoint** chosen correctly (the `-pooler` URL)
- **Maven wrapper** included — no need to install Maven globally
