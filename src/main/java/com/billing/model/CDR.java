package com.billing.model;

import java.math.BigDecimal;
import java.util.Date;

public class CDR {
    private int id;
    private int fileId;
    private String dialA;
    private String dialB;
    private Date startTime;
    private int duration; // seconds
    private Integer serviceId; // Can be null
    private String hplmn;
    private String vplmn;
    private BigDecimal externalCharges;
    private boolean ratedFlag;

    public CDR() {}

    public int getId() { return id; }
    public void setId(int id) { this.id = id; }

    public int getFileId() { return fileId; }
    public void setFileId(int fileId) { this.fileId = fileId; }

    public String getDialA() { return dialA; }
    public void setDialA(String dialA) { this.dialA = dialA; }

    public String getDialB() { return dialB; }
    public void setDialB(String dialB) { this.dialB = dialB; }

    public Date getStartTime() { return startTime; }
    public void setStartTime(Date startTime) { this.startTime = startTime; }

    public int getDuration() { return duration; }
    public void setDuration(int duration) { this.duration = duration; }

    public Integer getServiceId() { return serviceId; }
    public void setServiceId(Integer serviceId) { this.serviceId = serviceId; }

    public String getHplmn() { return hplmn; }
    public void setHplmn(String hplmn) { this.hplmn = hplmn; }

    public String getVplmn() { return vplmn; }
    public void setVplmn(String vplmn) { this.vplmn = vplmn; }

    public BigDecimal getExternalCharges() { return externalCharges; }
    public void setExternalCharges(BigDecimal externalCharges) { this.externalCharges = externalCharges; }

    public boolean isRatedFlag() { return ratedFlag; }
    public void setRatedFlag(boolean ratedFlag) { this.ratedFlag = ratedFlag; }
}
