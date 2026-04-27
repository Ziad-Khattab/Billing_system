package com.billing.model;

import java.math.BigDecimal;
import java.util.Date;

public class Bill {
    private int id;
    private int contractId;
    private Date billingPeriodStart;
    private Date billingPeriodEnd;
    private Date billingDate;
    
    // BigDecimal is used for financial calculations to ensure precision.
    // Unlike 'double' or 'float', it doesn't have rounding errors.
    private BigDecimal recurringFees;
    private BigDecimal oneTimeFees;
    private int voiceUsage; // Total minutes used in this period
    private int dataUsage;  // Total MB used in this period
    private int smsUsage;   // Total SMS sent in this period
    
    private BigDecimal rorCharge; // Rate of Return / Usage charges
    private BigDecimal taxes;
    private BigDecimal totalAmount;
    
    private String status; // Lifecycle: draft -> issued -> paid/overdue
    private boolean isPaid;

    public Bill() {}

    public int getId() { return id; }
    public void setId(int id) { this.id = id; }

    public int getContractId() { return contractId; }
    public void setContractId(int contractId) { this.contractId = contractId; }

    public Date getBillingPeriodStart() { return billingPeriodStart; }
    public void setBillingPeriodStart(Date billingPeriodStart) { this.billingPeriodStart = billingPeriodStart; }

    public Date getBillingPeriodEnd() { return billingPeriodEnd; }
    public void setBillingPeriodEnd(Date billingPeriodEnd) { this.billingPeriodEnd = billingPeriodEnd; }

    public Date getBillingDate() { return billingDate; }
    public void setBillingDate(Date billingDate) { this.billingDate = billingDate; }

    public BigDecimal getRecurringFees() { return recurringFees; }
    public void setRecurringFees(BigDecimal recurringFees) { this.recurringFees = recurringFees; }

    public BigDecimal getOneTimeFees() { return oneTimeFees; }
    public void setOneTimeFees(BigDecimal oneTimeFees) { this.oneTimeFees = oneTimeFees; }

    public int getVoiceUsage() { return voiceUsage; }
    public void setVoiceUsage(int voiceUsage) { this.voiceUsage = voiceUsage; }

    public int getDataUsage() { return dataUsage; }
    public void setDataUsage(int dataUsage) { this.dataUsage = dataUsage; }

    public int getSmsUsage() { return smsUsage; }
    public void setSmsUsage(int smsUsage) { this.smsUsage = smsUsage; }

    public BigDecimal getRorCharge() { return rorCharge; }
    public void setRorCharge(BigDecimal rorCharge) { this.rorCharge = rorCharge; }

    public BigDecimal getTaxes() { return taxes; }
    public void setTaxes(BigDecimal taxes) { this.taxes = taxes; }

    public BigDecimal getTotalAmount() { return totalAmount; }
    public void setTotalAmount(BigDecimal totalAmount) { this.totalAmount = totalAmount; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public boolean isPaid() { return isPaid; }
    public void setPaid(boolean paid) { isPaid = paid; }
}
