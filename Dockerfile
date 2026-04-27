# --- STAGE 1: Build Stage (The Workshop) ---
FROM maven:3.9.6-eclipse-temurin-21 AS build
WORKDIR /app

# 3. Build the Branded Engine
# Clean potential artifacts and trigger frontend-maven-plugin
COPY . .
RUN rm -rf node_dist node_modules frontend/node_modules && \
    mvn clean package -DskipTests

# --- STAGE 2: Runtime Stage (The Armor) ---
FROM eclipse-temurin:21-jre-jammy
WORKDIR /app

# 4. Create a non-root user for security
RUN addgroup --system javauser && adduser --system --ingroup javauser javauser

# 5. Copy artifacts from the build stage
COPY --from=build /app/target/Telecom-Billing-Engine.jar app.jar
COPY --from=build /app/src/main/webapp src/main/webapp

# Set ownership to the non-root user
RUN chown -R javauser:javauser app.jar src/main/webapp

# Switch to the non-root user
USER javauser

# Expose the application port
EXPOSE 8080

# Run the application
ENTRYPOINT ["java", "-Xmx512m", "-jar", "app.jar"]
