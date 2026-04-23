package com.billing.model;

import java.time.LocalDate;

/**
 * SOTA USER_ACCOUNT MODEL
 * 
 * Fouad has merged the Customer and AppUser tables into one: "user_account".
 * This class now handles both login credentials AND personal profile data.
 */
public class UserAccount {
    private int id;
    private String username;
    private String password; // Fouad renamed password_hash to password in his schema
    private String role;     // "admin" or "customer"
    private String name;     // Merged from Customer
    private String email;    // Merged from Customer
    private String address;  // Merged from Customer
    private LocalDate birthdate; // Merged from Customer

    public UserAccount() {}

    public UserAccount(int id, String username, String password, String role, String name, String email, String address, LocalDate birthdate) {
        this.id = id;
        this.username = username;
        this.password = password;
        this.role = role;
        this.name = name;
        this.email = email;
        this.address = address;
        this.birthdate = birthdate;
    }

    // Getters & Setters
    public int getId() { return id; }
    public void setId(int id) { this.id = id; }

    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }

    public String getRole() { return role; }
    public void setRole(String role) { this.role = role; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }

    public String getAddress() { return address; }
    public void setAddress(String address) { this.address = address; }

    public LocalDate getBirthdate() { return birthdate; }
    public void setBirthdate(LocalDate birthdate) { this.birthdate = birthdate; }
}
