# 📱 Telecom Billing System

<p align="center">
  <a href="#">
    <img src="https://img.shields.io/badge/Version-2.0-blueviolet?style=for-the-badge&logo=version" alt="Version">
  </a>
  <a href="#">
    <img src="https://img.shields.io/badge/Java-21-ED8B00?style=for-the-badge&logo=openjdk" alt="Java">
  </a>
  <a href="#">
    <img src="https://img.shields.io/badge/SvelteKit-5.x-FF3E00?style=for-the-badge&logo=svelte" alt="SvelteKit">
  </a>
  <a href="#">
    <img src="https://img.shields.io/badge/NeonDB-Cloud-9B59B6?style=for-the-badge&logo=cloud" alt="NeonDB">
  </a>
  <a href="#">
    <img src="https://img.shields.io/badge/Status-Production%20Ready-brightgreen?style=for-the-badge" alt="Status">
  </a>
</p>

> A modular, production-ready Telecom Billing System built with Java 21 (Jakarta EE 11) backend and SvelteKit 5.x reactive frontend. Features real-time billing, CDR processing, PDF invoicing, and comprehensive admin controls.

---

## 📋 Table of Contents

- [Architecture Stack](#-architecture-stack)
- [Deployment](#-deployment)
- [Key Features](#-key-features)
- [Quick Start](#-quick-start)
- [Technical Stack](#-technical-stack)
- [Database Schema](#-database-schema)
- [API Reference](#-api-reference)
- [Security](#-security)
- [Roadmap](#-roadmap)

---

## 🏗️ Architecture Stack

```
┌────────────────────────────────────────────────────────────────┐
│                    SYSTEM ARCHITECTURE                         │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│   ┌──────────┐     ┌──────────────┐     ┌───────────┐         │
│   │ SvelteKit│ ←── │  Tomcat 11   │ ←── │  Java 21  │         │
│   │   5.x    │     │ Embedded     │     │  Backend  │         │
│   └──────────┘     └──────────────┘     └───────────┘         │
│        ↓                                        ↓              │
│   ┌──────────────────────────────────────────────────┐        │
│   │             HikariCP Connection Pool              │        │
│   └──────────────────────────────────────────────────┘        │
│        ↓                                                     │
│   ┌──────────────────────────────────────────────────┐        │
│   │                  NeonDB Cloud                     │        │
│   └──────────────────────────────────────────────────┘        │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Layer Details

| Layer | Technology | Version | Purpose |
|:------:|:----------|:--------:|:--------|
| 💻 **Backend** | Java | 21 | Core language |
| 🌐 **Framework** | Jakarta EE | 11 | Enterprise APIs |
| 🖥️ **Server** | Tomcat | 11.0.21 | Embedded servlet |
| 🗄️ **Database** | NeonDB | 3.x | Cloud PostgreSQL |
| 🔄 **Pool** | HikariCP | 6.2.1 | Connection pooling |
| 📄 **JSON** | Jackson | 2.17.0 | JSON processing |
| 📊 **Reports** | JasperReports | 7.0.1 | PDF invoices |
| 🎨 **Frontend** | SvelteKit | 5.x | Reactive UI |
| ✨ **Styling** | Tailwind CSS | 4.0.0 | Dark mode UI |

---

## 🚂 Deployment

### Railway Deployment

The app is configured for seamless deployment on **Railway** with automatic health checks and environment variable support.

```
┌─────────────────────────────────────────────────────────────────┐
│                 RAILWAY SETUP                                    │
├─────────────────────────────────────────────────────────────────┤
│  🚂 Platform          │  Railway (railway.app)                 │
│  🌐 Database         │  NeonDB (your project)                │
│  🔌 Connection       │  JDBC with SSL required                │
│  ❤️ Health Check     │  GET /health                          │
│  📦 Build            │  Docker multi-stage build             │
│  🔄 Deploy           │  Automatic on git push              │
└─────────────────────────────────────────────────────────────────┘
```

### Environment Variables

| Variable | Description | Example |
|:---------|:------------|:--------|
| `DB_URL` | NeonDB JDBC URL | `jdbc:postgresql://your-endpoint.neondb?sslmode=require` |
| `DB_USER` | Database user | (from NeonDB dashboard) |
| `DB_PASSWORD` | Database password | (from NeonDB dashboard) |
| `CDR_INPUT_PATH` | Input directory | `/app/input` |
| `CDR_PROCESSED_PATH` | Processed directory | `/app/processed` |

### Railway Health Check

```bash
# Health endpoint (used for deployment detection)
GET https://your-app.railway.app/health

# Response:
# {"status":"UP","timestamp":"2026-04-30T12:00:00Z"}
```

### Deploy to Railway

```bash
# 1. Install Railway CLI
npm i -g @railway/cli

# 2. Login
railway login

# 3. Init project
railway init

# 4. Set environment variables (from NeonDB dashboard)
railway variables set DB_URL="jdbc:postgresql://..."
railway variables set DB_USER="..."
railway variables set DB_PASSWORD="..."

# 5. Deploy
railway deploy

# Or connect GitHub repo for auto-deploy:
# https://railway.app/new
```

### Docker Configuration

```dockerfile
# Multi-stage build for Railway
FROM maven:3.9.6-eclipse-temurin-21 AS build
WORKDIR /build

COPY pom.xml .
RUN mvn dependency:go-offline -B

COPY . .
RUN mvn package -DskipTests -B

FROM eclipse-temurin:21-jre-jammy
WORKDIR /app

# Security: Run as non-root user
RUN addgroup --system javauser && adduser --system --ingroup javauser javauser

# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /app/input /app/processed && chown -R javauser:javauser /app

# Copy artifacts
COPY --from=build /build/target/Telecom-Billing-Engine.jar app.jar
COPY --from=build /build/target/lib ./lib
COPY --from=build /build/src/main/webapp ./webapp_static
COPY --from=build /build/src/main/resources/invoice.jrxml .
COPY --from=build /build/src/main/resources/logo.svg .
COPY --from=build /build/src/main/resources/Pictures ./Pictures

# Set ownership
RUN chown -R javauser:javauser /app

# Switch to non-root user
USER javauser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Run command
ENTRYPOINT ["java", "-Xmx1g", "-Djava.awt.headless=true", "-cp", "app.jar:lib/*", "com.billing.Main"]
```

---

## ✨ Key Features

### 👑 Admin Features

| Feature | Endpoint | Description |
|:--------|:---------|:------------|
| 📊 **Dashboard** | `/admin` | Real-time stats & metrics |
| 👥 **Customers** | `/admin/customers` | Full customer CRUD |
| 📄 **Contracts** | `/admin/contracts` | Contract management |
| 💰 **Billing** | `/admin/bills` | Bill generation & payment |
| 📈 **CDR** | `/admin/cdr` | CDR upload & viewing |
| 📦 **Packages** | `/admin/service-packages` | Service packages |
| 📵 **Rate Plans** | `/admin/rateplans` | Tariff plans |
| 🔍 **Audit** | `/admin/audit` | Missing bill detection |

### 👤 Customer Features

| Feature | Endpoint | Description |
|:--------|:---------|:------------|
| 👤 **Profile** | `/profile` | View & edit profile |
| 📱 **Contracts** | `/profile/contracts` | My contracts |
| 📄 **Invoices** | `/profile/invoices` | Invoice history |
| 📥 **Download** | `/profile/invoices/download` | PDF downloads |
| 🛒 **Add-ons** | `/customer/addons` | Purchase add-ons |
| 📝 **Register** | `/register` | Self-registration |

### ⚙️ Backend Features

| Feature | Description |
|:--------|:------------|
| 🗂️ **CDR Engine** | Java CSV parser for call records |
| 🧪 **CDR Generator** | Test data generation |
| 📄 **Jasper 7** | PDF with element-kind schema |
| 🤖 **Automation** | Server-side billing (14% tax) |
| ❤️ **Health** | Railway-compatible `/health` endpoint |

---

## 🚀 Quick Start

### Development (IDE)

```bash
# 1. Configure secrets
cp .env.example .env

# 2. Edit .env with your NeonDB credentials
# DB_URL=jdbc:postgresql://your-endpoint.neondb?sslmode=require
# DB_USER=your_username
# DB_PASSWORD=your_password

# 3. Run in IntelliJ
#    File → Project Structure → Run Configurations
#    Select Main class → Environment → .env file

# 4. Run
com.billing.Main
```

### Production (Railway)

```bash
# Option 1: Deploy via GitHub (recommended)
# 1. Push code to GitHub
# 2. Create project at railway.app
# 3. Connect GitHub repository
# 4. Add environment variables in Railway dashboard
# 5. Deploy automatically on push

# Option 2: Deploy via CLI
railway init
railway deploy
```

### Production (Local Container)

```bash
# Build the JAR
./mvnw clean package -DskipTests

# Launch with Podman/Docker
podman-compose up -d --build

# Verify health
curl http://localhost:8080/health
```

---

## 🗄️ Database Schema

### NeonDB Configuration

```
┌─────────────────────────────────────────────────────────────────┐
│                  NEONDB CONFIGURATION                            │
├─────────────────────────────────────────────────────────────────┤
│  🌐 Service          │  NeonDB Cloud                           │
│  📍 Endpoint        │  (your-project-name)                   │
│  📂 Database        │  neondb                               │
│  🔒 SSL             │  Required (sslmode=require)            │
│  🔄 Pooling         │  HikariCP with 10 connections          │
│  💾 Type            │  PostgreSQL compatible               │
└──────��─��────────────────────────────────────────────────────────┘
```

### 14 Tables

```
┌─────────────────────────────────────────────────────────────────┐
│                      CORE TABLES                                │
├─────────────────────────────────────────────────────────────────┤
│  user_account          │  Customers & administrators         │
│  rateplan            │  Tariff plans                        │
│  service_package    │  Bundled services                   │
│  rateplan_service_package │  Rateplan ↔ Package links       │
│  contract           │  Customer contracts                 │
│  contract_consumption│  Usage tracking                    │
│  ror_contract       │  Applied rates                      │
│  bill               │  Billing invoices                  │
│  invoice            │  PDF records                      │
│  cdr                │  Call detail records               │
│  file               │  CDR file tracking                │
│  rejected_cdr       │  Rejected records                 │
│  contract_addon     │  Customer add-ons                 │
│  msisdn_pool        │  Phone number pool                │
└─────────────────────────────────────────────────────────────────┘
```

### 60+ Functions

```sql
-- Core Billing
SELECT generate_bill(1, '2026-04-01');
SELECT generate_all_bills('2026-04-01');

-- Contract Management
SELECT create_contract(1, 2, '201000000001', 500);
SELECT change_contract_status(1, 'suspended');
SELECT change_contract_rateplan(1, 2);

-- Customer
SELECT login('username', 'password');
SELECT get_all_customers('search', 50, 0);

-- Add-ons
SELECT purchase_addon(1, 3);
SELECT get_contract_addons(1);
```

### 3 Triggers

| Trigger | Event | Action |
|:--------|:------|:-------|
| `trg_auto_rate_cdr` | AFTER INSERT | Auto-rate CDR |
| `trg_auto_initialize_consumption` | BEFORE INSERT | Init period |
| `trg_bill_payment` | AFTER UPDATE | Restore credit |

---

## 🔌 API Reference

### Public Endpoints

| Method | Endpoint | Description |
|:------:|:---------|:------------|
| 🟢 GET | `/health` | Health check |

### Authentication

| Method | Endpoint | Description |
|:------:|:---------|:------------|
| ⚡ POST | `/api/auth/login` | User login |
| ⚡ POST | `/api/auth/register` | New customer |
| ⚡ POST | `/api/auth/logout` | User logout |
| 🟢 GET | `/api/auth/verify` | Verify session |

### Customer

| Method | Endpoint | Description |
|:------:|:---------|:------------|
| 🟢 GET | `/api/customer/profile` | Get profile |
| 🟡 PUT | `/api/customer/profile` | Update profile |
| 🟢 GET | `/api/customer/contracts` | My contracts |
| 🟢 GET | `/api/customer/invoices` | My invoices |
| 🟢 GET | `/api/customer/invoices/download` | Download PDF |
| 🟢 GET | `/api/customer/addons` | My add-ons |
| ⚡ POST | `/api/customer/addons` | Purchase add-on |
| 🟢 GET | `/api/onboarding/available-msisdn` | Phone numbers |
| ⚡ POST | `/api/onboarding/create-contract` | New contract |

### Admin

| Method | Endpoint | Description |
|:------:|:---------|:------------|
| 🟢 GET | `/api/admin/customers` | List customers |
| ⚡ POST | `/api/admin/customers` | Create customer |
| 🟢 GET | `/api/admin/customers/*` | Get customer |
| 🟡 PUT | `/api/admin/customers/*` | Update customer |
| 🔴 DELETE | `/api/admin/customers/*` | Delete customer |
| 🟢 GET | `/api/admin/contracts` | List contracts |
| ⚡ POST | `/api/admin/contracts` | Create contract |
| 🟡 PUT | `/api/admin/contracts/*/status` | Change status |
| 🟡 PUT | `/api/admin/contracts/*/rateplan` | Change rateplan |
| 🟢 GET | `/api/admin/cdr` | List CDRs |
| ⚡ POST | `/api/admin/cdr/upload` | Upload CDR |
| ⚡ POST | `/api/admin/cdr/generate` | Generate test |
| 🟢 GET | `/api/admin/bills` | List bills |
| ⚡ POST | `/api/admin/bills/*/pay` | Pay bill |
| ⚡ POST | `/api/admin/bills/generate-all` | Generate all |
| 🟢 GET | `/api/admin/stats` | Dashboard stats |
| 🟢 GET | `/api/admin/audit/missing` | Missing bills |

---

## 🛡️ Security Audit

| Component | Status | Description |
|:---------|:------:|:------------|
| 🔐 **Identity** | ✅ | Non-root `javauser` |
| 🔒 **Secrets** | ✅ | Environment variable priority |
| 📊 **Observability** | ✅ | `/health` endpoint |
| 🔧 **Build** | ✅ | LICENSE/NOTICE merge |
| 📄 **Reporting** | ✅ | JIT caching |
| 🌐 **Assets** | ✅ | Container-native |
| 🔀 **Routing** | ✅ | SPA normalization |
| 🎨 **Frontend** | ✅ | State fixes |
| 💳 **Billing** | ✅ | Idempotent upsert |
| 🚂 **Railway** | ✅ | Auto-deploy ready |

---

## 🗺️ Roadmap

### Phase 3: Advanced Auditability

```
┌─────────────────────────────────────────────────────────────┐
│                  CARRIER-GRADE FEATURES                    │
├─────────────────────────────────────────────────────────────┤
│  cdr_rating_detail    │  Per-bundle consumption audit    │
│  Multi-Bucket       │  Split across rating events  │
│  Itemized Logs      │  Millisecond-accurate trail│
│  Dual Rating       │  Wholesale & retail rates │
└─────────────────────────────────────────────────────────────┘
```

---

<div align="center">

### 📱 FMRZ Telecom Group

**Version 2.0** | **April 2026** | **Production Ready** 🏎️🛡️🚀

</div>