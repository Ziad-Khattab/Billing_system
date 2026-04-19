# 🏁 5-Minute Setup Guide (Teammate Edition)

Follow these steps to get the full project running on your local machine.

## 1. Prerequisites
Ensure you have the following installed:
- **Java 21** (`java -version`)
- **Node.js 20+** (`node -v`)
- **PostgreSQL 14+**
- **Apache Tomcat 11**

## 2. Database Setup
Run these commands to create the DB and load the initial data:
```bash
# 1. Create the database
createdb billing_db

# 2. Load the core telecom schema and dummy customers
psql -d billing_db -f Billing.sql

# 3. Load the login/auth schema and admin account
psql -d billing_db -f docs/reference/web_schema.sql
```

## 3. Configuration
Copy the example properties file and ensure your credentials are correct:
```bash
cp src/main/resources/db.properties.example src/main/resources/db.properties
# Edit src/main/resources/db.properties if you use a password for your local Postgres
```

## 4. Build & Deploy Backend
Compile the Java code and deploy it to your local Tomcat:
```bash
# Build the WAR file
./mvnw clean package -DskipTests

# Deploy to Tomcat (Replace PATH_TO_TOMCAT with your folder)
cp target/Billing_System-1.0-SNAPSHOT.war [PATH_TO_TOMCAT]/webapps/ROOT.war

# Start Tomcat
[PATH_TO_TOMCAT]/bin/startup.sh
```

## 5. Start Frontend
Run the SvelteKit development server:
```bash
cd frontend
npm install
npm run dev
```

## 6. Verify
1. Open your browser to `http://localhost:5173`.
2. Go to the Login page.
3. Login with **admin / admin**.
4. If you see the dashboard, everything is working!

---

### Troubleshooting
- **404 error on login?** Check if `ROOT.war` is correctly deployed and Tomcat is running.
- **Connection refused?** Ensure PostgreSQL is running and `db.properties` has the right credentials.
- **Vite errors?** Run `npm install` again in the `frontend` folder.
