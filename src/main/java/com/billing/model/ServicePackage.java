package com.billing.model;

import java.math.BigDecimal;

// Maps to "service_package" table — bundled quotas (voice minutes, data MB, SMS count).
// Service packages are assigned to contracts and consumed by CDR usage.
//
// Table: service_package (id, name, type, amount, priority)
// type is a PostgreSQL ENUM: 'voice', 'data', 'sms'
// In Java we store it as String — simpler than creating a Java enum for a DB enum.
public class ServicePackage {

    private int id;
    private String name;
    private String type;          // "voice", "data", or "sms"
    private BigDecimal amount;    // quota: minutes, MB, or SMS count
    private int priority;         // consumption order: lower = used first

    public ServicePackage() {}

    public int getId() { return id; }
    public void setId(int id) { this.id = id; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public String getType() { return type; }
    public void setType(String type) { this.type = type; }

    public BigDecimal getAmount() { return amount; }
    public void setAmount(BigDecimal amount) { this.amount = amount; }

    public int getPriority() { return priority; }
    public void setPriority(int priority) { this.priority = priority; }
}
