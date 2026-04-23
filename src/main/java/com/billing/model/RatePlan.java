package com.billing.model;

/**
 * SOTA RATEPLAN MODEL
 * Matches Fouad's renamed "rateplan" table.
 */
public class RatePlan {
    private int id;
    private String name;
    private double rorData;
    private double rorVoice;
    private double rorSms;
    private double price;

    public RatePlan() {}

    public RatePlan(int id, String name, double rorData, double rorVoice, double rorSms, double price) {
        this.id = id;
        this.name = name;
        this.rorData = rorData;
        this.rorVoice = rorVoice;
        this.rorSms = rorSms;
        this.price = price;
    }

    // Getters & Setters
    public int getId() { return id; }
    public void setId(int id) { this.id = id; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public double getRorData() { return rorData; }
    public void setRorData(double rorData) { this.rorData = rorData; }

    public double getRorVoice() { return rorVoice; }
    public void setRorVoice(double rorVoice) { this.rorVoice = rorVoice; }

    public double getRorSms() { return rorSms; }
    public void setRorSms(double rorSms) { this.rorSms = rorSms; }

    public double getPrice() { return price; }
    public void setPrice(double price) { this.price = price; }
}
