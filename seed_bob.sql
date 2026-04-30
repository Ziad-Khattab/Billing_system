
-- REFINED SEED DATA FOR BOB JOHNSON SCENARIO (V3)
BEGIN;

-- 1. Setup RatePlan
INSERT INTO rateplan (name, price, ror_voice, ror_data, ror_sms, ror_roaming_voice, ror_roaming_data, ror_roaming_sms)
VALUES ('Premium Gold', 370.00, 0.50, 5.00, 0.20, 25.00, 100.00, 5.00)
ON CONFLICT (name) DO UPDATE SET
    price = EXCLUDED.price,
    ror_voice = EXCLUDED.ror_voice,
    ror_data = EXCLUDED.ror_data,
    ror_sms = EXCLUDED.ror_sms,
    ror_roaming_voice = EXCLUDED.ror_roaming_voice,
    ror_roaming_data = EXCLUDED.ror_roaming_data,
    ror_roaming_sms = EXCLUDED.ror_roaming_sms;

-- 2. Setup User
INSERT INTO user_account (username, password, role, name, email, address)
VALUES ('bob_johnson', 'password123', 'customer', 'Bob Johnson', 'bob@gmail.com', '456 Elm St')
ON CONFLICT (username) DO UPDATE SET
    name = EXCLUDED.name,
    email = EXCLUDED.email,
    address = EXCLUDED.address;

-- 3. Setup Contract
INSERT INTO contract (user_account_id, rateplan_id, msisdn, status, available_credit)
SELECT ua.id, rp.id, '201000000002', 'active', 5000.00
FROM user_account ua, rateplan rp
WHERE ua.username = 'bob_johnson' AND rp.name = 'Premium Gold'
ON CONFLICT (msisdn) WHERE (status != 'terminated') DO UPDATE SET
    status = 'active',
    available_credit = 5000.00;

-- 4. Setup Consumption and Roaming
DO $$
DECLARE
    v_contract_id INTEGER;
    v_rateplan_id INTEGER;
BEGIN
    SELECT id, rateplan_id INTO v_contract_id, v_rateplan_id FROM contract WHERE msisdn = '201000000002';
    
    -- Ensure service packages exist
    INSERT INTO service_package (name, type, amount, priority, price)
    VALUES ('Voice Bundle', 'voice', 1000, 1, 0),
           ('Data Bundle', 'data', 10737418240, 1, 0) -- 10GB
    ON CONFLICT DO NOTHING;

    -- Update Voice Bundle consumption
    INSERT INTO contract_consumption (contract_id, service_package_id, rateplan_id, starting_date, ending_date, consumed, quota_limit)
    SELECT v_contract_id, sp.id, v_rateplan_id, '2026-03-01', '2026-03-31', sp.amount, sp.amount
    FROM service_package sp WHERE sp.name = 'Voice Bundle'
    ON CONFLICT (contract_id, service_package_id, rateplan_id, starting_date, ending_date) DO UPDATE SET
        consumed = EXCLUDED.consumed, quota_limit = EXCLUDED.quota_limit;

    -- Update Data Bundle consumption
    INSERT INTO contract_consumption (contract_id, service_package_id, rateplan_id, starting_date, ending_date, consumed, quota_limit)
    SELECT v_contract_id, sp.id, v_rateplan_id, '2026-03-01', '2026-03-31', sp.amount, sp.amount
    FROM service_package sp WHERE sp.name = 'Data Bundle'
    ON CONFLICT (contract_id, service_package_id, rateplan_id, starting_date, ending_date) DO UPDATE SET
        consumed = EXCLUDED.consumed, quota_limit = EXCLUDED.quota_limit;

    -- 5. Add BIG ROAMING AND OVERAGE in ror_contract
    INSERT INTO ror_contract (contract_id, rateplan_id, starting_date, voice, data, sms, roaming_voice, roaming_data, roaming_sms)
    VALUES (v_contract_id, v_rateplan_id, '2026-03-01', 
           100, -- voice overage
           5368709120, -- 5GB data overage (bytes)
           50, -- sms
           200, -- roaming voice
           10737418240, -- 10GB roaming data (bytes)
           20 -- roaming sms
    )
    ON CONFLICT (contract_id, rateplan_id, starting_date) DO UPDATE SET
        voice = EXCLUDED.voice,
        data = EXCLUDED.data,
        sms = EXCLUDED.sms,
        roaming_voice = EXCLUDED.roaming_voice,
        roaming_data = EXCLUDED.roaming_data,
        roaming_sms = EXCLUDED.roaming_sms;
END $$;

COMMIT;
