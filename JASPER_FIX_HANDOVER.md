# HANDOVER PROMPT: Stabilizing JasperReports 7.0.1 Invoice Engine

**Objective:** Resolve the `net.sf.jasperreports.engine.JRException: Unable to load report` occurring during PDF generation in a containerized (Podman/Railway) environment. The goal is to restore a fully functional, one-page, high-density Telecom Invoice with correct rating breakdowns.

---

## 1. TECHNICAL CONTEXT & STACK
- **System:** FMRZ Telecom Billing System (Java 21 / Tomcat 11).
- **JasperReports Version:** 7.0.1 (Modular/Modern Engine).
- **Environment:** Podman (Local) / Railway (Cloud).
- **Architecture:** Thin JAR strategy (`app.jar` + `lib/` directory) deployed in `eclipse-temurin:21-jre-jammy`.
- **Database:** PostgreSQL (Cloud NeonDB).
- **Frontend:** SvelteKit (Proxied via Tomcat).

---

## 2. THE CORE PROBLEM: THE "GHOST" JREXCEPTION
Every attempt to download a PDF invoice via `CustomerProfileServlet` or compile via the diagnostic tool `DebugJasper` fails with:
```text
net.sf.jasperreports.engine.JRException: Unable to load report
    at net.sf.jasperreports.engine.xml.JRXmlLoader.loadXML(JRXmlLoader.java:172)
    at net.sf.jasperreports.engine.xml.JRXmlLoader.load(JRXmlLoader.java:149)
    at com.billing.util.DebugJasper.main(DebugJasper.java:39)
```
### CRITICAL OBSERVATIONS:
1. **Source of Error:** Line 172 in Jasper 7.0.1's `JRXmlLoader` corresponds to the failure of the XML handler to return a `JasperDesign` object.
2. **Cause is Null:** The exception has **NO UNDERLYING CAUSE** (`getCause() == null`). This means it's an explicit throw by Jasper because it couldn't find a compatible XML reader extension.
3. **Environment vs Content:** Even a `minimal.jrxml` with zero logic fails. However, standard JDK `DocumentBuilder` (SAX) parses the same file perfectly in the same container.
4. **Shading vs Thin:** We are currently using a **Thin JAR**. Shading conflicts (merging `jasperreports_extension.properties`) are unlikely unless dependencies are leaking into the main JAR unexpectedly.

---

## 3. STABLE BASELINE (INSPIRATION)
The system was stable in the following commits:
- **Commit `8f8a95c`**: Initial stable baseline.
- **Commit `c861516`**: Optimized Thin JAR + TCCL stability.
- **Layout Requirements:** The invoice **MUST** stay on 1 page. Use small fonts (8pt-9pt), compact tables, and rounded UI borders.

---

## 4. WHAT HAS BEEN TRIED (AND FAILED)
1. **Namespace Updates:** Changed `http://jasperreports.sourceforge.net/jasperreports` to the 7.0.1 standards.
2. **Element Kind Tags:** Added `kind="staticText"`, `kind="textField"`, etc. (Mandatory in JR 7).
3. **Properties File:** Created `jasperreports.properties` with `net.sf.jasperreports.xml.load.handler.default=net.sf.jasperreports.engine.xml.JRXmlLoader`.
4. **TCCL Fix:** Implemented `Thread.currentThread().setContextClassLoader(JasperLoader.class.getClassLoader())` in the Servlet.
5. **Dependency Hunting:** Removed `jackson-dataformat-xml` to avoid conflicts; re-added it; excluded `xml-apis`. Nothing changed the error.

---

## 5. REPRODUCTION STEPS
To replicate the error yourself in the current environment:
1. Rebuild: `podman-compose down && podman-compose up -d --build --force-recreate`
2. Run Diagnostic: `podman exec billing-app-prod java -cp "app.jar:lib/*" com.billing.util.DebugJasper minimal.jrxml`
3. View Results: `podman exec billing-app-prod cat /app/debug_results.txt`

---

## 6. THE MASTER PLAN FOR RESOLUTION (YOUR TASK)

### STEP A: THE EXTENSION DISCOVERY AUDIT
Jasper 7.0.1 is modular. It discovers capabilities via `jasperreports_extension.properties` files in the classpath.
- **Task:** Verify that `jasperreports-7.0.1.jar`, `jasperreports-pdf-7.0.1.jar`, and `jasperreports-jdt-7.0.1.jar` are all present in `/app/lib`.
- **Task:** Use `DebugJasper` (v8+) to print the location of every `jasperreports_extension.properties` found by the ClassLoader. If they are missing or overwritten, the engine is blind.

### STEP B: THE JAXB / JAKARTA CONFLICT
Java 21 lacks JAXB. Jasper 7 requires it.
- **Task:** Ensure `jakarta.xml.bind-api` and `jaxb-runtime` (Glassfish) are compatible. 
- **Action:** Try swapping `jaxb-runtime` with `com.sun.xml.bind:jaxb-impl:4.0.5`.

### STEP C: THE "INTERNAL" COMPILER STRATEGY
- **Task:** In `jasperreports.properties`, ensure the compiler is set to `internal` (JDT) and that the classpath is explicitly defined.
- **Action:** `net.sf.jasperreports.compiler.java.executable=internal`

### STEP D: JRXML COMPATIBILITY FALLBACK
If the modular engine fails, there might be a "Legacy" parsing mode.
- **Task:** Research if `net.sf.jasperreports.xml.load.handler.default` can be set to a specific Jackson or Digester implementation that bypasses the extension registry.

### STEP E: UI RESTORATION
Once compilation works:
- **Goal:** Restore `invoice.jrxml` to the "V1" baseline style.
- **Constraints:** 
    - 1 Page strictly.
    - Detailed Rating: Usage charges, Roaming, Overages.
    - Financials: Subtotal, VAT (14%), Grand Total.
    - Font: 'Outfit' or 'Inter' (fallback to SansSerif).

---

## 7. FINAL INSTRUCTIONS
- **DO NOT** simplify the UI. The user wants a premium, compact billing look.
- **DO NOT** use the browser unless absolutely necessary (the current agent has CLI tools).
- **DO NOT** exit the loop until `DebugJasper` returns `✅ SUCCESS: Jasper compilation works!`.

---

## 7. DEEP DIVE: JRXML COMPONENT STANDARDS (JASPER 7)
JasperReports 7.0.1 is strictly component-based. The next agent must ensure the following XML structures are strictly followed:
- **Element Kinds:** Every element must have a `kind`. 
    - `<element kind="staticText" ...>`
    - `<element kind="textField" ...>`
    - `<element kind="image" ...>`
    - `<element kind="line" ...>`
- **Tables:** Use `kind="single"` for table components.
- **Namespaces:** Use the SourceForge namespace, but be aware that Jasper 7 might expect `https` or a specific versioned URL.
    - `xmlns="http://jasperreports.sourceforge.net/jasperreports"`
    - `xsi:schemaLocation="http://jasperreports.sourceforge.net/jasperreports http://jasperreports.sourceforge.net/xsd/jasperreport.xsd"`

---

## 8. UI/UX SPECIFICATIONS (THE "V1 STABLE" LOOK)
The user is extremely sensitive to the UI. The invoice must look "Premium" and fit on exactly **ONE PAGE**.
- **Header:**
    - Logo (Top Left): Scaled proportionally.
    - Company Info (Top Right): 8pt font, right-aligned.
- **Customer Section:**
    - 2-column grid.
    - Labels in bold red (Hex: #d32f2f), values in dark grey.
- **Detailed Rating Table:**
    - Must show: Type (Data/Voice/SMS), Volume, Rated Amount, Roaming Flag.
    - Font size: **7.5pt or 8pt**.
    - Row padding: Minimal (2px).
    - Alternate row colors: Very light grey (#f9f9f9).
- **Financial Breakdown:**
    - Right-aligned summary box.
    - Bold Grand Total with a bottom border.
- **Footer:**
    - "Thank you for choosing FMRZ" centered.
    - Page number (1/1).

---

## 9. DATABASE MAPPING & DATA SOURCE
The report uses a direct `java.sql.Connection` passed from `CustomerProfileServlet`.
- **Query Parameter:** `$P{BILL_ID}`
- **Core Queries to Verify:**
    - Main Bill Info: `SELECT * FROM bill WHERE id = $P{BILL_ID}`
    - Usage Details: `SELECT * FROM cdr WHERE bill_id = $P{BILL_ID}`
- **Rating Logic:** The rating is handled by the database trigger `auto_rate_cdr()`, so the JRXML only needs to display the calculated fields (total_amount, overage_charge).

---

## 10. RAILWAY DEPLOYMENT CAVEATS
When deploying to Railway:
1. **Headless Mode:** Must be `-Djava.awt.headless=true`. This is already in the `Dockerfile`.
2. **Font Discovery:** Railway JRE images (Ubuntu/Jammy) have minimal fonts.
    - **Fix:** We use `jasperreports-fonts-7.0.1.jar`. Ensure it is in the `lib/` folder.
    - **Verify:** Run `fc-list` in the container if needed (requires `fontconfig` install).
3. **Memory Limits:** Railway containers often have tight memory (512MB-1GB).
    - **Optimization:** Keep `JasperPrint` objects in memory only as long as needed. Use `JasperLoader` caching for compiled reports.

---

## 11. TROUBLESHOOTING CHECKLIST FOR THE NEXT AGENT
1. [ ] **Verify lib content:** `podman exec billing-app-prod ls /app/lib | grep jasper`
2. [ ] **Check Extension Properties:** Run `DebugJasper v8` and verify the `.jar!` paths for extensions.
3. [ ] **XML Parser Test:** Ensure `Standard JDK parsing works!` is still green.
4. [ ] **Compile Minimal:** Once `minimal.jrxml` works, only then move to `invoice.jrxml`.
5. [ ] **PDF Output:** Test the download via `/api/customer/invoices/download?id=1`.
6. [ ] **UI Audit:** Compare the generated PDF against the "Compact 1-Page" requirement.

---

## 12. FINAL INSTRUCTIONS
- **CRITICAL:** Do not simple the JRXML to "fix" it. The issue is in the engine loading the XML, not the XML content itself (verified by `minimal.jrxml` failure).
- **CRITICAL:** Use the provided `JASPER_FIX_HANDOVER.md` as your source of truth.
- **CRITICAL:** Maintain the high density of information. The user needs to see roaming, overages, and detailed breakdowns clearly.

**End of Handover.**
