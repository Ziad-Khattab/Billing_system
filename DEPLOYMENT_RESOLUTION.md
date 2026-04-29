# Deployment Resolution & Hardening Audit

This document provides an exhaustive technical audit of every technical hurdle faced during deployment - both locally with Podman/Docker and on Railway cloud platform. It explains the **Why, Where, and How** for each issue encountered.

---

## 🚂 Railway Deployment Issues

### R1. Health Check Detection
- **Where**: `Main.java`, Railway dashboard
- **Problem**: Railway needs to know if the app is "alive" before sending traffic. Without a proper health endpoint, Railway would fail deployment or mark the service as unhealthy.
- **Resolution**:
  - Created `/health` endpoint that returns JSON with database connectivity check
  - Updated `AppFilter` to whitelist `/health` so it bypasses SPA routing
  - Added Dockerfile health check:
    ```dockerfile
    HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
      CMD curl -f http://localhost:8080/health || exit 1
    ```

### R2. Environment Variable Loading
- **Where**: `DB.java`
- **Problem**: Missing environment variables on Railway cause cryptic "Driver not found" errors that waste debugging time.
- **Resolution**: Implemented **Environment Variable Priority** with defensive checks:
  ```java
  String dbUrl = System.getenv("DB_URL");
  if (dbUrl == null || dbUrl.contains("REPLACE_WITH_ENV_VAR")) {
      // Print helpful setup guide
  }
  ```

### R3. Database Connection Pooling
- **Where**: `docker-compose.yml`, Railway environment
- **Problem**: In Railway's containerized environment, HikariCP needs proper configuration. Connection timeouts and cold starts on NeonDB can cause issues.
- **Resolution**: Configured HikariCP with:
  ```java
  config.setMaximumPoolSize(10);
  config.setMinimumIdle(2);
  config.setConnectionTimeout(30000);
  config.setIdleTimeout(600000);
  config.setMaxLifetime(1800000);
  ```

### R4. NeonDB Cold Start
- **Where**: NeonDB (cloud PostgreSQL)
- **Problem**: NeonDB has "cold start" behavior - the database can pause after inactivity, causing initial connection delays.
- **Resolution**: Added connection retry logic and increased timeout values. The `/health` endpoint handles this gracefully.

### R5. Railway Build Timeout
- **Problem**: Default build timeout may be exceeded during Maven build.
- **Resolution**: 
  - Multi-stage Dockerfile optimization
  - Dependency caching in build stage
  - Use `mvn dependency:go-offline` for caching

---

## 🐳 Local Podman/Docker Issues

### L1. Startup Crash: The Permission Paradox
- **Where**: `Dockerfile` and `Main.java`
- **Problem**: Modern security requires running containers as non-root user (`javauser`). Tomcat defaults to writing work files in execution directory. Since `/app` was owned by root, app crashed with `AccessDeniedException`.
- **Resolution**:
  1. Dockerfile: Added `chown` to give app ownership
  2. Main.java: Moved Tomcat `baseDir` to `/tmp`

### L2. The 404 Ghost: Shaded JAR Annotation Blindness
- **Where**: `Main.java`
- **Problem**: In a "Shaded JAR", classes are inside a ZIP, not a folder. Tomcat looks for `WEB-INF/classes` which doesn't exist, causing `@WebServlet` annotations to be ignored.
- **Resolution**: Implemented **Dynamic JAR Detection**:
  ```java
  // Detect own JAR filename and map as JarResourceSet
  ```

### L3. The Empty Page: Frontend/Backend Desync
- **Where**: `nginx.conf` and `Dockerfile`
- **Problem**: SvelteKit/Vite uses unique hashes (e.g., `app.A1B2.js`). Nginx served JS from host disk, but HTML from container - hashes didn't match.
- **Resolution**: Disabled Nginx filesystem alias, now proxies everything to Tomcat.

### L4. SPA Router: Path Normalization
- **Where**: `AppFilter.java`
- **Problem**: Refreshing `/dashboard` returned 404 because Tomcat thought it was a real folder.
- **Resolution**: Updated filter to recognize deep links and forward to `index.html`.

### L5. Security: The Secrets Leak
- **Where**: `DB.java` and `db.properties`
- **Problem**: Storing passwords in bundled properties file exposes database credentials.
- **Resolution**: 
  - Removed credentials from properties
  - Use Environment Variable Priority

### L6. Branding: Centralized Configuration
- **Where**: `config.properties`
- **Problem**: Branding hardcoded in multiple places.
- **Resolution**: Created central `config.properties` loaded at startup.

### L7. JasperReport Compilation Lag
- **Where**: `CustomerProfileServlet.java`
- **Problem**: Every PDF download re-compiled `.jrxml`, adding delay.
- **Resolution**: Implemented **In-Memory Report Caching**.

### L8. Jasper 7: The Fragmented Font Fix
- **Where**: `pom.xml` (Maven Shade)
- **Problem**: JasperReports 7 splits config into multiple JARs, fonts overwrote each other.
- **Resolution**: Implemented **`AppendingTransformer`** in Maven Shade.

### L9. Environment Parity: The Golden Image
- **Where**: `Dockerfile`, `docker-compose.yml`
- **Problem**: Production images should be small and never run as root.
- **Resolution**:
  1. Switched to `eclipse-temurin:21-jre-jammy`
  2. Created non-root `javauser`
  3. Local-first build using `target/` artifacts

### L10. Container Networking: Localhost Barrier
- **Where**: `docker-compose.yml`
- **Problem**: Container `localhost` != host `localhost`.
- **Resolution**: Enabled `network_mode: host`.

---

## ⚙️ Database & SQL Issues

### D1. Billing Automation: Database Conflict
- **Where**: `BillAutomationWorker.java`
- **Problem**: Re-running bill generation caused duplicate key errors.
- **Resolution**:
  1. Added UNIQUE constraint to `invoice.bill_id`
  2. Implemented `ON CONFLICT (bill_id) DO UPDATE`

### D2. CDR Auto-Rating Trigger
- **Where**: `whole_billing_updated.sql`
- **Problem**: CDRs needed automatic rating on insert.
- **Resolution**: Created `auto_rate_cdr()` trigger.

### D3. Consumption Period Initialization
- **Where**: `whole_billing_updated.sql`
- **Problem**: First CDR of month needed consumption rows created.
- **Resolution**: Created `auto_initialize_consumption()` trigger.

---

## 🎨 Frontend Issues

### F1. Missing State & Syntax
- **Where**: `admin/contracts/+page.svelte`
- **Problem**: Searchable dropdown empty because variable never defined. Invalid `{@const}` placement caused build failures.
- **Resolution**:
  1. Implemented Svelte 5 `$derived()`
  2. Corrected `{@const}` syntax

---

## 📋 Complete Resolution Checklist

| # | Component | Status | Resolution |
|---|----------|--------|------------|
| R1 | Railway Health | ✅ | `/health` endpoint + Dockerfile healthcheck |
| R2 | Env Variables | ✅ | Environment Variable Priority |
| R3 | Connection Pool | ✅ | HikariCP tuning |
| R4 | NeonDB Cold Start | ✅ | Retry logic + timeouts |
| R5 | Build Timeout | ✅ | Multi-stage Dockerfile |
| L1 | Permission Paradox | ✅ | Non-root user + chown |
| L2 | JAR Annotations | ✅ | Dynamic JAR Detection |
| L3 | Frontend Sync | ✅ | Proxy to Tomcat |
| L4 | SPA Routing | ✅ | Deep link filter |
| L5 | Secrets Leak | ✅ | ENV variable priority |
| L6 | Branding | ✅ | config.properties |
| L7 | Jasper Caching | ✅ | In-memory cache |
| L8 | Jasper Fonts | ✅ | AppendingTransformer |
| L9 | Docker Image | ✅ | Slim JRE |
| L10 | Networking | ✅ | Host network mode |
| D1 | Bill Conflicts | ✅ | Upsert |
| D2 | CDR Auto-Rate | ✅ | Trigger |
| D3 | Consumption | ✅ | Trigger |
| F1 | Frontend State | ✅ | $derived() |

---

## 🔧 Environment Setup

### Local Development (.env)

```bash
# Copy from template
cp .env.example .env

# Edit with your credentials
DB_URL=jdbc:postgresql://localhost:5432/billing
DB_USER=your_user
DB_PASSWORD=your_password
```

### Railway Deployment

```bash
# 1. Create project at railway.app
# 2. Connect GitHub repository
# 3. Add environment variables:
#    - DB_URL (from NeonDB dashboard)
#    - DB_USER
#    - DB_PASSWORD
# 4. Deploy automatically on git push
```

### Docker Local

```bash
# Build and run
podman-compose up -d --build

# Check logs
podman-compose logs -f
```

---

## 📌 Final Notes

The system is now **fully hardened** for both local and cloud deployment:

- ✅ No hardcoded credentials
- ✅ Non-root container execution
- ✅ Health check endpoints
- ✅ Proper connection pooling
- ✅ SPA routing support
- ✅ Idempotent billing operations

This system is a self-contained "Engine" ready for any Linux server or cloud platform.

---

*Document Version: 2.0*
*Last Updated: April 30, 2026*
*FMRZ Telecom Group*