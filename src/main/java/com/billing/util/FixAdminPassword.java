package com.billing.util;

import com.billing.db.DB;
import org.mindrot.jbcrypt.BCrypt;
import java.sql.Connection;
import java.sql.PreparedStatement;

public class FixAdminPassword {
    public static void main(String[] args) {
        String newHash = BCrypt.hashpw("admin", BCrypt.gensalt());
        System.out.println("Generated Hash: " + newHash);
        
        String sql = "UPDATE app_user SET password_hash = ? WHERE username = 'admin'";
        
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            
            ps.setString(1, newHash);
            int rows = ps.executeUpdate();
            
            if (rows > 0) {
                System.out.println("SUCCESS: Admin password updated successfully!");
            } else {
                System.out.println("FAILED: User 'admin' not found in database.");
            }
            
        } catch (Exception e) {
            System.err.println("ERROR: Could not connect to database. Did you update db.properties?");
            e.printStackTrace();
        }
    }
}
