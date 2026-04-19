// ─── PACKAGE ───────────────────────────────────────────────
// All DAOs live here. Each DAO handles DB operations for ONE table.
package com.billing.dao;

// ─── IMPORTS ───────────────────────────────────────────────
// DB: our connection helper — returns a fresh connection per call
import com.billing.db.DB;
// The model this DAO works with
import com.billing.model.AppUser;

// java.sql: JDBC classes for database access
// Connection: represents one connection to the database
import java.sql.Connection;
// PreparedStatement: a pre-compiled SQL query with ? placeholders (prevents SQL injection)
import java.sql.PreparedStatement;
// ResultSet: the rows returned by a SELECT query — iterate with rs.next()
import java.sql.ResultSet;
// SQLException: thrown when anything goes wrong with the DB
import java.sql.SQLException;
// Statement: used to get auto-generated keys after INSERT
import java.sql.Statement;
// Timestamp: for converting between SQL TIMESTAMP and Java LocalDateTime
import java.sql.Timestamp;

public class UserDAO {

    // ─── FIND BY USERNAME ──────────────────────────────────
    // Used during login: look up user by username, then verify password
    // Returns null if no user found (caller checks this)
    public AppUser findByUsername(String username) {
        // SQL with ? placeholder — NEVER concatenate user input into SQL!
        // Bad:  "SELECT * FROM app_user WHERE username = '" + username + "'"  ← SQL INJECTION
        // Good: "SELECT * FROM app_user WHERE username = ?"  ← safe, parameterized
        String sql = "SELECT * FROM app_user WHERE username = ?";

        // try-with-resources: Connection, PreparedStatement, ResultSet all auto-close
        // when the try block ends. No need for manual conn.close() calls.
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {

            // Set the ? placeholder. Index starts at 1 (not 0!)
            ps.setString(1, username);

            try (ResultSet rs = ps.executeQuery()) {
                // rs.next() moves to the first row. Returns false if no rows.
                if (rs.next()) {
                    return mapRow(rs);  // convert DB row → Java object
                }
            }
        } catch (SQLException e) {
            // In production: use a logging framework. For learning: print stack trace.
            e.printStackTrace();
        }
        return null;  // user not found
    }

    // ─── FIND BY ID ────────────────────────────────────────
    public AppUser findById(int id) {
        String sql = "SELECT * FROM app_user WHERE id = ?";

        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {

            ps.setInt(1, id);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return mapRow(rs);
                }
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return null;
    }

    // ─── CREATE ────────────────────────────────────────────
    // Inserts a new user. Returns the user with generated ID filled in.
    // Password must already be hashed with bcrypt BEFORE calling this.
    public AppUser create(AppUser user) {
        // RETURNING id: PostgreSQL-specific. Returns the auto-generated ID.
        // Alternative (MySQL): use Statement.RETURN_GENERATED_KEYS
        String sql = "INSERT INTO app_user (username, password_hash, full_name, role) " +
                     "VALUES (?, ?, ?, ?) RETURNING id, created_at";

        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {

            ps.setString(1, user.getUsername());
            ps.setString(2, user.getPasswordHash());
            ps.setString(3, user.getFullName());
            ps.setString(4, user.getRole() != null ? user.getRole() : "customer");

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    user.setId(rs.getInt("id"));
                    user.setCreatedAt(rs.getTimestamp("created_at").toLocalDateTime());
                }
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return user;
    }

    // ─── MAP ROW ───────────────────────────────────────────
    // Converts one ResultSet row into an AppUser object.
    // Private helper — called by every "find" method.
    private AppUser mapRow(ResultSet rs) throws SQLException {
        AppUser user = new AppUser();
        // rs.getInt("column_name") reads the value from the current row
        user.setId(rs.getInt("id"));
        user.setUsername(rs.getString("username"));
        user.setPasswordHash(rs.getString("password_hash"));
        user.setFullName(rs.getString("full_name"));
        user.setRole(rs.getString("role"));
        // Convert SQL Timestamp → Java LocalDateTime
        Timestamp ts = rs.getTimestamp("created_at");
        if (ts != null) {
            user.setCreatedAt(ts.toLocalDateTime());
        }
        return user;
    }
}
