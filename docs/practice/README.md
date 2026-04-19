# ⌨️ Practice Guide — Code It Yourself

## How This Works

**Two folders:**
```
Billing_system/
├── src/          ← MY version (working, already built)
└── docs/practice/ ← YOUR version (instructions to build it yourself)
```

**Workflow:**
1. Read the step-by-step instructions here
2. Type the code yourself in a separate IntelliJ project or scratch folder
3. Compare with my version in `src/` when stuck
4. Delete your version and redo it from memory for deeper learning

---

## Step 1: Understand pom.xml Before Touching It

### What is pom.xml?

**POM** = **P**roject **O**bject **M**odel. It's Maven's configuration file — the "recipe" for your project.

Think of it like a cooking recipe:
- **Ingredients** = `<dependencies>` (libraries your code needs)
- **Cooking instructions** = `<build><plugins>` (how to compile and package)
- **Dish name** = `<artifactId>`, `<groupId>`, `<version>` (your project's identity)

Without pom.xml, you'd manually download JAR files and add them to your classpath. Maven does this automatically.

### Your pom.xml Explained Line by Line

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- ↑ XML declaration — every XML file starts with this -->

<project>
    <!-- ↓ These three identify YOUR project. Like a package address. -->
    <groupId>org.example</groupId>        <!-- Company/org name (reverse domain) -->
    <artifactId>Billing_System</artifactId> <!-- Project name -->
    <version>1.0-SNAPSHOT</version>         <!-- Version. SNAPSHOT = still in development -->
    <packaging>war</packaging>
    <!-- ↑ WAR = Web Application Archive. Tells Maven to package as a .war file
         that Tomcat can deploy. If this was "jar", it would be a standalone app. -->

    <properties>
        <!-- ↓ Variables you can reuse with ${...} syntax -->
        <maven.compiler.target>21</maven.compiler.target>  <!-- Compile FOR Java 21 -->
        <maven.compiler.source>21</maven.compiler.source>  <!-- Compile WITH Java 21 -->
        <junit.version>5.13.2</junit.version>  <!-- Used below as ${junit.version} -->
    </properties>

    <dependencies>
        <!-- ═══ WHAT TOMCAT PROVIDES ═══ -->
        <!-- scope=provided means: "I need this to COMPILE, but Tomcat already
             has it at runtime, so don't include it in the WAR file." -->

        <dependency>
            <groupId>jakarta.servlet</groupId>
            <artifactId>jakarta.servlet-api</artifactId>
            <version>6.1.0</version>
            <scope>provided</scope>  <!-- Tomcat has this built-in -->
        </dependency>

        <!-- ═══ DATABASE ═══ -->
        <dependency>
            <groupId>org.postgresql</groupId>
            <artifactId>postgresql</artifactId>
            <version>42.7.5</version>
            <!-- No scope = "compile" (default). Included in WAR file. -->
        </dependency>

        <!-- ═══ JSON ═══ -->
        <dependency>
            <groupId>com.google.code.gson</groupId>
            <artifactId>gson</artifactId>
            <version>2.11.0</version>
        </dependency>

        <!-- ═══ PASSWORD HASHING ═══ -->
        <dependency>
            <groupId>org.mindrot</groupId>
            <artifactId>jbcrypt</artifactId>
            <version>0.4</version>
        </dependency>

        <!-- ═══ PDF GENERATION ═══ -->
        <dependency>
            <groupId>com.github.librepdf</groupId>
            <artifactId>openpdf</artifactId>
            <version>2.0.3</version>
        </dependency>

        <!-- ═══ TESTING ═══ -->
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter-api</artifactId>
            <version>${junit.version}</version>  <!-- ← uses the property defined above -->
            <scope>test</scope>  <!-- Only available during tests, not in production -->
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <!-- maven-war-plugin: packages your compiled classes + web.xml into a .war -->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-war-plugin</artifactId>
                <version>3.4.0</version>
            </plugin>
        </plugins>
    </build>
</project>
```

### Dependency Scopes Cheatsheet

| Scope | When available | In WAR? | Example |
|-------|---------------|---------|---------|
| `compile` (default) | Compile + runtime | Yes | Gson, PostgreSQL driver |
| `provided` | Compile only | No | Servlet API (Tomcat has it) |
| `test` | Tests only | No | JUnit |
| `runtime` | Runtime only | Yes | JDBC driver (rare to use explicitly) |

### How Maven Downloads Dependencies

```
1. You write <dependency> in pom.xml
2. You run: ./mvnw compile
3. Maven reads pom.xml → checks Maven Central Repository (online)
4. Downloads JAR files to ~/.m2/repository/ (local cache)
5. Adds them to your classpath automatically
6. Next build: uses cached JARs (fast, no re-download)
```

---

## Step 2: Create Your First Model (Customer.java)

### Instructions (do these yourself):

1. **Think about what fields a customer has** — look at `Billing.sql`:
   ```sql
   CREATE TABLE customer (
       id        SERIAL PRIMARY KEY,
       name      VARCHAR(255) NOT NULL,
       address   TEXT,
       birthdate DATE
   );
   ```

2. **Create the file**:
   - Path: `src/main/java/com/billing/model/Customer.java`
   - Package: `com.billing.model`

3. **Type this skeleton from memory** (don't copy):
   ```java
   package com.billing.model;

   public class Customer {
       // Step 3a: What fields? Match the SQL columns:
       //   id → int
       //   name → String
       //   address → String
       //   birthdate → LocalDate (import java.time.LocalDate)
       //   user_id → Integer (nullable — not all customers have accounts)

       // Step 3b: Empty constructor (needed for Gson)

       // Step 3c: Getters and setters for each field
   }
   ```

4. **After typing, compare** with my version: `src/main/java/com/billing/model/Customer.java`

5. **Key things to learn while typing**:
   - `int` vs `Integer`: `int` can't be null, `Integer` can. Use `Integer` for optional FK columns.
   - `LocalDate` vs `Date`: `LocalDate` is modern Java (java.time), `Date` is legacy. Always use `LocalDate`.
   - `BigDecimal` for money: `double` has precision errors. `0.1 + 0.2 = 0.30000000004` with double.

---

## Step 3: Create Your First DAO (CustomerDAO.java)

### Instructions:

1. **Think**: What operations does the admin need?
   - List all customers
   - Find by ID
   - Search by name
   - Create a customer
   - Update a customer

2. **Write the skeleton**:
   ```java
   package com.billing.dao;

   public class CustomerDAO {
       // For each operation, the pattern is always:
       // 1. Get connection (try-with-resources)
       // 2. Prepare SQL with ? placeholders
       // 3. Set parameters (ps.setString, ps.setInt, etc.)
       // 4. Execute (executeQuery for SELECT, executeUpdate for INSERT/UPDATE)
       // 5. Read results (ResultSet → Model object)
       // 6. Connection auto-closes (try-with-resources)

       public List<Customer> findAll() { /* ... */ }
       public Customer findById(int id) { /* ... */ }
       public List<Customer> search(String query) { /* ... */ }
       public Customer create(Customer c) { /* ... */ }
       public Customer update(Customer c) { /* ... */ }
   }
   ```

3. **Implement one method at a time**. Start with `findAll()` — the simplest.

4. **Compare** with my version after each method.

---

## Step 4: Repeat for Each Model/DAO

Order to build (same as my version):
1. Customer → CustomerDAO
2. AppUser → UserDAO
3. RatePlan → RatePlanDAO
4. ServicePackage → ServicePackageDAO
5. Contract → ContractDAO
6. Bill → BillDAO
7. Invoice → InvoiceDAO

**Pattern**: Every DAO follows the same JDBC pattern. By DAO #3, you should be typing from muscle memory.

---

## IntelliJ IDEA Tips (If Using JetBrains)

### What Changes From VS Code?

| Feature | VS Code | IntelliJ |
|---------|---------|----------|
| **Run project** | `./mvnw compile` in terminal | Click green ▶️ or Shift+F10 |
| **Auto-import** | Manual | `Alt+Enter` on red class name |
| **Generate code** | Type manually | `Alt+Insert` → getters/setters/constructor |
| **Navigate** | Ctrl+P | `Ctrl+N` (class), `Ctrl+Shift+N` (file) |
| **Find usages** | Ctrl+Shift+F | `Alt+F7` (much smarter) |
| **Refactor rename** | F2 | `Shift+F6` (renames everywhere) |
| **Run single file** | Not easy | Right-click → Run |
| **Debug** | Limited | Full debugger with breakpoints |
| **Maven** | Terminal only | Maven tool window (right sidebar) |

### IntelliJ Shortcuts to Learn While Coding

```
Alt+Enter        → Quick fix (auto-import, create method, etc.)
Alt+Insert       → Generate (constructor, getters, setters, toString)
Ctrl+Space       → Code completion
Ctrl+Shift+Enter → Complete statement (adds semicolon, braces)
Ctrl+D           → Duplicate line
Ctrl+Y           → Delete line
Shift+F6         → Rename everywhere
Ctrl+B           → Go to definition
Ctrl+Alt+L       → Reformat code
Shift+Shift      → Search everything
```

### IntelliJ-Specific Setup

1. **Open project**: File → Open → select `Billing_system/` folder
2. **Set JDK**: File → Project Structure → Project → SDK → Java 21
3. **Maven auto-import**: IntelliJ detects pom.xml automatically — click "Load Maven Changes" when prompted
4. **Tomcat**: Run → Edit Configurations → + → Tomcat Server → Local → set Tomcat path
5. **Generate getters/setters**: Inside a class, press `Alt+Insert` → select fields → done

### What IntelliJ Does That VS Code Doesn't

- **Red underlines = compile errors** — IntelliJ compiles in real-time, no need to run Maven
- **Grey text = unused imports** — clean them with `Ctrl+Alt+O`
- **Light bulb 💡** = suggested fix — press `Alt+Enter` to apply
- **Database tool** — connect to Neon directly from IntelliJ, run SQL, browse tables
- **HTTP client** — test API endpoints without curl (Tools → HTTP Client)
