# 🚀 FMRZ Telecom Billing System

A high-performance, SOTA-designed telecom billing and customer management platform.

## 📖 Documentation
All technical documentation, deployment guides, and architectural notes have been consolidated into the **[Ultimate Project Guide](ULTIMATE_GUIDE.md)**. 

Please refer to that file for:
-   **Architecture**: Details on the Generic DB Helper and SvelteKit integration.
-   **Quick Start**: Commands to build and run the platform.
-   **API Specs**: REST endpoint documentation.
-   **Schema**: Database table descriptions.

## ⚡ Quick Start
To build and run the full stack:
```bash
cd frontend && npm install && npm run build && cd ..
./mvnw clean package cargo:run
```

## 🛠️ Tech Stack
-   **Java 21** & **Jakarta EE** (Tomcat 11)
-   **SvelteKit 5** (Runes)
-   **PostgreSQL** (Neon DB)
-   **HikariCP** Connection Pooling

---
© 2026 FMRZ Telecom Billing — ITI Project