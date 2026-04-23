package com.billing.dao;

import com.billing.db.DB;
import com.billing.model.UserAccount;
import org.mindrot.jbcrypt.BCrypt;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class UserAccountDAO {

    public UserAccount login(String username, String password) throws SQLException {
        String sql = "SELECT * FROM user_account WHERE username = ?";
        try (Connection conn = DB.getConnection();
             PreparedStatement stmt = conn.prepareStatement(sql)) {
            
            stmt.setString(1, username);
            ResultSet rs = stmt.executeQuery();
            
            if (rs.next()) {
                String hash = rs.getString("password");
                // Verify BCrypt hash
                if (BCrypt.checkpw(password, hash)) {
                    return mapRow(rs);
                }
            }
        }
        return null;
    }

    public void register(UserAccount user) throws SQLException {
        String sql = "INSERT INTO user_account (username, password, role, name, email, address, birthdate) " +
                     "VALUES (?, ?, ?::user_role, ?, ?, ?, ?)";
        try (Connection conn = DB.getConnection();
             PreparedStatement stmt = conn.prepareStatement(sql)) {
            
            stmt.setString(1, user.getUsername());
            // SOTA: Always hash the password before it hits the DB
            stmt.setString(2, BCrypt.hashpw(user.getPassword(), BCrypt.gensalt()));
            stmt.setString(3, user.getRole());
            stmt.setString(4, user.getName());
            stmt.setString(5, user.getEmail());
            stmt.setString(6, user.getAddress());
            stmt.setObject(7, user.getBirthdate());
            
            stmt.executeUpdate();
        }
    }

    public UserAccount getById(int id) throws SQLException {
        String sql = "SELECT * FROM user_account WHERE id = ?";
        try (Connection conn = DB.getConnection();
             PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setInt(1, id);
            ResultSet rs = stmt.executeQuery();
            if (rs.next()) return mapRow(rs);
        }
        return null;
    }

    private UserAccount mapRow(ResultSet rs) throws SQLException {
        return new UserAccount(
            rs.getInt("id"),
            rs.getString("username"),
            rs.getString("password"),
            rs.getString("role"),
            rs.getString("name"),
            rs.getString("email"),
            rs.getString("address"),
            rs.getObject("birthdate", java.time.LocalDate.class)
        );
    }
}
