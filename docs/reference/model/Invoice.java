package com.billing.model;

import java.time.LocalDateTime;

// Maps to "invoice" table — a generated PDF invoice derived from a bill.
// The PDF file is stored on disk; this table tracks the path and generation time.
//
// Table: invoice (id, bill_id, pdf_path, generation_date)
public class Invoice {

    private int id;
    private int billId;
    private String pdfPath;           // filesystem path to the generated PDF
    private LocalDateTime generationDate;

    // Display fields (from JOIN with bill → contract → customer)
    private String customerName;
    private String msisdn;

    public Invoice() {}

    public int getId() { return id; }
    public void setId(int id) { this.id = id; }

    public int getBillId() { return billId; }
    public void setBillId(int billId) { this.billId = billId; }

    public String getPdfPath() { return pdfPath; }
    public void setPdfPath(String pdfPath) { this.pdfPath = pdfPath; }

    public LocalDateTime getGenerationDate() { return generationDate; }
    public void setGenerationDate(LocalDateTime generationDate) { this.generationDate = generationDate; }

    public String getCustomerName() { return customerName; }
    public void setCustomerName(String customerName) { this.customerName = customerName; }

    public String getMsisdn() { return msisdn; }
    public void setMsisdn(String msisdn) { this.msisdn = msisdn; }
}
