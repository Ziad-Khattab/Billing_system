-- ============================================================
-- TELECOM BILLING SCHEMA
-- ============================================================
DROP TABLE IF EXISTS cdr,invoice,bill,ror_contract,contract_consumption,contract_addon,contract,rateplan_service_package,service_package,rateplan,msisdn_pool,user_account,file CASCADE;
DROP TYPE IF EXISTS service_type,contract_status,bill_status,user_role CASCADE;
-- ------------------------------------------------------------
-- FILE (raw CDR file ingestion tracker)
-- ------------------------------------------------------------
CREATE TABLE file (
                      id          SERIAL PRIMARY KEY,
                      parsed_flag BOOLEAN NOT NULL DEFAULT FALSE,
                      file_path   TEXT NOT NULL
);

-- ------------------------------------------------------------
-- USER
-- ------------------------------------------------------------
CREATE TYPE user_role AS ENUM ('admin', 'customer');
CREATE TABLE user_account (
                              id       SERIAL PRIMARY KEY,
                              username VARCHAR(255) NOT NULL UNIQUE,
                              password VARCHAR(30) NOT NULL,
                              role     user_role NOT NULL,
                              name     VARCHAR(255) NOT NULL,
                              email    VARCHAR(255) NOT NULL UNIQUE,
                              address  TEXT,
                              birthdate DATE
);

-- ------------------------------------------------------------
-- MSISDN POOL
-- ------------------------------------------------------------
CREATE TABLE msisdn_pool (
                             id          SERIAL PRIMARY KEY,
                             msisdn      VARCHAR(20) NOT NULL UNIQUE,
                             is_available BOOLEAN NOT NULL DEFAULT TRUE
);

-- ------------------------------------------------------------
-- CUSTOMER
-- ------------------------------------------------------------
-- CREATE TABLE customer (
--                           id        SERIAL PRIMARY KEY,
--                           name      VARCHAR(255) NOT NULL,
--                           address   TEXT,
--                           birthdate DATE
-- );
-- ALTER TABLE customer
--     ADD COLUMN user_account_id INTEGER REFERENCES user_account(id);

-- ------------------------------------------------------------
-- RATEPLAN
-- ------------------------------------------------------------
CREATE TABLE rateplan (
                          id        SERIAL PRIMARY KEY,
                          name      VARCHAR(255) NOT NULL,
                          ror_data  NUMERIC(10,2),     -- e.g. 0.05
                          ror_voice NUMERIC(10,2),     -- e.g. 0.05
                          ror_sms   NUMERIC(10,2),     -- e.g. 0.05
                          ror_roaming_data  NUMERIC(10,2),
                          ror_roaming_voice NUMERIC(10,2),
                          ror_roaming_sms   NUMERIC(10,2),
                          price     NUMERIC(10,2)      -- base price of the plan
);

-- ------------------------------------------------------------
-- SERVICE_PACKAGE
-- bundled quotas sold as part of a contract
-- ------------------------------------------------------------
CREATE TYPE service_type AS ENUM ('voice', 'data', 'sms', 'free_units');
CREATE TABLE service_package (
                                 id       SERIAL PRIMARY KEY,
                                 name     VARCHAR(255) NOT NULL,
                                 type     service_type  NOT NULL,  -- 'voice', 'data', 'sms', etc.
                                 amount   NUMERIC(12,4) NOT NULL, -- quota amount (minutes / MB / count)
                                 priority INTEGER NOT NULL DEFAULT 1, -- for consumption order (lower = consumed first)
                                 price    NUMERIC(12,2),
                                 is_roaming BOOLEAN NOT NULL DEFAULT FALSE,
                                 description TEXT
);
-- ------------------------------------------------------------
-- RATEPLAN SERVICE PACKAGES
-- ------------------------------------------------------------
CREATE TABLE rateplan_service_package (
                                          rateplan_id        INTEGER NOT NULL REFERENCES rateplan(id),
                                          service_package_id INTEGER NOT NULL REFERENCES service_package(id),
                                          PRIMARY KEY (rateplan_id, service_package_id)
);
-- ------------------------------------------------------------
-- CONTRACT
-- ties a customer to a rateplan + an MSISDN (phone number)
-- ------------------------------------------------------------
CREATE TYPE contract_status AS ENUM ('active', 'suspended', 'suspended_debt', 'terminated');
CREATE TABLE contract (
                          id              SERIAL PRIMARY KEY,
                          user_account_id     INTEGER NOT NULL REFERENCES user_account(id),
                          rateplan_id     INTEGER NOT NULL REFERENCES rateplan(id),
                          msisdn          VARCHAR(20) NOT NULL,
                          status          contract_status NOT NULL DEFAULT 'active',
                          credit_limit    NUMERIC(12,2) NOT NULL DEFAULT 0,
                          available_credit NUMERIC(12,2) NOT NULL DEFAULT 0
);

-- ------------------------------------------------------------
-- CONTRACT_CONSUMPTION
-- tracks how much of each service_package has been consumed
-- in a billing period for a contract
-- ------------------------------------------------------------
CREATE TABLE contract_consumption (
                                      contract_id         INTEGER NOT NULL REFERENCES contract(id),
                                      service_package_id  INTEGER NOT NULL REFERENCES service_package(id),
                                      rateplan_id         INTEGER NOT NULL REFERENCES rateplan(id),

                                      starting_date       DATE NOT NULL,
                                      ending_date         DATE NOT NULL,

                                      consumed            NUMERIC(12,4) NOT NULL DEFAULT 0,
                                      quota_limit         NUMERIC(12,4) NOT NULL DEFAULT 0,
                                      is_billed           BOOLEAN NOT NULL DEFAULT FALSE,

                                      PRIMARY KEY (contract_id, service_package_id, rateplan_id, starting_date, ending_date)
);

-- ------------------------------------------------------------
-- ROR_CONTRACT
-- Think of it as: "for this contract, these are the applied rates"
-- ------------------------------------------------------------
CREATE TABLE ror_contract (
                              contract_id INTEGER NOT NULL REFERENCES contract(id),
                              rateplan_id INTEGER NOT NULL REFERENCES rateplan(id),
                              starting_date DATE NOT NULL DEFAULT DATE_TRUNC('month', CURRENT_DATE)::DATE,
                              data        BIGINT DEFAULT 0,
                              voice       NUMERIC(12,2) DEFAULT 0,
                              sms         BIGINT DEFAULT 0,
                              roaming_voice NUMERIC(12,2) DEFAULT 0.00,
                              roaming_data BIGINT DEFAULT 0,
                              roaming_sms  BIGINT DEFAULT 0,
                              PRIMARY KEY (contract_id, rateplan_id, starting_date)
);

-- ------------------------------------------------------------
-- BILL
-- one bill per billing cycle per contract
-- ------------------------------------------------------------
CREATE TYPE bill_status AS ENUM ('draft', 'issued', 'paid', 'overdue', 'cancelled');

CREATE TABLE bill (
                      id                   SERIAL PRIMARY KEY,
                      contract_id          INTEGER NOT NULL REFERENCES contract(id),
                      billing_period_start DATE NOT NULL,
                      billing_period_end   DATE NOT NULL,
                      billing_date         DATE NOT NULL,
                      recurring_fees       NUMERIC(12,2) NOT NULL DEFAULT 0,
                      one_time_fees        NUMERIC(12,2) NOT NULL DEFAULT 0,
                      voice_usage          INTEGER       NOT NULL DEFAULT 0,  -- minutes
                      data_usage           INTEGER       NOT NULL DEFAULT 0,  -- MB
                      sms_usage            INTEGER       NOT NULL DEFAULT 0,  -- count
                      ROR_charge           NUMERIC(12,2) NOT NULL DEFAULT 0,
                      overage_charge       NUMERIC(12,2) NOT NULL DEFAULT 0,
                      roaming_charge       NUMERIC(12,2) NOT NULL DEFAULT 0,
                      promotional_discount NUMERIC(12,2) NOT NULL DEFAULT 0,
                      taxes                NUMERIC(12,2) NOT NULL DEFAULT 0,
                      total_amount         NUMERIC(12,2) NOT NULL DEFAULT 0,
                      status               bill_status   NOT NULL DEFAULT 'draft',
                      is_paid              BOOLEAN       NOT NULL DEFAULT FALSE,

                      UNIQUE (contract_id, billing_period_start)
);

-- Now we can add the FK from ror_contract -> bill
ALTER TABLE ror_contract
    ADD COLUMN bill_id INTEGER REFERENCES bill(id);
ALTER TABLE contract_consumption
    ADD COLUMN bill_id INTEGER REFERENCES bill(id);
-- ------------------------------------------------------------
-- INVOICE
-- generated PDF invoice derived from a bill
-- ------------------------------------------------------------
CREATE TABLE invoice (
                         id               SERIAL PRIMARY KEY,
                         bill_id          INTEGER NOT NULL UNIQUE REFERENCES bill(id),
                         pdf_path         TEXT,
                         generation_date  TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- REJECTED CDR
-- ------------------------------------------------------------
CREATE TABLE rejected_cdr (
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

-- ------------------------------------------------------------
-- CDR (Call Detail Record)
-- raw usage event; parsed from file, rated against rateplan
-- ------------------------------------------------------------
CREATE TABLE cdr (
                      id               SERIAL PRIMARY KEY,
                      file_id          INTEGER NOT NULL REFERENCES file(id),
                      dial_a           VARCHAR(20) NOT NULL,  -- calling party MSISDN
                      dial_b           VARCHAR(20) NOT NULL,  -- called party MSISDN
                      start_time       TIMESTAMP NOT NULL,
                      duration         INTEGER NOT NULL DEFAULT 0,  -- seconds
                      service_id       INTEGER REFERENCES service_package(id),
                      hplmn            VARCHAR(20),   -- Home PLMN code
                      vplmn            VARCHAR(20),   -- Visited PLMN code (roaming)
                      external_charges NUMERIC(12,2) NOT NULL DEFAULT 0,
                      rated_flag       BOOLEAN NOT NULL DEFAULT FALSE,
                      rated_service_id INTEGER
);

-- ------------------------------------------------------------
-- CUSTOMER ADD-ONS
-- Tracks extra service packages purchased by a customer
-- on top of their existing contract/rateplan
-- ------------------------------------------------------------
CREATE TABLE contract_addon (
                                id                 SERIAL PRIMARY KEY,
                                contract_id        INTEGER NOT NULL REFERENCES contract(id),
                                service_package_id INTEGER NOT NULL REFERENCES service_package(id),
                                purchased_date     DATE NOT NULL DEFAULT CURRENT_DATE,
                                expiry_date        DATE NOT NULL,
                                is_active          BOOLEAN NOT NULL DEFAULT TRUE,
                                price_paid         NUMERIC(12,2) NOT NULL DEFAULT 0
);


-- ============================================================
-- INDEXES (performance basics)
-- ============================================================
CREATE INDEX idx_cdr_rated_flag     ON cdr(rated_flag);
CREATE INDEX idx_cdr_file_id        ON cdr(file_id);
CREATE INDEX idx_cdr_dial_a         ON cdr(dial_a);
-- Partial unique index: recycled MSISDNs can be reassigned to new contracts
-- once the old contract is terminated (status = 'terminated')
CREATE UNIQUE INDEX IF NOT EXISTS contract_msisdn_active_idx ON contract (msisdn) WHERE (status != 'terminated');
CREATE INDEX idx_contract_user_account  ON contract(user_account_id);
CREATE INDEX idx_bill_contract      ON bill(contract_id);
CREATE INDEX idx_bill_billing_date  ON bill(billing_date);
CREATE INDEX idx_invoice_bill       ON invoice(bill_id);
CREATE INDEX idx_addon_contract ON contract_addon(contract_id);
CREATE INDEX idx_addon_active   ON contract_addon(contract_id, is_active);
-- ============================================================
-- FUNCTIONS (for billing calculations, etc.)
-- ============================================================

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

-- ------------------------------------------------------------
-- Get normalised usage amount from CDR based on service type
-- voice      -> seconds to minutes
-- data       -> already in MB
-- sms        -> always 1 per CDR
-- free_units -> treated as 1 unit for simplicity, but could be extended with more logic
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_cdr_usage_amount(
    p_duration     INTEGER,
    p_service_type service_type
)
RETURNS NUMERIC AS $$
BEGIN
RETURN CASE p_service_type
           WHEN 'voice' THEN CEIL(p_duration / 60.0)  -- convert seconds to minutes, round up
           WHEN 'data'  THEN p_duration
           WHEN 'sms'   THEN 1
           WHEN 'free_units' THEN p_duration
    END;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- CORE FUNCTIONS
-- ============================================================

-- ------------------------------------------------------------
-- SET PARSED FLAG IN FILE
-- ------------------------------------------------------------
   CREATE OR REPLACE FUNCTION set_file_parsed(p_file_id INTEGER)
RETURNS VOID AS $$
BEGIN
UPDATE file
SET parsed_flag = TRUE
WHERE id = p_file_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'set_file_parsed failed for file id %: %', p_file_id, SQLERRM;
END;
$$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- CREATE FILE RECORD
-- ------------------------------------------------------------

   CREATE OR REPLACE FUNCTION create_file_record(p_file_path TEXT)
          RETURNS INTEGER AS $$
          DECLARE v_new_id INTEGER;
BEGIN
INSERT INTO file (file_path) VALUES (p_file_path)
    RETURNING id INTO v_new_id;
RETURN v_new_id;
EXCEPTION
    WHEN OTHERS THEN
RAISE EXCEPTION 'create_file_record failed for file path %: %', p_file_path, SQLERRM;
END;
$$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- INSERT CDR
-- ------------------------------------------------------------
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
    -- 1. Validate file exists
    IF NOT EXISTS (SELECT 1 FROM file WHERE id = p_file_id) THEN
        RAISE EXCEPTION 'File with id % does not exist', p_file_id;
    END IF;

    -- 2. Validate service_package exists if provided
    IF p_service_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM service_package WHERE id = p_service_id
    ) THEN
        RAISE EXCEPTION 'Service package with id % does not exist', p_service_id;
    END IF;

    -- 3. Check for MSISDN Contract Status
    SELECT id, status INTO v_contract_id, v_status
    FROM contract 
    WHERE msisdn = p_dial_a;

    -- 4. REJECTION LOGIC: Handle missing or non-active contracts gracefully
    IF v_contract_id IS NULL THEN
        INSERT INTO rejected_cdr (file_id, dial_a, dial_b, start_time, duration, service_id, rejection_reason)
        VALUES (p_file_id, p_dial_a, p_dial_b, p_start_time, p_duration, p_service_id, 'NO_CONTRACT_FOUND');
        RETURN 0; -- Success (Graceful Rejection)
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
        RETURN 0; -- Success (Graceful Rejection)
    END IF;

    -- 5. Standard CDR Insertion (Proceed to Rating)
    INSERT INTO cdr (
        file_id, dial_a, dial_b, start_time, duration, 
        service_id, hplmn, vplmn, external_charges, rated_flag
    )
    VALUES (
        p_file_id, p_dial_a, p_dial_b, p_start_time, p_duration,
        p_service_id, p_hplmn, p_vplmn, COALESCE(p_external_charges, 0), FALSE
    )
    RETURNING id INTO v_new_id;

    RETURN v_new_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'insert_cdr failed: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- PURCHASE ADD-ON
-- Allows dynamic purchase of service packages (Top-ups).
-- Deducts price from credit and updates quota stacking.
-- [RULE] Welcome Bonus is restricted to once per customer.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION purchase_addon(
    p_contract_id        INTEGER,
    p_service_package_id INTEGER
)
    RETURNS INTEGER AS $$
DECLARE
    v_addon_id     INTEGER;
    v_pkg_price    NUMERIC(12,2);
    v_pkg_amount   NUMERIC(12,4);
    v_pkg_type     service_type;
    v_expiry       DATE;
    v_period_start DATE;
    v_period_end   DATE;
BEGIN
    -- Validate contract exists and is active
    IF NOT EXISTS (
        SELECT 1 FROM contract WHERE id = p_contract_id AND status = 'active'
    ) THEN
        RAISE EXCEPTION 'Contract % is not active', p_contract_id;
    END IF;

    -- Validate service package exists
    SELECT price, amount, type
    INTO v_pkg_price, v_pkg_amount, v_pkg_type
    FROM service_package
    WHERE id = p_service_package_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Service package % not found', p_service_package_id;
    END IF;

    -- [RULE] Welcome Bonus is only once per lifetime per customer (across all their lines)
    IF EXISTS (
        SELECT 1 FROM service_package sp
        WHERE sp.id = p_service_package_id AND sp.name = '🎁 Welcome Gift'
    ) AND EXISTS (
        SELECT 1 FROM contract_addon ca
        JOIN service_package sp ON ca.service_package_id = sp.id
        JOIN contract c ON ca.contract_id = c.id
        WHERE c.user_account_id = (SELECT user_account_id FROM contract WHERE id = p_contract_id)
          AND sp.name = '🎁 Welcome Gift'
    ) THEN
        RAISE EXCEPTION 'Welcome Bonus can only be provisioned once per customer';
    END IF;

    -- Check customer has enough credit
    IF NOT EXISTS (
        SELECT 1 FROM contract
        WHERE id = p_contract_id
          AND available_credit >= COALESCE(v_pkg_price, 0)
    ) THEN
        RAISE EXCEPTION 'Insufficient credit to purchase add-on';
    END IF;

    -- Expiry = end of current billing month
    v_expiry := (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE;

    -- Insert addon record
    INSERT INTO contract_addon (
        contract_id, service_package_id,
        purchased_date, expiry_date,
        is_active, price_paid
    ) VALUES (
                 p_contract_id, p_service_package_id,
                 CURRENT_DATE, v_expiry,
                 TRUE, COALESCE(v_pkg_price, 0)
             ) RETURNING id INTO v_addon_id;

    -- Deduct price from available credit
    UPDATE contract
    SET available_credit = available_credit - COALESCE(v_pkg_price, 0)
    WHERE id = p_contract_id;

    -- Update or Insert consumption row
    v_period_start := DATE_TRUNC('month', CURRENT_DATE)::DATE;
    v_period_end   := v_expiry;

    INSERT INTO contract_consumption (
        contract_id, service_package_id, rateplan_id,
        starting_date, ending_date, consumed, quota_limit, is_billed
    )
    SELECT
        p_contract_id,
        p_service_package_id,
        c.rateplan_id,
        v_period_start,
        v_period_end,
        0,
        v_pkg_amount,
        FALSE
    FROM contract c
    WHERE c.id = p_contract_id
    ON CONFLICT (contract_id, service_package_id, rateplan_id, starting_date, ending_date)
    DO UPDATE SET quota_limit = contract_consumption.quota_limit + EXCLUDED.quota_limit;

    RETURN v_addon_id;
END;
$$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- RATE CDR
-- Deducts usage from bundles in priority order,
-- writes any overage to ror_contract,
-- deducts overage charge from available_credit.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION rate_cdr(p_cdr_id INTEGER)
 RETURNS void
AS $$
 DECLARE
     v_cdr RECORD;
     v_contract RECORD;
     v_service_type VARCHAR;
     v_bundle RECORD;
     v_remaining NUMERIC;
     v_deduct NUMERIC;
     v_available NUMERIC;
     v_ror_rate NUMERIC;
     v_ror_rate_v NUMERIC;
     v_ror_rate_d NUMERIC;
     v_ror_rate_s NUMERIC;
     v_overage_charge NUMERIC := 0;
     v_rated_service_id INTEGER;
     v_is_roaming BOOLEAN;
     v_period_start DATE;
 BEGIN
     SELECT * INTO v_cdr FROM cdr WHERE id = p_cdr_id;
     
     -- Only rate for ACTIVE contracts
     SELECT * INTO v_contract FROM contract WHERE msisdn = v_cdr.dial_a AND status = 'active';
     
     IF NOT FOUND THEN
         UPDATE cdr SET rated_flag = TRUE, external_charges = 0, rated_service_id = NULL WHERE id = p_cdr_id;
         RETURN;
     END IF;

     SELECT type::TEXT INTO v_service_type FROM service_package WHERE id = v_cdr.service_id;
     v_remaining := get_cdr_usage_amount(v_cdr.duration, v_service_type::service_type);
     v_is_roaming := (v_cdr.vplmn IS NOT NULL AND v_cdr.vplmn != '');

     -- Determine billing period for this CDR
     v_period_start := DATE_TRUNC('month', v_cdr.start_time)::DATE;

     FOR v_bundle IN
         SELECT cc.contract_id, cc.service_package_id, cc.rateplan_id, cc.consumed, cc.quota_limit, sp.name, sp.is_roaming as pkg_roaming
         FROM contract_consumption cc
         JOIN service_package sp ON cc.service_package_id = sp.id
         WHERE cc.contract_id = v_contract.id AND cc.is_billed = FALSE
           AND cc.starting_date = v_period_start
           AND (sp.type::TEXT = v_service_type OR sp.type::TEXT = 'free_units')
           AND (sp.is_roaming = v_is_roaming OR sp.type::TEXT = 'free_units')
         ORDER BY sp.priority ASC
       LOOP
          EXIT WHEN v_remaining <= 0;
          v_available := v_bundle.quota_limit - v_bundle.consumed;
          IF v_available <= 0 THEN CONTINUE; END IF;
          v_deduct := LEAST(v_remaining, v_available);
          v_remaining := v_remaining - v_deduct;

          UPDATE contract_consumption
          SET consumed = consumed + v_deduct
          WHERE contract_id = v_bundle.contract_id
            AND service_package_id = v_bundle.service_package_id
            AND rateplan_id = v_bundle.rateplan_id
            AND starting_date = v_period_start;
          v_rated_service_id := v_bundle.service_package_id;
      END LOOP;

      IF v_remaining > 0 THEN
          IF v_is_roaming THEN
              INSERT INTO ror_contract (contract_id, rateplan_id, starting_date, roaming_voice, roaming_data, roaming_sms)
              VALUES (v_contract.id, v_contract.rateplan_id, v_period_start,
                     CASE WHEN v_service_type='voice' THEN v_remaining ELSE 0 END,
                     CASE WHEN v_service_type='data'  THEN v_remaining ELSE 0 END,
                     CASE WHEN v_service_type='sms'   THEN v_remaining ELSE 0 END)
              ON CONFLICT (contract_id, rateplan_id, starting_date) DO UPDATE SET
                 roaming_voice = ror_contract.roaming_voice + EXCLUDED.roaming_voice,
                 roaming_data = ror_contract.roaming_data + EXCLUDED.roaming_data,
                 roaming_sms = ror_contract.roaming_sms + EXCLUDED.roaming_sms;
          ELSE
              INSERT INTO ror_contract (contract_id, rateplan_id, starting_date, voice, data, sms)
              VALUES (v_contract.id, v_contract.rateplan_id, v_period_start,
                     CASE WHEN v_service_type='voice' THEN v_remaining ELSE 0 END,
                     CASE WHEN v_service_type='data'  THEN v_remaining ELSE 0 END,
                     CASE WHEN v_service_type='sms'   THEN v_remaining ELSE 0 END)
              ON CONFLICT (contract_id, rateplan_id, starting_date) DO UPDATE SET
                 voice = ror_contract.voice + EXCLUDED.voice,
                 data = ror_contract.data + EXCLUDED.data,
                 sms = ror_contract.sms + EXCLUDED.sms;
          END IF;

          -- Calculate charge for the CDR record
          SELECT 
            CASE WHEN v_is_roaming THEN ror_roaming_voice ELSE ror_voice END as v_rate,
            CASE WHEN v_is_roaming THEN ror_roaming_data ELSE ror_data END as d_rate,
            CASE WHEN v_is_roaming THEN ror_roaming_sms ELSE ror_sms END as s_rate
          INTO v_ror_rate_v, v_ror_rate_d, v_ror_rate_s
          FROM rateplan WHERE id = v_contract.rateplan_id;

          IF v_service_type = 'voice' THEN v_ror_rate := v_ror_rate_v;
          ELSIF v_service_type = 'data' THEN v_ror_rate := v_ror_rate_d;
          ELSIF v_service_type = 'sms' THEN v_ror_rate := v_ror_rate_s;
          END IF;
          
          IF v_service_type = 'data' THEN
              v_overage_charge := (v_remaining / 1073741824.0) * COALESCE(v_ror_rate, 0);
          ELSE
              v_overage_charge := v_remaining * COALESCE(v_ror_rate, 0);
          END IF;

          -- Deduct from available_credit
          UPDATE contract 
          SET available_credit = available_credit - v_overage_charge
          WHERE id = v_contract.id;
      END IF;

     UPDATE cdr SET rated_flag = TRUE, external_charges = v_overage_charge, rated_service_id = v_rated_service_id WHERE id = p_cdr_id;
 END;
$$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- INITIALIZE CONSUMPTION PERIOD
-- Call once at the start of each billing cycle.
-- Creates fresh zero-consumption rows for every active contract.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION initialize_consumption_period(p_period_start DATE)
RETURNS VOID AS $$
DECLARE
    v_period_end DATE;
BEGIN
    v_period_end := (DATE_TRUNC('month', p_period_start) + INTERVAL '1 month - 1 day')::DATE;

INSERT INTO contract_consumption (
    contract_id,
    service_package_id,
    rateplan_id,
    starting_date,
    ending_date,
    consumed,
    quota_limit,
    is_billed
)
SELECT
    c.id,
    rsp.service_package_id,
    c.rateplan_id,
    p_period_start,
    v_period_end,
    0,
    sp.amount, 
    FALSE
FROM contract c
         JOIN rateplan_service_package rsp ON rsp.rateplan_id = c.rateplan_id
         JOIN service_package sp ON sp.id = rsp.service_package_id
WHERE c.status = 'active'
    ON CONFLICT DO NOTHING;

END;
$$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- GENERATE BILL
-- Aggregates consumption + overage into a bill row.
-- Marks consumption rows and ror_contract row as billed.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION generate_bill(p_contract_id INTEGER, p_billing_period_start DATE)
    RETURNS INTEGER
AS $$
    DECLARE
        v_billing_period_end DATE;
        v_recurring_fees NUMERIC(12,2);
        v_voice_usage INTEGER;
        v_data_usage INTEGER;
        v_sms_usage INTEGER;
        v_overage_charge NUMERIC(12,2);
        v_roaming_charge NUMERIC(12,2);
        v_promo_discount NUMERIC(12,2) := 0;
        v_taxes NUMERIC(12,2);
        v_subtotal NUMERIC(12,2);
        v_total_amount NUMERIC(12,2);
        v_rateplan_id INTEGER;
        v_bill_id INTEGER;
        v_msisdn VARCHAR;
        v_ror_rate_v NUMERIC;
        v_ror_rate_d NUMERIC;
        v_ror_rate_s NUMERIC;
    BEGIN
        v_billing_period_end := (DATE_TRUNC('month', p_billing_period_start) + INTERVAL '1 month - 1 day')::DATE;
        SELECT rateplan_id, msisdn INTO v_rateplan_id, v_msisdn FROM contract WHERE id = p_contract_id;
        SELECT price, ror_voice, ror_data, ror_sms INTO v_recurring_fees, v_ror_rate_v, v_ror_rate_d, v_ror_rate_s FROM rateplan WHERE id = v_rateplan_id;

        -- Calculate actual usage from contract_consumption (normalized units)
        SELECT
            COALESCE(SUM(CASE WHEN sp.type::TEXT = 'voice' THEN cc.consumed ELSE 0 END), 0)::INT,
            COALESCE(SUM(CASE WHEN sp.type::TEXT = 'data' THEN cc.consumed ELSE 0 END), 0)::INT,
            COALESCE(SUM(CASE WHEN sp.type::TEXT = 'sms' THEN cc.consumed ELSE 0 END), 0)::INT
        INTO v_voice_usage, v_data_usage, v_sms_usage
        FROM contract_consumption cc
        JOIN service_package sp ON cc.service_package_id = sp.id
        WHERE cc.contract_id = p_contract_id AND cc.starting_date = p_billing_period_start;

        -- Calculate overage charges from ror_contract (units * rates)
        SELECT
            COALESCE(SUM((voice * v_ror_rate_v) + (data / 1073741824.0 * v_ror_rate_d) + (sms * v_ror_rate_s)), 0),
            COALESCE(SUM((roaming_voice * v_ror_rate_v) + (roaming_data / 1073741824.0 * v_ror_rate_d) + (roaming_sms * v_ror_rate_s)), 0)
        INTO v_overage_charge, v_roaming_charge
        FROM ror_contract 
        WHERE contract_id = p_contract_id 
          AND starting_date = p_billing_period_start
          AND bill_id IS NULL;

        v_overage_charge := COALESCE(v_overage_charge, 0);
        v_roaming_charge := COALESCE(v_roaming_charge, 0);

        -- Calculate Promotional Savings (free units don't cost anything)
        -- For now, set to 0 as promotional discounts should be calculated separately
        v_promo_discount := 0;

        -- Calculate subtotal and taxes
        v_subtotal := (v_recurring_fees + v_overage_charge + v_roaming_charge - v_promo_discount);
        v_taxes := 0.14 * v_subtotal;
        v_total_amount := v_subtotal + v_taxes;

        INSERT INTO bill (
            contract_id, billing_period_start, billing_period_end, billing_date,
            recurring_fees, voice_usage, data_usage, sms_usage,
            overage_charge, roaming_charge, promotional_discount, taxes, total_amount, status
        ) VALUES (
            p_contract_id, p_billing_period_start, v_billing_period_end, CURRENT_DATE,
            v_recurring_fees, v_voice_usage, v_data_usage, v_sms_usage,
            v_overage_charge, v_roaming_charge, v_promo_discount, v_taxes, v_total_amount, 'issued'
        ) RETURNING id INTO v_bill_id;

        UPDATE ror_contract SET bill_id = v_bill_id WHERE contract_id = p_contract_id AND starting_date = p_billing_period_start AND bill_id IS NULL;
        UPDATE contract_consumption SET bill_id = v_bill_id, is_billed = TRUE WHERE contract_id = p_contract_id AND starting_date = p_billing_period_start;

        RETURN v_bill_id;
    END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- GENERATE BILLS FOR ALL CONTRACTS
-- Convenience wrapper that calls generate_bill() for every
-- active contract. This is what your scheduler calls
-- at the end of each billing period.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION generate_all_bills(p_period_start DATE)
    RETURNS VOID AS $$
DECLARE
    v_contract RECORD;
    v_success  INTEGER := 0;
    v_failed   INTEGER := 0;
BEGIN
    -- Expire any add-ons from last period first
    PERFORM expire_addons();

    FOR v_contract IN
        SELECT id FROM contract 
        WHERE status = 'active'
          AND id NOT IN (SELECT contract_id FROM bill WHERE billing_period_start = p_period_start)
    LOOP
        BEGIN
            PERFORM generate_bill(v_contract.id, p_period_start);
            v_success := v_success + 1;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE WARNING 'generate_bill failed for contract %: %',
                    v_contract.id, SQLERRM;
                v_failed := v_failed + 1;
        END;
    END LOOP;

    RAISE NOTICE 'generate_all_bills complete: % succeeded, % failed',
        v_success, v_failed;
END;
$$ LANGUAGE plpgsql;
-- ------------------------------------------------------------
-- BILLING AUDIT: Get Missing Bills
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS get_missing_bills();
DROP FUNCTION IF EXISTS get_missing_bills();
CREATE OR REPLACE FUNCTION get_missing_bills(p_search TEXT DEFAULT NULL, p_limit INTEGER DEFAULT 50, p_offset INTEGER DEFAULT 0)
    RETURNS TABLE (
                      contract_id    INTEGER,
                      msisdn         VARCHAR(20),
                      customer_name  VARCHAR(255),
                      rateplan_name  VARCHAR(255),
                      last_bill_date DATE,
                      total_count    BIGINT
                  ) AS $$
DECLARE
    v_period_start DATE := DATE_TRUNC('month', CURRENT_DATE)::DATE;
    v_total BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_total
    FROM contract c
    JOIN user_account u ON c.user_account_id = u.id
    LEFT JOIN rateplan r ON c.rateplan_id = r.id
    WHERE c.status IN ('active', 'suspended', 'suspended_debt')
      AND NOT EXISTS (
        SELECT 1 FROM bill b
        WHERE b.contract_id = c.id
          AND b.billing_period_start = v_period_start
      )
      AND (p_search IS NULL OR p_search = '' OR
           c.msisdn ILIKE '%' || p_search || '%' OR
           u.name ILIKE '%' || p_search || '%' OR
           r.name ILIKE '%' || p_search || '%');

    RETURN QUERY
        SELECT
            c.id           AS contract_id,
            c.msisdn,
            u.name         AS customer_name,
            r.name         AS rateplan_name,
            (SELECT MAX(billing_date) FROM bill b WHERE b.contract_id = c.id) AS last_bill_date,
            v_total AS total_count
        FROM contract c
                 JOIN user_account u ON c.user_account_id = u.id
                 LEFT JOIN rateplan r ON c.rateplan_id = r.id
        WHERE c.status IN ('active', 'suspended', 'suspended_debt')
          AND NOT EXISTS (
            SELECT 1 FROM bill b
            WHERE b.contract_id = c.id
              AND b.billing_period_start = v_period_start
          )
          AND (p_search IS NULL OR p_search = '' OR
               c.msisdn ILIKE '%' || p_search || '%' OR
               u.name ILIKE '%' || p_search || '%' OR
               r.name ILIKE '%' || p_search || '%')
        ORDER BY c.id
        LIMIT p_limit OFFSET p_offset;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- GENERATE BULK MISSING
-- Generates bills for all contracts missing a bill for the current period
-- that match the search criteria.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE generate_bulk_missing(p_search TEXT)
    LANGUAGE plpgsql AS $$
DECLARE
    v_contract_id INTEGER;
    v_period_start DATE := DATE_TRUNC('month', CURRENT_DATE)::DATE;
BEGIN
    FOR v_contract_id IN
        SELECT c.id
        FROM contract c
        JOIN user_account u ON c.user_account_id = u.id
        LEFT JOIN rateplan r ON c.rateplan_id = r.id
        WHERE c.status IN ('active', 'suspended', 'suspended_debt')
          AND NOT EXISTS (
            SELECT 1 FROM bill b
            WHERE b.contract_id = c.id
              AND b.billing_period_start = v_period_start
          )
          AND (p_search IS NULL OR p_search = '' OR
               c.msisdn ILIKE '%' || p_search || '%' OR
               u.name ILIKE '%' || p_search || '%' OR
               r.name ILIKE '%' || p_search || '%')
    LOOP
        PERFORM generate_bill(v_contract_id, v_period_start);
    END LOOP;
END;
$$;

-- ------------------------------------------------------------
-- CREATE CONTRACT
-- Creates a new contract and immediately initializes
-- consumption rows for the current billing period.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_contract(
    p_user_account_id  INTEGER,
    p_rateplan_id      INTEGER,
    p_msisdn           VARCHAR(20),
    p_credit_limit     DOUBLE PRECISION
)
    RETURNS INTEGER AS $$
DECLARE
    v_contract_id  INTEGER;
    v_period_start DATE;
    v_period_end   DATE;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM user_account WHERE id = p_user_account_id) THEN
        RAISE EXCEPTION 'Customer with id % does not exist', p_user_account_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM rateplan WHERE id = p_rateplan_id) THEN
        RAISE EXCEPTION 'Rateplan with id % does not exist', p_rateplan_id;
    END IF;

    IF EXISTS (SELECT 1 FROM contract WHERE msisdn = p_msisdn) THEN
        RAISE EXCEPTION 'MSISDN % is already assigned to another contract', p_msisdn;
    END IF;

    -- Check MSISDN is actually available in the pool
    IF NOT EXISTS (
        SELECT 1 FROM msisdn_pool
        WHERE msisdn = p_msisdn AND is_available = TRUE
    ) THEN
        RAISE EXCEPTION 'MSISDN % is not available', p_msisdn;
    END IF;

    INSERT INTO contract (
        user_account_id, rateplan_id, msisdn,
        status, credit_limit, available_credit
    ) VALUES (
                 p_user_account_id, p_rateplan_id, p_msisdn,
                 'active', p_credit_limit::NUMERIC, p_credit_limit::NUMERIC
             ) RETURNING id INTO v_contract_id;

    -- Mark MSISDN as taken
    PERFORM mark_msisdn_taken(p_msisdn);

    INSERT INTO ror_contract (contract_id, rateplan_id, voice, data, sms)
    VALUES (v_contract_id, p_rateplan_id, 0, 0, 0);

    v_period_start := DATE_TRUNC('month', CURRENT_DATE)::DATE;
    v_period_end   := (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE;

    INSERT INTO contract_consumption (
        contract_id, service_package_id, rateplan_id,
        starting_date, ending_date, consumed, quota_limit, is_billed
    )
    SELECT v_contract_id, rsp.service_package_id, p_rateplan_id,
           v_period_start, v_period_end, 0, sp.amount, FALSE
    FROM rateplan_service_package rsp
    JOIN service_package sp ON rsp.service_package_id = sp.id
    WHERE rsp.rateplan_id = p_rateplan_id
    ON CONFLICT DO NOTHING;

    RETURN v_contract_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'create_contract failed: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- GET ALL CONTRACTS
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS get_all_contracts();
CREATE OR REPLACE FUNCTION get_all_contracts(p_search TEXT DEFAULT NULL, p_limit INTEGER DEFAULT 50, p_offset INTEGER DEFAULT 0)
    RETURNS TABLE (
                      id               INTEGER,
                      msisdn           VARCHAR(20),
                      status           contract_status,
                      available_credit NUMERIC(12,2),
                      customer_name    VARCHAR(255),
                      rateplan_name    VARCHAR(255),
                      total_count      BIGINT
                  ) AS $$
DECLARE
    v_total BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_total
    FROM contract c
    JOIN user_account u ON c.user_account_id = u.id
    LEFT JOIN rateplan r ON c.rateplan_id = r.id
    WHERE (p_search IS NULL OR p_search = '' OR
           c.msisdn ILIKE '%' || p_search || '%' OR
           u.name ILIKE '%' || p_search || '%' OR
           r.name ILIKE '%' || p_search || '%');

    RETURN QUERY
        SELECT
            c.id,
            c.msisdn,
            c.status,
            c.available_credit,
            u.name  AS customer_name,
            r.name  AS rateplan_name,
            v_total
        FROM contract c
                 JOIN user_account u ON c.user_account_id = u.id
                 LEFT JOIN rateplan r ON c.rateplan_id = r.id
        WHERE (p_search IS NULL OR p_search = '' OR
               c.msisdn ILIKE '%' || p_search || '%' OR
               u.name ILIKE '%' || p_search || '%' OR
               r.name ILIKE '%' || p_search || '%')
        ORDER BY c.id DESC
        LIMIT p_limit OFFSET p_offset;
END;
$$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- GET CONTRACT BY ID (detail view)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_contract_by_id(p_id INTEGER)
    RETURNS TABLE (
                      id               INTEGER,
                      user_account_id  INTEGER,
                      rateplan_id      INTEGER,
                      msisdn           VARCHAR(20),
                      status           contract_status,
                      credit_limit     NUMERIC(12,2),
                      available_credit NUMERIC(12,2),
                      customer_name    VARCHAR(255),
                      rateplan_name    VARCHAR(255)
                  ) AS $$
BEGIN
    RETURN QUERY
        SELECT
            c.id,
            c.user_account_id,
            c.rateplan_id,
            c.msisdn,
            c.status,
            c.credit_limit,
            c.available_credit,
            u.name AS customer_name,
            r.name AS rateplan_name
        FROM contract c
                 JOIN user_account u ON c.user_account_id = u.id
                 LEFT JOIN rateplan r ON c.rateplan_id = r.id
        WHERE c.id = p_id;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- GET ALL CUSTOMERS
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS get_all_customers(TEXT);
CREATE OR REPLACE FUNCTION get_all_customers(p_search TEXT DEFAULT NULL, p_limit INTEGER DEFAULT 50, p_offset INTEGER DEFAULT 0)
    RETURNS TABLE (
                      id        INTEGER,
                      username    VARCHAR(255),
                      name      VARCHAR(255),
                      email     VARCHAR(255),
                      role      user_role,
                      address   TEXT,
                      birthdate DATE,
                      msisdn    VARCHAR(20),
                      total_count BIGINT
                  ) AS $$
DECLARE
    v_total BIGINT;
BEGIN
    SELECT COUNT(DISTINCT ua.id) INTO v_total
    FROM user_account ua
    LEFT JOIN contract c ON ua.id = c.user_account_id
    WHERE ua.role = 'customer'
      AND (p_search IS NULL OR p_search = '' OR
           ua.name ILIKE '%' || p_search || '%' OR
           ua.email ILIKE '%' || p_search || '%' OR
           ua.username ILIKE '%' || p_search || '%' OR
           c.msisdn ILIKE '%' || p_search || '%');

    RETURN QUERY
        SELECT DISTINCT ON (ua.id)
            ua.id,
            ua.username,
            ua.name,
            ua.email,
            ua.role,
            ua.address,
            ua.birthdate,
            c.msisdn,
            v_total
        FROM user_account ua
        LEFT JOIN contract c ON ua.id = c.user_account_id
        WHERE ua.role = 'customer'
          AND (p_search IS NULL OR p_search = '' OR
               ua.name ILIKE '%' || p_search || '%' OR
               ua.email ILIKE '%' || p_search || '%' OR
               ua.username ILIKE '%' || p_search || '%' OR
               c.msisdn ILIKE '%' || p_search || '%')
        ORDER BY ua.id DESC
        LIMIT p_limit OFFSET p_offset;
END;
$$ LANGUAGE plpgsql;



-- ------------------------------------------------------------
-- GET USER DATA
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION get_user_data(p_user_account_id INTEGER)
    RETURNS TABLE (
                      username VARCHAR(255),
                      role VARCHAR(20),
                      name VARCHAR(255),
                      email VARCHAR(255),
                      address TEXT,
                      birthdate DATE
                  ) AS $$
BEGIN
    RETURN QUERY
        SELECT
            ua.username,
            ua.role,
            ua.name,
            ua.email,
            ua.address,
            ua.birthdate
        FROM user_account ua
        WHERE ua.id = p_user_account_id;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- AUTHENTICATE LOGIN
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION login(p_username VARCHAR(255), p_password VARCHAR(30))
    RETURNS TABLE (
                      id       INTEGER,
                      username VARCHAR(255),
                      name     VARCHAR(255),
                      email    VARCHAR(255),
                      role     user_role
                  ) AS $$
BEGIN
    RETURN QUERY
        SELECT
            ua.id,
            ua.username,
            ua.name,
            ua.email,
            ua.role
        FROM user_account ua
        WHERE ua.username = p_username
          AND ua.password = p_password;
END;
$$ LANGUAGE plpgsql;
-- ------------------------------------------------------------
-- GET CDRs (Baseline version)
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS get_cdrs(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION get_cdrs(p_limit INTEGER DEFAULT 50, p_offset INTEGER DEFAULT 0)
 RETURNS TABLE (
     id INTEGER,
     msisdn VARCHAR,
     destination VARCHAR,
     duration INTEGER,
     "timestamp" TIMESTAMP,
     rated BOOLEAN,
     type VARCHAR,
     service_id INTEGER,
     service_type TEXT
 ) AS $$
 BEGIN
     RETURN QUERY
     SELECT 
         c.id, 
         c.dial_a AS msisdn, 
         c.dial_b AS destination, 
         c.duration, 
         c.start_time AS "timestamp", 
         c.rated_flag AS rated,
         CASE 
            WHEN sp_rated.id IS NOT NULL THEN sp_rated.name
            WHEN c.external_charges > 0 THEN 'Overage (' || sp_base.name || ')'
            ELSE COALESCE(sp_base.name, 'Unrated')
         END AS type,
         COALESCE(c.rated_service_id, c.service_id) AS service_id,
         COALESCE(sp_rated.type::TEXT, sp_base.type::TEXT, 'other') AS service_type
     FROM cdr c
     LEFT JOIN service_package sp_rated ON c.rated_service_id = sp_rated.id
     LEFT JOIN service_package sp_base ON c.service_id = sp_base.id
     ORDER BY c.start_time DESC
     LIMIT p_limit OFFSET p_offset;
 END;
 $$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- GET USER CONTRACTS
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_user_contracts(p_user_id INTEGER)
    RETURNS TABLE (
                      id               INTEGER,
                      msisdn           VARCHAR(20),
                      status           contract_status,
                      available_credit NUMERIC(12,2),
                      credit_limit     NUMERIC(12,2),
                      rateplan_name    VARCHAR(255)
                  ) AS $$
BEGIN
    RETURN QUERY
        SELECT
            c.id,
            c.msisdn,
            c.status,
            c.available_credit,
            c.credit_limit,
            r.name AS rateplan_name
        FROM contract c
                 LEFT JOIN rateplan r ON c.rateplan_id = r.id
        WHERE c.user_account_id = p_user_id;
END;
$$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- GET USER INVOICES (bills)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_user_invoices(p_user_id INTEGER)
    RETURNS TABLE (
                      id                   INTEGER,
                      contract_id          INTEGER,
                      billing_period_start DATE,
                      billing_period_end   DATE,
                      billing_date         DATE,
                      recurring_fees       NUMERIC(12,2),
                      one_time_fees        NUMERIC(12,2),
                      voice_usage          INTEGER,
                      data_usage           INTEGER,
                      sms_usage            INTEGER,
                      ror_charge           NUMERIC(12,2),
                      taxes                NUMERIC(12,2),
                      total_amount         NUMERIC(12,2),
                      status               bill_status,
                      is_paid              BOOLEAN,
                      pdf_path             TEXT
                  ) AS $$
BEGIN
    RETURN QUERY
        SELECT
            b.id,
            b.contract_id,
            b.billing_period_start,
            b.billing_period_end,
            b.billing_date,
            b.recurring_fees,
            b.one_time_fees,
            b.voice_usage,
            b.data_usage,
            b.sms_usage,
            b.ror_charge,
            b.taxes,
            b.total_amount,
            b.status,
            b.is_paid,
            i.pdf_path
        FROM bill b
                 JOIN contract c ON b.contract_id = c.id
                 LEFT JOIN invoice i on b.id = i.bill_id
        WHERE c.user_account_id = p_user_id
        ORDER BY b.billing_date DESC;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- CREATE SERVICE PACKAGE
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_service_package(
    p_name        VARCHAR(255),
    p_type        service_type,
    p_amount      NUMERIC(12,4),
    p_priority    INTEGER,
    p_price       NUMERIC(10,2),
    p_description TEXT,
    p_is_roaming  BOOLEAN DEFAULT FALSE
)
    RETURNS TABLE (
                      id          INTEGER,
                      name        VARCHAR(255),
                      type        service_type,
                      amount      NUMERIC(12,4),
                      priority    INTEGER,
                      price       NUMERIC(10,2),
                      description TEXT,
                      is_roaming  BOOLEAN
                  ) AS $$
BEGIN
    RETURN QUERY
        INSERT INTO service_package (name, type, amount, priority, price, description, is_roaming)
            VALUES (p_name, p_type, p_amount, p_priority, p_price, p_description, p_is_roaming)
            RETURNING
                service_package.id,
                service_package.name,
                service_package.type,
                service_package.amount,
                service_package.priority,
                service_package.price,
                service_package.description,
                service_package.is_roaming;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- GET RATEPLANS BY NAME LIST
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_all_rateplans()
    RETURNS TABLE (
                      id        INTEGER,
                      name      VARCHAR(255),
                      price     NUMERIC(10,2),
                      ror_voice NUMERIC(10,2),
                      ror_data  NUMERIC(10,2),
                      ror_sms   NUMERIC(10,2)
                  ) AS $$
BEGIN
    RETURN QUERY
        SELECT
            r.id,
            r.name,
            r.price,
            r.ror_voice,
            r.ror_data,
            r.ror_sms
        FROM rateplan "r"
        ORDER BY r.price ASC;
END;
$$ LANGUAGE plpgsql;
-- ------------------------------------------------------------
-- Retrieve BILL DATA
-- In a real system, you'd likely have a separate service that queries the bill data
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION get_bill(p_bill_id INTEGER)
RETURNS TABLE (
    contract_id INTEGER,
    billing_period_start DATE,
    billing_period_end DATE,
    billing_date DATE,
    recurring_fees NUMERIC(12,2),
    one_time_fees NUMERIC(12,2),
    voice_usage INTEGER,
    data_usage INTEGER,
    sms_usage INTEGER,
    ROR_charge NUMERIC(12,2),
    taxes NUMERIC(12,2),
    total_amount NUMERIC(12,2),
    status bill_status,
    is_paid BOOLEAN
) AS $$
BEGIN
RETURN QUERY
SELECT
    b.contract_id,
    b.billing_period_start,
    b.billing_period_end,
    b.billing_date,
    b.recurring_fees,
    b.one_time_fees,
    b.voice_usage,
    b.data_usage,
    b.sms_usage,
    b.ROR_charge,
    b.taxes,
    b.total_amount,
    b.status,
    b.is_paid
FROM bill b
WHERE b.id = p_bill_id;
END;
$$ LANGUAGE plpgsql;
-- ------------------------------------------------------------
-- MARK BILL AS PAID
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION mark_bill_paid(p_bill_id INTEGER)
RETURNS VOID AS $$
BEGIN
UPDATE bill
SET is_paid = TRUE, status = 'paid'
WHERE id = p_bill_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'mark_bill_paid failed for bill id %: %', p_bill_id, SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- GENERATE INVOICE AND SAVE ITS PATH
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION generate_invoice(p_bill_id INTEGER, p_pdf_path TEXT)
       RETURNS VOID AS $$
BEGIN
INSERT INTO invoice (bill_id, pdf_path)
VALUES (p_bill_id, p_pdf_path);
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'generate_invoice failed for bill id %: %', p_bill_id, SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- PAY BILL
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION pay_bill(p_bill_id INTEGER, p_pdf_path TEXT)
         RETURNS VOID AS $$
BEGIN
         -- Mark bill as paid
         PERFORM mark_bill_paid(p_bill_id);
         -- Generate invoice PDF
         PERFORM generate_invoice(p_bill_id, p_pdf_path);
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'pay_bill failed for bill id %: %', p_bill_id, SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- CHANGE CONTRACT STATUS
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION change_contract_status(
    p_contract_id INTEGER,
    p_status      contract_status
)
    RETURNS VOID AS $$
DECLARE
    v_msisdn VARCHAR(20);
BEGIN
    SELECT msisdn INTO v_msisdn
    FROM contract WHERE id = p_contract_id;

    UPDATE contract SET status = p_status WHERE id = p_contract_id;

    -- Release number back to pool if terminated
    IF p_status = 'terminated' THEN
        PERFORM release_msisdn(v_msisdn);
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'change_contract_status failed for contract id %: %',
            p_contract_id, SQLERRM;
END;
$$ LANGUAGE plpgsql;
-- ------------------------------------------------------------
-- GET CONTRACT CONSUMPTION
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_contract_consumption(p_contract_id INTEGER, p_period_start DATE)
       RETURNS TABLE (
    service_package_id INTEGER,
    consumed INTEGER
) AS $$
BEGIN
RETURN QUERY
SELECT service_package_id, consumed
FROM contract_consumption
WHERE contract_id = p_contract_id
  AND starting_date = p_period_start
  AND is_billed = FALSE;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- GET ALL BILLS (PAGINATED)
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS get_all_bills(TEXT, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION get_all_bills(p_search TEXT DEFAULT NULL, p_limit INTEGER DEFAULT 50, p_offset INTEGER DEFAULT 0)
    RETURNS TABLE (
                      id                   INTEGER,
                      contract_id          INTEGER,
                      billing_date         DATE,
                      billing_period_start DATE,
                      billing_period_end   DATE,
                      total_amount         NUMERIC(12,2),
                      is_paid              BOOLEAN,
                      status               VARCHAR(20),
                      voice_usage          INTEGER,
                      data_usage           INTEGER,
                      sms_usage            INTEGER,
                      customer_name        VARCHAR(255),
                      msisdn               VARCHAR(20),
                      total_count          BIGINT
                  ) AS $$
DECLARE
    v_total BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_total
    FROM bill b
    JOIN contract c ON b.contract_id = c.id
    JOIN user_account ua ON c.user_account_id = ua.id
    WHERE (p_search IS NULL OR p_search = '' OR
           ua.name ILIKE '%' || p_search || '%' OR
           c.msisdn ILIKE '%' || p_search || '%' OR
           b.status::TEXT ILIKE '%' || p_search || '%');

    RETURN QUERY
        SELECT
            b.id,
            b.contract_id,
            b.billing_date,
            b.billing_period_start,
            b.billing_period_end,
            b.total_amount,
            b.is_paid,
            b.status::VARCHAR(20) AS status,
            b.voice_usage,
            b.data_usage,
            b.sms_usage,
            ua.name AS customer_name,
            c.msisdn,
            v_total
        FROM bill b
        JOIN contract c ON b.contract_id = c.id
        JOIN user_account ua ON c.user_account_id = ua.id
        WHERE (p_search IS NULL OR p_search = '' OR
               ua.name ILIKE '%' || p_search || '%' OR
               c.msisdn ILIKE '%' || p_search || '%' OR
               b.status::TEXT ILIKE '%' || p_search || '%')
        ORDER BY b.billing_date DESC
        LIMIT p_limit OFFSET p_offset;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- GET BILLS BY CONTRACT
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_bills_by_contract(p_contract_id INTEGER)
       RETURNS TABLE (
    id INTEGER,
    billing_period_start DATE,
    billing_period_end DATE,
    billing_date DATE,
    total_amount NUMERIC(12,2),
    status bill_status
) AS $$
BEGIN
RETURN QUERY
SELECT b.id, b.billing_period_start, billing_period_end, billing_date, total_amount, status
FROM bill b WHERE b.contract_id = p_contract_id
ORDER BY billing_period_start DESC;
END;
$$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- CREATE CUSTOMER
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_customer(
    p_username  VARCHAR(255),
    p_password  VARCHAR(30),
    p_name      VARCHAR(255),
    p_email     VARCHAR(255),
    p_address   TEXT,
    p_birthdate DATE
)
RETURNS INTEGER AS $$
DECLARE
v_new_id INTEGER;
BEGIN
INSERT INTO user_account (username, password, role, name, email, address, birthdate)
VALUES (p_username, p_password, 'customer', p_name, p_email, p_address, p_birthdate)
    RETURNING id INTO v_new_id;

RETURN v_new_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'create_customer failed for username %: %', p_username, SQLERRM;
END;
$$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- GET AVAILABLE MSISDNs
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_available_msisdns()
    RETURNS TABLE (
                      id     INTEGER,
                      msisdn VARCHAR(20)
                  ) AS $$
BEGIN
    RETURN QUERY
        SELECT mp.id, mp.msisdn
        FROM msisdn_pool mp
        WHERE mp.is_available = TRUE
        ORDER BY mp.msisdn;
END;
$$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- MARK MSISDN AS TAKEN
-- Called automatically when a contract is created
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION mark_msisdn_taken(p_msisdn VARCHAR(20))
    RETURNS VOID AS $$
BEGIN
    UPDATE msisdn_pool
    SET is_available = FALSE
    WHERE msisdn = p_msisdn;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'MSISDN % not found in pool', p_msisdn;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- MARK MSISDN AS AVAILABLE AGAIN
-- Called when a contract is terminated
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION release_msisdn(p_msisdn VARCHAR(20))
    RETURNS VOID AS $$
BEGIN
    UPDATE msisdn_pool
    SET is_available = TRUE
    WHERE msisdn = p_msisdn;
END;
$$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- CREATE ADMIN
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_admin(
    p_username  VARCHAR(255),
    p_password  VARCHAR(30),
    p_name      VARCHAR(255),
    p_email     VARCHAR(255),
    p_address   TEXT,
    p_birthdate DATE
)
RETURNS INTEGER AS $$
DECLARE
v_new_id INTEGER;
BEGIN
INSERT INTO user_account (username, password, role, name, email, address, birthdate)
VALUES (p_username, p_password, 'admin', p_name, p_email, p_address, p_birthdate)
    RETURNING id INTO v_new_id;

RETURN v_new_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'create_admin failed for username %: %', p_username, SQLERRM;
END;
$$ LANGUAGE plpgsql;
-- ---------------------------------------------------------
-- CHANGE CONTRACT RATEPLAN
-- ---------------------------------------------------------

CREATE OR REPLACE FUNCTION change_contract_rateplan(
    p_contract_id     INTEGER,
    p_new_rateplan_id INTEGER
)
RETURNS VOID AS $$
DECLARE
v_contract          contract;
    v_old_rateplan_id   INTEGER;
    v_period_start      DATE;
    v_period_end        DATE;
    v_change_day        INTEGER;
    v_days_in_month     INTEGER;
    v_days_used         INTEGER;
    v_days_remaining    INTEGER;
    v_usage_ratio       NUMERIC;  -- how far through the month (0.0 → 1.0)
    v_should_prorate    BOOLEAN := FALSE;
    v_bundle            RECORD;
    v_voice_overage     NUMERIC := 0;
    v_data_overage      NUMERIC := 0;
    v_sms_overage       NUMERIC := 0;
    v_old_ror_voice     NUMERIC;
    v_old_ror_data      NUMERIC;
    v_old_ror_sms       NUMERIC;
    v_prorated_charge   NUMERIC := 0;
    v_recurring_fees    NUMERIC;
    v_prorated_recurring NUMERIC;
    v_taxes             NUMERIC;
    v_total             NUMERIC;
    v_bill_id           INTEGER;
BEGIN
    -- Load contract
SELECT * INTO v_contract FROM contract WHERE id = p_contract_id;
IF NOT FOUND THEN
        RAISE EXCEPTION 'Contract with id % does not exist', p_contract_id;
END IF;

    IF v_contract.status != 'active' THEN
        RAISE EXCEPTION 'Contract % is not active, cannot change rateplan', p_contract_id;
END IF;

    IF NOT EXISTS (SELECT 1 FROM rateplan WHERE id = p_new_rateplan_id) THEN
        RAISE EXCEPTION 'Rateplan with id % does not exist', p_new_rateplan_id;
END IF;

    IF v_contract.rateplan_id = p_new_rateplan_id THEN
        RAISE EXCEPTION 'Contract % is already on rateplan %', p_contract_id, p_new_rateplan_id;
END IF;

    v_old_rateplan_id := v_contract.rateplan_id;

    -- --------------------------------------------------------
    -- DAY CALCULATIONS
    -- v_days_used      = how many days the old plan was active
    -- v_days_in_month  = total days in the current month
    -- v_days_remaining = days left for the new plan
    -- v_usage_ratio    = days_used / days_in_month (e.g. 0.5 on day 15 of 30)
    -- --------------------------------------------------------
    v_period_start   := DATE_TRUNC('month', CURRENT_DATE)::DATE;
    v_period_end     := (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE;
    v_change_day     := EXTRACT(DAY FROM CURRENT_DATE);
    v_days_in_month  := EXTRACT(DAY FROM v_period_end);
    v_days_used      := v_change_day - 1;   -- days 1 through yesterday were fully used
    v_days_remaining := v_days_in_month - v_days_used;
    v_usage_ratio    := v_days_used::NUMERIC / v_days_in_month::NUMERIC;

    -- --------------------------------------------------------
    -- PRORATION CHECK
    -- Prorate if ANY bundle consumption percentage exceeds
    -- the day-based fair share percentage
    --
    -- fair_share_pct = (days_used / days_in_month) * 100
    -- consumed_pct   = (consumed / bundle_amount)  * 100
    --
    -- if consumed_pct > fair_share_pct → prorate
    -- --------------------------------------------------------
FOR v_bundle IN
SELECT
    cc.consumed,
    sp.amount,
    sp.type
FROM contract_consumption cc
         JOIN service_package sp ON sp.id = cc.service_package_id
WHERE cc.contract_id   = p_contract_id
  AND cc.rateplan_id   = v_old_rateplan_id
  AND cc.starting_date = v_period_start
  AND cc.ending_date   = v_period_end
  AND cc.is_billed     = FALSE
  AND sp.type         != 'free_units'
          AND sp.amount        > 0
    LOOP
        -- consumed% exceeds what is proportionally fair for the days elapsed
        IF (v_bundle.consumed::NUMERIC / v_bundle.amount::NUMERIC) > v_usage_ratio THEN
            v_should_prorate := TRUE;
EXIT;
END IF;
END LOOP;

    -- --------------------------------------------------------
    -- PRORATED BILLING
    -- Charge for:
    --   1. Recurring fee prorated to days used
    --   2. Excess usage above the day-proportional fair share,
    --      rated at old rateplan ROR
    -- --------------------------------------------------------
    IF v_should_prorate THEN

SELECT ror_voice, ror_data, ror_sms, price
INTO v_old_ror_voice, v_old_ror_data, v_old_ror_sms, v_recurring_fees
FROM rateplan
WHERE id = v_old_rateplan_id;

-- Recurring fee = full price × (days used / days in month)
v_prorated_recurring := ROUND(v_recurring_fees * v_usage_ratio, 2);

        -- Calculate excess per service type
FOR v_bundle IN
SELECT
    cc.consumed,
    sp.amount,
    sp.type
FROM contract_consumption cc
         JOIN service_package sp ON sp.id = cc.service_package_id
WHERE cc.contract_id   = p_contract_id
  AND cc.rateplan_id   = v_old_rateplan_id
  AND cc.starting_date = v_period_start
  AND cc.ending_date   = v_period_end
  AND cc.is_billed     = FALSE
  AND sp.type         != 'free_units'
        LOOP
DECLARE
v_fair_share  NUMERIC;
                v_excess      NUMERIC;
BEGIN
                -- Fair share = what they should have used by this day
                v_fair_share := v_bundle.amount * v_usage_ratio;
                v_excess     := GREATEST(v_bundle.consumed - v_fair_share, 0);

CASE v_bundle.type
                    WHEN 'voice' THEN v_voice_overage := v_voice_overage + v_excess;
WHEN 'data'  THEN v_data_overage  := v_data_overage  + v_excess;
WHEN 'sms'   THEN v_sms_overage   := v_sms_overage   + v_excess;
ELSE NULL;
END CASE;
END;
END LOOP;

        -- Excess units × old ROR rates
        v_prorated_charge :=
            (v_voice_overage * COALESCE(v_old_ror_voice, 0)) +
            (v_data_overage  * COALESCE(v_old_ror_data,  0)) +
            (v_sms_overage   * COALESCE(v_old_ror_sms,   0));

        v_taxes := ROUND(0.10 * (v_prorated_recurring + v_prorated_charge), 2);
        v_total := v_prorated_recurring + v_prorated_charge + v_taxes;

        -- Insert prorated bill
INSERT INTO bill (
    contract_id,
    billing_period_start,
    billing_period_end,
    billing_date,
    recurring_fees,
    one_time_fees,
    voice_usage,
    data_usage,
    sms_usage,
    ror_charge,
    taxes,
    total_amount,
    status,
    is_paid
) VALUES (
             p_contract_id,
             v_period_start,
             CURRENT_DATE,
             CURRENT_DATE,
             v_prorated_recurring,
             0,
             v_voice_overage,
             v_data_overage,
             v_sms_overage,
             v_prorated_charge,
             v_taxes,
             v_total,
             'issued',
             FALSE
         )
    RETURNING id INTO v_bill_id;

-- Mark old consumption rows as billed
UPDATE contract_consumption
SET is_billed = TRUE,
    bill_id   = v_bill_id
WHERE contract_id   = p_contract_id
  AND rateplan_id   = v_old_rateplan_id
  AND starting_date = v_period_start
  AND ending_date   = v_period_end;

-- Link old ror_contract row to this bill
UPDATE ror_contract
SET bill_id = v_bill_id
WHERE contract_id = p_contract_id
  AND rateplan_id = v_old_rateplan_id
  AND bill_id IS NULL;

ELSE
        -- No proration: close old consumption silently
UPDATE contract_consumption
SET is_billed = TRUE
WHERE contract_id   = p_contract_id
  AND rateplan_id   = v_old_rateplan_id
  AND starting_date = v_period_start
  AND ending_date   = v_period_end
  AND is_billed     = FALSE;
END IF;

    -- --------------------------------------------------------
    -- SWITCH TO NEW RATEPLAN
    -- --------------------------------------------------------
UPDATE contract
SET rateplan_id = p_new_rateplan_id
WHERE id = p_contract_id;

-- Fresh ror_contract row for new rateplan
INSERT INTO ror_contract (contract_id, rateplan_id, voice, data, sms)
VALUES (p_contract_id, p_new_rateplan_id, 0, 0, 0)
    ON CONFLICT DO NOTHING;

-- Fresh consumption rows for new rateplan starting today
INSERT INTO contract_consumption (
    contract_id,
    service_package_id,
    rateplan_id,
    starting_date,
    ending_date,
    consumed,
    is_billed
)
SELECT
    p_contract_id,
    rsp.service_package_id,
    p_new_rateplan_id,
    CURRENT_DATE,
    v_period_end,
    0,
    FALSE
FROM rateplan_service_package rsp
WHERE rsp.rateplan_id = p_new_rateplan_id
    ON CONFLICT DO NOTHING;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'change_contract_rateplan failed for contract %: %',
                        p_contract_id, SQLERRM;
END;
$$ LANGUAGE plpgsql;
-- ============================================================
-- TRIGGERS
-- ============================================================

-- Automatically rate CDR after insert
CREATE OR REPLACE FUNCTION auto_rate_cdr()
           RETURNS TRIGGER AS $$
BEGIN
           IF NEW.service_id IS NOT NULL THEN
              PERFORM rate_cdr(NEW.id);
END IF;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auto_rate_cdr
    AFTER INSERT ON cdr
    FOR EACH ROW
    EXECUTE FUNCTION auto_rate_cdr();

-- AUTOMATICALLY INITIALIZE CONSUMPTION PERIOD ON FIRST CDR OF THE MONTH
CREATE OR REPLACE FUNCTION auto_initialize_consumption()
           RETURNS TRIGGER AS $$
           DECLARE v_period_start DATE;
BEGIN
                   v_period_start := DATE_TRUNC('month', New.start_time )::DATE;
                                  PERFORM initialize_consumption_period(v_period_start);
RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auto_initialize_consumption
    BEFORE INSERT ON cdr
    FOR EACH ROW
    EXECUTE FUNCTION auto_initialize_consumption();

-- Restore available credit after a bill is paid
CREATE OR REPLACE FUNCTION trg_restore_credit_on_payment()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_paid = TRUE AND OLD.is_paid = FALSE THEN
UPDATE contract
SET available_credit = credit_limit
WHERE id = NEW.contract_id;
END IF;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_bill_payment
    AFTER UPDATE ON bill
    FOR EACH ROW
    EXECUTE FUNCTION trg_restore_credit_on_payment();
-- ============================================================
-- ADDITIONAL HELPER FUNCTIONS
-- ============================================================

-- ------------------------------------------------------------
-- GET ALL SERVICE PACKAGES
-- Returns all available service packages
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_all_service_packages()
    RETURNS TABLE (
        id          INTEGER,
        name        VARCHAR(255),
        type        service_type,
        amount      NUMERIC(12,4),
        priority    INTEGER,
        price       NUMERIC(10,2),
        description TEXT,
        is_roaming  BOOLEAN
    ) AS $$
BEGIN
    RETURN QUERY
        SELECT
            sp.id,
            sp.name,
            sp.type,
            sp.amount,
            sp.priority,
            sp.price,
            sp.description,
            sp.is_roaming
        FROM service_package sp
        ORDER BY sp.type, sp.priority ASC;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- GET SERVICE PACKAGE BY ID
-- Returns a single service package detail
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_service_package_by_id(p_id INTEGER)
    RETURNS TABLE (
        id          INTEGER,
        name        VARCHAR(255),
        type        service_type,
        amount      NUMERIC(12,4),
        priority    INTEGER,
        price       NUMERIC(10,2),
        description TEXT,
        is_roaming  BOOLEAN
    ) AS $$
BEGIN
    RETURN QUERY
        SELECT
            sp.id,
            sp.name,
            sp.type,
            sp.amount,
            sp.priority,
            sp.price,
            sp.description,
            sp.is_roaming
        FROM service_package sp
        WHERE sp.id = p_id;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- GET RATEPLAN BY ID
-- Returns rateplan detail with all fields
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_rateplan_by_id(p_id INTEGER)
    RETURNS TABLE (
        id        INTEGER,
        name      VARCHAR(255),
        ror_voice NUMERIC(10,2),
        ror_data  NUMERIC(10,2),
        ror_sms   NUMERIC(10,2),
        price     NUMERIC(10,2)
    ) AS $$
BEGIN
    RETURN QUERY
        SELECT
            r.id,
            r.name,
            r.ror_voice,
            r.ror_data,
            r.ror_sms,
            r.price
        FROM rateplan r
        WHERE r.id = p_id;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- GET CUSTOMER BY ID
-- Returns customer details by ID
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_customer_by_id(p_id INTEGER)
    RETURNS TABLE (
        id        INTEGER,
        username  VARCHAR(255),
        name      VARCHAR(255),
        email     VARCHAR(255),
        role      user_role,
        address   TEXT,
        birthdate DATE
    ) AS $$
BEGIN
    RETURN QUERY
        SELECT
            ua.id,
            ua.username,
            ua.name,
            ua.email,
            ua.role,
            ua.address,
            ua.birthdate
        FROM user_account ua
        WHERE ua.id = p_id AND ua.role = 'customer';
END;
$$ LANGUAGE plpgsql;
-- --------------------------------------------------
-- DASHBOARD STATS (Baseline version)
-- --------------------------------------------------
DROP FUNCTION IF EXISTS get_dashboard_stats();
CREATE OR REPLACE FUNCTION get_dashboard_stats()
    RETURNS TABLE (
                      total_customers            BIGINT,
                      total_contracts            BIGINT,
                      active_contracts           BIGINT,
                      suspended_contracts        BIGINT,
                      suspended_debt_contracts   BIGINT,
                      terminated_contracts       BIGINT,
                      total_cdrs                 BIGINT,
                      revenue                    NUMERIC(12,2),
                      pending_bills              BIGINT
                  ) AS $$
BEGIN
    RETURN QUERY
        SELECT
            (SELECT COUNT(*) FROM user_account  WHERE role = 'customer'),
            (SELECT COUNT(*) FROM contract),
            (SELECT COUNT(*) FROM contract      WHERE status = 'active'),
            (SELECT COUNT(*) FROM contract      WHERE status = 'suspended'),
            (SELECT COUNT(*) FROM contract      WHERE status = 'suspended_debt'),
            (SELECT COUNT(*) FROM contract      WHERE status = 'terminated'),
            (SELECT COUNT(*) FROM cdr),
            (SELECT COALESCE(SUM(total_amount), 0) FROM bill WHERE status = 'paid'),
            (SELECT COUNT(*) FROM bill WHERE status = 'issued');
END;
$$ LANGUAGE plpgsql;



-- ------------------------------------------------------------
-- CANCEL ADD-ON
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION cancel_addon(p_addon_id INTEGER)
    RETURNS VOID AS $$
BEGIN
    UPDATE contract_addon
    SET is_active = FALSE
    WHERE id = p_addon_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Add-on % not found', p_addon_id;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'cancel_addon failed: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- GET ACTIVE ADD-ONS FOR A CONTRACT
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_contract_addons(p_contract_id INTEGER)
    RETURNS TABLE (
                      id                 INTEGER,
                      service_package_id INTEGER,
                      package_name       VARCHAR(255),
                      type               service_type,
                      amount             NUMERIC(12,4),
                      purchased_date     DATE,
                      expiry_date        DATE,
                      price_paid         NUMERIC(12,2),
                      is_active          BOOLEAN
                  ) AS $$
BEGIN
    RETURN QUERY
        SELECT
            ca.id,
            ca.service_package_id,
            sp.name        AS package_name,
            sp.type,
            sp.amount,
            ca.purchased_date,
            ca.expiry_date,
            ca.price_paid,
            ca.is_active
        FROM contract_addon ca
                 JOIN service_package sp ON sp.id = ca.service_package_id
        WHERE ca.contract_id = p_contract_id
        ORDER BY ca.purchased_date DESC;
END;
$$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- AUTO-EXPIRE ADD-ONS AT END OF BILLING PERIOD
-- Call this at the start of each new billing cycle
-- or add it inside generate_all_bills
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION expire_addons()
    RETURNS VOID AS $$
BEGIN
    UPDATE contract_addon
    SET is_active = FALSE
    WHERE expiry_date < CURRENT_DATE
      AND is_active   = TRUE;
END;
$$ LANGUAGE plpgsql;
--==========================================================
--       Function for adding new service package 
--
--==========================================================

CREATE OR REPLACE FUNCTION add_new_service_package(
    p_name character varying,
    p_type public.service_type,
    p_amount numeric,
    p_priority integer,
    p_price numeric,
    p_description text DEFAULT NULL,
    p_is_roaming boolean DEFAULT false
) RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_new_id INTEGER;
BEGIN
    INSERT INTO service_package (name, type, amount, priority, price, description, is_roaming)
    VALUES (p_name, p_type, p_amount, p_priority, p_price, p_description, p_is_roaming)
    RETURNING id INTO v_new_id;
    
    RETURN v_new_id;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'add_new_service_package failed: %', SQLERRM;
END;
$$;

--==========================================================
--       Function for update service package 
--
--==========================================================
CREATE OR REPLACE FUNCTION update_service_package(
    p_id INTEGER,
    p_name VARCHAR(255),
    p_type service_type,
    p_amount NUMERIC(12,4),
    p_priority INTEGER,
    p_price NUMERIC(12,2),
    p_description TEXT,
    p_is_roaming BOOLEAN DEFAULT FALSE
) RETURNS TABLE(
    id INTEGER,
    name VARCHAR(255),
    type service_type,
    amount NUMERIC(12,4),
    priority INTEGER,
    price NUMERIC(12,2),
    description TEXT,
    is_roaming BOOLEAN
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
        UPDATE service_package 
        SET 
            name = p_name,
            type = p_type,
            amount = p_amount,
            priority = p_priority,
            price = p_price,
            description = p_description,
            is_roaming = p_is_roaming
        WHERE service_package.id = p_id
        RETURNING 
            service_package.id,
            service_package.name,
            service_package.type,
            service_package.amount,
            service_package.priority,
            service_package.price,
            service_package.description,
            service_package.is_roaming;
            
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Service package with id % not found', p_id;
    END IF;
END;
$$;

--==========================================================
--       Function for delete service package 
--
--==========================================================

CREATE OR REPLACE FUNCTION delete_service_package(p_id INTEGER) 
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    -- Check if service package is referenced in any active contracts or addons
    IF EXISTS (
        SELECT 1 FROM contract_consumption cc 
        WHERE cc.service_package_id = p_id AND cc.is_billed = FALSE
    ) THEN
        RAISE EXCEPTION 'Cannot delete service package: it has active consumption records';
    END IF;
    
    IF EXISTS (
        SELECT 1 FROM contract_addon ca 
        WHERE ca.service_package_id = p_id AND ca.is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'Cannot delete service package: it has active addons';
    END IF;
    
    DELETE FROM service_package WHERE id = p_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Service package with id % not found', p_id;
    END IF;
END;
$$;

--==========================================================
--       Function for adding new rate_plan 
--
--==========================================================
CREATE OR REPLACE FUNCTION create_rateplan_with_packages(
    p_name VARCHAR(255),
    p_ror_voice NUMERIC(10,2),
    p_ror_data NUMERIC(10,2), 
    p_ror_sms NUMERIC(10,2),
    p_price NUMERIC(10,2),
    p_service_package_ids INTEGER[]
) RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_rateplan_id INTEGER;
    v_package_id INTEGER;
BEGIN
    -- Create the rateplan
    INSERT INTO rateplan (name, ror_voice, ror_data, ror_sms, price)
    VALUES (p_name, p_ror_voice, p_ror_data, p_ror_sms, p_price)
    RETURNING id INTO v_rateplan_id;
    
    -- Link service packages to the rateplan
    FOREACH v_package_id IN ARRAY p_service_package_ids
    LOOP
        IF NOT EXISTS (SELECT 1 FROM service_package WHERE id = v_package_id) THEN
            RAISE EXCEPTION 'Service package with id % does not exist', v_package_id;
        END IF;
        
        INSERT INTO rateplan_service_package (rateplan_id, service_package_id)
        VALUES (v_rateplan_id, v_package_id);
    END LOOP;
    
    RETURN v_rateplan_id;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'create_rateplan_with_packages failed: %', SQLERRM;
END;
$$;

--==========================================================
--       Function for delete rate_plan 
--
--==========================================================



CREATE OR REPLACE FUNCTION delete_rateplan(p_rateplan_id INTEGER) RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    -- Check if rateplan is used by any active contracts
    IF EXISTS (SELECT 1 FROM contract WHERE rateplan_id = p_rateplan_id) THEN
        RAISE EXCEPTION 'Cannot delete rateplan: it is assigned to active contracts';
    END IF;
    
    -- Delete service package associations first
    DELETE FROM rateplan_service_package WHERE rateplan_id = p_rateplan_id;
    
    -- Delete the rateplan
    DELETE FROM rateplan WHERE id = p_rateplan_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Rateplan with id % not found', p_rateplan_id;
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'delete_rateplan failed: %', SQLERRM;
END;
$$;
--==========================================================
--       Function for update rate_plan 
--
--==========================================================


CREATE OR REPLACE FUNCTION update_rateplan(
    p_rateplan_id INTEGER,
    p_name VARCHAR(255) DEFAULT NULL,
    p_ror_voice NUMERIC(10,2) DEFAULT NULL,
    p_ror_data NUMERIC(10,2) DEFAULT NULL,
    p_ror_sms NUMERIC(10,2) DEFAULT NULL,
    p_price NUMERIC(10,2) DEFAULT NULL,
    p_service_package_ids INTEGER[] DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_package_id INTEGER;
BEGIN
    -- Check if rateplan exists
    IF NOT EXISTS (SELECT 1 FROM rateplan WHERE id = p_rateplan_id) THEN
        RAISE EXCEPTION 'Rateplan with id % does not exist', p_rateplan_id;
    END IF;
    
    -- Update rateplan fields (only non-null values)
    UPDATE rateplan 
    SET 
        name = COALESCE(p_name, name),
        ror_voice = COALESCE(p_ror_voice, ror_voice),
        ror_data = COALESCE(p_ror_data, ror_data),
        ror_sms = COALESCE(p_ror_sms, ror_sms),
        price = COALESCE(p_price, price)
    WHERE id = p_rateplan_id;
    
    -- Update service package associations if provided
    IF p_service_package_ids IS NOT NULL THEN
        -- Remove existing associations
        DELETE FROM rateplan_service_package WHERE rateplan_id = p_rateplan_id;
        
        -- Add new associations
        FOREACH v_package_id IN ARRAY p_service_package_ids
        LOOP
            IF NOT EXISTS (SELECT 1 FROM service_package WHERE id = v_package_id) THEN
                RAISE EXCEPTION 'Service package with id % does not exist', v_package_id;
            END IF;
            
            INSERT INTO rateplan_service_package (rateplan_id, service_package_id)
            VALUES (p_rateplan_id, v_package_id);
        END LOOP;
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'update_rateplan failed: %', SQLERRM;
END;
$$;


-- =========================================================
-- DUMMY DATA
-- For testing and demonstration purposes
-- =========================================================

------------------------------------------------------------
-- FULL RESET
------------------------------------------------------------
TRUNCATE TABLE
    invoice,
    bill,
    cdr,
    contract_addon,
    contract_consumption,
    ror_contract,
    contract,
    rateplan_service_package,
    service_package,
    rateplan,
    user_account,
    file,
    msisdn_pool
RESTART IDENTITY CASCADE;

------------------------------------------------------------
-- FILES
------------------------------------------------------------
INSERT INTO file (parsed_flag, file_path)
VALUES
    (TRUE, '/tmp/cdr_april_batch1.csv'),
    (TRUE, '/tmp/cdr_april_batch2.csv');

------------------------------------------------------------
-- USER ACCOUNTS
------------------------------------------------------------
INSERT INTO user_account (name, address, birthdate, role, username, password, email)
VALUES
    -- Admin
    ('System Admin',   'HQ Cairo',        '1985-01-01', 'admin',    'admin',   '123456',   'admin@fmrz.com'),
    -- Customers
    ('Alice Smith',    '123 Main St',      '1990-01-01', 'customer', 'alice',   '123456',  'alice@gmail.com'),
    ('Bob Johnson',    '456 Elm St',       '1985-05-15', 'customer', 'bob',     '123456',  'bob@gmail.com'),
    ('Carol White',    '789 Oak Ave',      '1992-03-10', 'customer', 'carol',   '123456',  'carol@gmail.com'),
    ('David Brown',    '321 Pine Rd',      '1988-07-22', 'customer', 'david',   '123456',  'david@gmail.com'),
    ('Eva Green',      '654 Maple Dr',     '1995-11-05', 'customer', 'eva',     '123456',  'eva@gmail.com'),
    ('Frank Miller',   '987 Cedar Ln',     '1983-02-18', 'customer', 'frank',   '123456',  'frank@gmail.com'),
    ('Grace Lee',      '147 Birch Blvd',   '1991-09-30', 'customer', 'grace',   '123456',  'grace@gmail.com'),
    ('Henry Wilson',   '258 Walnut St',    '1987-04-14', 'customer', 'henry',   '123456',  'henry@gmail.com'),
    ('Iris Taylor',    '369 Spruce Ave',   '1993-06-25', 'customer', 'iris',    '123456',  'iris@gmail.com'),
    ('Jack Davis',     '741 Ash Ct',       '1986-12-03', 'customer', 'jack',    '123456', 'jack@gmail.com'),
    ('Karen Martinez', '852 Elm Pl',       '1994-08-17', 'customer', 'karen',   '123456', 'karen@gmail.com'),
    ('Leo Anderson',   '963 Oak St',       '1989-01-29', 'customer', 'leo',     '123456', 'leo@gmail.com'),
    ('Mia Thomas',     '159 Pine Ave',     '1996-05-08', 'customer', 'mia',     '123456', 'mia@gmail.com'),
    ('Noah Jackson',   '267 Maple Rd',     '1984-10-21', 'customer', 'noah',    '123456', 'noah@gmail.com'),
    ('Olivia Harris',  '348 Cedar Dr',     '1997-03-15', 'customer', 'olivia',  '123456', 'olivia@gmail.com'),
    ('Paul Clark',     '426 Birch Ln',     '1982-07-04', 'customer', 'paul',    '123456', 'paul@gmail.com'),
    ('Quinn Lewis',    '537 Walnut Blvd',  '1998-11-19', 'customer', 'quinn',   '123456', 'quinn@gmail.com'),
    ('Rachel Walker',  '648 Spruce St',    '1981-02-27', 'customer', 'rachel',  '123456', 'rachel@gmail.com');

------------------------------------------------------------
-- RATEPLANS
------------------------------------------------------------
INSERT INTO rateplan (name, ror_data, ror_voice, ror_sms, price)
VALUES
    ('Basic',            0.10, 0.20, 0.05,  75),
    ('Premium Gold',     0.05, 0.10, 0.02, 370),
    ('Elite Enterprise', 0.02, 0.05, 0.01, 950);

------------------------------------------------------------
-- SERVICE PACKAGES
-- id 1-4: domestic, id 5-7: roaming
------------------------------------------------------------
INSERT INTO service_package (name, type, amount, priority, price, is_roaming, description)
VALUES
    -- Group 1: Domestic Standard Packs
    ('Voice Pack',         'voice',      2000, 2,  75,   FALSE, '2000 local minutes per month'),
    ('Data Pack',          'data',      10000, 2,  150,  FALSE, '10GB data per month'),
    ('SMS Pack',           'sms',         500, 2,  25,   FALSE, '500 SMS per month'),
    
    -- Group 2: The Welcome Experience (High Priority)
    ('🎁 Welcome Gift',    'free_units', 10000, 1,  0,    FALSE, '10GB free data for new customers'),
    
    -- Group 3: Global Roaming Addons
    ('Roaming Voice Pack', 'voice',       100, 2, 250,   TRUE,  '100 roaming minutes'),
    ('Roaming Data Pack',  'data',       2000, 2, 500,   TRUE,  '2GB roaming data'),
    ('Roaming SMS Pack',   'sms',         100, 2, 100,   TRUE,  '100 roaming SMS');

------------------------------------------------------------
-- RATEPLAN → PACKAGES
------------------------------------------------------------
INSERT INTO rateplan_service_package (rateplan_id, service_package_id)
VALUES
    -- Basic: voice + sms only
    (1, 1), (1, 3),
    -- Premium Gold: everything domestic + roaming
    (2, 1), (2, 2), (2, 3), (2, 4), (2, 5), (2, 6), (2, 7),
    -- Elite Enterprise: everything
    (3, 1), (3, 2), (3, 3), (3, 4), (3, 5), (3, 6), (3, 7);

------------------------------------------------------------
-- MSISDN POOL
------------------------------------------------------------
INSERT INTO msisdn_pool (msisdn)
SELECT '2010000' || LPAD(i::TEXT, 5, '0')
FROM generate_series(1, 99) AS i;

------------------------------------------------------------
-- CONTRACTS
-- users 2-19 = customers (admin is user 1)
-- Basic: odd users, Premium Gold: even users, Elite: last 2
------------------------------------------------------------
INSERT INTO contract (user_account_id, rateplan_id, msisdn, status, credit_limit, available_credit)
VALUES
    (2,  1, '201000000001', 'active',     200, 200),  -- Alice,   Basic
    (3,  2, '201000000002', 'active',     500, 500),  -- Bob,     Premium Gold
    (4,  1, '201000000003', 'active',     200, 200),  -- Carol,   Basic
    (5,  2, '201000000004', 'active',     500, 500),  -- David,   Premium Gold
    (6,  1, '201000000005', 'active',     200, 200),  -- Eva,     Basic
    (7,  2, '201000000006', 'active',     500, 500),  -- Frank,   Premium Gold
    (8,  1, '201000000007', 'active',     200, 200),  -- Grace,   Basic
    (9,  2, '201000000008', 'active',     500, 500),  -- Henry,   Premium Gold
    (10, 1, '201000000009', 'active',     200, 200),  -- Iris,    Basic
    (11, 2, '201000000010', 'active',     500, 500),  -- Jack,    Premium Gold
    (12, 1, '201000000011', 'active',     200, 150),  -- Karen,   Basic  (some credit used)
    (13, 2, '201000000012', 'active',     500, 420),  -- Leo,     Premium Gold
    (14, 1, '201000000013', 'suspended',  200, 200),  -- Mia,     Basic  (suspended)
    (15, 2, '201000000014', 'active',     500, 500),  -- Noah,    Premium Gold
    (16, 3, '201000000015', 'active',    1000, 1000), -- Olivia,  Elite Enterprise
    (17, 3, '201000000016', 'active',    1000, 980),  -- Paul,    Elite Enterprise
    (18, 2, '201000000017', 'active',     500, 500),  -- Quinn,   Premium Gold
    (19, 1, '201000000018', 'terminated', 200, 200);  -- Rachel,  Basic  (terminated)

------------------------------------------------------------
-- MASTER DUMMY DATA LOADER (SURGICAL INJECTION)
------------------------------------------------------------
SELECT initialize_consumption_period('2026-04-01');
INSERT INTO file (file_path, parsed_flag) VALUES ('master_test.cdr', TRUE) ON CONFLICT DO NOTHING;

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
    v_fname TEXT; v_lname TEXT; v_uname TEXT; v_i INTEGER;
BEGIN
    FOR v_i IN 1..150 LOOP
        v_fname := v_first_names[1 + FLOOR(RANDOM() * ARRAY_LENGTH(v_first_names, 1))];
        v_lname := v_last_names[1 + FLOOR(RANDOM() * ARRAY_LENGTH(v_last_names, 1))];
        v_uname := LOWER(v_fname) || '_' || v_i || '_' || (1000 + FLOOR(RANDOM() * 9000));
        INSERT INTO user_account (name, address, birthdate, role, username, password, email)
        VALUES (v_fname || ' ' || v_lname, (10 + FLOOR(RANDOM() * 90)) || ' ' || v_streets[1 + FLOOR(RANDOM() * ARRAY_LENGTH(v_streets, 1))] || ', ' || v_cities[1 + FLOOR(RANDOM() * ARRAY_LENGTH(v_cities, 1))], '1970-01-01'::DATE + (FLOOR(RANDOM() * 15000) || ' days')::INTERVAL, 'customer', v_uname, '123456', v_uname || '@fmrz-telecom.com')
        ON CONFLICT (username) DO NOTHING RETURNING id INTO v_user_id;
        IF v_user_id IS NULL THEN SELECT id INTO v_user_id FROM user_account WHERE username = v_uname; END IF;
        v_rateplan_id := (CASE WHEN RANDOM() < 0.3 THEN 1 WHEN RANDOM() < 0.7 THEN 2 ELSE 3 END);
        v_msisdn := '201' || (100000000 + FLOOR(RANDOM() * 900000000))::TEXT;
        INSERT INTO msisdn_pool (msisdn, is_available) VALUES (v_msisdn, FALSE) ON CONFLICT (msisdn) DO UPDATE SET is_available = FALSE;
        v_status := (CASE WHEN RANDOM() < 0.5 THEN 'active'::contract_status WHEN RANDOM() < 0.7 THEN 'suspended'::contract_status WHEN RANDOM() < 0.9 THEN 'suspended_debt'::contract_status ELSE 'terminated'::contract_status END);
        v_credit_limit := (CASE v_rateplan_id WHEN 1 THEN 200 WHEN 2 THEN 500 ELSE 1000 END);
        SELECT id INTO v_contract_id FROM contract WHERE msisdn = v_msisdn AND status <> 'terminated';
        IF v_contract_id IS NULL THEN
            INSERT INTO contract (user_account_id, rateplan_id, msisdn, status, credit_limit, available_credit)
            VALUES (v_user_id, v_rateplan_id, v_msisdn, v_status, v_credit_limit, v_credit_limit) RETURNING id INTO v_contract_id;
        END IF;
        IF v_status = 'active' AND RANDOM() < 0.8 THEN
            FOR j IN 1..3 LOOP
                INSERT INTO cdr (file_id, dial_a, dial_b, start_time, duration, service_id, hplmn, vplmn, external_charges, rated_flag)
                VALUES (1, v_msisdn, '201090000000', '2026-04-01 10:00:00', 300, 1, 'EGYVO', NULL, 0, FALSE);
            END LOOP;
        END IF;
    END LOOP;
END $$;

INSERT INTO user_account (name, address, birthdate, role, username, password, email)
VALUES ('Alice Smith', '123 Main St, Cairo', '1990-05-15', 'customer', 'alice', '123456', 'alice@gmail.com') ON CONFLICT (username) DO NOTHING;

DO $$
DECLARE v_uid INTEGER;
BEGIN
    SELECT id INTO v_uid FROM user_account WHERE username = 'alice';
    INSERT INTO contract (user_account_id, rateplan_id, msisdn, status, credit_limit, available_credit)
    VALUES (v_uid, 1, '201000000001', 'active', 200, 200) ON CONFLICT DO NOTHING;
END $$;

-- 5. Final Rating Run
SELECT rate_cdr(id) FROM cdr WHERE rated_flag = FALSE;

-- 5.5 SIMULATE ADDON PURCHASES
DO $$
DECLARE
    v_cid INTEGER;
    v_pkg_id INTEGER;
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

DO $$
DECLARE v_cid INTEGER;
BEGIN
    FOR v_cid IN SELECT id FROM contract WHERE status IN ('active', 'suspended', 'suspended_debt') LOOP
        BEGIN PERFORM generate_bill(v_cid, '2026-03-01'); EXCEPTION WHEN unique_violation THEN NULL; END;
    END LOOP;
    FOR v_cid IN SELECT id FROM contract WHERE status IN ('active', 'suspended', 'suspended_debt') AND NOT EXISTS (SELECT 1 FROM bill WHERE contract_id = contract.id AND billing_period_start = '2026-04-01') ORDER BY id ASC LIMIT (SELECT GREATEST(0, COUNT(*) - 60) FROM contract WHERE status IN ('active', 'suspended', 'suspended_debt')) LOOP
        BEGIN PERFORM generate_bill(v_cid, '2026-04-01'); EXCEPTION WHEN unique_violation THEN NULL; END;
    END LOOP;
END $$;

------------------------------------------------------------
-- ROR_CONTRACT
------------------------------------------------------------
INSERT INTO ror_contract (contract_id, rateplan_id, data, voice, sms)
VALUES
    (1,  1,  0,  0, 0),
    (2,  2,  0,  0, 0),
    (3,  1,  0,  0, 0),
    (4,  2,  0,  0, 0),
    (5,  1,  0,  0, 0),
    (6,  2,  0,  0, 0),
    (7,  1,  0,  0, 0),
    (8,  2,  0,  0, 0),
    (9,  1,  0,  0, 0),
    (10, 2,  0,  0, 0),
    (11, 1,  0,  0, 0),
    (12, 2,  0,  0, 0),
    (13, 1,  0,  0, 0),
    (14, 2,  0,  0, 0),
    (15, 3,  0,  0, 0),
    (16, 3, 20,  0, 0),  -- Paul has some data overage
    (17, 2,  0,  0, 0),
    (18, 1,  0,  0, 0);

------------------------------------------------------------
-- CONTRACT_CONSUMPTION (APRIL 2026)
------------------------------------------------------------
INSERT INTO contract_consumption (
    contract_id, service_package_id, rateplan_id,
    starting_date, ending_date, consumed, is_billed
) VALUES
    -- Alice (Basic: voice+sms)
    (1, 1, 1, '2026-04-01', '2026-04-30', 350,  FALSE),
    (1, 3, 1, '2026-04-01', '2026-04-30', 45,   FALSE),
    -- Bob (Premium Gold: all packages)
    (2, 1, 2, '2026-04-01', '2026-04-30', 620,  FALSE),
    (2, 2, 2, '2026-04-01', '2026-04-30', 2100, FALSE),
    (2, 3, 2, '2026-04-01', '2026-04-30', 85,   FALSE),
    (2, 4, 2, '2026-04-01', '2026-04-30', 50,   FALSE),
    (2, 5, 2, '2026-04-01', '2026-04-30', 120,  FALSE),
    (2, 6, 2, '2026-04-01', '2026-04-30', 400,  FALSE),
    (2, 7, 2, '2026-04-01', '2026-04-30', 30,   FALSE),
    -- Carol (Basic)
    (3, 1, 1, '2026-04-01', '2026-04-30', 180,  FALSE),
    (3, 3, 1, '2026-04-01', '2026-04-30', 22,   FALSE),
    -- David (Premium Gold)
    (4, 1, 2, '2026-04-01', '2026-04-30', 480,  FALSE),
    (4, 2, 2, '2026-04-01', '2026-04-30', 1800, FALSE),
    (4, 3, 2, '2026-04-01', '2026-04-30', 65,   FALSE),
    (4, 4, 2, '2026-04-01', '2026-04-30', 30,   FALSE),
    -- Eva (Basic)
    (5, 1, 1, '2026-04-01', '2026-04-30', 95,   FALSE),
    (5, 3, 1, '2026-04-01', '2026-04-30', 12,   FALSE),
    -- Frank (Premium Gold)
    (6, 1, 2, '2026-04-01', '2026-04-30', 750,  FALSE),
    (6, 2, 2, '2026-04-01', '2026-04-30', 3200, FALSE),
    (6, 3, 2, '2026-04-01', '2026-04-30', 110,  FALSE),
    (6, 4, 2, '2026-04-01', '2026-04-30', 50,   FALSE),
    -- Grace (Basic)
    (7, 1, 1, '2026-04-01', '2026-04-30', 210,  FALSE),
    (7, 3, 1, '2026-04-01', '2026-04-30', 18,   FALSE),
    -- Henry (Premium Gold)
    (8, 1, 2, '2026-04-01', '2026-04-30', 390,  FALSE),
    (8, 2, 2, '2026-04-01', '2026-04-30', 1500, FALSE),
    (8, 3, 2, '2026-04-01', '2026-04-30', 55,   FALSE),
    (8, 4, 2, '2026-04-01', '2026-04-30', 20,   FALSE),
    -- Iris (Basic)
    (9, 1, 1, '2026-04-01', '2026-04-30', 140,  FALSE),
    (9, 3, 1, '2026-04-01', '2026-04-30', 8,    FALSE),
    -- Jack (Premium Gold)
    (10, 1, 2, '2026-04-01', '2026-04-30', 510,  FALSE),
    (10, 2, 2, '2026-04-01', '2026-04-30', 2400, FALSE),
    (10, 3, 2, '2026-04-01', '2026-04-30', 75,   FALSE),
    (10, 4, 2, '2026-04-01', '2026-04-30', 40,   FALSE),
    -- Karen (Basic - some overage)
    (11, 1, 1, '2026-04-01', '2026-04-30', 980,  FALSE),  -- over 1000 limit soon
    (11, 3, 1, '2026-04-01', '2026-04-30', 190,  FALSE),  -- near 200 limit
    -- Leo (Premium Gold)
    (12, 1, 2, '2026-04-01', '2026-04-30', 290,  FALSE),
    (12, 2, 2, '2026-04-01', '2026-04-30', 900,  FALSE),
    (12, 3, 2, '2026-04-01', '2026-04-30', 35,   FALSE),
    (12, 4, 2, '2026-04-01', '2026-04-30', 15,   FALSE),
    -- Noah (Premium Gold)
    (14, 1, 2, '2026-04-01', '2026-04-30', 430,  FALSE),
    (14, 2, 2, '2026-04-01', '2026-04-30', 1200, FALSE),
    (14, 3, 2, '2026-04-01', '2026-04-30', 60,   FALSE),
    (14, 4, 2, '2026-04-01', '2026-04-30', 25,   FALSE),
    -- Olivia (Elite Enterprise)
    (15, 1, 3, '2026-04-01', '2026-04-30', 820,  FALSE),
    (15, 2, 3, '2026-04-01', '2026-04-30', 3800, FALSE),
    (15, 3, 3, '2026-04-01', '2026-04-30', 145,  FALSE),
    (15, 4, 3, '2026-04-01', '2026-04-30', 50,   FALSE),
    (15, 5, 3, '2026-04-01', '2026-04-30', 80,   FALSE),
    (15, 6, 3, '2026-04-01', '2026-04-30', 320,  FALSE),
    (15, 7, 3, '2026-04-01', '2026-04-30', 20,   FALSE),
    -- Paul (Elite Enterprise - has overage)
    (16, 1, 3, '2026-04-01', '2026-04-30', 950,  FALSE),
    (16, 2, 3, '2026-04-01', '2026-04-30', 4900, FALSE),
    (16, 3, 3, '2026-04-01', '2026-04-30', 180,  FALSE),
    (16, 4, 3, '2026-04-01', '2026-04-30', 50,   FALSE),
    -- Quinn (Premium Gold)
    (17, 1, 2, '2026-04-01', '2026-04-30', 340,  FALSE),
    (17, 2, 2, '2026-04-01', '2026-04-30', 1100, FALSE),
    (17, 3, 2, '2026-04-01', '2026-04-30', 48,   FALSE),
    (17, 4, 2, '2026-04-01', '2026-04-30', 10,   FALSE);

------------------------------------------------------------
-- BILLS (FEBRUARY 2026) - all paid
------------------------------------------------------------
INSERT INTO bill (
    contract_id, billing_period_start, billing_period_end, billing_date,
    recurring_fees, one_time_fees, voice_usage, data_usage, sms_usage,
    ROR_charge, taxes, total_amount, status, is_paid
) VALUES
    (1,  '2026-02-01', '2026-02-28', '2026-03-01', 75,  0.69, 280,    0,    38,  0,    10.50,  86.19,  'paid', TRUE),
    (2,  '2026-02-01', '2026-02-28', '2026-03-01', 370, 0.69, 580,  1900,   72,  0,    51.80, 422.49, 'paid', TRUE),
    (3,  '2026-02-01', '2026-02-28', '2026-03-01', 75,  0.69, 150,    0,    18,  0,    10.50,  86.19,  'paid', TRUE),
    (4,  '2026-02-01', '2026-02-28', '2026-03-01', 370, 0.69, 410,  1400,   50,  0,    51.80, 422.49, 'paid', TRUE),
    (5,  '2026-02-01', '2026-02-28', '2026-03-01', 75,  0.69, 80,     0,    10,  0,    10.50,  86.19,  'paid', TRUE),
    (6,  '2026-02-01', '2026-02-28', '2026-03-01', 370, 0.69, 690,  2800,   95,  0,    51.80, 422.49, 'paid', TRUE),
    (7,  '2026-02-01', '2026-02-28', '2026-03-01', 75,  0.69, 190,    0,    25,  0,    10.50,  86.19,  'paid', TRUE),
    (8,  '2026-02-01', '2026-02-28', '2026-03-01', 370, 0.69, 350,  1200,   45,  0,    51.80, 422.49, 'paid', TRUE),
    (9,  '2026-02-01', '2026-02-28', '2026-03-01', 75,  0.69, 120,    0,    15,  0,    10.50,  86.19,  'paid', TRUE),
    (10, '2026-02-01', '2026-02-28', '2026-03-01', 370, 0.69, 470,  1750,   62,  0,    51.80, 422.49, 'paid', TRUE),
    (11, '2026-02-01', '2026-02-28', '2026-03-01', 75,  0.69, 820,    0,   175, 10.0,  6.07,  66.76,  'paid', TRUE),
    (12, '2026-02-01', '2026-02-28', '2026-03-01', 370, 0.69, 260,  800,    30,  0,    51.80, 422.49, 'paid', TRUE),
    (14, '2026-02-01', '2026-02-28', '2026-03-01', 370, 0.69, 390, 1050,    52,  0,    51.80, 422.49, 'paid', TRUE),
    (15, '2026-02-01', '2026-02-28', '2026-03-01', 950, 0.69, 750, 3500,   130,  0,    133.00, 1083.69, 'paid', TRUE),
    (16, '2026-02-01', '2026-02-28', '2026-03-01', 950, 0.69, 880, 4200,   160,  5.0,  35.47, 390.16, 'paid', TRUE),
    (17, '2026-02-01', '2026-02-28', '2026-03-01', 370, 0.69, 310,  950,    42,  0,    51.80, 422.49, 'paid', TRUE);

------------------------------------------------------------
-- BILLS (MARCH 2026) - mix of paid and issued
------------------------------------------------------------
INSERT INTO bill (
    contract_id, billing_period_start, billing_period_end, billing_date,
    recurring_fees, one_time_fees, voice_usage, data_usage, sms_usage,
    ROR_charge, taxes, total_amount, status, is_paid
) VALUES
    (1,  '2026-03-01', '2026-03-31', '2026-04-01', 75,  0.69, 310,    0,   42,  0,    10.50,  86.19,  'paid',   TRUE),
    (2,  '2026-03-01', '2026-03-31', '2026-04-01', 370, 0.69, 640,  2200,  80,  0,    51.80, 422.49, 'paid',   TRUE),
    (3,  '2026-03-01', '2026-03-31', '2026-04-01', 75,  0.69, 170,    0,   20,  0,    10.50,  86.19,  'issued', FALSE),
    (4,  '2026-03-01', '2026-03-31', '2026-04-01', 370, 0.69, 450,  1600,  58,  0,    51.80, 422.49, 'issued', FALSE),
    (5,  '2026-03-01', '2026-03-31', '2026-04-01', 75,  0.69, 90,     0,   11,  0,    10.50,  86.19,  'issued', FALSE),
    (6,  '2026-03-01', '2026-03-31', '2026-04-01', 370, 0.69, 720,  3100, 105,  0,    51.80, 422.49, 'issued', FALSE),
    (7,  '2026-03-01', '2026-03-31', '2026-04-01', 75,  0.69, 200,    0,   28,  0,    10.50,  86.19,  'issued', FALSE),
    (8,  '2026-03-01', '2026-03-31', '2026-04-01', 370, 0.69, 380,  1350,  50,  0,    51.80, 422.49, 'issued', FALSE),
    (9,  '2026-03-01', '2026-03-31', '2026-04-01', 75,  0.69, 130,    0,   16,  0,    10.50,  86.19,  'issued', FALSE),
    (10, '2026-03-01', '2026-03-31', '2026-04-01', 370, 0.69, 500,  1900,  68,  0,    51.80, 422.49, 'issued', FALSE),
    (11, '2026-03-01', '2026-03-31', '2026-04-01', 75,  0.69, 900,    0,  195, 14.5,  6.52,  71.71,  'issued', FALSE),
    (12, '2026-03-01', '2026-03-31', '2026-04-01', 370, 0.69, 280,  850,   35,  0,    51.80, 422.49, 'issued', FALSE),
    (14, '2026-03-01', '2026-03-31', '2026-04-01', 370, 0.69, 420, 1100,   55,  0,    51.80, 422.49, 'issued', FALSE),
    (15, '2026-03-01', '2026-03-31', '2026-04-01', 950, 0.69, 800, 3700,  140,  0,    133.00, 1083.69, 'issued', FALSE),
    (16, '2026-03-01', '2026-03-31', '2026-04-01', 950, 0.69, 920, 4800,  170,  8.0,  35.77, 393.46, 'issued', FALSE),
    (17, '2026-03-01', '2026-03-31', '2026-04-01', 370, 0.69, 330,  980,   45,  0,    51.80, 422.49, 'issued', FALSE);

------------------------------------------------------------
-- INVOICES (February bills only - all paid)
------------------------------------------------------------
INSERT INTO invoice (bill_id, pdf_path)
VALUES
    (1,  '/invoices/feb26_contract1.pdf'),
    (2,  '/invoices/feb26_contract2.pdf'),
    (3,  '/invoices/feb26_contract3.pdf'),
    (4,  '/invoices/feb26_contract4.pdf'),
    (5,  '/invoices/feb26_contract5.pdf'),
    (6,  '/invoices/feb26_contract6.pdf'),
    (7,  '/invoices/feb26_contract7.pdf'),
    (8,  '/invoices/feb26_contract8.pdf'),
    (9,  '/invoices/feb26_contract9.pdf'),
    (10, '/invoices/feb26_contract10.pdf'),
    (11, '/invoices/feb26_contract11.pdf'),
    (12, '/invoices/feb26_contract12.pdf'),
    (13, '/invoices/feb26_contract14.pdf'),
    (14, '/invoices/feb26_contract15.pdf'),
    (15, '/invoices/feb26_contract16.pdf'),
    (16, '/invoices/feb26_contract17.pdf'),
    -- March paid bills (contracts 1 and 2)
    (17, '/invoices/mar26_contract1.pdf'),
    (18, '/invoices/mar26_contract2.pdf');

------------------------------------------------------------
-- CDRs (APRIL 2026)
-- service_id: 1=Voice, 2=Data, 3=SMS, 4=FreeUnits
--             5=RoamVoice, 6=RoamData, 7=RoamSMS
-- duration: voice=seconds, data=MB, sms=1
------------------------------------------------------------
INSERT INTO cdr (file_id, dial_a, dial_b, start_time, duration, service_id, hplmn, vplmn, external_charges, rated_flag)
VALUES
    -- Alice (Basic: voice+sms)
    (1, '201000000001', '201000000002', '2026-04-01 09:15:00', 180,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000001', '201000000003', '2026-04-01 14:30:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000001', '201000000005', '2026-04-02 08:00:00', 300,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000001', '201000000007', '2026-04-03 11:20:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000001', '201000000009', '2026-04-04 10:05:00', 240,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000001', '201000000002', '2026-04-05 16:45:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000001', '201000000011', '2026-04-07 09:30:00', 420,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000001', '201000000013', '2026-04-08 13:00:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000001', '201000000015', '2026-04-09 17:20:00', 150,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000001', '201000000002', '2026-04-10 08:45:00', 360,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000001', '201000000003', '2026-04-12 12:10:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000001', '201000000017', '2026-04-14 15:30:00', 210,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000001', '201000000004', '2026-04-16 09:00:00', 270,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000001', '201000000006', '2026-04-18 14:00:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000001', '201000000008', '2026-04-20 10:30:00', 330,  1, 'EGYVO', NULL,   0, TRUE),

    -- Bob (Premium Gold: all packages + roaming)
    (1, '201000000002', '201000000001', '2026-04-01 08:30:00', 300,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000002', '201000000004', '2026-04-01 10:00:00', 500,  2, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000002', '201000000006', '2026-04-01 12:00:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000002', '201000000008', '2026-04-02 09:15:00', 450,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000002', '201000000010', '2026-04-02 14:30:00', 750,  2, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000002', '201000000012', '2026-04-03 08:00:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000002', '201000000001', '2026-04-04 11:45:00', 600,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000002', '201000000014', '2026-04-05 15:00:00', 1000, 2, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000002', '201000000016', '2026-04-06 09:30:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000002', '201000000018', '2026-04-07 13:20:00', 480,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000002', '201000000001', '2026-04-08 17:00:00', 800,  2, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000002', '201000000003', '2026-04-09 10:15:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    -- Bob roaming in Germany
    (2, '201000000002', '201000000001', '2026-04-15 10:00:00', 180,  5, 'EGYVO', 'DEUTS', 0, TRUE),
    (2, '201000000002', '201000000004', '2026-04-15 14:30:00', 200,  6, 'EGYVO', 'DEUTS', 0, TRUE),
    (2, '201000000002', '201000000006', '2026-04-16 09:00:00', 1,    7, 'EGYVO', 'DEUTS', 0, TRUE),
    (2, '201000000002', '201000000008', '2026-04-16 15:45:00', 120,  5, 'EGYVO', 'DEUTS', 0, TRUE),
    (2, '201000000002', '201000000001', '2026-04-17 11:00:00', 300,  6, 'EGYVO', 'DEUTS', 0, TRUE),

    -- Carol (Basic)
    (1, '201000000003', '201000000001', '2026-04-01 09:00:00', 120,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000003', '201000000005', '2026-04-02 11:30:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000003', '201000000007', '2026-04-04 14:00:00', 240,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000003', '201000000009', '2026-04-06 16:30:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000003', '201000000001', '2026-04-08 10:15:00', 180,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000003', '201000000011', '2026-04-10 13:45:00', 90,   1, 'EGYVO', NULL,   0, TRUE),

    -- David (Premium Gold)
    (1, '201000000004', '201000000002', '2026-04-01 08:00:00', 360,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000004', '201000000006', '2026-04-01 13:00:00', 600,  2, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000004', '201000000008', '2026-04-02 10:30:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000004', '201000000010', '2026-04-03 15:00:00', 420,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000004', '201000000012', '2026-04-05 09:45:00', 800,  2, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000004', '201000000002', '2026-04-07 14:00:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000004', '201000000014', '2026-04-09 11:30:00', 540,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000004', '201000000016', '2026-04-11 16:00:00', 700,  2, 'EGYVO', NULL,   0, TRUE),

    -- Eva (Basic)
    (1, '201000000005', '201000000001', '2026-04-01 10:00:00', 90,   1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000005', '201000000003', '2026-04-03 12:30:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000005', '201000000007', '2026-04-05 15:45:00', 150,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000005', '201000000009', '2026-04-08 09:00:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000005', '201000000001', '2026-04-11 11:15:00', 120,  1, 'EGYVO', NULL,   0, TRUE),

    -- Frank (Premium Gold - heavy user)
    (2, '201000000006', '201000000002', '2026-04-01 09:30:00', 540,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000006', '201000000008', '2026-04-01 13:00:00', 900,  2, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000006', '201000000010', '2026-04-02 08:15:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000006', '201000000012', '2026-04-02 14:00:00', 480,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000006', '201000000014', '2026-04-03 10:30:00', 1100, 2, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000006', '201000000002', '2026-04-04 15:45:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000006', '201000000016', '2026-04-05 09:00:00', 660,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000006', '201000000018', '2026-04-06 12:30:00', 850,  2, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000006', '201000000002', '2026-04-07 16:00:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000006', '201000000004', '2026-04-08 10:15:00', 720,  1, 'EGYVO', NULL,   0, TRUE),

    -- Grace (Basic)
    (2, '201000000007', '201000000001', '2026-04-01 08:45:00', 60,   1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000007', '201000000009', '2026-04-03 13:30:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000007', '201000000011', '2026-04-05 16:00:00', 120,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000007', '201000000001', '2026-04-08 10:00:00', 180,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000007', '201000000003', '2026-04-11 14:15:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000007', '201000000005', '2026-04-14 09:30:00', 240,  1, 'EGYVO', NULL,   0, TRUE),

    -- Henry (Premium Gold)
    (2, '201000000008', '201000000002', '2026-04-01 10:15:00', 300,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000008', '201000000004', '2026-04-02 12:00:00', 650,  2, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000008', '201000000006', '2026-04-03 15:30:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000008', '201000000010', '2026-04-04 09:00:00', 420,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000008', '201000000012', '2026-04-05 13:45:00', 750,  2, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000008', '201000000002', '2026-04-07 11:00:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000008', '201000000014', '2026-04-09 16:30:00', 390,  1, 'EGYVO', NULL,   0, TRUE),

    -- Iris (Basic)
    (2, '201000000009', '201000000001', '2026-04-01 11:00:00', 180,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000009', '201000000003', '2026-04-03 14:00:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000009', '201000000005', '2026-04-06 09:30:00', 150,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000009', '201000000007', '2026-04-09 12:45:00', 1,    3, 'EGYVO', NULL,   0, TRUE),

    -- Jack (Premium Gold)
    (2, '201000000010', '201000000002', '2026-04-01 09:45:00', 360,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000010', '201000000004', '2026-04-02 13:15:00', 700,  2, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000010', '201000000006', '2026-04-03 16:00:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000010', '201000000008', '2026-04-04 10:30:00', 480,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000010', '201000000012', '2026-04-05 14:00:00', 900,  2, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000010', '201000000002', '2026-04-07 09:15:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000010', '201000000014', '2026-04-09 15:45:00', 540,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000010', '201000000016', '2026-04-11 11:00:00', 800,  2, 'EGYVO', NULL,   0, TRUE),

    -- Karen (Basic - heavy user, near bundle limit)
    (1, '201000000011', '201000000001', '2026-04-01 08:00:00', 600,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000011', '201000000003', '2026-04-02 10:30:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000011', '201000000005', '2026-04-03 14:15:00', 480,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000011', '201000000007', '2026-04-04 16:45:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000011', '201000000009', '2026-04-05 09:30:00', 540,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000011', '201000000001', '2026-04-07 13:00:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000011', '201000000003', '2026-04-09 10:15:00', 420,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000011', '201000000005', '2026-04-11 15:30:00', 1,    3, 'EGYVO', NULL,   0, TRUE),

    -- Leo (Premium Gold)
    (1, '201000000012', '201000000002', '2026-04-01 11:30:00', 270,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000012', '201000000004', '2026-04-03 09:00:00', 550,  2, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000012', '201000000006', '2026-04-05 13:45:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000012', '201000000008', '2026-04-07 16:00:00', 330,  1, 'EGYVO', NULL,   0, TRUE),

    -- Noah (Premium Gold)
    (1, '201000000014', '201000000002', '2026-04-01 09:00:00', 390,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000014', '201000000004', '2026-04-02 11:30:00', 650,  2, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000014', '201000000006', '2026-04-03 14:00:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000014', '201000000008', '2026-04-05 16:30:00', 450,  1, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000014', '201000000010', '2026-04-07 10:15:00', 700,  2, 'EGYVO', NULL,   0, TRUE),
    (1, '201000000014', '201000000002', '2026-04-09 13:45:00', 1,    3, 'EGYVO', NULL,   0, TRUE),

    -- Olivia (Elite Enterprise - power user)
    (2, '201000000015', '201000000002', '2026-04-01 08:00:00', 480,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000015', '201000000004', '2026-04-01 10:30:00', 1200, 2, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000015', '201000000006', '2026-04-01 13:00:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000015', '201000000008', '2026-04-02 09:00:00', 600,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000015', '201000000010', '2026-04-02 14:00:00', 1500, 2, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000015', '201000000012', '2026-04-03 10:15:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000015', '201000000002', '2026-04-04 15:30:00', 720,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000015', '201000000016', '2026-04-05 09:45:00', 1800, 2, 'EGYVO', NULL,   0, TRUE),
    -- Olivia roaming in France
    (2, '201000000015', '201000000002', '2026-04-20 10:00:00', 240,  5, 'EGYVO', 'FRANC', 0, TRUE),
    (2, '201000000015', '201000000004', '2026-04-20 14:30:00', 400,  6, 'EGYVO', 'FRANC', 0, TRUE),
    (2, '201000000015', '201000000006', '2026-04-21 09:00:00', 1,    7, 'EGYVO', 'FRANC', 0, TRUE),

    -- Paul (Elite Enterprise - overage user)
    (2, '201000000016', '201000000002', '2026-04-01 09:30:00', 600,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000016', '201000000004', '2026-04-01 12:00:00', 1400, 2, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000016', '201000000006', '2026-04-01 15:30:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000016', '201000000008', '2026-04-02 08:30:00', 780,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000016', '201000000010', '2026-04-02 13:00:00', 1600, 2, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000016', '201000000012', '2026-04-03 10:00:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000016', '201000000014', '2026-04-03 16:00:00', 840,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000016', '201000000002', '2026-04-04 11:30:00', 1800, 2, 'EGYVO', NULL,   0, TRUE),

    -- Quinn (Premium Gold)
    (2, '201000000017', '201000000002', '2026-04-01 10:00:00', 300,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000017', '201000000004', '2026-04-02 12:30:00', 600,  2, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000017', '201000000006', '2026-04-03 15:00:00', 1,    3, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000017', '201000000008', '2026-04-05 09:30:00', 420,  1, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000017', '201000000010', '2026-04-07 14:00:00', 750,  2, 'EGYVO', NULL,   0, TRUE),
    (2, '201000000017', '201000000002', '2026-04-09 11:15:00', 1,    3, 'EGYVO', NULL,   0, TRUE);

------------------------------------------------------------
-- MARK MSISDNs AS TAKEN
------------------------------------------------------------
UPDATE msisdn_pool
SET is_available = FALSE
WHERE msisdn IN (SELECT msisdn FROM contract);

------------------------------------------------------------
-- GENERATE 30 REALISTIC ADDITIONAL CUSTOMERS
------------------------------------------------------------
DO $$
DECLARE
    v_user_id INTEGER;
    v_msisdn VARCHAR(20);
    v_rateplan_id INTEGER;
    v_first_names TEXT[] := ARRAY['Ahmed', 'Mohamed', 'Sara', 'Mona', 'Hassan', 'Youssef', 'Layla', 'Omar', 'Nour', 'Amir', 'Ziad', 'Mariam', 'Fatma', 'Ibrahim', 'Salma'];
    v_last_names TEXT[]  := ARRAY['Hassan', 'Mansour', 'Zaki', 'Khattab', 'Fouad', 'Salem', 'Nasr', 'Said', 'Gaber', 'Ezzat', 'Wahba', 'Soliman'];
    v_streets TEXT[]     := ARRAY['El-Nasr St', 'Cornish Rd', '9th Street', 'Tahrir Sq', 'Abbas El Akkad', 'Makram Ebeid', 'Gameat El Dowal'];
    v_cities TEXT[]      := ARRAY['Cairo', 'Giza', 'Alexandria', 'Mansoura', 'Suez', 'Luxor'];
    v_fname TEXT;
    v_lname TEXT;
    v_uname TEXT;
BEGIN
    FOR i IN 1..30 LOOP
        v_fname := v_first_names[1 + FLOOR(RANDOM() * ARRAY_LENGTH(v_first_names, 1))];
        v_lname := v_last_names[1 + FLOOR(RANDOM() * ARRAY_LENGTH(v_last_names, 1))];
        v_uname := LOWER(v_fname) || '_' || (100 + i);

        INSERT INTO user_account (name, address, birthdate, role, username, password, email)
        VALUES (
            v_fname || ' ' || v_lname,
            (10 + FLOOR(RANDOM() * 90)) || ' ' || v_streets[1 + FLOOR(RANDOM() * ARRAY_LENGTH(v_streets, 1))] || ', ' || v_cities[1 + FLOOR(RANDOM() * ARRAY_LENGTH(v_cities, 1))],
            '1985-01-01'::DATE + (FLOOR(RANDOM() * 10000) || ' days')::INTERVAL,
            'customer',
            v_uname,
            '123456', -- Simple password as requested
            LOWER(v_fname) || '.' || LOWER(v_lname) || (10 + i) || '@fmrz-telecom.com'
        ) RETURNING id INTO v_user_id;

        SELECT msisdn INTO v_msisdn FROM msisdn_pool WHERE is_available = TRUE LIMIT 1;
        UPDATE msisdn_pool SET is_available = FALSE WHERE msisdn = v_msisdn;

        v_rateplan_id := FLOOR(RANDOM() * 3 + 1);

        INSERT INTO contract (user_account_id, rateplan_id, msisdn, status, credit_limit, available_credit)
        VALUES (v_user_id, v_rateplan_id, v_msisdn, 'active', 300, 300);

        PERFORM initialize_consumption_period(CURRENT_DATE);
    END LOOP;
END;
$$;


-- ============================================================
-- AUTOMATION: NOTIFY BILL GENERATION
-- ============================================================
CREATE OR REPLACE FUNCTION notify_bill_generation()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_notify('generate_bill_event', NEW.id::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_bill_inserted
AFTER INSERT ON bill
FOR EACH ROW
EXECUTE FUNCTION notify_bill_generation();

-- ------------------------------------------------------------
-- GET BILL USAGE BREAKDOWN
-- Returns detailed line items for a given bill, showing
-- bundle consumption, overage, roaming, and promotional items.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_bill_usage_breakdown(p_bill_id INTEGER)
RETURNS TABLE (
    service_type      TEXT,
    category_label    TEXT,
    quota             INTEGER,
    consumed          INTEGER,
    unit_rate         NUMERIC(12,4),
    line_total        NUMERIC(12,2),
    is_roaming        BOOLEAN,
    is_promotional    BOOLEAN,
    notes             TEXT
) AS $$
DECLARE
    v_contract_id INTEGER;
    v_period_start DATE;
BEGIN
    -- Get contract and period for this bill
    SELECT contract_id, billing_period_start INTO v_contract_id, v_period_start
    FROM bill WHERE id = p_bill_id;
    
    -- 1. Bundled usage from contract_consumption (linked by bill_id)
    -- We ensure even 0-usage bundles show up if they were part of the billing period.
    RETURN QUERY
    SELECT 
        sp.type::TEXT AS service_type,
        sp.name::TEXT AS category_label,
        cc.quota_limit::INTEGER AS quota,
        cc.consumed::INTEGER AS consumed,
        0::NUMERIC(12,4) AS unit_rate,
        0::NUMERIC(12,2) AS line_total,
        sp.is_roaming,
        (sp.name ~* 'Welcome|Gift|Bonus|Bonus') AS is_promotional,
        CASE 
            WHEN cc.consumed >= cc.quota_limit THEN 'Bundle fully utilized'::TEXT
            WHEN cc.consumed = 0 THEN 'No usage recorded'::TEXT
            ELSE 'Partial bundle usage'::TEXT
        END AS notes
    FROM contract_consumption cc
    JOIN service_package sp ON cc.service_package_id = sp.id
    WHERE cc.bill_id = p_bill_id
    
    UNION ALL
    
    -- 2. Domestic overage (from ror_contract non-roaming columns)
    SELECT 
        'voice'::TEXT AS service_type,
        'Overage - Voice'::TEXT AS category_label,
        NULL::INTEGER AS quota,
        rc.voice::INTEGER AS consumed,
        rp.ror_voice AS unit_rate,
        ROUND((rc.voice * rp.ror_voice)::NUMERIC, 2) AS line_total,
        FALSE AS is_roaming,
        FALSE AS is_promotional,
        'Overage minutes beyond bundle allowance'::TEXT AS notes
    FROM ror_contract rc
    JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.contract_id = v_contract_id
      AND rc.bill_id = p_bill_id
      AND rc.voice > 0
    
    UNION ALL
    SELECT 
        'data'::TEXT AS service_type,
        'Overage - Data'::TEXT AS category_label,
        NULL::INTEGER, 
        (rc.data / 1024 / 1024)::INTEGER, -- Show as MB in consumed
        rp.ror_data,
        ROUND((rc.data / 1073741824.0 * rp.ror_data)::NUMERIC, 2), -- Convert Bytes to GB for pricing
        FALSE, FALSE,
        'Overage data beyond bundle allowance'::TEXT
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.contract_id = v_contract_id AND rc.bill_id = p_bill_id AND rc.data > 0
    
    UNION ALL
    -- 3. Roaming overage (from ror_contract roaming columns)
    SELECT 
        'voice'::TEXT AS service_type,
        'Roaming Overage - Voice'::TEXT AS category_label,
        NULL::INTEGER, rc.roaming_voice::INTEGER, rp.ror_roaming_voice,
        ROUND((rc.roaming_voice * rp.ror_roaming_voice)::NUMERIC, 2),
        TRUE, FALSE, 'Roaming overage minutes'::TEXT
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.contract_id = v_contract_id AND rc.bill_id = p_bill_id AND rc.roaming_voice > 0
    
    UNION ALL
    SELECT 
        'data'::TEXT AS service_type,
        'Roaming Overage - Data'::TEXT AS category_label,
        NULL::INTEGER, (rc.roaming_data / 1024 / 1024)::INTEGER, rp.ror_roaming_data,
        ROUND((rc.roaming_data / 1073741824.0 * rp.ror_roaming_data)::NUMERIC, 2),
        TRUE, FALSE, 'Roaming overage data (MB)'::TEXT
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.contract_id = v_contract_id AND rc.bill_id = p_bill_id AND rc.roaming_data > 0
    
    UNION ALL
    SELECT 
        'sms'::TEXT AS service_type,
        'Overage - SMS'::TEXT AS category_label,
        NULL::INTEGER, rc.sms::INTEGER, rp.ror_sms,
        ROUND((rc.sms * rp.ror_sms)::NUMERIC, 2), FALSE, FALSE,
        'Overage SMS beyond bundle allowance'::TEXT
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.contract_id = v_contract_id AND rc.bill_id = p_bill_id AND rc.sms > 0

    UNION ALL
    SELECT 
        'sms'::TEXT AS service_type,
        'Roaming Overage - SMS'::TEXT AS category_label,
        NULL::INTEGER, rc.roaming_sms::INTEGER, rp.ror_roaming_sms,
        ROUND((rc.roaming_sms * rp.ror_roaming_sms)::NUMERIC, 2),
        TRUE, FALSE, 'Roaming overage SMS'::TEXT
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.contract_id = v_contract_id AND rc.bill_id = p_bill_id AND rc.roaming_sms > 0
    
    ORDER BY service_type, is_roaming DESC, category_label;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- FINAL SYSTEM OPTIMIZATION
-- ============================================================
-- 1. Sync all quota limits that were missed during bulk insertion
UPDATE contract_consumption cc
SET quota_limit = sp.amount
FROM service_package sp
WHERE cc.service_package_id = sp.id AND cc.quota_limit = 0;

-- 2. Final Global Security Sweep
UPDATE user_account SET password = '123456';
COMMIT;


--==========================================================
-- 1. add_new_service_package
-- Creates a new service bundle (Voice/Data/SMS) in the catalog.
-- Parameters: name, type, amount, priority, price, description, is_roaming.
-- Returns: The ID of the newly created package.
--==========================================================
CREATE OR REPLACE FUNCTION add_new_service_package(
    p_name character varying,
    p_type public.service_type,
    p_amount numeric,
    p_priority integer,
    p_price numeric,
    p_description text DEFAULT NULL,
    p_is_roaming boolean DEFAULT false
) RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_new_id INTEGER;
BEGIN
    INSERT INTO service_package (name, type, amount, priority, price, description, is_roaming)
    VALUES (p_name, p_type, p_amount, p_priority, p_price, p_description, p_is_roaming)
    RETURNING id INTO v_new_id;

    RETURN v_new_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'add_new_service_package failed: %', SQLERRM;
END;
$$;

--==========================================================
-- 2. update_service_package
-- Updates an existing service package's details.
-- Parameters: id (target), plus all package fields.
-- Returns: The updated record as a table row.
--==========================================================
CREATE OR REPLACE FUNCTION update_service_package(
    p_id INTEGER,
    p_name VARCHAR(255),
    p_type service_type,
    p_amount NUMERIC(12,4),
    p_priority INTEGER,
    p_price NUMERIC(12,2),
    p_description TEXT,
    p_is_roaming BOOLEAN DEFAULT FALSE
) RETURNS TABLE(
    id INTEGER,
    name VARCHAR(255),
    type service_type,
    amount NUMERIC(12,4),
    priority INTEGER,
    price NUMERIC(12,2),
    description TEXT,
    is_roaming BOOLEAN
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
        UPDATE service_package 
        SET 
            name = p_name,
            type = p_type,
            amount = p_amount,
            priority = p_priority,
            price = p_price,
            description = p_description,
            is_roaming = p_is_roaming
        WHERE service_package.id = p_id
        RETURNING 
            service_package.id,
            service_package.name,
            service_package.type,
            service_package.amount,
            service_package.priority,
            service_package.price,
            service_package.description,
            service_package.is_roaming;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Service package with id % not found', p_id;
    END IF;
END;
$$;

--==========================================================
-- 3. delete_service_package
-- Safely removes a service package from the catalog.
-- Logic: Checks for active contract consumptions or active addons before deleting
-- to prevent foreign key or business logic violations.
-- Parameters: p_id (ID of the package to delete).
--==========================================================
CREATE OR REPLACE FUNCTION delete_service_package(p_id INTEGER) 
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    -- Check if service package is referenced in any active contracts or addons
    IF EXISTS (
        SELECT 1 FROM contract_consumption cc 
        WHERE cc.service_package_id = p_id AND cc.is_billed = FALSE
    ) THEN
        RAISE EXCEPTION 'Cannot delete service package: it has active consumption records';
    END IF;

    IF EXISTS (
        SELECT 1 FROM contract_addon ca 
        WHERE ca.service_package_id = p_id AND ca.is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'Cannot delete service package: it has active addons';
    END IF;

    DELETE FROM service_package WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Service package with id % not found', p_id;
    END IF;
END;
$$;

--==========================================================
-- 4. create_rateplan_with_packages
-- Atomic operation to create a Rate Plan and link it to multiple Service Packages.
-- Parameters: name, overage rates (ror), base price, and an ARRAY of service package IDs.
-- Logic: Creates rateplan first, then loops through IDs to populate rateplan_service_package.
--==========================================================
CREATE OR REPLACE FUNCTION create_rateplan_with_packages(
    p_name VARCHAR(255),
    p_ror_voice NUMERIC(10,2),
    p_ror_data NUMERIC(10,2), 
    p_ror_sms NUMERIC(10,2),
    p_price NUMERIC(10,2),
    p_service_package_ids INTEGER[]
) RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_rateplan_id INTEGER;
    v_package_id INTEGER;
BEGIN
    -- Create the rateplan
    INSERT INTO rateplan (name, ror_voice, ror_data, ror_sms, price)
    VALUES (p_name, p_ror_voice, p_ror_data, p_ror_sms, p_price)
    RETURNING id INTO v_rateplan_id;

    -- Link service packages to the rateplan
    IF p_service_package_ids IS NOT NULL THEN
        FOREACH v_package_id IN ARRAY p_service_package_ids
        LOOP
            IF NOT EXISTS (SELECT 1 FROM service_package WHERE id = v_package_id) THEN
                RAISE EXCEPTION 'Service package with id % does not exist', v_package_id;
            END IF;

            INSERT INTO rateplan_service_package (rateplan_id, service_package_id)
            VALUES (v_rateplan_id, v_package_id);
        END LOOP;
    END IF;

    RETURN v_rateplan_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'create_rateplan_with_packages failed: %', SQLERRM;
END;
$$;

--==========================================================
-- 5. delete_rateplan
-- Safely removes a rate plan and its bundle associations.
-- Logic: Prevents deletion if any active customer contracts are currently using this plan.
-- Parameters: p_rateplan_id.
--==========================================================
CREATE OR REPLACE FUNCTION delete_rateplan(p_rateplan_id INTEGER) RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    -- Check if rateplan is used by any active contracts
    IF EXISTS (SELECT 1 FROM contract WHERE rateplan_id = p_rateplan_id) THEN
        RAISE EXCEPTION 'Cannot delete rateplan: it is assigned to active contracts';
    END IF;

    -- Delete service package associations first
    DELETE FROM rateplan_service_package WHERE rateplan_id = p_rateplan_id;

    -- Delete the rateplan
    DELETE FROM rateplan WHERE id = p_rateplan_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Rateplan with id % not found', p_rateplan_id;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'delete_rateplan failed: %', SQLERRM;
END;
$$;

--==========================================================
-- 6. update_rateplan
-- Multi-purpose function to update Rate Plan metadata and its linked bundles.
-- Parameters: id, plus optional fields (COALESCE handles partial updates).
-- Logic: If p_service_package_ids is provided, it clears and replaces old associations.
--==========================================================
CREATE OR REPLACE FUNCTION update_rateplan(
    p_rateplan_id INTEGER,
    p_name VARCHAR(255) DEFAULT NULL,
    p_ror_voice NUMERIC(10,2) DEFAULT NULL,
    p_ror_data NUMERIC(10,2) DEFAULT NULL,
    p_ror_sms NUMERIC(10,2) DEFAULT NULL,
    p_price NUMERIC(10,2) DEFAULT NULL,
    p_service_package_ids INTEGER[] DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_package_id INTEGER;
BEGIN
    -- Check if rateplan exists
    IF NOT EXISTS (SELECT 1 FROM rateplan WHERE id = p_rateplan_id) THEN
        RAISE EXCEPTION 'Rateplan with id % does not exist', p_rateplan_id;
    END IF;

    -- Update rateplan fields (only non-null values)
    UPDATE rateplan 
    SET 
        name = COALESCE(p_name, name),
        ror_voice = COALESCE(p_ror_voice, ror_voice),
        ror_data = COALESCE(p_ror_data, ror_data),
        ror_sms = COALESCE(p_ror_sms, ror_sms),
        price = COALESCE(p_price, price)
    WHERE id = p_rateplan_id;

    -- Update service package associations if provided
    IF p_service_package_ids IS NOT NULL THEN
        -- Remove existing associations
        DELETE FROM rateplan_service_package WHERE rateplan_id = p_rateplan_id;

        -- Add new associations
        FOREACH v_package_id IN ARRAY p_service_package_ids
        LOOP
            IF NOT EXISTS (SELECT 1 FROM service_package WHERE id = v_package_id) THEN
                RAISE EXCEPTION 'Service package with id % does not exist', v_package_id;
            END IF;

            INSERT INTO rateplan_service_package (rateplan_id, service_package_id)
            VALUES (p_rateplan_id, v_package_id);
        END LOOP;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'update_rateplan failed: %', SQLERRM;
END;
$$;

--==========================================================
-- 10. get_rateplan_data
-- Fetches detailed metadata for a specific rate plan.
-- Parameters: p_rateplan_id.
-- Returns: TABLE with id, name, ror_data, ror_voice, ror_sms, price.
--==========================================================
CREATE OR REPLACE FUNCTION get_rateplan_data(p_rateplan_id INTEGER)
RETURNS TABLE(
    id INTEGER,
    name VARCHAR(255),
    ror_data NUMERIC(10,2),
    ror_voice NUMERIC(10,2),
    ror_sms NUMERIC(10,2),
    price NUMERIC(10,2)
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
        SELECT 
            r.id,
            r.name,
            r.ror_data,
            r.ror_voice,
            r.ror_sms,
            r.price
        FROM rateplan r
        WHERE r.id = p_rateplan_id;
END;
$$;
