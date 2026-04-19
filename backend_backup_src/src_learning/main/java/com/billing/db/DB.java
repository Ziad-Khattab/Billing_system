package com.billing.db;
import java.sql.*;

public class DB {
    private static final String db_url = "jdbc:postgresql://ep-snowy-dawn-algt9iaq-pooler.c-3.eu-central-1.aws.neon.tech/neondb?sslmode=require&channelBinding=require";
    private static final String db_user = "neondb_owner";
    private static final String db_password = "npg_eZDj1hp4uUMT";

    static Connection conn;

    public static Connection getConnection() throws SQLException {
        if (conn == null || conn.isClosed()) {
            try {
                Class.forName("org.postgresql.Driver");
                conn = DriverManager.getConnection(db_url, db_user, db_password);
                System.out.println("Connected to PostgreSQL database!");
            } catch (ClassNotFoundException e) {
                throw new SQLException("PostgreSQL Driver not found.", e);
            }
        }
        return conn;
    }

    public static void close() {
        if (conn != null) {
            try {
                conn.close();
                System.out.println("Database connection closed.");
            } catch (SQLException e) {
                System.err.println("Error closing connection: " + e.getMessage());
            }
        }
    }
}


