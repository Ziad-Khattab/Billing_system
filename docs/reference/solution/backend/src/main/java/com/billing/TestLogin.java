package com.billing;

import org.mindrot.jbcrypt.BCrypt;
import com.billing.dao.UserDAO;
import com.billing.model.AppUser;

public class TestLogin {
    public static void main(String[] args) {
        String username = "admin";
        String password = "admin";
        
        UserDAO dao = new UserDAO();
        AppUser user = dao.findByUsername(username);
        
        if (user == null) {
            System.out.println("FAILED: User 'admin' not found in database.");
            return;
        }
        
        System.out.println("User found: " + user.getUsername());
        System.out.println("Stored hash: " + user.getPasswordHash());
        
        boolean match = BCrypt.checkpw(password, user.getPasswordHash());
        System.out.println("Password match: " + match);
        
        if (match) {
            System.out.println("SUCCESS: Logic is correct.");
        } else {
            System.out.println("FAILED: Password does not match hash.");
        }
    }
}
