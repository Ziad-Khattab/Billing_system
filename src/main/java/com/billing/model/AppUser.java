package com.billing.model;

import java.time.LocalDateTime;

// Maps to the "app_user" table — login credentials for admins and customers.
// This is NOT the same as "customer". A customer has a profile (name, address).
// An app_user has login credentials (username, password hash).
// They're linked: customer.user_id → app_user.id
//
// Table structure:
//   id            SERIAL PRIMARY KEY
//   username      VARCHAR(50) NOT NULL UNIQUE
//   password_hash VARCHAR(255) NOT NULL
//   full_name     VARCHAR(255) NOT NULL
//   role          VARCHAR(20) NOT NULL DEFAULT 'customer'
//   created_at    TIMESTAMP NOT NULL DEFAULT NOW()
public class AppUser {

    private int id;
    private String username;
    private String passwordHash;  // bcrypt hash, NEVER plain text
    private String fullName;
    private String role;          // "admin" or "customer"
    private LocalDateTime createdAt;

    public AppUser() {}

    public AppUser(int id, String username, String passwordHash,
                   String fullName, String role, LocalDateTime createdAt) {
        this.id = id;
        this.username = username;
        this.passwordHash = passwordHash;
        this.fullName = fullName;
        this.role = role;
        this.createdAt = createdAt;
    }

    // Getters & Setters
    public int getId() { return id; }
    public void setId(int id) { this.id = id; }

    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public String getPasswordHash() { return passwordHash; }
    public void setPasswordHash(String passwordHash) { this.passwordHash = passwordHash; }

    public String getFullName() { return fullName; }
    public void setFullName(String fullName) { this.fullName = fullName; }

    public String getRole() { return role; }
    public void setRole(String role) { this.role = role; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }
}
