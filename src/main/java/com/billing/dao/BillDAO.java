package com.billing.dao;

import com.billing.model.Bill;
import com.billing.db.DB;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;

public class BillDAO {

    public List<Bill> findByContractId(int contractId) throws SQLException {
        List<Bill> bills = new ArrayList<>();
        String sql = "SELECT * FROM bill WHERE contract_id = ? ORDER BY billing_period_start DESC";

        try (Connection conn = DB.getConnection();
             PreparedStatement pstmt = conn.prepareStatement(sql)) {
            
            pstmt.setInt(1, contractId);
            ResultSet rs = pstmt.executeQuery();

            while (rs.next()) {
                Bill bill = new Bill();
                bill.setId(rs.getInt("id"));
                bill.setContractId(rs.getInt("contract_id"));
                bill.setBillingPeriodStart(rs.getDate("billing_period_start"));
                bill.setBillingPeriodEnd(rs.getDate("billing_period_end"));
                bill.setBillingDate(rs.getDate("billing_date"));
                
                // BigDecimal: used for money to avoid floating point rounding errors
                bill.setRecurringFees(rs.getBigDecimal("recurring_fees"));
                bill.setOneTimeFees(rs.getBigDecimal("one_time_fees"));
                bill.setVoiceUsage(rs.getInt("voice_usage"));
                bill.setDataUsage(rs.getInt("data_usage"));
                bill.setSmsUsage(rs.getInt("sms_usage"));
                
                bill.setRorCharge(rs.getBigDecimal("ROR_charge"));
                bill.setTaxes(rs.getBigDecimal("taxes"));
                bill.setTotalAmount(rs.getBigDecimal("total_amount"));
                
                bill.setStatus(rs.getString("status"));
                bill.setPaid(rs.getBoolean("is_paid"));
                
                bills.add(bill);
            }
        }
        return bills;
    }

    public Bill findById(int id) throws SQLException {
        String sql = "SELECT * FROM bill WHERE id = ?";

        try (Connection conn = DB.getConnection();
             PreparedStatement pstmt = conn.prepareStatement(sql)) {
            
            pstmt.setInt(1, id);
            ResultSet rs = pstmt.executeQuery();

            if (rs.next()) {
                Bill bill = new Bill();
                bill.setId(rs.getInt("id"));
                bill.setContractId(rs.getInt("contract_id"));
                bill.setBillingPeriodStart(rs.getDate("billing_period_start"));
                bill.setBillingPeriodEnd(rs.getDate("billing_period_end"));
                bill.setBillingDate(rs.getDate("billing_date"));
                
                bill.setRecurringFees(rs.getBigDecimal("recurring_fees"));
                bill.setOneTimeFees(rs.getBigDecimal("one_time_fees"));
                bill.setVoiceUsage(rs.getInt("voice_usage"));
                bill.setDataUsage(rs.getInt("data_usage"));
                bill.setSmsUsage(rs.getInt("sms_usage"));
                
                bill.setRorCharge(rs.getBigDecimal("ROR_charge"));
                bill.setTaxes(rs.getBigDecimal("taxes"));
                bill.setTotalAmount(rs.getBigDecimal("total_amount"));
                
                bill.setStatus(rs.getString("status"));
                bill.setPaid(rs.getBoolean("is_paid"));
                
                return bill;
            }
        }
        return null;
    }
    public List<Bill> findAll() throws SQLException {
        List<Bill> bills = new ArrayList<>();
        String sql = "SELECT * FROM bill ORDER BY billing_date DESC";

        try (Connection conn = DB.getConnection();
             PreparedStatement pstmt = conn.prepareStatement(sql);
             ResultSet rs = pstmt.executeQuery()) {

            while (rs.next()) {
                Bill bill = new Bill();
                bill.setId(rs.getInt("id"));
                bill.setContractId(rs.getInt("contract_id"));
                bill.setBillingPeriodStart(rs.getDate("billing_period_start"));
                bill.setBillingPeriodEnd(rs.getDate("billing_period_end"));
                bill.setBillingDate(rs.getDate("billing_date"));
                bill.setRecurringFees(rs.getBigDecimal("recurring_fees"));
                bill.setOneTimeFees(rs.getBigDecimal("one_time_fees"));
                bill.setVoiceUsage(rs.getInt("voice_usage"));
                bill.setDataUsage(rs.getInt("data_usage"));
                bill.setSmsUsage(rs.getInt("sms_usage"));
                bill.setRorCharge(rs.getBigDecimal("ROR_charge"));
                bill.setTaxes(rs.getBigDecimal("taxes"));
                bill.setTotalAmount(rs.getBigDecimal("total_amount"));
                bill.setStatus(rs.getString("status"));
                bill.setPaid(rs.getBoolean("is_paid"));
                bills.add(bill);
            }
        }
        return bills;
    }
}
