# 🚀 FMRZ Startup & Testing Guide

## Quick Start (2 terminals)

### Terminal 1 — Backend (Java Servlets on Tomcat)

```bash
# From project root
cd Billing_system

# 1. Build the WAR file
./mvnw clean package -DskipTests

# 2. Copy WAR to Tomcat
cp target/Billing_System-1.0-SNAPSHOT.war $CATALINA_HOME/webapps/api.war
# $CATALINA_HOME is where Tomcat is installed (e.g., /opt/tomcat)

# 3. Start Tomcat
$CATALINA_HOME/bin/startup.sh

# Backend is now at: http://localhost:8080/api/
```

**IntelliJ shortcut:** Instead of steps 1-3, configure Tomcat in:
Run → Edit Configurations → + → Tomcat Server → Local → set path → Run ▶️

### Terminal 2 — Frontend (SvelteKit)

```bash
cd Billing_system/frontend

# Install dependencies (first time only)
npm install

# Start dev server
npm run dev

# Frontend is now at: http://localhost:5173/
```

---

## First-Time Database Setup

Since we merged the full enterprise rating engine from Fouad, it's best to run your database **locally** to avoid conflicts and test without latency.

### 1. Install & Start PostgreSQL (Local)
If you don't have PostgreSQL installed:
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
```

### 2. Create the Database & User
Run this to create the `fmrz_billing` database:
```bash
sudo -u postgres psql -c "CREATE USER fmrz_admin WITH PASSWORD 'fmrz123';"
sudo -u postgres psql -c "CREATE DATABASE fmrz_billing OWNER fmrz_admin;"
```

### 3. Run the Schema Scripts
Run your teammate's core engine, then our web schema on top:
```bash
# 1. Run the core rating engine (tables, PL/pgSQL functions)
psql -U fmrz_admin -d fmrz_billing -h localhost -f Billing.sql

# 2. Run the web layer (app_user table for logins)
psql -U fmrz_admin -d fmrz_billing -h localhost -f docs/reference/web_schema.sql
```

*(Note: you'll need to update your `src/main/resources/db.properties` or `DB.java` connection string to point to `jdbc:postgresql://localhost:5432/fmrz_billing` instead of Neon).*

This creates:
- The full billing rating engine (`contract_consumption`, `rate_cdr()`, etc.)
- `app_user` table (login accounts)
- Default admin account: `admin` / `admin123`

---

## Test Accounts

| Role | Username | Password | What you can access |
|------|----------|----------|-------------------|
| Admin | `admin` | `admin123` | Everything: /admin/*, /api/admin/* |
| Customer | (register one) | (your choice) | /dashboard, /api/customer/* |

---

## Testing Walkthrough

### 1. Test Public Pages (no login needed)

Open browser → http://localhost:5173/
- ✅ Landing page loads with FMRZ branding
- ✅ Click "Packages" → pricing cards show
- ✅ Click "Login" → login form shows

### 2. Test Admin Login

1. Go to http://localhost:5173/login
2. Enter: `admin` / `admin123`
3. Should redirect to `/admin`
4. Check: navbar shows "admin" badge + Dashboard/Customers/Contracts/Billing links
5. Click "Customers" → should load customer list from DB
6. Click "+ Add" → create a test customer
7. Click "Contracts" → see contracts with status badges

### 3. Test Customer Registration

1. Click "Logout" in navbar
2. Go to http://localhost:5173/register
3. Fill in: name, username, password, address
4. Submit → should redirect to `/dashboard`
5. Check: navbar shows "customer" badge + Dashboard/Invoices links
6. Dashboard shows your profile, contracts (empty initially), invoices

### 4. Test API with curl (optional, for backend verification)

```bash
# Public — no auth needed
curl http://localhost:8080/api/public/rateplans

# Login as admin
curl -c cookies.txt -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'

# Use session cookie for protected endpoints
curl -b cookies.txt http://localhost:8080/api/admin/customers

# Register a new customer
curl -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"test123","fullName":"Test User","address":"Cairo"}'

# Check who's logged in
curl -b cookies.txt http://localhost:8080/api/auth/me
```

---

## Common Issues

### "Cannot connect to server" on frontend
- Is Tomcat running? Check: `curl http://localhost:8080/api/public/rateplans`
- Is the WAR deployed? Check: `ls $CATALINA_HOME/webapps/api.war`
- CORS error? Check CorsFilter is deployed (allow-origin: localhost:5173)

### "Not authenticated" when accessing /api/admin/*
- Did you login first? Sessions use cookies — must send `credentials: 'include'`
- Using Postman? Enable "Send cookies" in settings

### "Table app_user does not exist"
- Run `docs/reference/web_schema.sql` against your Neon database first

### "Invalid username or password" for admin
- Run the INSERT from `web_schema.sql` — the bcrypt hash must match
- Or register a new user via /register and test with that

---

## Are We Using Servlets or Spring Boot?

**We are using Java Servlets (Jakarta Servlets 6.1).**

They are NOT the same thing, but they ARE related:

```
Servlets (what we use)
  ↓ built on top of
Spring MVC (adds convenience)
  ↓ auto-configured by
Spring Boot (adds zero-config magic)
```

Think of it like:
- **Servlets** = driving a manual car (you control everything)
- **Spring Boot** = driving an automatic car (easier but same engine)

### Why learn servlets first?
You understand WHAT happens under the hood. When Spring Boot auto-configures something, you know what it's actually doing. Most Spring developers don't — you will.

### Do we need two implementations?
**No.** Build with servlets now. The study guide already has a "Migration to Spring Boot" section showing the 1:1 mapping. After this project, recreating it in Spring Boot takes ~2 hours because you already understand the concepts.

---

## About Tailwind CSS

**Tailwind is free** (MIT license, no fees ever, scales infinitely).

But we're NOT using it because:
1. We already built a complete design system in vanilla CSS
2. Adding Tailwind now = rewriting every component's styles
3. Vanilla CSS teaches you the fundamentals — Tailwind is a shortcut
4. When you learn Tailwind later (1-2 hours), you'll understand WHY each utility exists

**If starting a NEW project:** Tailwind is excellent. For this project: not worth the migration cost.
