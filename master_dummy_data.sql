-- ============================================================
-- MASTER DUMMY DATA LOADER (MERGED & OPTIMIZED)
-- ============================================================

-- 1. Initialize System State
SELECT initialize_consumption_period('2026-04-01');

-- 2. Ensure Audit Table Exists
CREATE TABLE IF NOT EXISTS rejected_cdr (
    id               SERIAL PRIMARY KEY,
    file_id          INTEGER REFERENCES file(id),
    dial_a           VARCHAR(20),
    dial_b           VARCHAR(20),
    start_time       TIMESTAMP,
    duration         INTEGER,
    service_id       INTEGER,
    rejection_reason VARCHAR(255),
    rejected_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. Register Source File
INSERT INTO file (file_path, parsed_flag) VALUES ('master_test.cdr', TRUE) ON CONFLICT DO NOTHING;

-- 4. Update core function to support auditing
CREATE OR REPLACE FUNCTION insert_cdr(
    p_file_id          INTEGER,
    p_dial_a           VARCHAR(20),
    p_dial_b           VARCHAR(20),
    p_start_time       TIMESTAMP,
    p_duration         INTEGER,
    p_service_id       INTEGER,
    p_hplmn            VARCHAR(20),
    p_vplmn            VARCHAR(20),
    p_external_charges NUMERIC(12,2)
)
RETURNS INTEGER AS $$
DECLARE
    v_new_id      INTEGER;
    v_contract_id INTEGER;
    v_status      contract_status;
BEGIN
    -- MSISDN check
    SELECT id, status INTO v_contract_id, v_status FROM contract WHERE msisdn = p_dial_a;

    -- Handle Rejections
    IF v_contract_id IS NULL THEN
        INSERT INTO rejected_cdr (file_id, dial_a, dial_b, start_time, duration, service_id, rejection_reason)
        VALUES (p_file_id, p_dial_a, p_dial_b, p_start_time, p_duration, p_service_id, 'NO_CONTRACT_FOUND');
        RETURN 0;
    END IF;

    IF v_status != 'active' THEN
        INSERT INTO rejected_cdr (file_id, dial_a, dial_b, start_time, duration, service_id, rejection_reason)
        VALUES (p_file_id, p_dial_a, p_dial_b, p_start_time, p_duration, p_service_id, 
            CASE v_status
                WHEN 'suspended' THEN 'CONTRACT_ADMIN_HOLD'
                WHEN 'suspended_debt' THEN 'CONTRACT_DEBT_HOLD'
                WHEN 'terminated' THEN 'CONTRACT_TERMINATED'
                ELSE 'CONTRACT_BLOCK'
            END);
        RETURN 0;
    END IF;

    INSERT INTO cdr (file_id, dial_a, dial_b, start_time, duration, service_id, hplmn, vplmn, external_charges, rated_flag)
    VALUES (p_file_id, p_dial_a, p_dial_b, p_start_time, p_duration, p_service_id, p_hplmn, p_vplmn, COALESCE(p_external_charges, 0), FALSE)
    RETURNING id INTO v_new_id;
    RETURN v_new_id;
END;
$$ LANGUAGE plpgsql;

-- 5. MASSIVE REAL-WORLD DATA INJECTION
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
        -- Generate Random User Data
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

        -- Pick Random RatePlan
        v_rateplan_id := (CASE 
            WHEN RANDOM() < 0.3 THEN 1 -- Basic
            WHEN RANDOM() < 0.7 THEN 2 -- Gold
            ELSE 3                     -- Elite
        END);

        -- MSISDN Generation
        v_msisdn := '201' || (100000000 + FLOOR(RANDOM() * 900000000))::TEXT;
        INSERT INTO msisdn_pool (msisdn, is_available) VALUES (v_msisdn, FALSE)
        ON CONFLICT (msisdn) DO UPDATE SET is_available = FALSE;

        -- Diverse Statuses
        v_status := (CASE 
            WHEN RANDOM() < 0.5 THEN 'active'::contract_status
            WHEN RANDOM() < 0.7 THEN 'suspended'::contract_status
            WHEN RANDOM() < 0.9 THEN 'suspended_debt'::contract_status
            ELSE 'terminated'::contract_status
        END);

        v_credit_limit := (CASE v_rateplan_id WHEN 1 THEN 200 WHEN 2 THEN 500 ELSE 1000 END);

        -- Create Contract
        SELECT id INTO v_contract_id FROM contract WHERE msisdn = v_msisdn AND status <> 'terminated';
        IF v_contract_id IS NULL THEN
            INSERT INTO contract (user_account_id, rateplan_id, msisdn, status, credit_limit, available_credit)
            VALUES (v_user_id, v_rateplan_id, v_msisdn, v_status, v_credit_limit, v_credit_limit)
            RETURNING id INTO v_contract_id;
        END IF;

        -- Randomly Add CDRs
        IF v_status = 'active' AND RANDOM() < 0.8 THEN
            FOR j IN 1..3 LOOP
                INSERT INTO cdr (file_id, dial_a, dial_b, start_time, duration, service_id, hplmn, vplmn, external_charges, rated_flag)
                VALUES (1, v_msisdn, '201090000000', '2026-04-01 10:00:00', 300, 1, 'EGYVO', NULL, 0, FALSE);
            END LOOP;
        END IF;
    END LOOP;
END $$;

-- 4. Frontend Scenario: Alice Welcome Bonus Test
INSERT INTO user_account (name, address, birthdate, role, username, password, email)
VALUES ('Alice Smith', '123 Main St, Cairo', '1990-05-15', 'customer', 'alice', '123456', 'alice@gmail.com')
ON CONFLICT (username) DO NOTHING;

DO $$
DECLARE
    v_uid INTEGER;
BEGIN
    SELECT id INTO v_uid FROM user_account WHERE username = 'alice';
    INSERT INTO contract (user_account_id, rateplan_id, msisdn, status, credit_limit, available_credit)
    VALUES (v_uid, 1, '201000000001', 'active', 200, 200)
    ON CONFLICT DO NOTHING;
END $$;

INSERT INTO cdr (file_id, dial_a, dial_b, start_time, duration, service_id, hplmn, vplmn)
VALUES (1, '201000000001', '201000000002', '2026-04-01 10:00:00', 120, 1, 'EGYVO', NULL)
ON CONFLICT DO NOTHING;

-- 5. Final Rating Run
SELECT rate_cdr(id) FROM cdr WHERE rated_flag = FALSE;

-- 5.5 SIMULATE ADDON PURCHASES
DO $$
DECLARE
    v_cid INTEGER;
BEGIN
    -- Assign Welcome Gift to about 40% of active users
    FOR v_cid IN SELECT id FROM contract WHERE status = 'active' AND RANDOM() < 0.4 LOOP
        BEGIN
            PERFORM purchase_addon(v_cid, (SELECT id FROM service_package WHERE name = '🎁 Welcome Gift' LIMIT 1));
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;

    -- Assign Roaming Addons to about 10% of users
    FOR v_cid IN SELECT id FROM contract WHERE status = 'active' AND RANDOM() < 0.1 LOOP
        BEGIN
            PERFORM purchase_addon(v_cid, (SELECT id FROM service_package WHERE name = 'Roaming Data Pack' LIMIT 1));
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END $$;

-- 6. Historical Data (March 2026) - Ensure all have some history
DO $$
DECLARE
    v_cid INTEGER;
BEGIN
    FOR v_cid IN 
        SELECT id FROM contract 
        WHERE status IN ('active', 'suspended', 'suspended_debt') 
        ORDER BY id ASC
    LOOP
        BEGIN
            PERFORM generate_bill(v_cid, '2026-03-01');
        EXCEPTION WHEN unique_violation THEN NULL;
        END;
    END LOOP;
END $$;

-- 7. Generate Bills (Leaving ~60 Missing Statements for Audit Demo)
DO $$
DECLARE
    v_cid INTEGER;
BEGIN
    FOR v_cid IN 
        SELECT id FROM contract 
        WHERE status IN ('active', 'suspended', 'suspended_debt') 
          AND NOT EXISTS (SELECT 1 FROM bill WHERE contract_id = contract.id AND billing_period_start = '2026-04-01')
        ORDER BY id ASC
        LIMIT (SELECT GREATEST(0, COUNT(*) - 60) FROM contract WHERE status IN ('active', 'suspended', 'suspended_debt'))
    LOOP
        BEGIN
            PERFORM generate_bill(v_cid, '2026-04-01');
        EXCEPTION WHEN unique_violation THEN
            NULL;
        END;
    END LOOP;
END $$;

-- ============================================================
-- DATA INJECTION COMPLETE
-- ============================================================
