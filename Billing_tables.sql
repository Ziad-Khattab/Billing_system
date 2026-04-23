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
    filename    TEXT,
    parsed_flag BOOLEAN NOT NULL DEFAULT FALSE
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
                          user_account_id     INTEGER NOT NULL REFERENCES user_account(id),
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
CREATE INDEX idx_contract_user_account  ON contract(user_account_id);
CREATE INDEX idx_bill_contract      ON bill(contract_id);
CREATE INDEX idx_bill_billing_date  ON bill(billing_date);
CREATE INDEX idx_invoice_bill       ON invoice(bill_id);

-- ============================================================
-- FUNCTIONS (for billing calculations, etc.)
-- ============================================================


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
RETURNS INTEGER  -- returns the new CDR id
LANGUAGE plpgsql
AS $$
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
    rated_flag          -- always starts as false, rating engine handles this
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
$$;


-- ============================================================
-- dummy data for testing
-- ============================================================

INSERT INTO rateplan (name, ror_data, ror_voice, ror_sms, price)
VALUES
    ('Basic', 0.10, 0.20, 0.05, 50),
    ('Premium', 0.05, 0.10, 0.02, 120);

-- ------------------------------------------------------------
-- SERVICE PACKAGES
-- ------------------------------------------------------------
INSERT INTO service_package (name, type, amount, priority)
VALUES
    ('Voice Pack', 'voice', 1000, 1),
    ('Data Pack', 'data', 5000, 1),
    ('SMS Pack', 'sms', 200, 1);

-- ------------------------------------------------------------
-- CUSTOMERS
-- ------------------------------------------------------------
INSERT INTO customer (name, address, birthdate)
VALUES
    ('Ahmed Ali', 'Beni Suef', '1998-05-10'),
    ('Mohamed Hassan', 'Cairo', '1995-09-22');

-- ------------------------------------------------------------
-- CONTRACTS
-- ------------------------------------------------------------
INSERT INTO contract (customer_id, rateplan_id, msisdn, credit_limit, available_credit, status)
VALUES
    (1, 1, '201000000001', 200, 200, 'active'),
    (2, 2, '201000000002', 500, 500, 'active');
