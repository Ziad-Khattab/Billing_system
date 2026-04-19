package com.billing.util;

// ─── JASPERREPORTS IMPORTS ─────────────────────────────────
// JasperCompileManager: compiles .jrxml (XML) → .jasper (binary)
import net.sf.jasperreports.engine.JasperCompileManager;
// JasperFillManager: fills compiled template with data → JasperPrint (in-memory report)
import net.sf.jasperreports.engine.JasperFillManager;
// JasperPrint: the filled report — ready to export to PDF, HTML, Excel, etc.
import net.sf.jasperreports.engine.JasperPrint;
// JasperReport: the compiled template object
import net.sf.jasperreports.engine.JasperReport;
// JasperExportManager: exports JasperPrint → PDF file or byte array
import net.sf.jasperreports.engine.JasperExportManager;
// JRBeanCollectionDataSource: wraps a List<Map> as a data source for the detail band
import net.sf.jasperreports.engine.data.JRBeanCollectionDataSource;
// JRException: Jasper's checked exception (wraps all errors)
import net.sf.jasperreports.engine.JRException;

import com.billing.model.Bill;
import java.io.InputStream;
import java.util.*;

// ─── HOW JASPERREPORTS WORKS ───────────────────────────────
//
// Step 1: DESIGN (.jrxml) — XML template defining layout
//   └→ You create this once (we made invoice.jrxml)
//
// Step 2: COMPILE (.jrxml → .jasper)
//   └→ JasperCompileManager.compileReport(inputStream)
//   └→ Converts XML → binary. Do this ONCE, cache the result.
//
// Step 3: FILL (.jasper + data → JasperPrint)
//   └→ JasperFillManager.fillReport(report, parameters, dataSource)
//   └→ Parameters = single values (customer name, date)
//   └→ DataSource = repeating rows (service charges table)
//
// Step 4: EXPORT (JasperPrint → PDF)
//   └→ JasperExportManager.exportReportToPdf(jasperPrint)
//   └→ Returns byte[] — send to browser or save to file
//
public class InvoicePDFGenerator {

    // Cache the compiled template — compile once, reuse forever
    // This avoids the 2-5 second compilation on every request
    private static JasperReport compiledReport = null;

    // Compile template on first use (lazy initialization)
    private static JasperReport getCompiledReport() throws JRException {
        if (compiledReport == null) {
            // Load .jrxml from classpath (src/main/resources/)
            InputStream stream = InvoicePDFGenerator.class
                .getResourceAsStream("/reports/invoice.jrxml");
            // Compile XML → binary report object
            compiledReport = JasperCompileManager.compileReport(stream);
        }
        return compiledReport;
    }

    /**
     * Generate a PDF invoice as a byte array.
     *
     * @param bill          The bill data (fees, usage, taxes)
     * @param customerName  Customer's full name
     * @param address       Customer's address
     * @param msisdn        Phone number
     * @param planName      Rate plan name (e.g., "Gold")
     * @return byte[] containing the PDF file
     */
    public static byte[] generateInvoice(Bill bill, String customerName,
                                          String address, String msisdn,
                                          String planName) throws JRException {

        // ─── STEP 1: Set parameters (single values) ───
        Map<String, Object> params = new HashMap<>();
        params.put("companyName", "FMRZ");
        params.put("invoiceNumber", "INV-" + bill.getId());
        params.put("invoiceDate", bill.getBillingDate() != null
            ? bill.getBillingDate().toString() : "N/A");
        params.put("customerName", customerName);
        params.put("customerAddress", address != null ? address : "");
        params.put("msisdn", msisdn != null ? msisdn : "");
        params.put("profileName", planName != null ? planName : "");
        BigDecimal subtotal = bill.getRecurringFees().add(bill.getOneTimeFees()).add(bill.getRorCharge());
        params.put("subtotal", subtotal.toPlainString());
        params.put("taxes", bill.getTaxes().toPlainString());
        params.put("total", bill.getTotalAmount().toPlainString());

        // ─── STEP 2: Build data source (repeating rows) ───
        // Each Map = one row in the services table
        List<Map<String, String>> rows = new ArrayList<>();

        // Recurring fees row
        rows.add(Map.of(
            "service", "Monthly Subscription",
            "description", planName + " plan recurring fee",
            "amount", bill.getRecurringFees().toPlainString()
        ));

        // One-time fees (if any)
        if (bill.getOneTimeFees().signum() > 0) {
            rows.add(Map.of(
                "service", "One-time Fees",
                "description", "Setup/activation charges",
                "amount", bill.getOneTimeFees().toPlainString()
            ));
        }

        // Voice usage
        if (bill.getVoiceUsage() > 0) {
            rows.add(Map.of(
                "service", "Voice Usage",
                "description", bill.getVoiceUsage() + " minutes",
                "amount", "Included"
            ));
        }

        // Data usage
        if (bill.getDataUsage() > 0) {
            rows.add(Map.of(
                "service", "Data Usage",
                "description", bill.getDataUsage() + " MB",
                "amount", "Included"
            ));
        }

        // SMS usage
        if (bill.getSmsUsage() > 0) {
            rows.add(Map.of(
                "service", "SMS Usage",
                "description", bill.getSmsUsage() + " messages",
                "amount", "Included"
            ));
        }

        // Wrap as JasperReports data source
        JRBeanCollectionDataSource dataSource = new JRBeanCollectionDataSource(rows);

        // ─── STEP 3: Fill template with data ───
        JasperPrint print = JasperFillManager.fillReport(
            getCompiledReport(), params, dataSource
        );

        // ─── STEP 4: Export to PDF byte array ───
        return JasperExportManager.exportReportToPdf(print);
    }
}
