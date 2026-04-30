# --- STAGE 1: Build the Application (Maven Builder) ---
FROM maven:3.9.6-eclipse-temurin-21 AS build
WORKDIR /build

# 1. Copy pom.xml and download dependencies (for caching)
COPY pom.xml .
RUN mvn dependency:go-offline -B

# 2. Copy frontend manifests to cache node/npm installation
COPY frontend/package*.json ./frontend/
# We trigger a partial build that only handles the frontend setup
RUN mvn generate-resources -DskipTests -B || true

# 3. Copy source code and build
COPY . .
RUN mvn package -DskipTests -B

# --- STAGE 2: Run the Application (JRE Runtime) ---
FROM eclipse-temurin:21-jre-jammy
WORKDIR /app

# 1. Create a non-root user for security
RUN addgroup --system javauser && adduser --system --ingroup javauser javauser

# 2. Install curl for healthchecks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# 3. Create required directories for CDR processing
RUN mkdir -p /app/input /app/processed && chown -R javauser:javauser /app/input /app/processed

# 4. Copy the Thin JAR and the lib directory with all dependencies
COPY --from=build /build/target/Telecom-Billing-Engine.jar app.jar
COPY --from=build /build/target/lib ./lib

# 5. Copy required resources for Jasper and UI
COPY --from=build /build/src/main/webapp ./webapp_static
COPY --from=build /build/src/main/resources/invoice.jrxml .
COPY --from=build /build/src/main/resources/logo.svg .
COPY --from=build /build/src/main/resources/Pictures ./Pictures

# 6. Set ownership to the non-root user
RUN chown -R javauser:javauser /app

# 7. Switch to the non-root user
USER javauser

# 8. Expose the application port
EXPOSE 8080

# 9. Run the application with a wildcard classpath
ENTRYPOINT ["java", "-Xmx1g", "-Djava.awt.headless=true", "-cp", "app.jar:lib/*", "com.billing.Main"]
