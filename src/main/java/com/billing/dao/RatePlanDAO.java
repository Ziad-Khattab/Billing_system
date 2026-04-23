package com.billing.dao;

import com.billing.db.DB;
import com.billing.model.RatePlan;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class RatePlanDAO {

    public List<RatePlan> findAll() throws SQLException {
        List<RatePlan> list = new ArrayList<>();
        String sql = "SELECT * FROM rateplan";
        try (Connection conn = DB.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) list.add(mapRow(rs));
        }
        return list;
    }

    private RatePlan mapRow(ResultSet rs) throws SQLException {
        RatePlan rp = new RatePlan();
        rp.setId(rs.getInt("id"));
        rp.setName(rs.getString("name"));
        // Handling BigDecimal to double conversion for numerical precision
        rp.setRorData(rs.getBigDecimal("ror_data").doubleValue());
        rp.setRorVoice(rs.getBigDecimal("ror_voice").doubleValue());
        rp.setRorSms(rs.getBigDecimal("ror_sms").doubleValue());
        rp.setPrice(rs.getBigDecimal("price").doubleValue());
        return rp;
    }
}
