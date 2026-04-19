package com.billing.model;

import java.math.BigDecimal;

// Maps to "rateplan" table — pricing plan that customers subscribe to.
// Contains rates (Rate Of Rating) for voice, data, SMS per unit.
//
// Table: rateplan (id, name, ror_data, ror_voice, ror_sms, price)
// BigDecimal: used for money/rates instead of double.
//   double has floating-point errors: 0.1 + 0.2 = 0.30000000000000004
//   BigDecimal is exact: 0.1 + 0.2 = 0.3
public class RatePlan {

    private int id;
    private String name;
    private BigDecimal rorData;   // rate per MB of data
    private BigDecimal rorVoice;  // rate per minute of voice
    private BigDecimal rorSms;    // rate per SMS
    private BigDecimal price;     // base subscription price

    public RatePlan() {}

    public int getId() { return id; }
    public void setId(int id) { this.id = id; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public BigDecimal getRorData() { return rorData; }
    public void setRorData(BigDecimal rorData) { this.rorData = rorData; }

    public BigDecimal getRorVoice() { return rorVoice; }
    public void setRorVoice(BigDecimal rorVoice) { this.rorVoice = rorVoice; }

    public BigDecimal getRorSms() { return rorSms; }
    public void setRorSms(BigDecimal rorSms) { this.rorSms = rorSms; }

    public BigDecimal getPrice() { return price; }
    public void setPrice(BigDecimal price) { this.price = price; }
}
