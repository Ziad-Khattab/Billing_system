# --- FMRZ Telecom Billing System: Optimized Local Deployment ---
# This version assumes you have already run './mvnw clean package' locally.

FROM eclipse-temurin:21-jre-jammy
WORKDIR /app

# 1. Create a non-root user for security
RUN addgroup --system javauser && adduser --system --ingroup javauser javauser

# 2. Copy local artifacts directly
# (Requires that you've run the build locally first)
COPY target/Telecom-Billing-Engine.jar app.jar
COPY src/main/webapp webapp_static

# 3. Set ownership to the non-root user
RUN chown -R javauser:javauser /app

# 4. Switch to the non-root user
USER javauser

# 5. Expose the application port
EXPOSE 8080

# 6. Run the application
# We use -DDB_URL, etc. via docker-compose environment or .env
ENTRYPOINT ["java", "-Xmx512m", "-jar", "app.jar"]
