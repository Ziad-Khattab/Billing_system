# Production Deployment Guide: JAR + Nginx

This branch implements the transition to an **Executable JAR** architecture, allowing the FMRZ Billing System to run as a standalone service with an Nginx reverse proxy.

## 1. Build the Executable JAR
Run the following command to perform a clean build. This will trigger the SvelteKit frontend build and bundle everything into a single JAR:
```bash
./mvnw clean package
```
The result will be located at: `target/ROOT.jar`

## 2. Running the Application
You can run the application directly from the terminal:
```bash
java -jar target/ROOT.jar
```
The app will start on port `8080` by default. You can change this using an environment variable:
```bash
PORT=9090 java -jar target/ROOT.jar
```

## 3. Systemd Service (Best Practice)
For production, create a service file (e.g., `/etc/systemd/system/fmrz.service`):
```ini
[Unit]
Description=FMRZ Billing System
After=network.target

[Service]
User=youruser
WorkingDirectory=/path/to/Billing_system
ExecStart=/usr/bin/java -jar target/ROOT.jar
SuccessExitStatus=143
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

## 4. Nginx Setup
1. Copy the template from `deploy/nginx.conf` to `/etc/nginx/sites-available/fmrz`.
2. Update the `alias` paths to point to your project's `src/main/webapp` directory.
3. Link the site and restart Nginx:
   ```bash
   sudo ln -s /etc/nginx/sites-available/fmrz /etc/nginx/sites-enabled/
   sudo nginx -t
   sudo systemctl restart nginx
   ```

## 🚀 Enhancements Included:
- **Embedded Tomcat 11**: Removed dependency on external Tomcat installations.
- **RemoteIpValve**: Ensures `HttpServletRequest.getRemoteAddr()` returns the real client IP, not the proxy IP.
- **Nginx Caching**: Static assets (`/_app/`) are served directly by Nginx with `Cache-Control: immutable` for maximum speed.
- **Gzip**: Enabled in Nginx to reduce payload size for the frontend.
