package com.billing.dao;

import com.billing.db.DB;
import com.billing.model.Customer;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class CustomerDAO {

    // ─── FIND ALL ──────────────────────────────────────────
    // Returns every customer. Used by admin list page.
    public List<Customer> findAll() {
        String sql = "SELECT * FROM customer ORDER BY id";
        List<Customer> list = new ArrayList<>();

        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            // rs.next() advances to each row. Loop until no more rows.
            while (rs.next()) {
                list.add(mapRow(rs));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return list;
    }

    // ─── FIND BY ID ────────────────────────────────────────
    public Customer findById(int id) {
        String sql = "SELECT * FROM customer WHERE id = ?";

        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return mapRow(rs);
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return null;
    }

    // ─── FIND BY USER ID ──────────────────────────────────
    // Used after customer login: find their profile by their app_user.id
    public Customer findByUserId(int userId) {
        String sql = "SELECT * FROM customer WHERE user_id = ?";

        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, userId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return mapRow(rs);
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return null;
    }

    // ─── SEARCH ────────────────────────────────────────────
    // Case-insensitive partial name match. "ahm" matches "Ahmed Ali".
    public List<Customer> search(String query) {
        String sql = "SELECT * FROM customer WHERE LOWER(name) LIKE LOWER(?) ORDER BY id";
        List<Customer> list = new ArrayList<>();

        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            // % wildcards: %query% matches anywhere in the name
            ps.setString(1, "%" + query + "%");
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(mapRow(rs));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return list;
    }

    // ─── CREATE ────────────────────────────────────────────
    public Customer create(Customer c) {
        String sql = "INSERT INTO customer (name, address, email, birthdate, user_id) " +
                     "VALUES (?, ?, ?, ?, ?) RETURNING id";

        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, c.getName());
            ps.setString(2, c.getAddress());
            ps.setString(3, c.getEmail());
            // setObject handles null gracefully for nullable columns
            ps.setObject(4, c.getBirthdate());
            ps.setObject(5, c.getUserId());

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) c.setId(rs.getInt("id"));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return c;
    }

    // ─── UPDATE ────────────────────────────────────────────
    public Customer update(Customer c) {
        String sql = "UPDATE customer SET name = ?, address = ?, email = ?, birthdate = ? WHERE id = ?";

        try (Connection conn = DB.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, c.getName());
            ps.setString(2, c.getAddress());
            ps.setString(3, c.getEmail());
            ps.setObject(4, c.getBirthdate());
            ps.setInt(5, c.getId());

            int rows = ps.executeUpdate();  // returns number of rows affected
            if (rows == 0) return null;      // no customer with that ID
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return c;
    }

    // ─── MAP ROW ───────────────────────────────────────────
    private Customer mapRow(ResultSet rs) throws SQLException {
        Customer c = new Customer();
        c.setId(rs.getInt("id"));
        c.setName(rs.getString("name"));
        c.setAddress(rs.getString("address"));
        c.setEmail(rs.getString("email"));
        // getDate returns java.sql.Date → convert to LocalDate
        Date d = rs.getDate("birthdate");
        if (d != null) c.setBirthdate(d.toLocalDate());
        // getObject for nullable Integer column
        int userId = rs.getInt("user_id");
        if (!rs.wasNull()) c.setUserId(userId);
        return c;
    }
}
