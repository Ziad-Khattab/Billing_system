# Technical Design Document (TDD) for FMRZ Telecom Billing System

## Document Information

- **Document Title**: Technical Design Document (TDD) for FMRZ Telecom Billing System
- **Version**: 1.2
- **Date**: April 29, 2026
- **Authors**: Ziad Khattab, Fouad (Contributors)
- **Project Name**: Telecom Billing System
- **Project Version**: v1.2
- **Confidentiality**: Internal Use

## Table of Contents

1. [Introduction](#1-introduction)
   1.1 [Purpose](#11-purpose)
   1.2 [Scope](#12-scope)
   1.3 [Definitions and Acronyms](#13-definitions-and-acronyms)
   1.4 [References](#14-references)

2. [System Overview](#2-system-overview)
   2.1 [Business Context](#21-business-context)
   2.2 [High-Level Requirements](#22-high-level-requirements)
   2.3 [Assumptions and Constraints](#23-assumptions-and-constraints)

3. [Architecture Overview](#3-architecture-overview)
   3.1 [System Architecture](#31-system-architecture)
   3.2 [Technology Stack](#32-technology-stack)
   3.3 [Deployment Architecture](#33-deployment-architecture)
   3.4 [Data Flow Diagrams](#34-data-flow-diagrams)

4. [Detailed Design](#4-detailed-design)
   4.1 [Backend Design](#41-backend-design)
      4.1.1 [Servlet Architecture](#411-servlet-architecture)
      4.1.2 [Database Layer](#412-database-layer)
      4.1.3 [CDR Processing Engine](#413-cdr-processing-engine)
      4.1.4 [Reporting Engine](#414-reporting-engine)
   4.2 [Frontend Design](#42-frontend-design)
      4.2.1 [Component Structure](#421-component-structure)
      4.2.2 [Routing and Navigation](#422-routing-and-navigation)
      4.2.3 [State Management](#423-state-management)
   4.3 [Security Design](#43-security-design)
      4.3.1 [Authentication and Authorization](#431-authentication-and-authorization)
      4.3.2 [Data Protection](#432-data-protection)
      4.3.3 [Session Management](#433-session-management)
   4.4 [API Design](#44-api-design)
      4.4.1 [RESTful Endpoints](#441-restful-endpoints)
      4.4.2 [Data Formats](#442-data-formats)

5. [Data Model Design](#5-data-model-design)
   5.1 [Database Schema](#51-database-schema)
   5.2 [Entity-Relationship Diagram](#52-entity-relationship-diagram)
   5.3 [Key Tables](#53-key-tables)
   5.4 [Data Validation Rules](#54-data-validation-rules)

6. [Integration Design](#6-integration-design)
   6.1 [External Systems](#61-external-systems)
   6.2 [Third-Party Libraries](#62-third-party-libraries)
   6.3 [Containerization](#63-containerization)

7. [Performance and Scalability](#7-performance-and-scalability)
   7.1 [Performance Requirements](#71-performance-requirements)
   7.2 [Scalability Considerations](#72-scalability-considerations)
   7.3 [Caching Strategies](#73-caching-strategies)

8. [Security Considerations](#8-security-considerations)
   8.1 [Threat Model](#81-threat-model)
   8.2 [Security Controls](#82-security-controls)
   8.3 [Compliance](#83-compliance)

9. [Testing Strategy](#9-testing-strategy)
   9.1 [Unit Testing](#91-unit-testing)
   9.2 [Integration Testing](#92-integration-testing)
   9.3 [System Testing](#93-system-testing)
   9.4 [Performance Testing](#94-performance-testing)

10. [Deployment and Operations](#10-deployment-and-operations)
    10.1 [Build Process](#101-build-process)
    10.2 [Deployment Pipeline](#102-deployment-pipeline)
    10.3 [Monitoring and Logging](#103-monitoring-and-logging)
    10.4 [Backup and Recovery](#104-backup-and-recovery)

11. [Risks and Mitigation](#11-risks-and-mitigation)

12. [Appendices](#12-appendices)
    12.1 [Code Snippets](#121-code-snippets)
    12.2 [Configuration Files](#122-configuration-files)
    12.3 [Glossary](#123-glossary)

---

## 1. Introduction

### 1.1 Purpose

This Technical Design Document (TDD) provides a comprehensive blueprint for the design, implementation, and maintenance of the FMRZ Telecom Billing System. The document serves as a reference for developers, architects, testers, and stakeholders to understand the system's technical foundations, ensuring consistent implementation and future scalability. It covers all aspects from high-level architecture to low-level design details, aiming for a production-ready, carrier-grade billing solution.

### 1.2 Scope

The TDD encompasses:
- System architecture and component design
- Backend (Java/Jakarta EE) and frontend (SvelteKit) implementation details
- Database schema and data models
- Security mechanisms and compliance
- Integration points and APIs
- Deployment strategies and operational procedures
- Testing methodologies and performance benchmarks

Out of scope: Business analysis, user manuals, marketing materials.

### 1.3 Definitions and Acronyms

- **CDR**: Call Detail Record
- **JasperReports**: Open-source reporting library for Java
- **HikariCP**: High-performance JDBC connection pool
- **SPA**: Single Page Application
- **JRE**: Java Runtime Environment
- **POD**: Plain Old Documentation (informal term for simple documentation)
- **TDD**: Technical Design Document (this document)
- **API**: Application Programming Interface
- **SSL/TLS**: Secure Sockets Layer/Transport Layer Security
- **JDBC**: Java Database Connectivity
- **JSP**: JavaServer Pages (though not used in this project)
- **WAR**: Web Application Archive
- **JAR**: Java Archive
- **Maven**: Build automation tool for Java

### 1.4 References

- [Jakarta EE 11 Specification](https://jakarta.ee/specifications/)
- [SvelteKit Documentation](https://kit.svelte.dev/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [JasperReports Documentation](https://jasperreports.sourceforge.net/)
- [Project README.md](./README.md)
- [Deployment Resolution Document](./DEPLOYMENT_RESOLUTION.md)

---

## 2. System Overview

### 2.1 Business Context

The FMRZ Telecom Billing System is designed to handle the billing operations for a telecommunications provider. It processes call detail records (CDRs), generates invoices, manages customer accounts, and provides administrative oversight. The system supports multiple service packages, rate plans, and automated billing cycles, ensuring accurate financial transactions for telecom services.

Key business objectives:
- Automate billing processes to reduce manual errors
- Provide real-time visibility into customer usage and charges
- Support scalable operations for growing subscriber bases
- Ensure compliance with financial and data protection regulations
- Enable quick integration with existing telecom infrastructure

### 2.2 High-Level Requirements

Functional Requirements:
- Process CDR files and apply rating rules
- Generate PDF invoices using JasperReports
- Manage customer profiles, contracts, and service packages
- Provide web-based administrative interface
- Support automated billing cycles with tax calculations
- Implement health checks for system monitoring

Non-Functional Requirements:
- **Performance**: Process 10,000 CDRs per minute
- **Scalability**: Support up to 1 million subscribers
- **Availability**: 99.9% uptime
- **Security**: Encrypt sensitive data, implement secure authentication
- **Usability**: Intuitive UI with dark mode support
- **Maintainability**: Modular code with comprehensive documentation

### 2.3 Assumptions and Constraints

Assumptions:
- PostgreSQL database is available and configured
- Input CDR files are in CSV format with predefined schema
- Users have basic web browsing capabilities
- Network connectivity is reliable for cloud deployments

Constraints:
- Must use Java 21 and Jakarta EE 11 standards
- Frontend limited to SvelteKit with Tailwind CSS
- Database must be PostgreSQL-compatible (NeonDB)
- Deployment must support containerization (Podman/Docker)
- Budget for third-party tools is limited to open-source options

---

## 3. Architecture Overview

### 3.1 System Architecture

The system follows a layered architecture:

```
[Presentation Layer]
    ↓
[Application Layer] (Servlets, Filters)
    ↓
[Business Logic Layer] (Services, Engines)
    ↓
[Data Access Layer] (DAO, JDBC)
    ↓
[Database Layer] (PostgreSQL)
```

- **Presentation Layer**: SvelteKit SPA served by embedded Tomcat
- **Application Layer**: Jakarta Servlets handling HTTP requests
- **Business Logic Layer**: CDR parsing, rating, invoice generation
- **Data Access Layer**: JDBC with HikariCP connection pooling
- **Database Layer**: PostgreSQL with schema for billing entities

### 3.2 Technology Stack

| Layer | Technology | Version | Purpose |
|-------|------------|---------|---------|
| Backend | Java | 21 | Core language |
| Framework | Jakarta EE | 11 | Enterprise APIs |
| Web Server | Apache Tomcat | 11.0.21 | Embedded servlet container |
| Database | PostgreSQL | 15+ | Relational data storage |
| Connection Pool | HikariCP | 6.2.1 | Database connection management |
| ORM | JDBC | N/A | Data access |
| Reporting | JasperReports | 7.0.1 | PDF generation |
| Frontend | SvelteKit | 2.0.0 | Reactive UI framework |
| Styling | Tailwind CSS | 4.0.0 | Utility-first CSS |
| Build Tool | Maven | 3.8+ | Dependency management |
| Container | Podman | Latest | Orchestration |
| Proxy | Nginx | 1.24+ | Edge proxy (optional) |

### 3.3 Deployment Architecture

Development:
- Local IDE execution with embedded Tomcat
- Direct JAR run with environment variables

Production:
- Containerized JAR in Podman/Docker
- Health checks and auto-recovery
- Optional Nginx proxy for load balancing

```
[Client Browser]
    ↓
[Nginx Proxy] (optional)
    ↓
[Podman Container]
    ↓
[Embedded Tomcat :8080]
    ↓
[Java Application]
    ↙        ↘
[PostgreSQL] [File System (CDRs/PDFs)]
```

### 3.4 Data Flow Diagrams

#### High-Level Data Flow:
1. CDR files uploaded to input directory
2. CDRParser processes CSV, validates, rates
3. Rated data stored in database
4. Invoice generation triggered via UI/API
5. JasperReports compiles .jrxml to PDF
6. PDF served to client

#### User Interaction Flow:
- User logs in → Authenticated via session
- Admin accesses dashboard → Loads data from DB
- CDR upload → Processed asynchronously
- Invoice view → Generated on-demand

---

## 4. Detailed Design

### 4.1 Backend Design

#### 4.1.1 Servlet Architecture

The backend uses Jakarta Servlet API for request handling:

- **Main.java**: Application entry point, configures Tomcat
- **AppFilter.java**: Handles path normalization, SPA routing
- **CustomerProfileServlet.java**: Manages customer data and invoice generation
- **AdminUserServlet.java**: Administrative operations

Servlet Mapping:
```java
@WebServlet("/api/customers")
public class CustomerProfileServlet extends HttpServlet {
    // Handles GET, POST for customer operations
}
```

#### 4.1.2 Database Layer

Database access via JDBC with HikariCP:

```java
// DB.java
public class DB {
    private static HikariDataSource ds;
    
    static {
        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(System.getenv("DB_URL"));
        config.setUsername(System.getenv("DB_USER"));
        config.setPassword(System.getenv("DB_PASSWORD"));
        ds = new HikariDataSource(config);
    }
    
    public static Connection getConnection() throws SQLException {
        return ds.getConnection();
    }
}
```

Entity Classes:
- Customer, Contract, ServicePackage, CDR, Invoice

#### 4.1.3 CDR Processing Engine

**CDRParser.java**: Core engine for processing CSV files.

Algorithm:
1. Read CSV file line by line
2. Validate fields (phone numbers, timestamps, duration)
3. Apply rating rules based on service packages
4. Calculate charges with taxes (10%)
5. Insert rated records into database
6. Generate summary reports

Rating Logic:
```java
public double calculateCharge(CDR cdr, ServicePackage pkg) {
    double baseRate = pkg.getRatePerMinute();
    double duration = cdr.getDurationMinutes();
    double subtotal = baseRate * duration;
    double tax = subtotal * 0.10; // 10% tax
    return subtotal + tax;
}
```

#### 4.1.4 Reporting Engine

Uses JasperReports for PDF generation:

- **Template**: invoice.jrxml (JRXML format)
- **Data Source**: Java objects or JDBC ResultSet
- **Output**: PDF with embedded fonts and images

Jasper Integration:
```java
JasperReport report = JasperCompileManager.compileReport("invoice.jrxml");
JasperPrint print = JasperFillManager.fillReport(report, parameters, dataSource);
JasperExportManager.exportReportToPdfFile(print, "invoice.pdf");
```

### 4.2 Frontend Design

#### 4.2.1 Component Structure

SvelteKit app structure:
```
src/
├── app.html (layout)
├── app.css (global styles)
├── routes/
│   ├── +page.svelte (dashboard)
│   ├── admin/
│   │   ├── cdr/+page.svelte
│   │   ├── customers/+page.svelte
│   │   └── contracts/+page.svelte
│   └── packages/+page.svelte
└── lib/
    ├── components/
    │   ├── Header.svelte
    │   ├── Table.svelte
    │   └── Form.svelte
    └── stores/
        ├── auth.js
        └── data.js
```

#### 4.2.2 Routing and Navigation

Client-side routing with SvelteKit:
- `/` : Dashboard
- `/admin/cdr` : CDR management
- `/admin/customers` : Customer profiles
- `/admin/contracts` : Contract administration
- `/packages` : Service package management

SPA routing handled by AppFilter for deep links.

#### 4.2.3 State Management

Uses Svelte stores for reactive state:
```javascript
// stores/auth.js
import { writable } from 'svelte/store';

export const user = writable(null);
export const isAuthenticated = writable(false);
```

Data fetching via fetch API to backend endpoints.

### 4.3 Security Design

#### 4.3.1 Authentication and Authorization

Session-based auth:
- Login form posts to `/api/login`
- Server sets HTTP-only cookie
- Subsequent requests validated via session

#### 4.3.2 Data Protection

- SSL/TLS for database connections
- Password hashing (if implemented)
- Input validation to prevent injection

#### 4.3.3 Session Management

- Session timeout: 30 minutes
- Secure cookie flags: HttpOnly, Secure

### 4.4 API Design

#### 4.4.1 RESTful Endpoints

| Endpoint | Method | Description | Servlet |
|----------|--------|-------------|---------|
| `/health` | GET | System health check | Main.java |
| `/api/auth/login` | POST | User authentication | AuthServlet |
| `/api/auth/logout` | POST | User logout | AuthServlet |
| `/api/admin/customers/*` | GET/POST/PUT/DELETE | Manage customers (admin) | AdminUserServlet |
| `/api/admin/contracts/*` | GET/POST/PUT/DELETE | Manage contracts (admin) | AdminContractServlet |
| `/api/admin/rateplans/*` | GET/POST/PUT/DELETE | Manage rateplans (admin) | AdminRatePlanServlet |
| `/api/admin/service-packages/*` | GET/POST/PUT/DELETE | Manage service packages (admin) | AdminServicePkgServlet |
| `/api/admin/cdr/*` | GET/POST | CDR file management (admin) | AdminCDRServlet |
| `/api/admin/bills/*` | GET/POST/PUT | Bill management (admin) | AdminBillServlet |
| `/api/admin/addons/*` | GET/POST | Addon management (admin) | AdminAddonServlet |
| `/api/admin/stats` | GET | System statistics (admin) | AdminStatsServlet |
| `/api/customer/profile` | GET | Customer profile | CustomerProfileServlet |
| `/api/customer/contracts` | GET | Customer contracts | CustomerProfileServlet |
| `/api/customer/invoices` | GET | Customer invoices | CustomerProfileServlet |
| `/api/customer/invoices/download` | GET | Download PDF invoice | CustomerProfileServlet |
| `/api/customer/addons/*` | GET/POST | Customer addons | CustomerAddonServlet |
| `/api/public/*` | GET | Public data access | PublicServlet |
#### 4.4.2 Data Formats

Request/Response in JSON:
```json
{
  "customer": {
    "id": 1,
    "name": "John Doe",
    "phone": "+1234567890"
  },
  "contract": {
    "id": 1,
    "startDate": "2026-01-01",
    "packageId": 2
  }
}
```

---

## 5. Data Model Design

### 5.1 Database Schema

PostgreSQL schema with tables for billing entities.

### 5.2 Entity-Relationship Diagram

```
```
user_account --(1:N)-- contract --(1:N)-- contract_consumption --(N:1)-- service_package
contract --(1:N)-- bill --(1:1)-- invoice
contract --(1:N)-- ror_contract --(N:1)-- rateplan
rateplan --(1:N)-- rateplan_service_package --(N:1)-- service_package
contract --(1:N)-- cdr
file --(1:N)-- cdr
user_account --(1:1)-- msisdn_pool (via contract)
```

### 5.3 Key Tables

**customers**:
- id (PK)
- name
- email
- phone
- address

**contracts**:
- id (PK)
- customer_id (FK)
- package_id (FK)
- start_date
- end_date

**service_packages**:
- id (PK)
- name
- description
- rate_per_minute

**cdrs**:
- id (PK)
- contract_id (FK)
- caller_number
- callee_number
- start_time
- duration
- rated_charge

**invoices**:
- id (PK)
- customer_id (FK)
- period_start
- period_end
- total_amount
- pdf_path

### 5.4 Data Validation Rules

- Phone numbers: E.164 format validation
- Dates: ISO 8601 format
- Amounts: Non-negative decimals
- Email: Standard regex validation

---

## 6. Integration Design

### 6.1 External Systems

- PostgreSQL (NeonDB) for data storage
- File system for CDR input/output
- Optional: Nginx for proxying

### 6.2 Third-Party Libraries

- Gson for JSON handling
- JasperReports for reporting
- HikariCP for connection pooling
- Batik for SVG processing in reports

### 6.3 Containerization

Dockerfile builds JRE-based image with JAR and resources.

---

## 7. Performance and Scalability

### 7.1 Performance Requirements

- Response time < 2s for UI interactions
- CDR processing: 1000 records/second
- Concurrent users: 100+

### 7.2 Scalability Considerations

- Horizontal scaling via load balancer
- Database partitioning for large datasets
- Asynchronous processing for heavy operations

### 7.3 Caching Strategies

- Jasper report templates cached in memory
- Database query result caching
- Static assets cached at browser level

---

## 8. Security Considerations

### 8.1 Threat Model

Potential threats: SQL injection, XSS, unauthorized access.

### 8.2 Security Controls

- Input sanitization
- Prepared statements for SQL
- HTTPS enforcement
- Non-root container execution

### 8.3 Compliance

- GDPR for data protection
- PCI DSS for payment data (if applicable)

---

## 9. Testing Strategy

### 9.1 Unit Testing

JUnit for backend classes.

### 9.2 Integration Testing

Test servlet interactions and DB operations.

### 9.3 System Testing

End-to-end testing with sample data.

### 9.4 Performance Testing

Load testing with JMeter.

---

## 10. Deployment and Operations

### 10.1 Build Process

Maven build compiles and packages JAR.

### 10.2 Deployment Pipeline

Git-based with automated builds.

### 10.3 Monitoring and Logging

Health endpoint and log files.

### 10.4 Backup and Recovery

Database backups and file system snapshots.

---

## 11. Risks and Mitigation

- Dependency vulnerabilities: Regular updates
- Data loss: Backup strategies
- Performance bottlenecks: Profiling and optimization

---

## 12. Appendices

### 12.1 Code Snippets

Examples of key code sections.

### 12.2 Configuration Files

.env.example, pom.xml excerpts.

### 12.3 Glossary

Additional terms.

---

*This TDD provides a comprehensive guide for the Telecom Billing System implementation. For updates, refer to the project repository.*

### 5.3 Key Tables (Detailed from SQL Schema)

**user_account** (Customers/Users):
- id (SERIAL PK)
- username (VARCHAR(255) UNIQUE)
- password (VARCHAR(30))
- role (user_role ENUM: 'admin', 'customer')
- name (VARCHAR(255))
- email (VARCHAR(255) UNIQUE)
- address (TEXT)
- birthdate (DATE)

**msisdn_pool** (Phone Number Pool):
- id (SERIAL PK)
- msisdn (VARCHAR(20) UNIQUE)
- is_available (BOOLEAN DEFAULT TRUE)

**rateplan** (Tariff Plans):
- id (SERIAL PK)
- name (VARCHAR(255))
- ror_data (NUMERIC(10,2)) - Rate of Return for data
- ror_voice (NUMERIC(10,2)) - Rate of Return for voice
- ror_sms (NUMERIC(10,2)) - Rate of Return for SMS
- price (NUMERIC(10,2)) - Base price

**service_package** (Bundled Services):
- id (SERIAL PK)
- name (VARCHAR(255))
- type (service_type ENUM: 'voice', 'data', 'sms', 'free_units')
- amount (NUMERIC(12,4)) - Quota amount
- priority (INTEGER DEFAULT 1)
- price (NUMERIC(12,2))
- is_roaming (BOOLEAN DEFAULT FALSE)
- description (TEXT)

**rateplan_service_package** (Many-to-Many Link):
- rateplan_id (FK to rateplan.id)
- service_package_id (FK to service_package.id)
- PRIMARY KEY (rateplan_id, service_package_id)

**contract** (Customer Contracts):
- id (SERIAL PK)
- user_account_id (FK to user_account.id)
- rateplan_id (FK to rateplan.id)
- msisdn (VARCHAR(20))
- status (contract_status ENUM: 'active', 'suspended', 'suspended_debt', 'terminated')
- credit_limit (NUMERIC(12,2) DEFAULT 0)
- available_credit (NUMERIC(12,2) DEFAULT 0)

**contract_consumption** (Usage Tracking):
- contract_id (FK to contract.id)
- service_package_id (FK to service_package.id)
- rateplan_id (FK to rateplan.id)
- starting_date (DATE)
- ending_date (DATE)
- consumed (NUMERIC(12,4) DEFAULT 0)
- quota_limit (NUMERIC(12,4) DEFAULT 0)
- is_billed (BOOLEAN DEFAULT FALSE)
- bill_id (FK to bill.id)
- PRIMARY KEY (contract_id, service_package_id, rateplan_id, starting_date, ending_date)

**ror_contract** (Applied Rates):
- contract_id (FK to contract.id)
- rateplan_id (FK to rateplan.id)
- starting_date (DATE DEFAULT DATE_TRUNC('month', CURRENT_DATE)::DATE)
- data (INTEGER DEFAULT 0)
- voice (INTEGER DEFAULT 0)
- sms (INTEGER DEFAULT 0)
- roaming_voice (NUMERIC(12,2) DEFAULT 0.00)
- roaming_data (NUMERIC(12,2) DEFAULT 0.00)
- roaming_sms (NUMERIC(12,2) DEFAULT 0.00)
- bill_id (FK to bill.id)
- PRIMARY KEY (contract_id, rateplan_id, starting_date)

**bill** (Billing Cycle Invoices):
- id (SERIAL PK)
- contract_id (FK to contract.id)
- billing_period_start (DATE)
- billing_period_end (DATE)
- billing_date (DATE)
- recurring_fees (NUMERIC(12,2) DEFAULT 0)
- one_time_fees (NUMERIC(12,2) DEFAULT 0)
- voice_usage (INTEGER DEFAULT 0) - minutes
- data_usage (INTEGER DEFAULT 0) - MB
- sms_usage (INTEGER DEFAULT 0) - count
- ROR_charge (NUMERIC(12,2) DEFAULT 0)
- overage_charge (NUMERIC(12,2) DEFAULT 0)
- roaming_charge (NUMERIC(12,2) DEFAULT 0)
- promotional_discount (NUMERIC(12,2) DEFAULT 0)
- taxes (NUMERIC(12,2) DEFAULT 0)
- total_amount (NUMERIC(12,2) DEFAULT 0)
- status (bill_status ENUM: 'draft', 'issued', 'paid', 'overdue', 'cancelled')
- is_paid (BOOLEAN DEFAULT FALSE)
- UNIQUE (contract_id, billing_period_start)

**invoice** (PDF Invoice Records):
- id (SERIAL PK)
- bill_id (FK to bill.id UNIQUE)
- pdf_path (TEXT)
- generation_date (TIMESTAMP DEFAULT NOW())

**cdr** (Call Detail Records):
- id (SERIAL PK)
- file_id (FK to file.id)
- dial_a (VARCHAR(20)) - Calling party
- dial_b (VARCHAR(20)) - Called party
- start_time (TIMESTAMP)
- duration (INTEGER DEFAULT 0) - seconds
- service_id (FK to service_package.id)
- hplmn (VARCHAR(20)) - Home PLMN
- vplmn (VARCHAR(20)) - Visited PLMN (roaming)
- external_charges (NUMERIC(12,2) DEFAULT 0)
- rated_flag (BOOLEAN DEFAULT FALSE)
- rated_service_id (INTEGER)

**file** (CDR File Tracking):
- id (SERIAL PK)
- parsed_flag (BOOLEAN DEFAULT FALSE)
- file_path (TEXT)


---

## 5. Data Model Design (Detailed from whole_billing_updated.sql)

### 5.1 Database Schema

The database uses PostgreSQL with custom ENUM types and stored functions for billing logic.

#### ENUM Types:
- **user_role**: 'admin', 'customer'
- **contract_status**: 'active', 'suspended', 'suspended_debt', 'terminated'
- **bill_status**: 'draft', 'issued', 'paid', 'overdue', 'cancelled'
- **service_type**: 'voice', 'data', 'sms', 'free_units'

### 5.3 Key Tables (From whole_billing_updated.sql)

**user_account**:
- id (SERIAL PK)
- username (VARCHAR(255) UNIQUE)
- password (VARCHAR(30))
- role (user_role)
- name (VARCHAR(255))
- email (VARCHAR(255) UNIQUE)
- address (TEXT)
- birthdate (DATE)

**msisdn_pool**:
- id (SERIAL PK)
- msisdn (VARCHAR(20) UNIQUE)
- is_available (BOOLEAN DEFAULT TRUE)

**rateplan**:
- id (SERIAL PK)
- name (VARCHAR(255))
- ror_data (NUMERIC(10,2)) - Rate of Return for data
- ror_voice (NUMERIC(10,2)) - Rate of Return for voice
- ror_sms (NUMERIC(10,2)) - Rate of Return for SMS
- price (NUMERIC(10,2)) - Base price

**service_package**:
- id (SERIAL PK)
- name (VARCHAR(255))
- type (service_type)
- amount (NUMERIC(12,4)) - Quota amount
- priority (INTEGER DEFAULT 1)
- price (NUMERIC(12,2))
- is_roaming (BOOLEAN DEFAULT FALSE)
- description (TEXT)

**rateplan_service_package**:
- rateplan_id (FK to rateplan.id)
- service_package_id (FK to service_package.id)
- PRIMARY KEY (rateplan_id, service_package_id)

**contract**:
- id (SERIAL PK)
- user_account_id (FK to user_account.id)
- rateplan_id (FK to rateplan.id)
- msisdn (VARCHAR(20))
- status (contract_status DEFAULT 'active')
- credit_limit (NUMERIC(12,2) DEFAULT 0)
- available_credit (NUMERIC(12,2) DEFAULT 0)

**contract_consumption**:
- contract_id (FK to contract.id)
- service_package_id (FK to service_package.id)
- rateplan_id (FK to rateplan.id)
- starting_date (DATE)
- ending_date (DATE)
- consumed (NUMERIC(12,4) DEFAULT 0)
- quota_limit (NUMERIC(12,4) DEFAULT 0)
- is_billed (BOOLEAN DEFAULT FALSE)
- bill_id (FK to bill.id)
- PRIMARY KEY (contract_id, service_package_id, rateplan_id, starting_date, ending_date)

**ror_contract**:
- contract_id (FK to contract.id)
- rateplan_id (FK to rateplan.id)
- starting_date (DATE DEFAULT DATE_TRUNC('month', CURRENT_DATE)::DATE)
- data (INTEGER DEFAULT 0)
- voice (INTEGER DEFAULT 0)
- sms (INTEGER DEFAULT 0)
- roaming_voice (NUMERIC(12,2) DEFAULT 0.00)
- roaming_data (NUMERIC(12,2) DEFAULT 0.00)
- roaming_sms (NUMERIC(12,2) DEFAULT 0.00)
- bill_id (FK to bill.id)
- PRIMARY KEY (contract_id, rateplan_id, starting_date)

**bill**:
- id (SERIAL PK)
- contract_id (FK to contract.id)
- billing_period_start (DATE)
- billing_period_end (DATE)
- billing_date (DATE)
- recurring_fees (NUMERIC(12,2) DEFAULT 0)
- one_time_fees (NUMERIC(12,2) DEFAULT 0)
- voice_usage (INTEGER DEFAULT 0)
- data_usage (INTEGER DEFAULT 0)
- sms_usage (INTEGER DEFAULT 0)
- ROR_charge (NUMERIC(12,2) DEFAULT 0)
- overage_charge (NUMERIC(12,2) DEFAULT 0)
- roaming_charge (NUMERIC(12,2) DEFAULT 0)
- promotional_discount (NUMERIC(12,2) DEFAULT 0)
- taxes (NUMERIC(12,2) DEFAULT 0)
- total_amount (NUMERIC(12,2) DEFAULT 0)
- status (bill_status DEFAULT 'draft')
- is_paid (BOOLEAN DEFAULT FALSE)
- UNIQUE (contract_id, billing_period_start)

**invoice**:
- id (SERIAL PK)
- bill_id (FK to bill.id UNIQUE)
- pdf_path (TEXT)
- generation_date (TIMESTAMP DEFAULT NOW())

**cdr**:
- id (SERIAL PK)
- file_id (FK to file.id)
- dial_a (VARCHAR(20)) - Calling party MSISDN
- dial_b (VARCHAR(20)) - Called party MSISDN
- start_time (TIMESTAMP)
- duration (INTEGER DEFAULT 0)
- service_id (FK to service_package.id)
- hplmn (VARCHAR(20)) - Home PLMN
- vplmn (VARCHAR(20)) - Visited PLMN
- external_charges (NUMERIC(12,2) DEFAULT 0)
- rated_flag (BOOLEAN DEFAULT FALSE)
- rated_service_id (INTEGER)

**file**:
- id (SERIAL PK)
- parsed_flag (BOOLEAN DEFAULT FALSE)
- file_path (TEXT)

**contract_addon**:
- id (SERIAL PK)
- contract_id (FK to contract.id)
- service_package_id (FK to service_package.id)
- purchased_date (DATE DEFAULT CURRENT_DATE)
- expiry_date (DATE)
- is_active (BOOLEAN DEFAULT TRUE)
- price_paid (NUMERIC(12,2) DEFAULT 0)

---

## 6. Integration Design (Extended)

### 6.4 Database Functions

Key stored functions for business logic:

#### Billing Functions:
- **generate_bill(contract_id, period_start)**: Aggregates usage into a bill.
- **generate_all_bills(period_start)**: Bills all active contracts.
- **get_bill(bill_id)**: Retrieves bill details.
- **mark_bill_paid(bill_id)**: Marks bill as paid.
- **pay_bill(bill_id, pdf_path)**: Pays and generates invoice.

#### Contract Management:
- **create_contract(user_id, rateplan_id, msisdn, credit_limit)**: Creates new contract.
- **change_contract_status(contract_id, status)**: Updates contract status.
- **change_contract_rateplan(contract_id, new_rateplan_id)**: Changes rateplan with proration.

#### CDR Processing:
- **insert_cdr(file_id, dial_a, dial_b, start_time, duration, ...)**: Inserts CDR record.
- **rate_cdr(cdr_id)**: Rates a CDR against contract bundles.
- **get_cdr_usage_amount(duration, service_type)**: Normalizes usage.

#### Add-ons:
- **purchase_addon(contract_id, service_package_id)**: Purchases top-up.
- **expire_addons()**: Deactivates expired add-ons.

#### Authentication:
- **login(username, password)**: Authenticates user.

#### Data Retrieval:
- **get_all_customers()**, **get_all_contracts()**, **get_all_rateplans()**, etc.: List functions.
- **get_user_contracts(user_id)**, **get_user_invoices(user_id)**: User-specific data.

### 6.5 Triggers

- **auto_initialize_consumption()**: Triggers on CDR insert to init consumption periods.
- **auto_rate_cdr()**: Triggers on CDR insert to auto-rate.
- **notify_bill_generation()**: Sends PostgreSQL NOTIFY on bill creation.

---

## 9. Testing Strategy (Enhanced)

### 9.5 Database Testing

- Unit tests for stored functions using pgTAP or similar.
- Integration tests for trigger behavior.
- Data validation tests for schema constraints.

### 9.6 Function Testing Examples

- Test rate_cdr() with sample CDRs and verify consumption updates.
- Test generate_bill() for accurate calculations.
- Test purchase_addon() for credit deduction and quota stacking.

---

## 10. Deployment and Operations (Extended)

### 10.5 Database Operations

- Use whole_billing_updated.sql for initial setup.
- Run initialize_consumption_period() monthly for billing cycles.
- Monitor triggers for automatic processing.

---

## 12. Appendices (Expanded)

### 12.1 Code Snippets

#### Main.java Startup:
```java
Tomcat tomcat = new Tomcat();
tomcat.setPort(8080);
// ... resource mapping and health check
```

#### DB Connection:
```java
HikariConfig config = new HikariConfig();
config.setJdbcUrl(System.getenv("DB_URL"));
// ... pool settings
```

#### CDR Rating Function (PL/pgSQL):
```sql
CREATE OR REPLACE FUNCTION rate_cdr(p_cdr_id INTEGER)
RETURNS void AS $$
DECLARE
    v_cdr RECORD;
    v_contract RECORD;
    v_service_type VARCHAR;
    -- ... logic for bundle consumption
BEGIN
    -- Rate logic implementation
END;
$$ LANGUAGE plpgsql;
```

### 12.2 Configuration Files

#### pom.xml (Maven Dependencies):
```xml
<dependency>
    <groupId>com.zaxxer</groupId>
    <artifactId>HikariCP</artifactId>
    <version>6.2.1</version>
</dependency>
<!-- JasperReports, Tomcat Embed, etc. -->
```

#### .env Example:
```
DB_URL=jdbc:postgresql://localhost:5432/billing
DB_USER=billing_user
DB_PASSWORD=secure_pass
CDR_INPUT_PATH=./input
CDR_PROCESSED_PATH=./processed
```

### 12.4 Database Triggers

From backups/local_db_dump.sql:
- **auto_initialize_consumption()**: ON INSERT TO cdr, calls initialize_consumption_period().
- **auto_rate_cdr()**: ON INSERT TO cdr, calls rate_cdr() if service_id set.
- **notify_bill_generation()**: ON INSERT TO bill, sends pg_notify().

---

*This updated TDD incorporates real database schemas, functions, and triggers from whole_billing_updated.sql and backups/local_db_dump.sql for comprehensive coverage.*

---

## 13. Comprehensive Audit & Hardening Details

This section documents every technical hurdle faced during the integration of Java 21, Tomcat 11, Nginx, and Podman, along with their solutions.

### 13.1 Startup Crash: The Permission Paradox
- **Where**: `Dockerfile` and `com.billing.Main.java`
- **Why**: Modern security requires running containers as non-root user (`javauser`). Tomcat defaults to writing work files in execution directory. Since `/app` was owned by root, the app crashed with `AccessDeniedException` before first log line.
- **Fix**:
  1. **Dockerfile**: Added `chown` to give app ownership of its folder.
  2. **Main.java**: Programmatically moved Tomcat `baseDir` to `/tmp` following "ReadOnly Filesystem" best practice.

### 13.2 The 404 Ghost: Shaded JAR Annotation Blindness
- **Where**: `com.billing.Main.java`
- **Why**: In a "Shaded JAR", classes aren't in a folder; they're inside a ZIP. Tomcat's default scanner looks for `WEB-INF/classes` folder which doesn't exist in JAR. This caused all `@WebServlet` and `@WebFilter` annotations to be ignored.
- **Fix**: Implemented **Dynamic JAR Detection**. Code now detects its own JAR filename at runtime and maps it as `JarResourceSet`. This tells Tomcat: *"Everything inside this JAR should be treated as a web class."*

### 13.3 The Empty Page: Frontend/Backend Desynchronization
- **Where**: `deploy/nginx.conf` and `Dockerfile`
- **Why**: SvelteKit/Vite uses unique hashes for filenames (e.g., `app.A1B2.js`). Nginx was trying to serve these from Host's disk, but HTML was served by Container. Because Host and Container builds happened at different times, hashes didn't match. Nginx gave 404 for JS, page stayed empty.
- **Fix**: Disabled Nginx's filesystem `alias`. Now, Nginx proxies everything to Tomcat. Since Tomcat and JS files are in same container, they're always perfectly in sync.

### 13.4 The SPA Router: Path Normalization
- **Where**: `com.billing.filter.AppFilter.java`
- **Why**: SvelteKit handles navigation in browser. If user refreshes `http://billing.local/dashboard`, Tomcat thinks `/dashboard` is a real folder and returns 404.
- **Fix**: Updated filter to recognize "Deep Links" and forward them to `index.html`. Also fixed JAR-specific bug where `getRealPath()` returned `null`, breaking dynamic CSS injection.

### 13.5 Security Hardening: The Secrets Leak
- **Where**: `com.billing.db.DB.java` and `src/main/resources/db.properties`
- **Why**: Storing passwords in `db.properties` is dangerous because that file is bundled into JAR. If JAR is shared, database is exposed.
- **Fix**: Scrubbed properties file and refactored `DB.java` to use **Environment Variable Priority**. App now looks for `DB_URL` and `DB_PASSWORD` in secure container environment first.

### 13.6 Branding: Centralized Configuration
- **Where**: `src/main/resources/config.properties` and `CustomerProfileServlet.java`
- **Why**: Branding (Phone, Web, Email) was hardcoded in multiple places. Changing company website required full rebuild.
- **Fix**: Created central `config.properties`. Servlet now loads this at startup and injects values into JasperReport as parameters.

### 13.7 Performance: JasperReport Compilation Lag
- **Where**: `com.billing.servlet.CustomerProfileServlet.java`
- **Why**: Every PDF download request was re-compiling `.jrxml` file from scratch, adding 2-second delay and heavy CPU load.
- **Fix**: Implemented **In-Memory Report Caching**. Report is compiled once and binary object is reused for all subsequent downloads, making them nearly instant.

### 13.8 Jasper 7: The Fragmented Font Fix
- **Where**: `pom.xml` (Maven Shade Plugin)
- **Why**: JasperReports 7 splits configuration into multiple JARs. When shading into Fat JAR, these configuration files were overwriting each other, causing fonts and PDF functions to vanish in cloud.
- **Fix**: Implemented **`AppendingTransformer`**. This tells Maven: *"Instead of choosing one file, stitch them all together."* This ensures all fonts and Jasper functions are available in final production JAR.

### 13.9 Production Observability: The Health Guard
- **Where**: `Main.java` and `AppFilter.java`
- **Why**: Cloud platforms like Railway need to know if app is "alive" before sending traffic. Also, app needs to clean up database connections when stopping.
- **Fix**:
  1. **Health Endpoint**: Created JSON `/health` servlet that verifies DB connectivity.
  2. **Graceful Shutdown**: Added `ShutdownHook` to Tomcat to close HikariCP pool cleanly, preventing "Zombie" database connections.
  3. **Routing Bypass**: Updated `AppFilter` to whitelist `/health` so it bypasses SPA routing.

### 13.10 Environment Parity: The Golden Image
- **Where**: `Dockerfile`, `.dockerignore`, and `docker-compose.yml`
- **Why**: Production images should be as small as possible and never run as root. Also, local builds shouldn't leak "garbage" files into image.
- **Fix**:
  1. **Slim JRE**: Switched to `eclipse-temurin:21-jre-jammy` (saving 150MB).
  2. **Non-Root User**: Created `javauser` to run app, following "Least Privilege" security principle.
  3. **Local-First Build**: Updated `Dockerfile` to use local `target/` artifacts, bypassing container-specific network DNS issues during Node/Maven downloads.

### 13.11 Safety Net: Defensive Configuration
- **Where**: `com.billing.db.DB.java`
- **Why**: Missing environment variables in IntelliJ or Railway lead to cryptic "Driver not found" errors that waste developer time.
- **Fix**: Implemented **Placeholder Awareness**. App now checks for literal string `REPLACE_WITH_ENV_VAR`. If found, it stops immediately and prints clean, human-readable "How-To Fix" guide in console.

### 13.12 JasperReports 7 Automation: Jackson Schema Bug
- **Where**: `BillAutomationWorker.java`
- **Why**: JasperReports 7 changed how it parses XML templates. Traditional `JasperCompileManager` failed inside containerized environment because it couldn't resolve new XML schemas at runtime.
- **Fix**: Refactored loading logic to use **`JacksonUtil.loadXml`**. This modern Jackson-based approach bypasses old XML validation bottlenecks and successfully loads `.jrxml` templates directly from JAR.

### 13.13 Container Networking: The Localhost Barrier
- **Where**: `docker-compose.yml`
- **Why**: Inside container, `localhost` refers to container itself, not host computer. This meant app couldn't find PostgreSQL database running on machine.
- **Fix**: Enabled **`network_mode: host`**. This allows container to share host's networking stack, giving it direct access to database on `localhost:5432` without needing complicated bridge configurations.

### 13.14 Frontend Logic: Missing State & Syntax
- **Where**: `admin/contracts/+page.svelte`
- **Why**: "Provision New Line" feature had searchable customer dropdown that was empty because `filteredCustomers` variable was used in template but never defined in script. Additionally, invalid placement of `{@const}` tags caused build failures.
- **Fix**:
  1. **Derived State**: Implemented Svelte 5 `$derived()` to calculate filtered search results in real-time.
  2. **Syntax Hardening**: Corrected placement of `{@const}` tags to ensure they're immediate children of logic blocks, resolving SvelteKit build crash.

### 13.15 Billing Automation: Database Conflict Resolution
- **Where**: `whole_billing_updated.sql` and `BillAutomationWorker.java`
- **Why**: Automated bill generation was failing due to duplicate key violations when re-running bill for same period.
- **Fix**:
  1. **Unique Constraint**: Added `UNIQUE` constraint to `invoice.bill_id`.
  2. **Atomic Upsert**: Implemented `ON CONFLICT (bill_id) DO UPDATE` in automation worker. This ensures billing cycle is idempotent—if you re-run it, system updates existing invoice instead of crashing.

---

## 14. Security Hardening Audit Summary

| Component | Status | Fix Description | Section |
| :--- | :--- | :--- | :--- |
| **Identity** | ✅ Hardened | Running as non-root `javauser` to prevent container escape. | 13.1, 13.10 |
| **Secrets** | ✅ Secured | Defensive "Safety Net" check prevents boot-up with leaked secrets. | 13.5, 13.11 |
| **Observability**| ✅ Production | Integrated `/health` endpoint for automated Cloud monitoring. | 13.9 |
| **Build** | ✅ Enterprise | All LICENSE/NOTICE and Jasper properties merged for Zero-Warning build. | 13.8 |
| **Reporting** | ✅ Optimized | JIT Caching + Fragmented Font merging (Jasper 7 fix). | 13.7, 13.12 |
| **Assets** | ✅ Synchronized | Atomic UI/API updates via container-native asset serving. | 13.3 |
| **Routing** | ✅ Fixed | SPA path normalization for deep links and JAR resources. | 13.2, 13.4 |
| **Networking** | ✅ Configured | Host network mode for container-to-host database access. | 13.13 |
| **Frontend** | ✅ Hardened | Missing state variables and SvelteKit syntax fixes. | 13.14 |
| **Billing** | ✅ Idempotent | Atomic upsert for bill generation, unique constraints. | 13.15 |

---

*This comprehensive audit ensures the FMRZ Telecom Billing System is production-ready with all known technical hurdles resolved.*
