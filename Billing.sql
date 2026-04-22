-- ============================================================
-- TELECOM BILLING SCHEMA
-- ============================================================
DROP TABLE IF EXISTS cdr,invoice,bill,ror_contract,contract_consumption,contract,rateplan_service_package,service_package,rateplan,customer,user_account,file CASCADE;
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
                          role     user_role NOT NULL
);

-- ------------------------------------------------------------
-- CUSTOMER
-- ------------------------------------------------------------
CREATE TABLE customer (
                          id        SERIAL PRIMARY KEY,
                          name      VARCHAR(255) NOT NULL,
                          address   TEXT,
                          birthdate DATE
);
ALTER TABLE customer
    ADD COLUMN user_account_id INTEGER REFERENCES user_account(id);

-- ------------------------------------------------------------
-- RATEPLAN
-- ------------------------------------------------------------
CREATE TABLE rateplan (
                          id        SERIAL PRIMARY KEY,
                          name      VARCHAR(255) NOT NULL,
                          ror_data  NUMERIC(10,2),     -- e.g. 0.05
                          ror_voice NUMERIC(10,2),     -- e.g. 0.05
                          ror_sms   NUMERIC(10,2),     -- e.g. 0.05
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
                                 priority INTEGER NOT NULL DEFAULT 1 -- for consumption order (lower = consumed first)
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
CREATE TYPE contract_status AS ENUM ('active', 'suspended', 'terminated');
CREATE TABLE contract (
                          id              SERIAL PRIMARY KEY,
                          customer_id     INTEGER NOT NULL REFERENCES customer(id),
                          rateplan_id     INTEGER NOT NULL REFERENCES rateplan(id),
                          msisdn          VARCHAR(20) NOT NULL UNIQUE,
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

                            consumed            INTEGER NOT NULL DEFAULT 0,

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
                              data        INTEGER,
                              voice       INTEGER,
                              sms         INTEGER,
                              PRIMARY KEY (contract_id, rateplan_id)
    -- bill_id added after bill table below (FK added via ALTER)
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
                         bill_id          INTEGER NOT NULL REFERENCES bill(id),
                         pdf_path         TEXT,
                         generation_date  TIMESTAMP NOT NULL DEFAULT NOW()
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
                     rated_flag       BOOLEAN NOT NULL DEFAULT FALSE
);


-- ============================================================
-- INDEXES (performance basics)
-- ============================================================
CREATE INDEX idx_cdr_rated_flag     ON cdr(rated_flag);
CREATE INDEX idx_cdr_file_id        ON cdr(file_id);
CREATE INDEX idx_cdr_dial_a         ON cdr(dial_a);
CREATE INDEX idx_contract_msisdn    ON contract(msisdn);
CREATE INDEX idx_contract_customer  ON contract(customer_id);
CREATE INDEX idx_bill_contract      ON bill(contract_id);
CREATE INDEX idx_bill_billing_date  ON bill(billing_date);
CREATE INDEX idx_invoice_bill       ON invoice(bill_id);

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
           WHEN 'free_units' THEN 1
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
v_new_id INTEGER;
BEGIN
    -- Validate file exists
    IF NOT EXISTS (SELECT 1 FROM file WHERE id = p_file_id) THEN
        RAISE EXCEPTION 'File with id % does not exist', p_file_id;
END IF;

    -- Validate service_package exists if provided
    IF p_service_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM service_package WHERE id = p_service_id
    ) THEN
        RAISE EXCEPTION 'Service package with id % does not exist', p_service_id;
END IF;

    -- Validate dial_a is not empty
    IF p_dial_a IS NULL OR TRIM(p_dial_a) = '' THEN
        RAISE EXCEPTION 'dial_a (calling party MSISDN) cannot be empty';
END IF;

    -- Validate duration is non-negative
    IF p_duration < 0 THEN
        RAISE EXCEPTION 'Duration cannot be negative';
END IF;

INSERT INTO cdr (
    file_id,
    dial_a,
    dial_b,
    start_time,
    duration,
    service_id,
    hplmn,
    vplmn,
    external_charges,
    rated_flag
)
VALUES (
           p_file_id,
           p_dial_a,
           p_dial_b,
           p_start_time,
           p_duration,
           p_service_id,
           p_hplmn,
           p_vplmn,
           COALESCE(p_external_charges, 0),
           FALSE
       )
    RETURNING id INTO v_new_id;

RETURN v_new_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'insert_cdr failed: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- RATE CDR
-- Deducts usage from bundles in priority order,
-- writes any overage to ror_contract,
-- deducts overage charge from available_credit.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION rate_cdr(p_cdr_id INTEGER)
RETURNS VOID AS $$
DECLARE
v_cdr            cdr;
    v_contract       contract;
    v_service_type   service_type;
    v_usage_amount   NUMERIC;
    v_remaining      NUMERIC;
    v_bundle         RECORD;
    v_available      NUMERIC;
    v_deduct         NUMERIC;
    v_ror_rate       NUMERIC;
    v_overage_charge NUMERIC := 0;
    v_period_start   DATE;
    v_period_end     DATE;
BEGIN
    -- Load CDR
SELECT * INTO v_cdr FROM cdr WHERE id = p_cdr_id;
IF NOT FOUND THEN
        RAISE EXCEPTION 'CDR with id % not found', p_cdr_id;
END IF;

    -- Guard: skip if already rated
    IF v_cdr.rated_flag THEN
        RAISE NOTICE 'CDR % already rated, skipping.', p_cdr_id;
        RETURN;
END IF;

    -- Resolve active contract from dial_a
SELECT * INTO v_contract
FROM contract
WHERE msisdn = v_cdr.dial_a
  AND status = 'active';
IF NOT FOUND THEN
        RAISE EXCEPTION 'No active contract found for MSISDN %', v_cdr.dial_a;
END IF;

    -- Resolve service type from the CDR's service_package
SELECT type INTO v_service_type
FROM service_package
WHERE id = v_cdr.service_id;
IF NOT FOUND THEN
        RAISE EXCEPTION 'Service package with id % not found', v_cdr.service_id;
END IF;

    -- Normalise usage into the unit used by contract_consumption
    v_usage_amount := get_cdr_usage_amount(v_cdr.duration, v_service_type);
    v_remaining    := v_usage_amount;

    -- Billing period boundaries
    v_period_start := DATE_TRUNC('month', v_cdr.start_time)::DATE;
    v_period_end   := (DATE_TRUNC('month', v_cdr.start_time) + INTERVAL '1 month - 1 day')::DATE;

    -- Deduct from bundles in priority order
FOR v_bundle IN
SELECT
    cc.service_package_id,
    cc.rateplan_id,
    cc.starting_date,
    cc.ending_date,
    sp.amount,
    sp.priority,
    cc.consumed
FROM contract_consumption cc
         JOIN service_package sp ON sp.id = cc.service_package_id
WHERE cc.contract_id   = v_contract.id
  AND cc.rateplan_id   = v_contract.rateplan_id
  AND cc.starting_date = v_period_start
  AND cc.ending_date   = v_period_end
  AND cc.is_billed     = FALSE
  AND sp.type          = v_service_type   -- only match relevant service type
ORDER BY sp.priority ASC
    LOOP
        EXIT WHEN v_remaining <= 0;

v_available := v_bundle.amount - v_bundle.consumed;

        IF v_available <= 0 THEN
            CONTINUE;  -- bundle exhausted, move to next
END IF;

        v_deduct    := LEAST(v_remaining, v_available);
        v_remaining := v_remaining - v_deduct;

UPDATE contract_consumption
SET consumed = consumed + v_deduct
WHERE contract_id        = v_contract.id
  AND service_package_id = v_bundle.service_package_id
  AND rateplan_id        = v_bundle.rateplan_id
  AND starting_date      = v_bundle.starting_date
  AND ending_date        = v_bundle.ending_date;
END LOOP;

    -- Handle overage: anything remaining after all bundles exhausted
    IF v_remaining > 0 AND v_service_type != 'free_units' THEN
SELECT CASE v_service_type
           WHEN 'voice' THEN ror_voice
           WHEN 'data'  THEN ror_data
           WHEN 'sms'   THEN ror_sms
           END INTO v_ror_rate
FROM rateplan
WHERE id = v_contract.rateplan_id;

v_overage_charge := v_remaining * COALESCE(v_ror_rate, 0);

        -- Accumulate overage units in ror_contract
INSERT INTO ror_contract (contract_id, rateplan_id, voice, data, sms)
VALUES (
           v_contract.id,
           v_contract.rateplan_id,
           CASE WHEN v_service_type = 'voice' THEN v_remaining ELSE 0 END,
           CASE WHEN v_service_type = 'data'  THEN v_remaining ELSE 0 END,
           CASE WHEN v_service_type = 'sms'   THEN v_remaining ELSE 0 END
       )
    ON CONFLICT (contract_id, rateplan_id) DO UPDATE SET
    voice = ror_contract.voice + EXCLUDED.voice,
                                                  data  = ror_contract.data  + EXCLUDED.data,
                                                  sms   = ror_contract.sms   + EXCLUDED.sms;

-- Deduct overage charge from available credit
UPDATE contract
SET available_credit = available_credit - v_overage_charge
WHERE id = v_contract.id;
END IF;

    -- Mark CDR as rated
UPDATE cdr
SET rated_flag = TRUE
WHERE id = p_cdr_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'rate_cdr failed for CDR id %: %', p_cdr_id, SQLERRM;
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
    is_billed
)
SELECT
    c.id,
    rsp.service_package_id,
    c.rateplan_id,
    p_period_start,
    v_period_end,
    0,
    FALSE
FROM contract c
         JOIN rateplan_service_package rsp ON rsp.rateplan_id = c.rateplan_id
WHERE c.status = 'active'
    ON CONFLICT DO NOTHING;  -- safe to re-run

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'initialize_consumption_period failed for period %: %', p_period_start, SQLERRM;
END;
$$ LANGUAGE plpgsql;


-- ------------------------------------------------------------
-- GENERATE BILL
-- Aggregates consumption + overage into a bill row.
-- Marks consumption rows and ror_contract row as billed.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION generate_bill(p_contract_id INTEGER, p_billing_period_start DATE)
       RETURNS VOID AS $$
       DECLARE v_billing_period_end DATE;
               v_recurring_fees NUMERIC(12,2);
               v_one_time_fees NUMERIC(12,2);
               v_voice_usage INTEGER;
               v_data_usage INTEGER;
               v_sms_usage INTEGER;
               v_ROR_charge NUMERIC(12,2);
               v_taxes NUMERIC(12,2);
               v_total_amount NUMERIC(12,2);
               v_rateplan_id INTEGER;
               v_bill_id INTEGER;
               BEGIN
               v_billing_period_end := (DATE_TRUNC('month', p_billing_period_start) + INTERVAL '1 month - 1 day')::DATE;
                -- Load rateplan_id for convenience
SELECT rateplan_id INTO v_rateplan_id
FROM contract
WHERE id = p_contract_id;

    -- Calculate recurring fees from rateplan price
SELECT price INTO v_recurring_fees
FROM rateplan
WHERE id = v_rateplan_id;

    -- Calculate usage fees from consumption and ROR
        SELECT SUM(CASE WHEN sp.type = 'voice' THEN cc.consumed ELSE 0 END),
               SUM(CASE WHEN sp.type = 'data' THEN cc.consumed ELSE 0 END),
               SUM(CASE WHEN sp.type = 'sms' THEN cc.consumed ELSE 0 END)

INTO v_voice_usage, v_data_usage, v_sms_usage
FROM contract_consumption cc
        JOIN service_package sp ON sp.id = cc.service_package_id
        WHERE cc.contract_id = p_contract_id
          AND cc.starting_date = p_billing_period_start
          AND cc.ending_date = v_billing_period_end
          AND cc.is_billed = FALSE;
SELECT COALESCE(
    (rc.data * rp.ror_data) + (rc.voice * rp.ror_voice) + (rc.sms * rp.ror_sms),0) INTO v_ROR_charge
FROM ror_contract rc
JOIN rateplan rp ON rp.id = rc.rateplan_id
WHERE contract_id = p_contract_id
  AND rateplan_id = v_rateplan_id
  AND bill_id IS NULL;  -- only consider unbilled ROR

    -- For simplicity, let's say taxes are 15% of (recurring + ROR)
v_one_time_fees := 0.69;  -- could include one-time charges here
v_taxes := 0.15 * (v_recurring_fees + v_ROR_charge);
v_total_amount := v_recurring_fees + v_one_time_fees + v_ROR_charge + v_taxes;

    -- Insert bill
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
    ROR_charge,
    taxes,
    total_amount,
    status,
    is_paid
)VALUES (
           p_contract_id,
           p_billing_period_start,
           v_billing_period_end,
           CURRENT_DATE,
           v_recurring_fees,
           v_one_time_fees,
           v_voice_usage,
           v_data_usage,
           v_sms_usage,
           v_ROR_charge,
           v_taxes,
           v_total_amount,
           'issued',
           FALSE
       )RETURNING id INTO v_bill_id;
    -- Mark consumption and ROR rows as billed
UPDATE contract_consumption
SET is_billed = TRUE, bill_id = v_bill_id
WHERE contract_id = p_contract_id
  AND starting_date = p_billing_period_start
  AND ending_date = v_billing_period_end;
UPDATE ror_contract
SET bill_id = v_bill_id
WHERE contract_id = p_contract_id  AND rateplan_id = v_rateplan_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'generate_bill failed for contract id % and period %: %', p_contract_id, p_billing_period_start, SQLERRM;
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
FOR v_contract IN
SELECT id FROM contract WHERE status = 'active'
    LOOP
BEGIN
            PERFORM generate_bill(v_contract.id, p_period_start);
            v_success := v_success + 1;
EXCEPTION
            WHEN OTHERS THEN
                -- Log failure but continue processing remaining contracts
                RAISE WARNING 'generate_bill failed for contract %: %', v_contract.id, SQLERRM;
                v_failed := v_failed + 1;
END;
END LOOP;

    RAISE NOTICE 'generate_all_bills complete: % succeeded, % failed', v_success, v_failed;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- CREATE CONTRACT
-- Creates a new contract and immediately initializes
-- consumption rows for the current billing period.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_contract(
    p_customer_id    INTEGER,
    p_rateplan_id    INTEGER,
    p_msisdn         VARCHAR(20),
    p_credit_limit   NUMERIC(12,2)
)
RETURNS INTEGER AS $$
DECLARE
v_contract_id  INTEGER;
    v_period_start DATE;
    v_period_end   DATE;
BEGIN
    -- Validate customer exists
    IF NOT EXISTS (SELECT 1 FROM customer WHERE id = p_customer_id) THEN
        RAISE EXCEPTION 'Customer with id % does not exist', p_customer_id;
END IF;

    -- Validate rateplan exists
    IF NOT EXISTS (SELECT 1 FROM rateplan WHERE id = p_rateplan_id) THEN
        RAISE EXCEPTION 'Rateplan with id % does not exist', p_rateplan_id;
END IF;

    -- Validate MSISDN is not already taken
    IF EXISTS (SELECT 1 FROM contract WHERE msisdn = p_msisdn) THEN
        RAISE EXCEPTION 'MSISDN % is already assigned to another contract', p_msisdn;
END IF;

    -- Insert contract
INSERT INTO contract (
    customer_id,
    rateplan_id,
    msisdn,
    status,
    credit_limit,
    available_credit
) VALUES (
             p_customer_id,
             p_rateplan_id,
             p_msisdn,
             'active',
             p_credit_limit,
             p_credit_limit   -- available starts equal to limit
         )
    RETURNING id INTO v_contract_id;

-- Initialize an empty ror_contract row for this contract
INSERT INTO ror_contract (contract_id, rateplan_id, voice, data, sms)
VALUES (v_contract_id, p_rateplan_id, 0, 0, 0);

-- Initialize consumption rows for the current billing period
v_period_start := DATE_TRUNC('month', CURRENT_DATE)::DATE;
    v_period_end   := (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE;

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
    v_contract_id,
    rsp.service_package_id,
    p_rateplan_id,
    v_period_start,
    v_period_end,
    0,
    FALSE
FROM rateplan_service_package rsp
WHERE rsp.rateplan_id = p_rateplan_id
    ON CONFLICT DO NOTHING;

RETURN v_contract_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'create_contract failed: %', SQLERRM;
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
    contract_id,
    billing_period_start,
    billing_period_end,
    billing_date,
    recurring_fees,
    one_time_fees,
    voice_usage,
    data_usage,
    sms_usage,
    ROR_charge,
    taxes,
    total_amount,
    status,
    is_paid
FROM bill
WHERE id = p_bill_id;
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
    CREATE OR REPLACE FUNCTION change_contract_status(p_contract_id INTEGER, p_status contract_status)
           RETURNS VOID AS $$
           BEGIN
           UPDATE contract SET status = p_status WHERE id = p_contract_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'terminate_contract failed for contract id %: %', p_contract_id, SQLERRM;
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
-- CREATE USER ACCOUNT
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION create_user_account(
    p_username VARCHAR(255),
    p_password VARCHAR(30),
    p_role user_role
) RETURNS INTEGER
AS $$
DECLARE v_new_id INTEGER;
BEGIN
    INSERT INTO user_account (username, password, role)
    VALUES (p_username, p_password, p_role)
    RETURNING id INTO v_new_id;
RETURN v_new_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'create_user_account failed for username %: %', p_username, SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- CREATE CUSTOMER
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_customer(
    p_name VARCHAR(255),
    p_address TEXT,
    p_birthdate DATE,
    p_user_account_id INTEGER
) RETURNS INTEGER
AS $$
DECLARE v_new_id INTEGER;
BEGIN
    -- Validate user account exists
    IF NOT EXISTS (SELECT 1 FROM user_account WHERE id = p_user_account_id) THEN
        RAISE EXCEPTION 'User account with id % does not exist', p_user_account_id;
END IF;
INSERT INTO customer (name, address, birthdate, user_account_id)VALUES (p_name, p_address, p_birthdate, p_user_account_id)
RETURNING id INTO v_new_id;
RETURN v_new_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'create_customer failed for name %: %', p_name, SQLERRM;
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

        v_taxes := ROUND(0.15 * (v_prorated_recurring + v_prorated_charge), 2);
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

-- Block CDR insert if contract is not active
CREATE OR REPLACE FUNCTION validate_cdr_contract()
       RETURNS TRIGGER AS $$
       DECLARE v_contract contract;
               BEGIN
               SELECT c.* INTO v_contract
               FROM contract c WHERE c.msisdn = NEW.dial_a;
IF NOT FOUND THEN
   RAISE EXCEPTION 'No contract found for MSISDN %', NEW.dial_a;
   END IF ;
   IF v_contract.status <> 'active' THEN
      RAISE EXCEPTION 'contract for MSISDN % is not active it is %', NEW.dial_a, v_contract.status;
      END IF;
      RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--trigger on cdr before insert to validate contract status
   CREATE TRIGGER trg_cdr_validate_contract
    BEFORE INSERT ON cdr
    FOR EACH ROW
    EXECUTE FUNCTION validate_cdr_contract();

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
-- CUSTOMERS
------------------------------------------------------------
INSERT INTO customer (name, address, birthdate)
VALUES
    ('Ahmed Ali', 'Beni Suef', '1998-05-10'),
    ('Mohamed Hassan', 'Cairo', '1995-09-22');

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
INSERT INTO contract (customer_id, rateplan_id, msisdn, status, credit_limit, available_credit)
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

