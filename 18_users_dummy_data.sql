
-- =========================================================
-- BILLING SYSTEM DUMMY DATA (FULL TEST SET)
-- Restored with all 18 users, addresses, and credentials
-- =========================================================

------------------------------------------------------------
-- RESET
------------------------------------------------------------
TRUNCATE TABLE
    invoice, bill, cdr, contract_consumption, ror_contract, 
    contract, rateplan_service_package, service_package, 
    rateplan, user_account, customer, file
RESTART IDENTITY CASCADE;

------------------------------------------------------------
-- 1. CUSTOMERS (Full 18 Profiles)
------------------------------------------------------------
INSERT INTO customer (name, email, address, birthdate)
VALUES
    ('Alice Smith',    'alice@gmail.com',   '123 Main St',    '1990-01-01'),
    ('Bob Johnson',    'bob@gmail.com',     '456 Elm St',     '1985-05-15'),
    ('Carol White',    'carol@gmail.com',   '789 Oak Ave',    '1992-03-10'),
    ('David Brown',    'david@gmail.com',   '321 Pine Rd',    '1988-07-22'),
    ('Eva Green',      'eva@gmail.com',     '654 Maple Dr',   '1995-11-05'),
    ('Frank Miller',   'frank@gmail.com',   '987 Cedar Ln',   '1983-02-18'),
    ('Grace Lee',      'grace@gmail.com',   '147 Birch Blvd', '1991-09-30'),
    ('Henry Wilson',   'henry@gmail.com',   '258 Walnut St',  '1987-04-14'),
    ('Iris Taylor',    'iris@gmail.com',    '369 Spruce Ave', '1993-06-25'),
    ('Jack Davis',     'jack@gmail.com',    '741 Ash Ct',     '1986-12-03'),
    ('Karen Martinez', 'karen@gmail.com',   '852 Elm Pl',     '1994-08-17'),
    ('Leo Anderson',   'leo@gmail.com',     '963 Oak St',     '1989-01-29'),
    ('Mia Thomas',     'mia@gmail.com',     '159 Pine Ave',   '1996-05-08'),
    ('Noah Jackson',   'noah@gmail.com',    '267 Maple Rd',   '1984-10-21'),
    ('Olivia Harris',  'olivia@gmail.com',  '348 Cedar Dr',   '1997-03-15'),
    ('Paul Clark',     'paul@gmail.com',    '426 Birch Ln',   '1982-07-04'),
    ('Quinn Lewis',    'quinn@gmail.com',   '537 Walnut Blvd','1998-11-19'),
    ('Rachel Walker',  'rachel@gmail.com',  '648 Spruce St',  '1981-02-27');

------------------------------------------------------------
-- 2. USER ACCOUNTS (Linked Credentials)
------------------------------------------------------------
INSERT INTO user_account (username, password, role, customer_id)
VALUES
    ('alice',  'password1',  'customer', 1),
    ('bob',    'password2',  'customer', 2),
    ('carol',  'password3',  'customer', 3),
    ('david',  'password4',  'customer', 4),
    ('eva',    'password5',  'customer', 5),
    ('frank',  'password6',  'customer', 6),
    ('grace',  'password7',  'customer', 7),
    ('henry',  'password8',  'customer', 8),
    ('iris',   'password9',  'customer', 9),
    ('jack',   'password10', 'customer', 10),
    ('karen',  'password11', 'customer', 11),
    ('leo',    'password12', 'customer', 12),
    ('mia',    'password13', 'customer', 13),
    ('noah',   'password14', 'customer', 14),
    ('olivia', 'password15', 'customer', 15),
    ('paul',   'password16', 'customer', 16),
    ('quinn',  'password17', 'customer', 17),
    ('rachel', 'password18', 'customer', 18),
    ('admin',  'adminpass',  'admin',    NULL);

------------------------------------------------------------
-- 3. RATE PLANS
------------------------------------------------------------
INSERT INTO rateplan (name, ror_data, ror_voice, ror_sms, price, description)
VALUES
    ('Prepaid Standard',  0.10, 0.20, 0.05,  50, 'Perfect for light usage and essential connectivity.'),
    ('Premium Gold',      0.05, 0.10, 0.02, 120, 'Our most popular plan with high-speed data and roaming.'),
    ('Elite Enterprise',  0.02, 0.05, 0.01, 349, 'Ultimate performance with unlimited potential for power users.');

------------------------------------------------------------
-- 4. SERVICE PACKAGES
------------------------------------------------------------
INSERT INTO service_package (name, type, amount, priority, is_roaming, price, description)
VALUES
    ('Voice Pack', 'voice', 1000, 1, FALSE, 15.00, '1000 mins local'),
    ('Data Pack', 'data', 5000, 1, FALSE, 25.00, '5 GB local'),
    ('SMS Pack', 'sms', 200, 1, FALSE, 5.00, '200 SMS messages'),
    ('Welcome Bonus', 'free_units', 50, 2, FALSE, 0.00, 'Free 50 bonus units'),
    ('Roaming Voice', 'voice', 200, 1, TRUE, 30.00, '200 mins roaming'),
    ('Roaming Data', 'data', 1000, 1, TRUE, 45.00, '1 GB roaming'),
    ('Roaming SMS', 'sms', 50, 1, TRUE, 10.00, '50 roaming SMS');

INSERT INTO rateplan_service_package (rateplan_id, service_package_id)
VALUES (1,1), (1,3), (2,1), (2,2), (2,3), (2,4), (2,5), (2,6), (2,7), (3,1), (3,2), (3,3), (3,4), (3,5), (3,6), (3,7);

------------------------------------------------------------
-- 5. CONTRACTS (All 18 Lines Provisioned)
------------------------------------------------------------
INSERT INTO contract (customer_id, rateplan_id, msisdn, status, credit_limit, available_credit)
VALUES
    (1,  1, '201000000001', 'active', 200, 200),
    (2,  2, '201000000002', 'active', 500, 500),
    (3,  1, '201000000003', 'active', 200, 200),
    (4,  2, '201000000004', 'active', 500, 500),
    (5,  1, '201000000005', 'active', 200, 200),
    (6,  2, '201000000006', 'active', 500, 500),
    (7,  1, '201000000007', 'active', 200, 200),
    (8,  2, '201000000008', 'active', 500, 500),
    (9,  1, '201000000009', 'active', 200, 200),
    (10, 2, '201000000010', 'active', 500, 500),
    (11, 1, '201000000011', 'active', 200, 200),
    (12, 2, '201000000012', 'active', 500, 500),
    (13, 1, '201000000013', 'active', 200, 200),
    (14, 2, '201000000014', 'active', 500, 500),
    (15, 3, '201000000015', 'active', 1000, 1000),
    (16, 3, '201000000016', 'active', 1000, 1000),
    (17, 3, '201000000017', 'active', 1000, 1000),
    (18, 3, '201000000018', 'active', 1000, 1000);

------------------------------------------------------------
-- 6. USAGE TRACKERS (All 18 Initialized)
------------------------------------------------------------
INSERT INTO ror_contract (contract_id, rateplan_id)
SELECT id, rateplan_id FROM contract;

INSERT INTO contract_consumption (contract_id, service_package_id, rateplan_id, starting_date, ending_date)
SELECT c.id, rsp.service_package_id, c.rateplan_id, '2026-04-01', '2026-04-30'
FROM contract c 
JOIN rateplan_service_package rsp ON rsp.rateplan_id = c.rateplan_id;
