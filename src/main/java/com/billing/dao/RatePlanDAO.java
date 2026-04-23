package com.billing.dao;

import com.billing.db.DB;
import com.billing.model.RatePlan;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class RatePlanDAO {

    public List<RatePlan> findAll() throws SQLException {
        List<RatePlan> list = new ArrayList<>();
        String sql = "SELECT * FROM rateplan ORDER BY id";
        try (Connection conn = DB.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) list.add(mapRow(rs));
        }
        return list;
    }

    public RatePlan findById(int id) throws SQLException {
        String sql = "SELECT * FROM rateplan WHERE id = ?";
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return mapRow(rs);
            }
        }
        return null;
    }

    public RatePlan create(RatePlan rp) throws SQLException {
        String sql = "INSERT INTO rateplan (name, ror_data, ror_voice, ror_sms, price) VALUES (?, ?, ?, ?, ?) RETURNING id";
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, rp.getName());
            ps.setDouble(2, rp.getRorData());
            ps.setDouble(3, rp.getRorVoice());
            ps.setDouble(4, rp.getRorSms());
            ps.setDouble(5, rp.getPrice());
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) rp.setId(rs.getInt(1));
            }
        }
        return rp;
    }

    private RatePlan mapRow(ResultSet rs) throws SQLException {
        RatePlan rp = new RatePlan();
        rp.setId(rs.getInt("id"));
        rp.setName(rs.getString("name"));
        rp.setRorData(rs.getBigDecimal("ror_data").doubleValue());
        rp.setRorVoice(rs.getBigDecimal("ror_voice").doubleValue());
        rp.setRorSms(rs.getBigDecimal("ror_sms").doubleValue());
        rp.setPrice(rs.getBigDecimal("price").doubleValue());
        return rp;
    }
}
