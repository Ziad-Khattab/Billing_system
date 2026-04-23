package com.billing.model;

import java.math.BigDecimal;

// Maps to "contract" table — ties a customer to a rateplan with a phone number.
// This is the core business entity: a customer subscribes to a plan via a contract.
//
// Table: contract (id, customer_id, rateplan_id, msisdn, status, credit_limit, available_credit)
// status is a PostgreSQL ENUM: 'active', 'suspended', 'terminated'
public class Contract {

    private int id;
    private int customerId;
    private int rateplanId;
    private String msisdn;            // phone number (Mobile Station International Subscriber Directory Number)
    private String status;            // "active", "suspended", "terminated"
    private BigDecimal creditLimit;
    private BigDecimal availableCredit;

    // Extra fields for display — populated via JOIN, not stored in contract table
    private String customerName;
    private String rateplanName;

    public Contract() {}

    public int getId() { return id; }
    public void setId(int id) { this.id = id; }

    public int getCustomerId() { return customerId; }
    public void setCustomerId(int customerId) { this.customerId = customerId; }

    public int getRateplanId() { return rateplanId; }
    public void setRateplanId(int rateplanId) { this.rateplanId = rateplanId; }

    public String getMsisdn() { return msisdn; }
    public void setMsisdn(String msisdn) { this.msisdn = msisdn; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public BigDecimal getCreditLimit() { return creditLimit; }
    public void setCreditLimit(BigDecimal creditLimit) { this.creditLimit = creditLimit; }

    public BigDecimal getAvailableCredit() { return availableCredit; }
    public void setAvailableCredit(BigDecimal availableCredit) { this.availableCredit = availableCredit; }

    public String getCustomerName() { return customerName; }
    public void setCustomerName(String customerName) { this.customerName = customerName; }

    public String getRateplanName() { return rateplanName; }
    public void setRateplanName(String rateplanName) { this.rateplanName = rateplanName; }
}
