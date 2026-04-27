package com.billing.model;

/**
 * CONTRACT MODEL
 */
public class Contract {
    private int id;
    private int userAccountId; // Linked to user_account.id
    private int ratePlanId;    // Linked to rateplan.id
    private String msisdn;
    private String status;     // "active", "suspended", etc.
    private double creditLimit;
    private double availableCredit;

    public Contract() {}

    public Contract(int id, int userAccountId, int ratePlanId, String msisdn, String status, double creditLimit, double availableCredit) {
        this.id = id;
        this.userAccountId = userAccountId;
        this.ratePlanId = ratePlanId;
        this.msisdn = msisdn;
        this.status = status;
        this.creditLimit = creditLimit;
        this.availableCredit = availableCredit;
    }

    // Getters & Setters
    public int getId() { return id; }
    public void setId(int id) { this.id = id; }

    public int getUserAccountId() { return userAccountId; }
    public void setUserAccountId(int userAccountId) { this.userAccountId = userAccountId; }

    public int getRatePlanId() { return ratePlanId; }
    public void setRatePlanId(int ratePlanId) { this.ratePlanId = ratePlanId; }

    public String getMsisdn() { return msisdn; }
    public void setMsisdn(String msisdn) { this.msisdn = msisdn; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public double getCreditLimit() { return creditLimit; }
    public void setCreditLimit(double creditLimit) { this.creditLimit = creditLimit; }

    public double getAvailableCredit() { return availableCredit; }
    public void setAvailableCredit(double availableCredit) { this.availableCredit = availableCredit; }
}
