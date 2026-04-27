# Use Eclipse Temurin JRE for a smaller, secure production image
FROM eclipse-temurin:21-jre-jammy

# Set working directory
WORKDIR /app

# Create a non-root user for security (Enterprise Best Practice)
RUN addgroup --system javauser && adduser --system --ingroup javauser javauser

# Copy the Fat JAR and static assets
COPY target/Telecom-Billing-Engine.jar app.jar
COPY src/main/webapp src/main/webapp

# Set ownership to the non-root user
RUN chown -R javauser:javauser app.jar src/main/webapp

# Switch to the non-root user
USER javauser

# Expose the application port
EXPOSE 8080

# Run the application
ENTRYPOINT ["java", "-Xmx512m", "-jar", "app.jar"]
