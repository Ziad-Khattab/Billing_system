package com.billing.servlet;

import com.billing.cdr.CDRGenerator;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Map;

@WebServlet("/api/admin/cdr/generate")
public class AdminCDRGeneratorServlet extends BaseServlet {

    @Override
    protected void doPost(HttpServletRequest req, HttpServletResponse res) throws IOException {
        if (!isAdmin(req)) {
            sendError(res, 403, "Admin privileges required");
            return;
        }

        handle(res, () -> {
            int count = getIntParam(req, "count", 150);
            String resultPath = CDRGenerator.generateSamples(count);
            return Map.of(
                "success", true,
                "message", "Successfully generated " + count + " realistic CDRs in the input folder.",
                "path", resultPath
            );
        });
    }
}
