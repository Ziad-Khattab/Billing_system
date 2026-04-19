# SQL Quick Reference — Billing Project

## Queries You'll Write in DAOs

### SELECT (Read)
```sql
-- Find all customers
SELECT * FROM customer;

-- Find by ID
SELECT * FROM customer WHERE id = ?;
-- The ? is a placeholder. In Java: ps.setInt(1, id);

-- Search by name (partial match, case-insensitive)
SELECT * FROM customer WHERE LOWER(name) LIKE LOWER(?);
-- In Java: ps.setString(1, "%" + query + "%");
-- % = wildcard. "%ahmed%" matches "Ahmed Ali", "Mohamed Ahmed"

-- JOIN: Get customer's contracts with rateplan name
SELECT c.*, r.name AS rateplan_name
FROM contract c
JOIN rateplan r ON c.rateplan_id = r.id
WHERE c.customer_id = ?;
-- JOIN connects two tables using a shared column (FK → PK)
```

### INSERT (Create)
```sql
-- Create customer, return the new ID
INSERT INTO customer (name, address, birthdate)
VALUES (?, ?, ?)
RETURNING id;
-- RETURNING is PostgreSQL-specific. MySQL uses getGeneratedKeys() instead.
```

### UPDATE (Modify)
```sql
-- Update customer
UPDATE customer SET name = ?, address = ?, birthdate = ?
WHERE id = ?;
-- Always include WHERE! Without it, ALL rows get updated.
```

### DELETE
```sql
DELETE FROM customer WHERE id = ?;
-- Same warning: always use WHERE.
```

## JDBC Pattern (Java Side)

```java
// Pattern you'll repeat in every DAO method:
try (Connection conn = DB.getConnection();                    // 1. Get connection
     PreparedStatement ps = conn.prepareStatement(sql)) {     // 2. Prepare SQL
    ps.setString(1, name);                                    // 3. Set parameters
    ps.setString(2, address);
    try (ResultSet rs = ps.executeQuery()) {                  // 4. Execute
        while (rs.next()) {                                   // 5. Read results
            Customer c = new Customer();
            c.setId(rs.getInt("id"));
            c.setName(rs.getString("name"));
        }
    }
}  // Connection auto-closed here (try-with-resources)
```

## Key Differences: PostgreSQL vs MySQL
| Feature | PostgreSQL (Your Project) | MySQL |
|---------|--------------------------|-------|
| Auto-increment | `SERIAL` | `AUTO_INCREMENT` |
| Return new ID | `RETURNING id` | `getGeneratedKeys()` |
| Enums | `CREATE TYPE ... AS ENUM` | `ENUM('a','b')` inline |
| Boolean | `TRUE/FALSE` | `1/0` |
| Case-sensitive | Yes by default | No by default |

## Your Database Tables (Quick Reference)
```
customer       → id, name, address, birthdate
rateplan       → id, name, ror_data, ror_voice, ror_sms, price
service_package → id, name, type(voice/data/sms), amount, priority
contract       → id, customer_id(FK), rateplan_id(FK), msisdn, status, credit_limit
bill           → id, contract_id(FK), billing_date, recurring_fees, one_time_fees, usage, taxes
invoice        → id, bill_id(FK), pdf_path, generation_date
cdr            → id, file_id(FK), dial_a, dial_b, start_time, duration, service_id, external_charges
app_user       → id, username, password_hash, full_name, role
```
