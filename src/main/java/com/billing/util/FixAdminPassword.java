package com.billing.util;

import com.billing.db.DB;
import java.sql.Connection;
import java.sql.PreparedStatement;

public class FixAdminPassword {
    public static void main(String[] args) {
        try (Connection conn = DB.getConnection()) {
            System.out.println("--- CREATING PLAIN TEXT ADMIN ACCOUNT ---");
            
            // Create/Update Admin Account with lowercase role 'admin'
            String insert = "INSERT INTO user_account (username, password, role, name, email) " +
                            "VALUES ('admin', 'admin123', 'admin'::user_role, 'System Admin', 'admin@fmrz.com') " +
                            "ON CONFLICT (username) DO UPDATE SET password = EXCLUDED.password, role = 'admin'::user_role";
            
            try (PreparedStatement ps = conn.prepareStatement(insert)) {
                ps.executeUpdate();
                System.out.println("✅ SUCCESS: Admin account ready!");
                System.out.println("   Username: admin");
                System.out.println("   Password: admin123");
            }
            
        } catch (Exception e) {
            System.err.println("❌ Database Error: " + e.getMessage());
        }
    }
}
