package com.billing.servlet;

import com.billing.db.DB;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import java.util.Map;

@WebServlet("/api/customer/onboarding/*")
public class CustomerOnboardingServlet extends BaseServlet {

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            String path = req.getPathInfo();

            // GET /api/customer/onboarding/msisdns
            if ("/msisdns".equals(path)) {
                return DB.executeSelect("SELECT * FROM get_available_msisdns()");
            }

            // GET /api/customer/onboarding/rateplans
            if ("/rateplans".equals(path)) {
                return DB.executeSelect("SELECT * FROM get_all_rateplans()");
            }

            throw new RuntimeException("Unknown endpoint: " + path);
        });
    }

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        handle(res, () -> {
            // POST /api/customer/onboarding/activate
            // Body: { msisdn, ratePlanId, creditLimit }
            Map<String, Object> user = (Map<String, Object>)
                    req.getSession().getAttribute("user");

            if (user == null) throw new RuntimeException("Not logged in");

            int userId = ((Number) user.get("id")).intValue();
            Map<String, Object> body = readJson(req);

            String msisdn      = (String) body.get("msisdn");
            int    ratePlanId  = ((Number) body.get("ratePlanId")).intValue();
            double creditLimit = body.get("creditLimit") != null
                    ? ((Number) body.get("creditLimit")).doubleValue()
                    : 100.0; // default credit limit

            // Check user doesn't already have a contract
            List<Map<String, Object>> existing = DB.executeSelect(
                    "SELECT id FROM contract WHERE user_account_id = ?", userId);
            if (!existing.isEmpty()) {
                throw new RuntimeException("You already have an active contract");
            }
            System.out.println("[Onboarding] userId from session: " + userId);
            System.out.println("[Onboarding] ratePlanId: " + ratePlanId);
            System.out.println("[Onboarding] msisdn: " + msisdn);
            List<Map<String, Object>> result = DB.executeSelect(

                    "SELECT create_contract(?, ?, ?, ?) AS id",
                    userId, ratePlanId, msisdn, creditLimit
            );

            int contractId = ((Number) result.get(0).get("id")).intValue();
            return Map.of(
                    "success", true,
                    "contractId", contractId,
                    "msisdn", msisdn,
                    "message", "Your number has been activated!"
            );
        });
    }
}