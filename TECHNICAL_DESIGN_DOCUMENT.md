# Technical Design Document (TDD) for FMRZ Telecom Billing System

## Document Information

- **Document Title**: Technical Design Document (TDD) for FMRZ Telecom Billing System
- **Version**: 2.0
- **Date**: April 30, 2026
- **Authors**: Ziad Khattab, Fouad (Contributors)
- **Project Name**: Telecom Billing System
- **Project Version**: v2.0
- **Confidentiality**: Internal Use

## Table of Contents

1. [Introduction](#1-introduction)
2. [System Overview](#2-system-overview)
3. [Architecture Overview](#3-architecture-overview)
4. [Detailed Design](#4-detailed-design)
5. [Data Model Design](#5-data-model-design)
6. [Integration Design](#6-integration-design)
7. [Performance and Scalability](#7-performance-and-scalability)
8. [Security Considerations](#8-security-considerations)
9. [Testing Strategy](#9-testing-strategy)
10. [Deployment and Operations](#10-deployment-and-operations)
11. [Risks and Mitigation](#11-risks-and-mitigation)
12. [Appendices](#12-appendices)
13. [Java Class Reference](#13-java-class-reference)
14. [Database Function Reference](#14-database-function-reference)
15. [API Endpoint Reference](#15-api-endpoint-reference)
16. [Integration Issues and Resolutions](#16-integration-issues-and-resolutions)

---

## 1. Introduction

### 1.1 Purpose

This Technical Design Document (TDD) version 2.0 provides a comprehensive blueprint for the design, implementation, and maintenance of the FMRZ Telecom Billing System. The document serves as a reference for developers, architects, testers, and stakeholders to understand the system's technical foundations, ensuring consistent implementation and future scalability. It covers all aspects from high-level architecture to low-level design details, aiming for a production-ready, carrier-grade billing solution.

This version represents a major update from v1.2, incorporating all discovered integration issues, complete API documentation, full database function reference, and comprehensive class reference.

### 1.2 Scope

The TDD encompasses:
- System architecture and component design
- Backend (Java/Jakarta EE) and frontend (SvelteKit) implementation details
- Database schema, functions, and triggers
- Security mechanisms and compliance
- Integration points and APIs (complete endpoint documentation)
- Deployment strategies and operational procedures
- Complete Java class reference (32 classes)
- Complete database function reference (60+ functions)
- Complete API endpoint documentation (25+ endpoints)

### 1.3 Definitions and Acronyms

| Term | Definition |
|------|-----------|
| **CDR** | Call Detail Record |
| **JasperReports** | Open-source reporting library for Java |
| **HikariCP** | High-performance JDBC connection pool |
| **SPA** | Single Page Application |
| **JRE** | Java Runtime Environment |
| **TDD** | Technical Design Document (this document) |
| **API** | Application Programming Interface |
| **SSL/TLS** | Secure Sockets Layer/Transport Layer Security |
| **JDBC** | Java Database Connectivity |
| **WAR** | Web Application Archive |
| **JAR** | Java Archive |
| **Maven** | Build automation tool for Java |
| **NeonDB** | Cloud-hosted PostgreSQL database |
| **PL/pgSQL** | PostgreSQL procedural language |

### 1.4 References

- [Jakarta EE 11 Specification](https://jakarta.ee/specifications/)
- [SvelteKit Documentation](https://kit.svelte.dev/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [JasperReports Documentation](https://jasperreports.sourceforge.net/)
- [Project README.md](./README.md)

---

## 2. System Overview

### 2.1 Business Context

The FMRZ Telecom Billing System handles billing operations for a telecommunications provider. It processes call detail records (CDRs), generates invoices, manages customer accounts, and provides administrative oversight. The system supports multiple service packages, rate plans, and automated billing cycles.

Key business objectives:
- Automate billing processes to reduce manual errors
- Provide real-time visibility into customer usage and charges
- Support scalable operations for growing subscriber bases
- Ensure compliance with financial and data protection regulations

### 2.2 High-Level Requirements

**Functional Requirements:**
- Process CDR files and apply rating rules
- Generate PDF invoices using JasperReports
- Manage customer profiles, contracts, and service packages
- Provide web-based administrative interface
- Support automated billing cycles with tax calculations
- Implement health checks for system monitoring
- Self-service customer portal with profile management
- Add-on purchase and management
- Contract provisioning with MSISDN assignment

**Non-Functional Requirements:**
- **Performance**: Process 10,000 CDRs per minute
- **Scalability**: Support up to 1 million subscribers
- **Availability**: 99.9% uptime
- **Security**: Encrypt sensitive data, implement secure authentication
- **Usability**: Intuitive UI with dark mode support
- **Maintainability**: Modular code with comprehensive documentation

### 2.3 Assumptions and Constraints

**Assumptions:**
- PostgreSQL database is available and configured (NeonDB)
- Input CDR files are in CSV format with predefined schema
- Users have basic web browsing capabilities

**Constraints:**
- Must use Java 21 and Jakarta EE 11 standards
- Frontend limited to SvelteKit with Tailwind CSS
- Database must be PostgreSQL-compatible (NeonDB)
- Deployment must support containerization (Podman/Docker)

---

## 3. Architecture Overview

### 3.1 System Architecture

The system follows a layered architecture:

```
[Presentation Layer]     → SvelteKit SPA
       ↓
[Application Layer]     → Jakarta Servlets & Filters
       ↓
[Business Logic Layer]  → CDR Engine, Billing Engine
       ↓
[Data Access Layer]     → JDBC with HikariCP
       ↓
[Database Layer]        → PostgreSQL/NeonDB
```

### 3.2 Technology Stack

| Layer | Technology | Version | Purpose |
|-------|------------|---------|---------|
| Backend | Java | 21 | Core language |
| Framework | Jakarta EE | 11 | Enterprise APIs |
| Web Server | Apache Tomcat | 11.0.21 | Embedded servlet container |
| Database | PostgreSQL | 15+ | Relational data storage (NeonDB) |
| Connection Pool | HikariCP | 6.2.1 | Database connection management |
| JSON | Jackson | 2.17.0 | JSON processing |
| Reporting | JasperReports | 7.0.1 | PDF generation |
| Frontend | SvelteKit | 5.x | Reactive UI framework |
| Styling | Tailwind CSS | 4.0.0 | Utility-first CSS |
| Build Tool | Maven | 3.8+ | Dependency management |
| Container | Podman | Latest | Orchestration |

### 3.3 Deployment Architecture

**Development:** Local IDE execution with embedded Tomcat

**Production:**
```
[Client Browser]
       ↓
[Podman Container :8080]
       ↓
[Embedded Tomcat]
       ↓
[Java Application]
      ↙      ↘
[PostgreSQL]  [File System]
```

### 3.4 Data Flow

1. CDR files uploaded to input directory
2. CDRParser processes CSV, validates, rates
3. Rated data stored in database
4. Invoice generation triggered via UI/API
5. JasperReports generates PDF
6. PDF served to client

---

## 4. Detailed Design

### 4.1 Backend Design

#### 4.1.1 Servlet Architecture

The backend implements 17 servlets/filters for comprehensive functionality.

**Entry Point:**
- **Main.java**: Application entry point, configures embedded Tomcat, health endpoints

**Authentication & Security:**
- **AppFilter.java**: Path normalization, SPA routing, deep link support
- **AuthFilter.java**: Authentication enforcement on protected routes
- **CORSFilter.java**: Cross-Origin Resource Sharing

**Customer Servlets:**
- **AuthServlet.java**: /api/auth/* (login, register, logout, verify)
- **CustomerProfileServlet.java**: Profile, contracts, invoices, PDF downloads
- **CustomerOnboardingServlet.java**: New customer registration, contract creation
- **CustomerAddonServlet.java**: Add-on purchases

**Admin Servlets:**
- **AdminUserServlet.java**: Customer management
- **AdminContractServlet.java**: Contract CRUD, status/rateplan changes
- **AdminRatePlanServlet.java**: Rateplan management
- **AdminServicePkgServlet.java**: Service package management
- **AdminCDRServlet.java**: CDR viewing
- **AdminCDRUploadServlet.java**: CDR file upload
- **AdminCDRGeneratorServlet.java**: Test CDR generation
- **AdminBillServlet.java**: Billing operations
- **AdminAddonServlet.java**: Add-on management
- **AdminStatsServlet.java**: Dashboard statistics
- **AdminAuditServlet.java**: Billing audit, missing bill detection
- **PublicServlet.java**: Public rate plans, service packages

**Base Class:**
- **BaseServlet.java**: Common functionality (JSON parsing, error handling)

#### 4.1.2 Database Layer

```java
public class DB {
    private static HikariDataSource ds;
    
    static {
        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(System.getenv("DB_URL"));
        config.setUsername(System.getenv("DB_USER"));
        config.setPassword(System.getenv("DB_PASSWORD"));
        config.setMaximumPoolSize(10);
        ds = new HikariDataSource(config);
    }
    
    public static Connection getConnection() throws SQLException {
        return ds.getConnection();
    }
}
```

#### 4.1.3 CDR Processing Engine

**CDRParser.java**: Process CSV files

**CDRGenerator.java**: Generate test data

```java
public double calculateCharge(CDR cdr, ServicePackage pkg) {
    double subtotal = pkg.getRatePerMinute() * cdr.getDurationMinutes();
    double tax = subtotal * 0.10;
    return subtotal + tax;
}
```

#### 4.1.4 Reporting Engine

Uses JasperReports for PDF generation with in-memory caching:

```java
JasperReport report = JasperCompileManager.compileReport("invoice.jrxml");
JasperPrint print = JasperFillManager.fillReport(report, parameters, dataSource);
JasperExportManager.exportReportToPdfFile(print, "invoice.pdf");
```

### 4.2 Frontend Design

#### 4.2.1 Component Structure

```
src/
├── routes/
│   ├── +page.svelte (dashboard)
│   ├── login/, register/, onboarding/
│   ├── profile/, profile/edit/, profile/invoices/
│   ├── admin/, admin/cdr/, admin/customers/
│   ├── admin/contracts/, admin/billing/
│   └── packages/
└── lib/
    ├── components/ (Modal, Toast, Table, Form)
    └── stores/ (auth, data)
```

#### 4.2.2 Routing

| Route | Purpose |
|-------|---------|
| `/` | Dashboard |
| `/login`, `/register` | Authentication |
| `/onboarding` | Contract provisioning |
| `/profile*` | Customer portal |
| `/admin*` | Admin panel |
| `/packages` | Service packages |

#### 4.2.3 State Management

```javascript
export const user = writable(null);
export const isAuthenticated = writable(false);
```

### 4.3 Security Design

- **Session-based auth** with HTTP-only cookies
- **Role-based access** (admin vs customer)
- **CORS configuration**
- **Input validation**
- **Prepared statements**

### 4.4 API Design

#### RESTful Endpoints (25+)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | System health check |
| `/api/public/rateplans` | GET | List rate plans |
| `/api/public/packages` | GET | List service packages |
| `/api/auth/login` | POST | User authentication |
| `/api/auth/register` | POST | New customer registration |
| `/api/auth/logout` | POST | User logout |
| `/api/auth/verify` | GET | Verify session |
| `/api/customer/profile` | GET/PUT | Customer profile |
| `/api/customer/contracts` | GET | Customer contracts |
| `/api/customer/invoices` | GET | Customer invoices |
| `/api/customer/invoices/download` | GET | Download PDF |
| `/api/customer/addons` | GET/POST | Customer add-ons |
| `/api/onboarding/*` | GET/POST | Contract provisioning |
| `/api/admin/customers/*` | CRUD | Customer management |
| `/api/admin/contracts/*` | CRUD | Contract management |
| `/api/admin/rateplans/*` | CRUD | Rateplan management |
| `/api/admin/service-packages/*` | CRUD | Package management |
| `/api/admin/cdr*` | GET/POST | CDR management |
| `/api/admin/bills*` | CRUD | Billing operations |
| `/api/admin/addons/*` | GET/DELETE | Add-on management |
| `/api/admin/stats` | GET | Dashboard statistics |
| `/api/admin/audit/*` | GET/POST | Billing audit |

#### Data Formats

**Login Request:**
```json
{"username": "alice", "password": "123456"}
```

**Login Response:**
```json
{"id": 2, "username": "alice", "name": "Alice Smith", "role": "customer"}
```

**Invoice:**
```json
{
  "id": 1,
  "billing_period_start": "2026-04-01",
  "total_amount": 450.00,
  "status": "issued",
  "is_paid": false
}
```

---

## 5. Data Model Design

### 5.1 Database Schema

PostgreSQL with 14 tables.

### 5.2 Entity Relationships

```
user_account --(1:N)-- contract --(1:N)-- contract_consumption
contract --(1:N)-- bill --(1:1)-- invoice
contract --(1:N)-- ror_contract --(N:1)-- rateplan
rateplan --(1:N)-- rateplan_service_package
contract --(1:N)-- cdr
file --(1:N)-- cdr
contract --(1:N)-- contract_addon
```

### 5.3 Key Tables

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `user_account` | Customers/Admins | id, username, password, role, name, email |
| `rateplan` | Tariff Plans | id, name, ror_voice, ror_data, ror_sms, price |
| `service_package` | Bundled Services | id, name, type, amount, priority, price |
| `contract` | Customer Contracts | id, user_account_id, rateplan_id, msisdn, status, credit_limit |
| `contract_consumption` | Usage Tracking | contract_id, service_package_id, consumed, quota_limit |
| `ror_contract` | Applied Rates | contract_id, voice, data, sms |
| `bill` | Billing Invoices | id, contract_id, billing_period, recurring_fees, total_amount |
| `invoice` | PDF Records | id, bill_id, pdf_path |
| `cdr` | Call Records | id, dial_a, dial_b, duration, rated_flag |
| `contract_addon` | Add-ons | id, contract_id, service_package_id, is_active |

### 5.4 Data Validation

- Phone numbers: E.164 format
- Dates: ISO 8601
- Amounts: Non-negative decimals
- MSISDN: 11-digit format

---

## 6. Integration Design

### 6.1 External Systems

- PostgreSQL (NeonDB)
- File system for CDR input/output

### 6.2 Third-Party Libraries

- Gson, Jackson for JSON
- JasperReports for PDF
- HikariCP for pooling

### 6.3 Containerization

Multi-stage Dockerfile with non-root user.

### 6.4 Database Functions (60+)

See Section 14 for complete reference.

| Category | Functions |
|----------|-----------|
| Helper | get_cdr_usage_amount, set_file_parsed, create_file_record |
| Billing | insert_cdr, rate_cdr, generate_bill, generate_all_bills |
| Contract | create_contract, change_contract_status, change_contract_rateplan |
| Customer | login, create_customer, get_all_customers |
| Add-on | purchase_addon, get_contract_addons, cancel_addon |

### 6.5 Database Triggers

| Trigger | Event | Action |
|---------|-------|--------|
| `trg_auto_rate_cdr` | AFTER INSERT ON cdr | Rate CDR |
| `trg_auto_initialize_consumption` | BEFORE INSERT ON cdr | Initialize period |
| `trg_bill_payment` | AFTER UPDATE ON bill | Restore credit |

---

## 7. Performance and Scalability

### 7.1 Performance Requirements

- Response time < 2s
- CDR processing: 1000 records/second
- Concurrent users: 100+

### 7.2 Scalability

- Horizontal scaling via load balancer
- Database partitioning
- Asynchronous processing

### 7.3 Caching

- Jasper templates cached in memory
- Static assets cached at browser
- Query result caching

---

## 8. Security Considerations

### 8.1 Threats

- SQL injection
- XSS
- Unauthorized access
- Session hijacking

### 8.2 Controls

- Input sanitization
- Prepared statements
- HTTPS enforcement
- Non-root containers
- HTTP-only cookies
- CORS configuration

### 8.3 Compliance

- GDPR for data protection

---

## 9. Testing Strategy

### 9.1 Unit Testing

JUnit for backend classes.

### 9.2 Integration Testing

Servlet and DB operations.

### 9.3 System Testing

End-to-end with sample data.

### 9.4 Performance Testing

Load testing with JMeter.

### 9.5 Database Testing

- Function unit tests
- Trigger behavior tests
- Schema constraint validation

---

## 10. Deployment and Operations

### 10.1 Build Process

Maven: `mvn clean package`

### 10.2 Deployment

Podman: `podman-compose up -d --build`

### 10.3 Monitoring

- Health endpoint at `/health`
- Log files

### 10.4 Database Operations

- Use whole_billing_updated.sql
- Monthly billing cycles

---

## 11. Risks and Mitigation

| Risk | Mitigation |
|------|------------|
| Dependency vulnerabilities | Regular updates |
| Data loss | Backup strategies |
| Performance bottlenecks | Profiling |

---

## 12. Appendices

### 12.1 Configuration

**.env:**
```
DB_URL=jdbc:postgresql://host:5432/database
DB_USER=username
DB_PASSWORD=password
CDR_INPUT_PATH=/app/input
CDR_PROCESSED_PATH=/app/processed
```

### 12.2 Key Dependencies

```xml
<dependency>
    <groupId>com.zaxxer</groupId>
    <artifactId>HikariCP</artifactId>
    <version>6.2.1</version>
</dependency>
<dependency>
    <groupId>net.sf.jasperreports</groupId>
    <artifactId>jasperreports</artifactId>
    <version>7.0.1</version>
</dependency>
```

### 12.3 Glossary

- **CDR**: Call Detail Record
- **MSISDN**: Phone number
- **PLMN**: Mobile network identifier
- **ROR**: Rate of Return

---

## 13. Java Class Reference

### 13.1 Entry Points

| Class | Purpose | Location |
|-------|---------|----------|
| `Main` | Tomcat startup, health endpoints | `com.billing.Main` |

### 13.2 Servlets & Filters (17)

| Class | Path | Purpose |
|-------|------|---------|
| `BaseServlet` | - | Abstract base, JSON handling |
| `AuthServlet` | /api/auth/* | Login, register, logout |
| `CustomerProfileServlet` | /api/customer/* | Profile, contracts, invoices |
| `CustomerOnboardingServlet` | /api/onboarding/* | Contract creation |
| `CustomerAddonServlet` | /api/customer/addons | Add-on management |
| `AdminUserServlet` | /api/admin/customers | Customer CRUD |
| `AdminContractServlet` | /api/admin/contracts | Contract CRUD |
| `AdminRatePlanServlet` | /api/admin/rateplans | Rateplan CRUD |
| `AdminServicePkgServlet` | /api/admin/service-packages | Package CRUD |
| `AdminCDRServlet` | /api/admin/cdr | CDR viewing |
| `AdminCDRUploadServlet` | /api/admin/cdr/upload | File upload |
| `AdminCDRGeneratorServlet` | /api/admin/cdr/generate | Test data |
| `AdminBillServlet` | /api/admin/bills | Billing ops |
| `AdminAddonServlet` | /api/admin/addons | Add-on CRUD |
| `AdminStatsServlet` | /api/admin/stats | Statistics |
| `AdminAuditServlet` | /api/admin/audit | Audit |
| `PublicServlet` | /api/public/* | Public data |
| `AppFilter` | - | SPA routing |
| `AuthFilter` | - | Auth enforcement |
| `CORSFilter` | - | CORS handling |

### 13.3 Business Logic

| Class | Purpose |
|-------|---------|
| `CDRParser` | Parse CSV CDR files |
| `CDRGenerator` | Generate test CDRs |
| `BillAutomationWorker` | Automated billing |

### 13.4 Model Classes (7)

- UserAccount, Contract, ServicePackage
- RatePlan, CDR, Bill, Invoice

### 13.5 Utilities

| Class | Purpose |
|-------|---------|
| `DB` | HikariCP connection pool |
| `JasperLoader` | Report template caching |
| `GsonTypeAdapters` | JSON serialization |

---

## 14. Database Function Reference

### Helper Functions

| Function | Parameters | Returns | Purpose |
|----------|------------|---------|---------|
| `get_cdr_usage_amount` | (INTEGER, service_type) | NUMERIC | Normalize usage |
| `set_file_parsed` | (INTEGER) | VOID | Mark file parsed |
| `create_file_record` | (TEXT) | INTEGER | Create file record |

### Core Billing Functions

| Function | Parameters | Returns | Purpose |
|----------|------------|---------|---------|
| `insert_cdr` | (file_id, dial_a, dial_b, ...) | INTEGER | Insert CDR |
| `purchase_addon` | (contract_id, package_id) | INTEGER | Buy add-on |
| `rate_cdr` | (cdr_id) | VOID | Rate CDR |
| `initialize_consumption_period` | (DATE) | VOID | Init billing period |
| `generate_bill` | (contract_id, DATE) | INTEGER | Generate bill |
| `generate_all_bills` | (DATE) | VOID | Generate all bills |

### Contract Management

| Function | Parameters | Returns | Purpose |
|----------|------------|---------|---------|
| `create_contract` | (user_id, rateplan_id, msisdn, limit) | INTEGER | Create contract |
| `get_all_contracts` | (search, limit, offset) | TABLE | List contracts |
| `get_contract_by_id` | (id) | TABLE | Get contract |
| `change_contract_status` | (id, status) | VOID | Change status |
| `change_contract_rateplan` | (id, rateplan_id) | VOID | Change rateplan |

### Customer Management

| Function | Parameters | Returns | Purpose |
|----------|------------|---------|---------|
| `get_all_customers` | (search, limit, offset) | TABLE | List customers |
| `get_user_data` | (id) | TABLE | Get profile |
| `login` | (username, password) | TABLE | Authenticate |
| `create_customer` | (...) | INTEGER | Create customer |
| `get_customer_by_id` | (id) | TABLE | Get customer |

### Service Package Functions

| Function | Parameters | Returns | Purpose |
|----------|------------|---------|---------|
| `get_all_service_packages` | () | TABLE | List packages |
| `get_service_package_by_id` | (id) | TABLE | Get package |
| `create_service_package` | (...) | TABLE | Create package |

### Rateplan Functions

| Function | Parameters | Returns | Purpose |
|----------|------------|---------|---------|
| `get_all_rateplans` | () | TABLE | List rateplans |
| `get_rateplan_by_id` | (id) | TABLE | Get rateplan |

### Billing Functions

| Function | Parameters | Returns | Purpose |
|----------|------------|---------|---------|
| `get_bill` | (id) | TABLE | Get bill |
| `mark_bill_paid` | (id) | VOID | Mark paid |
| `generate_invoice` | (id, path) | VOID | Create invoice |
| `pay_bill` | (id, path) | VOID | Pay bill |
| `get_all_bills` | (search, limit, offset) | TABLE | List bills |
| `get_user_invoices` | (user_id) | TABLE | User invoices |
| `get_missing_bills` | (search, limit, offset) | TABLE | Missing bills |
| `generate_bulk_missing` | (search) | VOID | Generate missing |

### CDR Functions

| Function | Parameters | Returns | Purpose |
|----------|------------|---------|---------|
| `get_cdrs` | (limit, offset) | TABLE | List CDRs |
| `get_contract_consumption` | (id, DATE) | TABLE | Consumption |

### MSISDN Functions

| Function | Parameters | Returns | Purpose |
|----------|------------|---------|---------|
| `get_available_msisdns` | () | TABLE | List available |
| `mark_msisdn_taken` | (msisdn) | VOID | Mark taken |
| `release_msisdn` | (msisdn) | VOID | Release |

### Add-on Functions

| Function | Parameters | Returns | Purpose |
|----------|------------|---------|---------|
| `get_contract_addons` | (id) | TABLE | List add-ons |
| `cancel_addon` | (id) | VOID | Cancel |
| `expire_addons` | () | VOID | Expire past-due |

### Statistics Functions

| Function | Parameters | Returns | Purpose |
|----------|------------|---------|---------|
| `get_dashboard_stats` | () | TABLE | Dashboard stats |

---

## 15. API Endpoint Reference

### 15.1 Public Endpoints

| Endpoint | Method | Response |
|----------|--------|----------|
| `/health` | GET | `{"status": "UP"}` |
| `/api/public/rateplans` | GET | `[{"id": 1, "name": "Basic"}]` |
| `/api/public/packages` | GET | `[{"id": 1, "name": "Voice Pack"}]` |

### 15.2 Authentication

| Endpoint | Method | Request | Response |
|----------|--------|---------|----------|
| `/api/auth/login` | POST | `{"username": "...", "password": "..."}` | `{"id": 1, "role": "customer"}` |
| `/api/auth/register` | POST | `{"username": "...", "password": "..."}` | `{"id": 1}` |
| `/api/auth/logout` | POST | - | `{"success": true}` |
| `/api/auth/verify` | GET | Cookie | User data or 401 |

### 15.3 Customer

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/customer/profile` | GET/PUT | Profile |
| `/api/customer/contracts` | GET | Contracts |
| `/api/customer/invoices` | GET | Invoices |
| `/api/customer/invoices/download` | GET | PDF |
| `/api/customer/addons` | GET/POST | Add-ons |
| `/api/onboarding/available-msisdn` | GET | Phone numbers |
| `/api/onboarding/create-contract` | POST | New contract |

### 15.4 Admin

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/admin/customers` | CRUD | Customers |
| `/api/admin/contracts` | CRUD | Contracts |
| `/api/admin/contracts/*/status` | PUT | Status change |
| `/api/admin/rateplans` | CRUD | Rateplans |
| `/api/admin/service-packages` | CRUD | Packages |
| `/api/admin/cdr` | GET | CDRs |
| `/api/admin/cdr/upload` | POST | Upload |
| `/api/admin/bills` | CRUD | Bills |
| `/api/admin/addons` | CRUD | Add-ons |
| `/api/admin/stats` | GET | Statistics |
| `/api/admin/audit/missing` | GET | Missing bills |

---

## 16. Integration Issues and Resolutions

### 16.1 Startup Crash: The Permission Paradox

- **Issue**: Container crashed with AccessDeniedException
- **Fix**: Dockerfile added chown; Main.java moved baseDir to /tmp

### 16.2 The 404 Ghost: Shaded JAR Annotation Blindness

- **Issue**: @WebServlet annotations ignored in JAR
- **Fix**: Dynamic JAR Detection with JarResourceSet

### 16.3 The Empty Page: Frontend/Backend Desync

- **Issue**: JS 404 due to hash mismatch
- **Fix**: Nginx proxies to Tomcat instead of filesystem

### 16.4 SPA Router: Path Normalization

- **Issue**: Deep links returned 404
- **Fix**: AppFilter forwards to index.html

### 16.5 Security: Secrets Leak

- **Issue**: Passwords in bundled properties
- **Fix**: Environment variable priority

### 16.6 Branding: Centralized Config

- **Issue**: Hardcoded values
- **Fix**: config.properties loaded at startup

### 16.7 Performance: Jasper Compilation Lag

- **Issue**: Re-compiling on every request
- **Fix**: In-memory caching

### 16.8 Jasper 7: Fragmented Fonts

- **Issue**: Font files overwrote each other
- **Fix**: AppendingTransformer in Maven

### 16.9 Health Guard

- **Issue**: No health check for cloud
- **Fix**: /health endpoint + shutdown hook

### 16.10 Environment Parity

- **Issue**: Running as root
- **Fix**: Non-root javauser

### 16.11 Safety Net

- **Issue**: Cryptic missing var errors
- **Fix**: Placeholder awareness

### 16.12 Jasper 7 Automation

- **Issue**: XML schema failure
- **Fix**: Jackson-based loading

### 16.13 Networking: Localhost

- **Issue**: Container localhost != host
- **Fix**: network_mode: host

### 16.14 Frontend State

- **Issue**: Missing state variables
- **Fix**: $derived() reactive state

### 16.15 Billing Conflicts

- **Issue**: Duplicate key errors
- **Fix**: ON CONFLICT DO UPDATE

---

## Security Hardening Summary

| Component | Status | Fix |
|-----------|--------|-----|
| Identity | ✅ | Non-root user |
| Secrets | ✅ | ENV variables |
| Observability | ✅ | /health endpoint |
| Build | ✅ | Merger |
| Reporting | ✅ | Caching |
| Assets | ✅ | Container-native |
| Routing | ✅ | SPA fix |
| Networking | ✅ | Host mode |
| Frontend | ✅ | State fixes |
| Billing | ✅ | Idempotent |

---

*Document Version: 2.0*
*Last Updated: April 30, 2026*
*FMRZ Telecom Group | Stabilized & Production-Ready | 2026*