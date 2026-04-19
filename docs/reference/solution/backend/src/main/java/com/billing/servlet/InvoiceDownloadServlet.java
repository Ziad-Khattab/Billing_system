package com.billing.servlet;

import com.billing.dao.BillDAO;
import com.billing.dao.ContractDAO;
import com.billing.dao.CustomerDAO;
import com.billing.dao.InvoiceDAO;
import com.billing.model.AppUser;
import com.billing.model.Bill;
import com.billing.model.Contract;
import com.billing.model.Customer;
import com.billing.model.Invoice;
import com.billing.util.InvoicePDFGenerator;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;

@WebServlet("/api/customer/invoices/download")
public class InvoiceDownloadServlet extends BaseServlet {

    private final InvoiceDAO invoiceDAO = new InvoiceDAO();
    private final BillDAO billDAO = new BillDAO();
    private final CustomerDAO customerDAO = new CustomerDAO();
    private final ContractDAO contractDAO = new ContractDAO();

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
        AppUser user = (AppUser) req.getSession().getAttribute("user");
        String idParam = req.getParameter("id");

        if (idParam == null) {
            sendError(res, 400, "Missing invoice ID");
            return;
        }

        try {
            int invoiceId = Integer.parseInt(idParam);
            Invoice invoice = invoiceDAO.findById(invoiceId);

            if (invoice == null) {
                sendError(res, 404, "Invoice not found");
                return;
            }

            // Fetch all related data for the PDF
            Bill bill = billDAO.findById(invoice.getBillId());
            Contract contract = contractDAO.findById(bill.getContractId());
            Customer customer = customerDAO.findById(contract.getCustomerId());

            // Generate PDF using the full data set
            byte[] pdfBytes = InvoicePDFGenerator.generateInvoice(
                bill, 
                customer.getName(), 
                customer.getAddress(), 
                contract.getMsisdn(), 
                contract.getRateplanName()
            );

            res.setContentType("application/pdf");
            res.setHeader("Content-Disposition", "attachment; filename=Invoice_" + invoiceId + ".pdf");
            res.setContentLength(pdfBytes.length);
            res.getOutputStream().write(pdfBytes);

        } catch (Exception e) {
            e.printStackTrace();
            sendError(res, 500, "Error generating PDF: " + e.getMessage());
        }
    }
}
