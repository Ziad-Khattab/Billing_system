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
                throw new RuntimeException("CRITICAL: db.properties not found!");
            }
            props.load(input);

            HikariConfig config = new HikariConfig();
            config.setDriverClassName("org.postgresql.Driver");
            config.setJdbcUrl(props.getProperty("db.url"));
            config.setUsername(props.getProperty("db.user"));
            config.setPassword(props.getProperty("db.password"));
            
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
        return props.getProperty(key);
    }

    /**
     * SIMPLE OPTION: Execute a teammate's SQL function with a single line.
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
     * SIMPLE OPTION: Execute a SELECT and get a List of Maps (No Model classes needed!).
     * This is perfect for the frontend as GSON can turn this List into JSON instantly.
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
     * SIMPLE OPTION: Execute an INSERT, UPDATE, or DELETE statement.
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
}
