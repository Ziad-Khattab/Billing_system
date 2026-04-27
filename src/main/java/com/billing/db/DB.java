package com.billing.db;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import java.io.InputStream;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.Properties;

/**
 * Database Connection Manager
 * 
 * This class uses HikariCP (Connection Pool) to manage database connections.
 * Instead of opening a new connection every time, it keeps a pool of connections 
 * ready to use, significantly reducing latency.
 */
public class DB {
    private static final Properties props = new Properties();
    private static final HikariDataSource dataSource;

    static {
        try (InputStream input = DB.class.getClassLoader().getResourceAsStream("db.properties")) {
            if (input == null) {
                System.err.println("WARNING: db.properties not found in classpath. Relying on Environment Variables.");
            } else {
                props.load(input);
            }

            HikariConfig config = new HikariConfig();
            config.setDriverClassName("org.postgresql.Driver");
            
            // Safety Net: Priority logic with placeholder detection
            String url = getEnvOrProp("DB_URL", "db.url");
            String user = getEnvOrProp("DB_USER", "db.user");
            String pass = getEnvOrProp("DB_PASSWORD", "db.password");

            if (url == null || url.contains("REPLACE_WITH_ENV_VAR")) {
                System.err.println("\n" + "=".repeat(60));
                System.err.println("❌ CRITICAL: DATABASE CREDENTIALS MISSING");
                System.err.println("=".repeat(60));
                System.err.println("How to fix this:");
                System.err.println("1. Locally (IntelliJ): Edit your 'Main' Run Configuration.");
                System.err.println("   Add Environment Variables: DB_URL, DB_USER, DB_PASSWORD");
                System.err.println("2. Cloud (Railway): Go to the 'Variables' tab and add them.");
                System.err.println("=".repeat(60) + "\n");
                throw new RuntimeException("Database URL is missing or placeholder. See logs above for help.");
            }

            config.setJdbcUrl(url);
            config.setUsername(user);
            config.setPassword(pass);
            
            // Pool Configuration
            config.setMaximumPoolSize(10);
            config.setMinimumIdle(2);
            config.setIdleTimeout(300000); // 5 minutes
            config.setConnectionTimeout(20000); // 20 seconds
            config.setMaxLifetime(1800000); // 30 minutes
            
            // Performance settings for PostgreSQL
            config.addDataSourceProperty("cachePrepStmts", "true");
            config.addDataSourceProperty("prepStmtCacheSize", "250");
            config.addDataSourceProperty("prepStmtCacheSqlLimit", "2048");

            dataSource = new HikariDataSource(config);
        } catch (Exception e) {
            System.err.println("CRITICAL: Failed to initialize HikariCP Connection Pool");
            e.printStackTrace();
            throw new RuntimeException(e);
        }
    }

    /**
     * Returns a connection from the pool.
     * The caller MUST still close it (try-with-resources) to return it to the pool.
     */
    public static Connection getConnection() throws SQLException {
        return dataSource.getConnection();
    }

    public static String getProperty(String key) {
        // Support for Environment Overrides
        if (key.equals("cdr.input.path") && System.getenv("CDR_INPUT_PATH") != null) {
            return System.getenv("CDR_INPUT_PATH");
        }
        if (key.equals("cdr.processed.path") && System.getenv("CDR_PROCESSED_PATH") != null) {
            return System.getenv("CDR_PROCESSED_PATH");
        }
        return props.getProperty(key);
    }

    /**
     * Executes a stored procedure or function call.
     * Example: DB.executeCall("generate_bill", 101, "2023-10-01");
     */
    public static void executeCall(String functionName, Object... params) throws SQLException {
        StringBuilder sql = new StringBuilder("{ call ").append(functionName).append("(");
        for (int i = 0; i < params.length; i++) {
            sql.append(i == 0 ? "?" : ", ?");
        }
        sql.append(") }");

        try (Connection conn = getConnection();
             java.sql.CallableStatement cs = conn.prepareCall(sql.toString())) {
            for (int i = 0; i < params.length; i++) {
                cs.setObject(i + 1, params[i]);
            }
            cs.execute();
        }
    }

    /**
     * Executes a SELECT statement and returns a List of Maps.
     * This format is optimized for JSON serialization via GSON.
     */
    public static java.util.List<java.util.Map<String, Object>> executeSelect(String sql, Object... params) throws SQLException {
        java.util.List<java.util.Map<String, Object>> rows = new java.util.ArrayList<>();
        try (Connection conn = getConnection();
             java.sql.PreparedStatement ps = conn.prepareStatement(sql)) {
            for (int i = 0; i < params.length; i++) {
                ps.setObject(i + 1, params[i]);
            }
            try (java.sql.ResultSet rs = ps.executeQuery()) {
                java.sql.ResultSetMetaData md = rs.getMetaData();
                int columns = md.getColumnCount();
                while (rs.next()) {
                    java.util.Map<String, Object> row = new java.util.HashMap<>();
                    for (int i = 1; i <= columns; i++) {
                        Object val = rs.getObject(i);
                        if (val != null && val.getClass().getName().contains("PGobject")) {
                            val = val.toString();
                        }
                        row.put(md.getColumnLabel(i), val);
                    }
                    rows.add(row);
                }
            }
        }
        return rows;
    }

    /**
     * Executes an INSERT, UPDATE, or DELETE statement.
     * @return The number of rows affected.
     */
    public static int executeUpdate(String sql, Object... params) throws SQLException {
        try (Connection conn = getConnection();
             java.sql.PreparedStatement ps = conn.prepareStatement(sql)) {
            for (int i = 0; i < params.length; i++) {
                ps.setObject(i + 1, params[i]);
            }
            return ps.executeUpdate();
        }
    }

    /**
     * Shut down the pool (useful for clean app shutdown).
     */
    public static void closePool() {
        if (dataSource != null) {
            dataSource.close();
        }
    }

    private static String getEnvOrProp(String envKey, String propKey) {
        String val = System.getenv(envKey);
        if (val == null || val.trim().isEmpty() || val.contains("REPLACE_WITH_ENV_VAR")) {
            val = props.getProperty(propKey);
        }
        return val;
    }
}
