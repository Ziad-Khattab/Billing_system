-- =========================================================
-- DUMMY DATA
-- For testing and demonstration purposes
-- =========================================================

------------------------------------------------------------
-- FILES
------------------------------------------------------------
INSERT INTO file (parsed_flag, file_path)
VALUES
    (FALSE, '/tmp/test_cdr_april_1.csv'),
    (FALSE, '/tmp/test_cdr_april_2.csv');

------------------------------------------------------------
-- user_accounts
------------------------------------------------------------
INSERT INTO user_account (name, address, birthdate, role, username, password)
VALUES
    ('Alice Smith', '123 Main St', '1990-01-01', 'customer', 'alice', 'password1'),
    ('Bob Johnson', '456 Elm St', '1985-05-15', 'customer', 'bob', 'password2');

------------------------------------------------------------
-- RATEPLANS
------------------------------------------------------------
INSERT INTO rateplan (name, ror_data, ror_voice, ror_sms, price)
VALUES
    ('Basic',   0.10, 0.20, 0.05, 50),
    ('Premium', 0.05, 0.10, 0.02, 120);

------------------------------------------------------------
-- SERVICE PACKAGES
------------------------------------------------------------
INSERT INTO service_package (name, type, amount, priority)
VALUES
    ('Voice Pack',   'voice', 1000, 1),
    ('Data Pack',    'data',  5000, 1),
    ('SMS Pack',     'sms',    200, 1),
    ('Welcome Bonus','free_units', 50, 2);

------------------------------------------------------------
-- RATEPLAN → PACKAGES
------------------------------------------------------------
INSERT INTO rateplan_service_package (rateplan_id, service_package_id)
VALUES
    (1, 1), (1, 3),
    (2, 1), (2, 2), (2, 3), (2, 4);

------------------------------------------------------------
-- CONTRACTS
------------------------------------------------------------
INSERT INTO contract (user_account_id, rateplan_id, msisdn, status, credit_limit, available_credit)
VALUES
    (1, 1, '201000000001', 'active', 200, 200),
    (2, 2, '201000000002', 'active', 500, 500);

------------------------------------------------------------
-- ROR_CONTRACT
------------------------------------------------------------
INSERT INTO ror_contract (contract_id, rateplan_id, data, voice, sms)
VALUES
    (1, 1, 10, 20, 5),
    (2, 2,  5, 10, 2);

------------------------------------------------------------
-- CONTRACT_CONSUMPTION (CURRENT PERIOD = APRIL 2026)
------------------------------------------------------------
INSERT INTO contract_consumption (
    contract_id, service_package_id, rateplan_id,
    starting_date, ending_date, consumed, is_billed
) VALUES
      -- Contract 1 (Basic)
      (1, 1, 1, '2026-04-01', '2026-04-30', 120, FALSE),
      (1, 3, 1, '2026-04-01', '2026-04-30', 15,  FALSE),

      -- Contract 2 (Premium)
      (2, 1, 2, '2026-04-01', '2026-04-30', 300, FALSE),
      (2, 2, 2, '2026-04-01', '2026-04-30', 800, FALSE),
      (2, 3, 2, '2026-04-01', '2026-04-30', 40,  FALSE),
      (2, 4, 2, '2026-04-01', '2026-04-30', 10,  FALSE);

------------------------------------------------------------
-- BILL (PREVIOUS PERIOD = MARCH 2026)
------------------------------------------------------------
INSERT INTO bill (
    contract_id, billing_period_start, billing_period_end, billing_date,
    recurring_fees, one_time_fees,
    voice_usage, data_usage, sms_usage,
    ROR_charge, taxes, total_amount, status, is_paid
)
VALUES
    (1, '2026-03-01', '2026-03-31', '2026-04-01',
     50, 0,
     200, 0, 20,
     12.0, 5.0, 67.0, 'issued', FALSE),

    (2, '2026-03-01', '2026-03-31', '2026-04-01',
     120, 0,
     400, 1200, 60,
     25.0, 10.0, 155.0, 'issued', FALSE);

------------------------------------------------------------
-- INVOICES
------------------------------------------------------------
INSERT INTO invoice (bill_id, pdf_path)
VALUES
    (1, '/tmp/invoice_march_1.pdf'),
    (2, '/tmp/invoice_march_2.pdf');
