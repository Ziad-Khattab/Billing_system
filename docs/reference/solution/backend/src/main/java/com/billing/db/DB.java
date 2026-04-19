package com.billing.db;

import java.io.InputStream;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.Properties;

public class DB {
    private static final Properties props = new Properties();

    static {
        try (InputStream input = DB.class.getClassLoader().getResourceAsStream("db.properties")) {
            if (input == null) {
                System.err.println("CRITICAL: db.properties not found in classpath!");
            } else {
                props.load(input);
                // Load the PostgreSQL JDBC driver class. 
                // This tells Java "I'm going to use Postgres as my DB".
                Class.forName("org.postgresql.Driver");
            }
        } catch (Exception e) {
            // If the driver isn't found or properties file is missing, the app cannot start.
            System.err.println("CRITICAL: Failed to initialize Database Driver");
            e.printStackTrace();
        }
    }

    /**
     * getConnection() is the most important method here.
     * It uses the properties we loaded above to open a real network connection to Postgres.
     * 
     * LEARNING TIP: We call this every time we need the DB. 
     * The caller MUST close it (usually using try-with-resources in the DAO).
     */
    public static Connection getConnection() throws SQLException {
        String url = props.getProperty("db.url");
        String user = props.getProperty("db.user");
        String pass = props.getProperty("db.password");
        
        if (url == null || user == null) {
            throw new SQLException("Database credentials missing in db.properties");
        }
        // pass can be empty string for local peer-auth PostgreSQL
        
        return DriverManager.getConnection(url, user, pass);
    }
}
