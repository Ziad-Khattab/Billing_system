// ─── PACKAGE ───────────────────────────────────────────────
// All model classes live here. Models are POJOs (Plain Old Java Objects):
// just data + getters/setters. No logic, no database code.
package com.billing.model;

// ─── IMPORTS ───────────────────────────────────────────────
// java.time.LocalDate: Modern Java date type (replaces old java.util.Date)
// Stores date without time: 2000-01-15
import java.time.LocalDate;

// ─── MODEL ─────────────────────────────────────────────────
// Maps to the "customer" table in PostgreSQL:
//   id        SERIAL PRIMARY KEY
//   name      VARCHAR(255) NOT NULL
//   address   TEXT
//   birthdate DATE
//   user_id   INTEGER REFERENCES app_user(id)  -- links to login account
public class Customer {

    // Each field matches a column in the customer table
    private int id;
    private String name;
    private String address;
    private String email;
    private LocalDate birthdate;
    private Integer userId;  // Integer (not int) so it can be null — not all customers have accounts

    // ─── CONSTRUCTORS ──────────────────────────────────────
    // Empty constructor: needed by Gson to create objects from JSON
    public Customer() {}

    // Full constructor: for when you create a Customer with all fields known
    public Customer(int id, String name, String address, String email, LocalDate birthdate, Integer userId) {
        this.id = id;
        this.name = name;
        this.address = address;
        this.email = email;
        this.birthdate = birthdate;
        this.userId = userId;
    }

    // ─── GETTERS & SETTERS ─────────────────────────────────
    // Getters: let other classes READ the value
    // Setters: let other classes CHANGE the value
    // Why not just make fields public? Encapsulation — you can add validation later
    // without changing every class that uses Customer.

    public int getId() { return id; }
    public void setId(int id) { this.id = id; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public String getAddress() { return address; }
    public void setAddress(String address) { this.address = address; }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }

    public LocalDate getBirthdate() { return birthdate; }
    public void setBirthdate(LocalDate birthdate) { this.birthdate = birthdate; }

    public Integer getUserId() { return userId; }
    public void setUserId(Integer userId) { this.userId = userId; }
}
