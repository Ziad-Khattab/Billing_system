# Billing System — Revised Implementation Plan

## What Changed

Previous plan: admin-only system. **Now**: three-zone app (public + customer + admin).

| Zone | Auth | Who | Purpose |
|------|------|-----|---------|
| **Public** | None | Anyone | Browse packages, pricing, register |
| **Customer** | Login (role=customer) | Registered customers | View profile, invoices, choose package |
| **Admin** | Login (role=admin) | Operators | Full CRUD, billing, manage customers |

---

## Database — No New Tables

Existing tables, one column added:

```sql
-- app_user: ALL logins (admin + customer)
-- Already planned. role = 'admin' | 'customer'
CREATE TABLE app_user (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(50)  NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name     VARCHAR(255) NOT NULL,
    role          VARCHAR(20)  NOT NULL DEFAULT 'customer', -- changed default
    created_at    TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- customer: profile data. Linked to app_user when customer has an account.
-- ADD ONE COLUMN to existing table:
ALTER TABLE customer ADD COLUMN user_id INTEGER REFERENCES app_user(id) UNIQUE;
```

**Flows:**
- Customer registers → create `app_user` (role=customer) + `customer` record → link via `user_id`
- Admin creates customer via panel → create `customer` only (user_id=NULL, no login)
- Admin creates customer with account → create both, link them

---

## Architecture

```
Browser
  │
  ├─ Public pages (/, /packages)     → No auth needed
  ├─ Customer pages (/dashboard)     → Customer login required
  └─ Admin pages (/admin/*)          → Admin login required
  │
  ▼
SvelteKit :5173
  │ server-side fetch
  ▼
Java Servlets :8080
  ├─ /api/public/*      → No auth (read-only)
  ├─ /api/customer/*    → Customer or Admin session
  ├─ /api/admin/*       → Admin session only
  └─ /api/auth/*        → Login/Register/Logout
  │
  ▼
Neon PostgreSQL (PgBouncer)
```

---

## Phase 0 — Setup (30 min) — No changes from before

- Git upstream remote
- Update `pom.xml` (Gson, jBCrypt, OpenPDF, Java 21)
- `.gitignore` ✅ already done

---

## Phase 1 — Database Layer (2.5 hrs)

### [MODIFY] DB.java
Make thread-safe: new connection per call. **Don't touch teammate's file** — create a wrapper if needed, or flag for team discussion.

### [NEW] `db.properties` + `db.properties.example`

### [MODIFY] Billing.sql — Add app_user table + customer.user_id column

### [NEW] Models (8 files)
Customer, RatePlan, ServicePackage, Contract, Bill, Invoice, AppUser, CDR

### [NEW] DAOs (7 files)

| DAO | Key methods |
|-----|-------------|
| `UserDAO` | `findByUsername()`, `create()`, `findById()` |
| `CustomerDAO` | `findAll()`, `findById()`, `findByUserId()`, `search()`, `create()`, `update()` |
| `RatePlanDAO` | `findAll()`, `findById()`, `create()` |
| `ServicePackageDAO` | `findAll()`, `findByRateplanId()`, `create()` |
| `ContractDAO` | `findAll()`, `findById()`, `findByCustomerId()`, `create()` |
| `BillDAO` | `findByContractId()`, `findById()` |
| `InvoiceDAO` | `findById()`, `findByCustomerId()`, `create()` |

---

## Phase 2 — Auth System (2 hrs)

### [NEW] AuthFilter.java — Three-zone logic

```java
String path = req.getRequestURI();

if (path.startsWith("/api/public") || path.startsWith("/api/auth")) {
    chain.doFilter(req, res);  // no auth needed
} else if (path.startsWith("/api/admin")) {
    // require admin role
} else if (path.startsWith("/api/customer")) {
    // require customer OR admin role
}
```

### [NEW] AuthServlet.java — `/api/auth/*`

| Endpoint | Description |
|----------|-------------|
| `POST /api/auth/login` | Login (admin or customer) |
| `POST /api/auth/register` | Customer self-registration (creates app_user + customer) |
| `POST /api/auth/logout` | Destroy session |
| `GET /api/auth/me` | Current user info |

### [NEW] CorsFilter.java — Same as before

---

## Phase 3 — API Servlets (4 hrs)

### Public Endpoints (no auth)

| Servlet | Endpoints |
|---------|-----------|
| `PublicServlet` | `GET /api/public/rateplans` — list plans with prices |
| | `GET /api/public/rateplans/{id}` — plan detail with service packages |
| | `GET /api/public/service-packages` — list all packages |

### Customer Endpoints (customer or admin auth)

| Servlet | Endpoints |
|---------|-----------|
| `CustomerProfileServlet` | `GET /api/customer/profile` — own profile |
| | `PUT /api/customer/profile` — update own profile |
| | `GET /api/customer/invoices` — own invoices |
| | `GET /api/customer/contracts` — own contracts |
| | `POST /api/customer/choose-plan` — select a rate plan |

### Admin Endpoints (admin auth only)

| Servlet | Endpoints |
|---------|-----------|
| `AdminCustomerServlet` | Full CRUD on `/api/admin/customers/*` |
| `AdminRatePlanServlet` | Full CRUD on `/api/admin/rateplans/*` |
| `AdminServicePkgServlet` | Full CRUD on `/api/admin/service-packages/*` |
| `AdminContractServlet` | CRUD + assign recurring/one-time on `/api/admin/contracts/*` |
| `AdminBillServlet` | `GET /api/admin/bills/*` |
| `AdminInvoiceServlet` | CRUD + PDF on `/api/admin/invoices/*` |
| `AdminProfileServlet` | Composite rateplan+packages view on `/api/admin/profiles/*` |

### [NEW] BaseServlet.java — Same helpers as before

---

## Phase 4 — PDF Invoice (2 hrs)

### [NEW] InvoicePDFGenerator.java

PDF content (from requirements):
- **FMRZ** (company name) header
- Customer data (name, address, MSISDN)
- Profile/rateplan name
- Services breakdown (voice, SMS, data)
- Calculations: recurring + one-time + usage
- Tax: 10% on total
- Invoice date, number

---

## Phase 5 — SvelteKit Frontend (7 hrs)

### Route Structure

```
src/routes/
├── +layout.svelte                # Detects role → shows correct nav
├── +page.svelte                  # Public landing page (hero, features)
├── packages/
│   └── +page.svelte              # Public: browse plans & prices
├── login/
│   └── +page.svelte              # Shared login (admin + customer)
├── register/
│   └── +page.svelte              # Customer registration
├── dashboard/
│   ├── +page.svelte              # Customer dashboard (profile summary)
│   ├── profile/
│   │   └── +page.svelte          # Customer: edit profile
│   ├── invoices/
│   │   └── +page.svelte          # Customer: view own invoices
│   └── contracts/
│       └── +page.svelte          # Customer: view own contracts
├── admin/
│   ├── +page.svelte              # Admin dashboard (stats)
│   ├── customers/
│   │   ├── +page.svelte          # Admin: manage customers
│   │   ├── new/+page.svelte
│   │   └── [id]/+page.svelte
│   ├── profiles/
│   │   ├── +page.svelte          # Admin: manage profiles
│   │   └── new/+page.svelte
│   ├── services/
│   │   ├── +page.svelte
│   │   └── new/+page.svelte
│   ├── contracts/
│   │   ├── +page.svelte
│   │   └── [id]/+page.svelte
│   └── billing/
│       └── +page.svelte          # Admin: bills + invoices + PDF
```

### Layout Logic (simplified)

```svelte
<!-- +layout.svelte -->
{#if !user}
    <!-- Public nav: Home, Packages, Login, Register -->
{:else if user.role === 'customer'}
    <!-- Customer nav: Dashboard, Profile, Invoices, Logout -->
{:else if user.role === 'admin'}
    <!-- Admin nav: Dashboard, Customers, Profiles, Contracts, Billing, Logout -->
{/if}
```

One layout, one login page, role determines what you see. No separate apps.

### Page Descriptions

| Page | What it shows |
|------|--------------|
| **Landing** `/` | Hero banner (e& branded), feature highlights, CTA to browse packages |
| **Packages** `/packages` | Card grid: each rateplan with price, included services, "Choose" button |
| **Login** `/login` | Centered card, username/password, routes to correct dashboard |
| **Register** `/register` | Name, address, birthdate, username, password → creates account |
| **Customer Dashboard** `/dashboard` | Profile card, active contracts, recent invoices |
| **Customer Profile** `/dashboard/profile` | Edit name, address, view MSISDN |
| **Customer Invoices** `/dashboard/invoices` | Table of invoices, download PDF |
| **Admin Dashboard** `/admin` | Stats cards: total customers, contracts, revenue |
| **Admin pages** `/admin/*` | Same as original plan — full CRUD |

---

## Verification Plan

**Backend**: `./mvnw clean package` + curl tests per zone
**Frontend**: `npm run dev` + `npm run build`
**Integration**:
1. Public: Browse packages without login
2. Register as customer → login → see profile → view invoices
3. Login as admin → create customer → create profile → assign contract → generate invoice
4. Customer downloads PDF invoice
