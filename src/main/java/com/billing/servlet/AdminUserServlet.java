package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import java.util.Map;

@WebServlet("/api/admin/customers/*")
public class AdminUserServlet extends BaseServlet {

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            String pathParam = getPathParam(req);
            if (pathParam == null) {
                return DB.executeSelect("SELECT * FROM get_all_customers()");
            } else {
                int id = Integer.parseInt(pathParam);
                List<Map<String, Object>> list = DB.executeSelect("SELECT * FROM get_customer_by_id(?)", id);
                if (list.isEmpty()) throw new RuntimeException("Customer not found");
                return list.get(0);
            }
        });
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            Map<String, Object> data = readJson(req);
            String msisdn = (String) data.get("msisdn");
            String name = (String) data.get("name");
            String email = (String) data.get("email");
            String address = (String) data.get("address");
            String birthdate = (String) data.get("birthdate");
            if (birthdate != null && birthdate.trim().isEmpty()) birthdate = null;
            
            // Using our fixed stored function to handle 2-table insertion
            DB.executeSelect(
                "SELECT create_customer(?, ?, ?, ?, ?, ?::DATE) as id",
                msisdn, "customer123", name, email, address, birthdate
            );
            
            return Map.of("success", true, "message", "Customer created successfully");
        });
    }
}
