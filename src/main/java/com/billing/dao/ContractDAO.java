package com.billing.dao;

import com.billing.db.DB;
import com.billing.model.Contract;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class ContractDAO {

    private static final String SELECT_WITH_JOINS = 
        "SELECT c.*, u.name AS user_name, r.name AS rateplan_name " +
        "FROM contract c " +
        "JOIN user_account u ON c.user_account_id = u.id " +
        "JOIN rateplan r ON c.rateplan_id = r.id";

    public List<Contract> findAll() throws SQLException {
        List<Contract> list = new ArrayList<>();
        try (Connection conn = DB.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(SELECT_WITH_JOINS)) {
            while (rs.next()) list.add(mapRow(rs));
        }
        return list;
    }

    public Contract findById(int id) throws SQLException {
        String sql = SELECT_WITH_JOINS + " WHERE c.id = ?";
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return mapRow(rs);
            }
        }
        return null;
    }

    public void create(Contract c) throws SQLException {
        String sql = "INSERT INTO contract (user_account_id, rateplan_id, msisdn, status, credit_limit, available_credit) " +
                     "VALUES (?, ?, ?, ?::contract_status, ?, ?)";
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, c.getUserAccountId());
            ps.setInt(2, c.getRatePlanId());
            ps.setString(3, c.getMsisdn());
            ps.setString(4, c.getStatus());
            ps.setDouble(5, c.getCreditLimit());
            ps.setDouble(6, c.getAvailableCredit());
            ps.executeUpdate();
        }
    }

    public List<Contract> findByUserId(int userId) throws SQLException {
        List<Contract> list = new ArrayList<>();
        String sql = SELECT_WITH_JOINS + " WHERE c.user_account_id = ? ORDER BY c.id";
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, userId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(mapRow(rs));
            }
        }
        return list;
    }

    private Contract mapRow(ResultSet rs) throws SQLException {
        Contract c = new Contract();
        c.setId(rs.getInt("id"));
        c.setUserAccountId(rs.getInt("user_account_id"));
        c.setRatePlanId(rs.getInt("rateplan_id"));
        c.setMsisdn(rs.getString("msisdn"));
        c.setStatus(rs.getString("status"));
        c.setCreditLimit(rs.getDouble("credit_limit"));
        c.setAvailableCredit(rs.getDouble("available_credit"));
        return c;
    }
}
