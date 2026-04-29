# --- STAGE 1: Build the Application (Maven Builder) ---
FROM maven:3.9.6-eclipse-temurin-21 AS build
WORKDIR /build

# 1. Copy pom.xml and download dependencies (for caching)
COPY pom.xml .
RUN mvn dependency:go-offline -B

# 2. Copy source code and build the Fat JAR
COPY . .
RUN mvn clean package -DskipTests

# --- STAGE 2: Run the Application (JRE Runtime) ---
FROM eclipse-temurin:21-jre-jammy
WORKDIR /app

# 1. Create a non-root user for security
RUN addgroup --system javauser && adduser --system --ingroup javauser javauser

# 2. Install curl for healthchecks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# 3. Copy only the Fat JAR from the build stage
COPY --from=build /build/target/Telecom-Billing-Engine.jar app.jar

# 4. Copy static resources needed at runtime
COPY src/main/webapp ./webapp_static
COPY src/main/resources/invoice.jrxml .
COPY src/main/resources/logo.svg .
COPY src/main/resources/Pictures ./Pictures

# 5. Set ownership to the non-root user
RUN chown -R javauser:javauser /app

# 6. Switch to the non-root user
USER javauser

# 7. Expose the application port
EXPOSE 8080

# 8. Run the application
# Environment variables (DB_URL, etc.) are provided at runtime by Railway or Docker Compose
ENTRYPOINT ["java", "-Xmx512m", "-jar", "app.jar"]
