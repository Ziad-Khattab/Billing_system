package com.billing.dao;

import com.billing.db.DB;
import com.billing.model.ServicePackage;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class ServicePackageDAO {

    public List<ServicePackage> findAll() throws SQLException {
        String sql = "SELECT * FROM service_package ORDER BY id";
        List<ServicePackage> list = new ArrayList<>();
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) list.add(mapRow(rs));
        }
        return list;
    }

    public ServicePackage findById(int id) throws SQLException {
        String sql = "SELECT * FROM service_package WHERE id = ?";
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return mapRow(rs);
            }
        }
        return null;
    }

    public ServicePackage create(ServicePackage sp) throws SQLException {
        String sql = "INSERT INTO service_package (name, type, amount, priority) " +
                     "VALUES (?, ?::service_type, ?, ?) RETURNING id";
        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, sp.getName());
            ps.setString(2, sp.getType());
            ps.setBigDecimal(3, sp.getAmount());
            ps.setInt(4, sp.getPriority());
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) sp.setId(rs.getInt(1));
            }
        }
        return sp;
    }

    private ServicePackage mapRow(ResultSet rs) throws SQLException {
        ServicePackage sp = new ServicePackage();
        sp.setId(rs.getInt("id"));
        sp.setName(rs.getString("name"));
        sp.setType(rs.getString("type"));
        sp.setAmount(rs.getBigDecimal("amount"));
        sp.setPriority(rs.getInt("priority"));
        return sp;
    }
}
