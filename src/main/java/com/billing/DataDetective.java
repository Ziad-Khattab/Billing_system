package com.billing;

import com.billing.db.DB;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

/**
 * DataDetective: Billing & Rating Audit Tool
 * Use this to verify that the math in the database matches the expectations 
 * for JasperReports and customer invoices.
 */
public class DataDetective {
    public static void main(String[] args) {
        System.out.println("🔍 [DataDetective] Starting Billing Audit...");
        
        try {
            // 1. Check Latest Bills
            List<Map<String, Object>> latestBills = DB.executeSelect(
                "SELECT b.id, b.contract_id, b.total_amount, b.overage_charge, b.recurring_fees, c.msisdn " +
                "FROM bill b JOIN contract c ON b.contract_id = c.id " +
                "ORDER BY b.id DESC LIMIT 5"
            );

            if (latestBills.isEmpty()) {
                System.out.println("⚠️ No bills found to audit.");
                return;
            }

            for (Map<String, Object> bill : latestBills) {
                int billId = (int) bill.get("id");
                String msisdn = (String) bill.get("msisdn");
                BigDecimal billOverage = (BigDecimal) bill.get("overage_charge");
                BigDecimal billTotal = (BigDecimal) bill.get("total_amount");

                System.out.println("\n--- Auditing Bill #" + billId + " (MSISDN: " + msisdn + ") ---");
                System.out.println("Bill Overage (Header): " + billOverage + " EGP");

                // 2. Audit Usage Breakdown (The data Jasper uses)
                List<Map<String, Object>> breakdown = DB.executeSelect(
                    "SELECT * FROM get_bill_usage_breakdown(?)", billId
                );

                BigDecimal calculatedOverage = BigDecimal.ZERO;
                boolean foundIssues = false;

                System.out.println("Details Breakdown:");
                for (Map<String, Object> line : breakdown) {
                    String label = (String) line.get("category_label");
                    BigDecimal lineTotal = (BigDecimal) line.get("line_total");
                    BigDecimal rate = (BigDecimal) line.get("unit_rate");
                    
                    // Sum up non-bundled overages
                    if (rate != null && rate.compareTo(BigDecimal.ZERO) > 0) {
                        calculatedOverage = calculatedOverage.add(lineTotal);
                    }

                    System.out.printf("  - %-30s: %8.2f EGP (Rate: %s)\n", label, lineTotal, rate);
                }

                System.out.println("Calculated Overage Sum: " + calculatedOverage + " EGP");

                // 3. Verification
                if (billOverage.setScale(2, BigDecimal.ROUND_HALF_UP).equals(calculatedOverage.setScale(2, BigDecimal.ROUND_HALF_UP))) {
                    System.out.println("✅ MATH MATCH: Overage breakdown matches bill header.");
                } else {
                    System.err.println("❌ MATH MISMATCH: Overage breakdown (" + calculatedOverage + ") does NOT match bill header (" + billOverage + ")!");
                    foundIssues = true;
                }
                
                if (foundIssues) {
                    System.out.println("💡 Recommendation: Check get_bill_usage_breakdown() vs generate_bill() logic.");
                }
            }

        } catch (Exception e) {
            System.err.println("❌ Audit Failed with exception:");
            e.printStackTrace();
        }
    }
}
