-- ============================================================
-- MASSIVE REAL-WORLD DUMMY DATA INJECTION
-- Total: 100+ Customers, 100+ Contracts, 300+ Rated CDRs, 100+ Bills
-- Targets: Dashboard Stats & Demo Realism
-- ============================================================

DO $$
DECLARE
    v_user_id INTEGER;
    v_msisdn VARCHAR(20);
    v_rateplan_id INTEGER;
    v_contract_id INTEGER;
    v_status contract_status;
    v_credit_limit NUMERIC;
    v_first_names TEXT[] := ARRAY['Ahmed', 'Mohamed', 'Sara', 'Mona', 'Hassan', 'Youssef', 'Layla', 'Omar', 'Nour', 'Amir', 'Ziad', 'Mariam', 'Fatma', 'Ibrahim', 'Salma', 'Khaled', 'Dina', 'Tarek', 'Hala', 'Sameh'];
    v_last_names TEXT[]  := ARRAY['Hassan', 'Mansour', 'Zaki', 'Khattab', 'Fouad', 'Salem', 'Nasr', 'Said', 'Gaber', 'Ezzat', 'Wahba', 'Soliman', 'Badawi', 'Moussa', 'Hamad'];
    v_streets TEXT[]     := ARRAY['El-Nasr St', 'Cornish Rd', '9th Street', 'Tahrir Sq', 'Abbas El Akkad', 'Makram Ebeid', 'Gameat El Dowal', 'Zamalek Dr', 'Maadi St'];
    v_cities TEXT[]      := ARRAY['Cairo', 'Giza', 'Alexandria', 'Mansoura', 'Suez', 'Luxor', 'Aswan', 'Hurghada'];
    v_fname TEXT;
    v_lname TEXT;
    v_uname TEXT;
    v_i INTEGER;
BEGIN
    RAISE NOTICE 'Starting Massive Data Injection...';

    FOR v_i IN 1..150 LOOP
        -- 1. Generate Random User Data
        v_fname := v_first_names[1 + FLOOR(RANDOM() * ARRAY_LENGTH(v_first_names, 1))];
        v_lname := v_last_names[1 + FLOOR(RANDOM() * ARRAY_LENGTH(v_last_names, 1))];
        v_uname := LOWER(v_fname) || '_' || v_i || '_' || (1000 + FLOOR(RANDOM() * 9000));

        INSERT INTO user_account (name, address, birthdate, role, username, password, email)
        VALUES (
            v_fname || ' ' || v_lname,
            (10 + FLOOR(RANDOM() * 90)) || ' ' || v_streets[1 + FLOOR(RANDOM() * ARRAY_LENGTH(v_streets, 1))] || ', ' || v_cities[1 + FLOOR(RANDOM() * ARRAY_LENGTH(v_cities, 1))],
            '1970-01-01'::DATE + (FLOOR(RANDOM() * 15000) || ' days')::INTERVAL,
            'customer',
            v_uname,
            '123456',
            v_uname || '@fmrz-telecom.com'
        ) ON CONFLICT (username) DO NOTHING 
        RETURNING id INTO v_user_id;

        IF v_user_id IS NULL THEN
            SELECT id INTO v_user_id FROM user_account WHERE username = v_uname;
        END IF;

        -- 2. Pick Random RatePlan (30% Basic, 40% Gold, 30% Elite)
        v_rateplan_id := (CASE 
            WHEN RANDOM() < 0.3 THEN 1 -- Basic
            WHEN RANDOM() < 0.7 THEN 2 -- Gold
            ELSE 3                     -- Elite
        END);

        -- 3. MSISDN Generation (Randomized range to avoid collisions)
        v_msisdn := '201' || (100000000 + FLOOR(RANDOM() * 900000000))::TEXT;
        INSERT INTO msisdn_pool (msisdn, is_available) VALUES (v_msisdn, FALSE)
        ON CONFLICT (msisdn) DO UPDATE SET is_available = FALSE;

        -- 4. Diverse Statuses (50% Active, 20% Suspended, 20% Debt, 10% Terminated)
        v_status := (CASE 
            WHEN RANDOM() < 0.5 THEN 'active'::contract_status
            WHEN RANDOM() < 0.7 THEN 'suspended'::contract_status
            WHEN RANDOM() < 0.9 THEN 'suspended_debt'::contract_status
            ELSE 'terminated'::contract_status
        END);

        v_credit_limit := (CASE v_rateplan_id WHEN 1 THEN 200 WHEN 2 THEN 500 ELSE 1000 END);

        -- 5. Create Contract (Manual check because of partial index)
        SELECT id INTO v_contract_id FROM contract WHERE msisdn = v_msisdn AND status <> 'terminated';
        
        IF v_contract_id IS NULL THEN
            INSERT INTO contract (user_account_id, rateplan_id, msisdn, status, credit_limit, available_credit)
            VALUES (v_user_id, v_rateplan_id, v_msisdn, v_status, v_credit_limit, v_credit_limit)
            RETURNING id INTO v_contract_id;
        END IF;

        -- 6. Randomly Add CDRs for some of these new contracts (simulating traffic)
        IF v_status = 'active' AND RANDOM() < 0.8 THEN
            FOR j IN 1..3 LOOP
                INSERT INTO cdr (file_id, dial_a, dial_b, start_time, duration, service_id, hplmn, vplmn, external_charges, rated_flag)
                VALUES (1, v_msisdn, '201090000000', '2026-04-01 10:00:00', 300, 1, 'EGYVO', NULL, 0, FALSE);
            END LOOP;
        END IF;
    END LOOP;

    RAISE NOTICE '150 Customers & Contracts created successfully.';
END $$;

-- Run Rating Engine for new CDRs
SELECT rate_cdr(id) FROM cdr WHERE rated_flag = FALSE;

-- ============================================================
-- GENERATE BILLS (EXCLUDING SOME FOR AUDIT)
-- ============================================================
-- We only generate bills for 80% of billable contracts to leave some for the Audit Demo
DO $$
DECLARE
    v_cid INTEGER;
BEGIN
    FOR v_cid IN 
        SELECT id FROM contract 
        WHERE status IN ('active', 'suspended', 'suspended_debt') 
          AND NOT EXISTS (SELECT 1 FROM bill WHERE contract_id = contract.id AND billing_period_start = '2026-04-01')
          AND RANDOM() < 0.8  -- 20% will be missing
    LOOP
        PERFORM generate_bill(v_cid, '2026-04-01');
    END LOOP;
END $$;

DO $$
BEGIN
    RAISE NOTICE 'Massive Data Injection Complete. Dashboard should now show 140+ Contracts.';
END $$;
