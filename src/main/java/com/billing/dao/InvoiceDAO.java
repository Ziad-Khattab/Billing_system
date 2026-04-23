package com.billing.dao;

import com.billing.db.DB;
import com.billing.model.Invoice;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class InvoiceDAO {

    public List<Invoice> findAll() throws SQLException {
        List<Invoice> list = new ArrayList<>();
        String sql = "SELECT i.*, u.name AS user_name, co.msisdn " +
                     "FROM invoice i " +
                     "JOIN bill b ON i.bill_id = b.id " +
                     "JOIN contract co ON b.contract_id = co.id " +
                     "JOIN user_account u ON co.user_account_id = u.id";
        
        try (Connection conn = DB.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) list.add(mapRow(rs));
        }
        return list;
    }

    private Invoice mapRow(ResultSet rs) throws SQLException {
        Invoice i = new Invoice();
        i.setId(rs.getInt("id"));
        i.setBillId(rs.getInt("bill_id"));
        i.setAmount(rs.getDouble("amount"));
        i.setDueDate(rs.getObject("due_date", java.time.LocalDate.class));
        i.setPaid(rs.getBoolean("is_paid"));
        i.setCustomerName(rs.getString("user_name"));
        return i;
    }
}
