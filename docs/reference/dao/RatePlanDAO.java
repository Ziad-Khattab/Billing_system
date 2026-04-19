package com.billing.dao;

import com.billing.db.DB;
import com.billing.model.RatePlan;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class RatePlanDAO {

    public List<RatePlan> findAll() {
        String sql = "SELECT * FROM rateplan ORDER BY id";
        List<RatePlan> list = new ArrayList<>();
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) list.add(mapRow(rs));
        } catch (SQLException e) { e.printStackTrace(); }
        return list;
    }

    public RatePlan findById(int id) {
        String sql = "SELECT * FROM rateplan WHERE id = ?";
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return mapRow(rs);
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return null;
    }

    public RatePlan create(RatePlan r) {
        String sql = "INSERT INTO rateplan (name, ror_data, ror_voice, ror_sms, price) " +
                     "VALUES (?, ?, ?, ?, ?) RETURNING id";
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, r.getName());
            ps.setBigDecimal(2, r.getRorData());
            ps.setBigDecimal(3, r.getRorVoice());
            ps.setBigDecimal(4, r.getRorSms());
            ps.setBigDecimal(5, r.getPrice());
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) r.setId(rs.getInt("id"));
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return r;
    }

    private RatePlan mapRow(ResultSet rs) throws SQLException {
        RatePlan r = new RatePlan();
        r.setId(rs.getInt("id"));
        r.setName(rs.getString("name"));
        r.setRorData(rs.getBigDecimal("ror_data"));
        r.setRorVoice(rs.getBigDecimal("ror_voice"));
        r.setRorSms(rs.getBigDecimal("ror_sms"));
        r.setPrice(rs.getBigDecimal("price"));
        return r;
    }
}
