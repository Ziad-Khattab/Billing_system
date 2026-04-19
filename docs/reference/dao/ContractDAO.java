package com.billing.dao;

import com.billing.db.DB;
import com.billing.model.Contract;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class ContractDAO {

    // JOIN query — pulls customer name and rateplan name for display
    private static final String SELECT_WITH_JOINS =
        "SELECT c.*, cu.name AS customer_name, r.name AS rateplan_name " +
        "FROM contract c " +
        "JOIN customer cu ON c.customer_id = cu.id " +
        "JOIN rateplan r ON c.rateplan_id = r.id";

    public List<Contract> findAll() {
        String sql = SELECT_WITH_JOINS + " ORDER BY c.id";
        List<Contract> list = new ArrayList<>();
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) list.add(mapRow(rs));
        } catch (SQLException e) { e.printStackTrace(); }
        return list;
    }

    public Contract findById(int id) {
        String sql = SELECT_WITH_JOINS + " WHERE c.id = ?";
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return mapRow(rs);
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return null;
    }

    public List<Contract> findByCustomerId(int customerId) {
        String sql = SELECT_WITH_JOINS + " WHERE c.customer_id = ? ORDER BY c.id";
        List<Contract> list = new ArrayList<>();
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, customerId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(mapRow(rs));
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return list;
    }

    public Contract create(Contract c) {
        String sql = "INSERT INTO contract (customer_id, rateplan_id, msisdn, status, credit_limit, available_credit) " +
                     "VALUES (?, ?, ?, ?::contract_status, ?, ?) RETURNING id";
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, c.getCustomerId());
            ps.setInt(2, c.getRateplanId());
            ps.setString(3, c.getMsisdn());
            ps.setString(4, c.getStatus() != null ? c.getStatus() : "active");
            ps.setBigDecimal(5, c.getCreditLimit());
            ps.setBigDecimal(6, c.getAvailableCredit());
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) c.setId(rs.getInt("id"));
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return c;
    }

    private Contract mapRow(ResultSet rs) throws SQLException {
        Contract c = new Contract();
        c.setId(rs.getInt("id"));
        c.setCustomerId(rs.getInt("customer_id"));
        c.setRateplanId(rs.getInt("rateplan_id"));
        c.setMsisdn(rs.getString("msisdn"));
        c.setStatus(rs.getString("status"));
        c.setCreditLimit(rs.getBigDecimal("credit_limit"));
        c.setAvailableCredit(rs.getBigDecimal("available_credit"));
        // JOIN fields — may not exist in every query
        try {
            c.setCustomerName(rs.getString("customer_name"));
            c.setRateplanName(rs.getString("rateplan_name"));
        } catch (SQLException ignored) {} // column not in result set
        return c;
    }
}
