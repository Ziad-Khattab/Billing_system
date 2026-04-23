package com.billing.dao;

import com.billing.db.DB;
import com.billing.model.Invoice;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class InvoiceDAO {

    public Invoice findById(int id) {
        String sql = "SELECT i.*, cu.name AS customer_name, co.msisdn " +
                     "FROM invoice i " +
                     "JOIN bill b ON i.bill_id = b.id " +
                     "JOIN contract co ON b.contract_id = co.id " +
                     "JOIN customer cu ON co.customer_id = cu.id " +
                     "WHERE i.id = ?";
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return mapRow(rs);
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return null;
    }

    public List<Invoice> findByCustomerId(int customerId) {
        String sql = "SELECT i.*, cu.name AS customer_name, co.msisdn " +
                     "FROM invoice i " +
                     "JOIN bill b ON i.bill_id = b.id " +
                     "JOIN contract co ON b.contract_id = co.id " +
                     "JOIN customer cu ON co.customer_id = cu.id " +
                     "WHERE cu.id = ? ORDER BY i.generation_date DESC";
        List<Invoice> list = new ArrayList<>();
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, customerId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(mapRow(rs));
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return list;
    }

    public Invoice create(Invoice inv) {
        String sql = "INSERT INTO invoice (bill_id, pdf_path) VALUES (?, ?) RETURNING id, generation_date";
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, inv.getBillId());
            ps.setString(2, inv.getPdfPath());
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    inv.setId(rs.getInt("id"));
                    inv.setGenerationDate(rs.getTimestamp("generation_date").toLocalDateTime());
                }
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return inv;
    }

    private Invoice mapRow(ResultSet rs) throws SQLException {
        Invoice i = new Invoice();
        i.setId(rs.getInt("id"));
        i.setBillId(rs.getInt("bill_id"));
        i.setPdfPath(rs.getString("pdf_path"));
        Timestamp ts = rs.getTimestamp("generation_date");
        if (ts != null) i.setGenerationDate(ts.toLocalDateTime());
        try {
            i.setCustomerName(rs.getString("customer_name"));
            i.setMsisdn(rs.getString("msisdn"));
        } catch (SQLException ignored) {}
        return i;
    }
}
