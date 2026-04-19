# 📋 Teammate Briefing — Web Interface & API Layer

This doc explains what I'm building and how it connects to your work.

## What I'm Adding

A **web interface + REST API** on top of the existing database and CDR parser. Think of it as the user-facing layer:

```
Your work (DB + CDR)  →  My work (API + Website)  →  User sees everything in browser
```

### What This Means for You

- **I won't modify your core logic** (`CDRParser.java`, `Billing.sql` core tables)
- **Architectural Fix**: I refactored `DB.java` for safety. It now loads from `db.properties` and handles multiple users concurrently. This is a standard architectural improvement that benefits the whole team.
- **I will ADD** new tables (`app_user`), new Java packages (`servlet/`, `dao/`, `model/`, `filter/`), and a frontend folder
- **Your DB functions still work** — my API reads from the same tables you write to

## New Files I'm Adding

```
src/main/java/com/billing/
├── model/        # Java classes matching DB tables (Customer.java, etc.)
├── dao/          # Classes that query the DB (CustomerDAO.java, etc.)
├── servlet/      # HTTP endpoints — the API layer
├── filter/       # Security (login check) and CORS (browser security)
└── util/         # PDF invoice generator

frontend/         # SvelteKit web app (separate from Java)
```

## How the API Uses Your Database

My servlets call DAOs → DAOs run SQL against the **same tables** you designed:

```java
// Example: CustomerDAO reads from your customer table
public List<Customer> findAll() {
    String sql = "SELECT * FROM customer";
    // ... standard JDBC query
}
```

## Database Changes I Need

**One new table** for login accounts:
```sql
CREATE TABLE app_user (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name     VARCHAR(255) NOT NULL,
    role          VARCHAR(20) NOT NULL DEFAULT 'customer',
    created_at    TIMESTAMP NOT NULL DEFAULT NOW()
);
```

**One new column** on existing customer table:
```sql
ALTER TABLE customer ADD COLUMN user_id INTEGER REFERENCES app_user(id) UNIQUE;
```

This links a customer profile to a login account. Customers created by the parser/admin without accounts will have `user_id = NULL` — no impact on existing data.

## Review of Fouad's Latest Database Changes

**✅ What was done RIGHT (Excellent Architecture):**
Moving the rating engine into PostgreSQL (`rate_cdr`) using PL/pgSQL stored procedures is an industry-standard enterprise pattern. Instead of Java pulling millions of call records over the network to calculate costs (which crashes servers), the database does all the math internally. This was a brilliant architectural choice.

**❌ What was missed (Incomplete Web Auth):**
The updated script assumes the billing engine runs in isolation and completely forgot about Web Authentication. The `app_user` table (needed to log into the SvelteKit frontend) was missing, and the `customer` table lacked emails/passwords. 

**Our Action (100% Conflict-Free):** We are keeping your powerful rating engine and simply injecting our `app_user` table into your `Billing.sql` script. Adding `app_user` and linking it to `customer.user_id` is completely safe and **does not conflict** with your `rate_cdr` or billing logic. The rating engine runs completely independently of web authentication.

## Completed Architectural Fixes

### 1. DB.java: Thread Safety & Properties (DONE ✅)
I've refactored `DB.java` to load credentials from `db.properties` and support multi-user concurrency.

**Student-Friendly Explanation:**
Imagine a single-lane bridge. If only one car (user) uses it at a time, it's fine. But if two cars try to cross simultaneously, they crash. The old `DB.java` was a single-lane bridge. The new version gives every user their own lane (a fresh connection). This is called **Thread Safety**. I also moved the passwords into a separate `db.properties` file so we don't accidentally leak them on GitHub!


## How to Test Together

Once the API is running locally:
```bash
# Check if API is alive
curl http://localhost:8080/api/public/rateplans

# After you run CDR parser, I can show the usage in invoices
curl -b cookies.txt http://localhost:8080/api/admin/bills?contract_id=1
```

## 🛠️ Important Environment Notes

### 1. Java 21 is Mandatory
I've upgraded the `pom.xml` to **Java 21**. 
*   **Why?** Java 21 is the current Long Term Support (LTS) version. It's faster and more secure. 
*   **Action**: Ensure your IDE (IntelliJ/VS Code) is using JDK 21. If you use an older version (like 8 or 11), the project will not compile.

### 2. The "Java 21 Vaccine" (`GsonTypeAdapters.java`)
Java 21 is very strict about internal data privacy. If we try to convert a `LocalDate` (date) to JSON for the frontend, it will crash. 
*   **My Fix**: I added `com.billing.util.GsonTypeAdapters`. Do not delete this! It tells Java how to safely handle dates without crashing.

### 3. Use the Maven Wrapper (`./mvnw`)
Instead of just running `mvn`, use `./mvnw` (on Linux/Mac) or `mvnw.cmd` (on Windows).
*   **Why?** This ensures we all use the exact same Maven version (3.9.x) regardless of what is installed on our individual laptops. This prevents "it works on my machine" bugs.
