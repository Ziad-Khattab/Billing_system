--
-- PostgreSQL database dump
--

\restrict nCQtnlw3KbRt5p5DQAOzkHaVCTWYZBzfPnj8E1eWGfoqfMgfbij0BJfuaJ2c1qC

-- Dumped from database version 18.3
-- Dumped by pg_dump version 18.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: bill_status; Type: TYPE; Schema: public; Owner: zkhattab
--

CREATE TYPE public.bill_status AS ENUM (
    'draft',
    'issued',
    'paid',
    'overdue',
    'cancelled'
);


ALTER TYPE public.bill_status OWNER TO zkhattab;

--
-- Name: contract_recurring_status; Type: TYPE; Schema: public; Owner: zkhattab
--

CREATE TYPE public.contract_recurring_status AS ENUM (
    'Active',
    'Suspended',
    'Cancelled',
    'Completed'
);


ALTER TYPE public.contract_recurring_status OWNER TO zkhattab;

--
-- Name: contract_status; Type: TYPE; Schema: public; Owner: zkhattab
--

CREATE TYPE public.contract_status AS ENUM (
    'active',
    'suspended',
    'suspended_debt',
    'terminated'
);


ALTER TYPE public.contract_status OWNER TO zkhattab;

--
-- Name: contract_status_enum; Type: TYPE; Schema: public; Owner: zkhattab
--

CREATE TYPE public.contract_status_enum AS ENUM (
    'Active',
    'Suspended',
    'Terminated',
    'Credit_Blocked'
);


ALTER TYPE public.contract_status_enum OWNER TO zkhattab;

--
-- Name: cot_status_enum; Type: TYPE; Schema: public; Owner: zkhattab
--

CREATE TYPE public.cot_status_enum AS ENUM (
    'Active',
    'Expired',
    'Cancelled'
);


ALTER TYPE public.cot_status_enum OWNER TO zkhattab;

--
-- Name: cr_status_enum; Type: TYPE; Schema: public; Owner: zkhattab
--

CREATE TYPE public.cr_status_enum AS ENUM (
    'Active',
    'Suspended',
    'Cancelled',
    'Completed'
);


ALTER TYPE public.cr_status_enum OWNER TO zkhattab;

--
-- Name: customer_type; Type: TYPE; Schema: public; Owner: zkhattab
--

CREATE TYPE public.customer_type AS ENUM (
    'Individual',
    'Corporate'
);


ALTER TYPE public.customer_type OWNER TO zkhattab;

--
-- Name: one_time_status; Type: TYPE; Schema: public; Owner: zkhattab
--

CREATE TYPE public.one_time_status AS ENUM (
    'Active',
    'Expired',
    'Cancelled'
);


ALTER TYPE public.one_time_status OWNER TO zkhattab;

--
-- Name: rateplan_status; Type: TYPE; Schema: public; Owner: zkhattab
--

CREATE TYPE public.rateplan_status AS ENUM (
    'Active',
    'Inactive'
);


ALTER TYPE public.rateplan_status OWNER TO zkhattab;

--
-- Name: rateplan_status_enum; Type: TYPE; Schema: public; Owner: zkhattab
--

CREATE TYPE public.rateplan_status_enum AS ENUM (
    'Active',
    'Inactive'
);


ALTER TYPE public.rateplan_status_enum OWNER TO zkhattab;

--
-- Name: service_type; Type: TYPE; Schema: public; Owner: zkhattab
--

CREATE TYPE public.service_type AS ENUM (
    'voice',
    'data',
    'sms',
    'free_units'
);


ALTER TYPE public.service_type OWNER TO zkhattab;

--
-- Name: service_type_enum; Type: TYPE; Schema: public; Owner: zkhattab
--

CREATE TYPE public.service_type_enum AS ENUM (
    'Voice',
    'Data',
    'SMS',
    'Roaming',
    'VAS',
    'Other'
);


ALTER TYPE public.service_type_enum OWNER TO zkhattab;

--
-- Name: service_uom; Type: TYPE; Schema: public; Owner: zkhattab
--

CREATE TYPE public.service_uom AS ENUM (
    'Minute',
    'MB',
    'GB',
    'SMS',
    'Event'
);


ALTER TYPE public.service_uom OWNER TO zkhattab;

--
-- Name: service_uom_enum; Type: TYPE; Schema: public; Owner: zkhattab
--

CREATE TYPE public.service_uom_enum AS ENUM (
    'Minute',
    'MB',
    'GB',
    'SMS',
    'Event'
);


ALTER TYPE public.service_uom_enum OWNER TO zkhattab;

--
-- Name: user_role; Type: TYPE; Schema: public; Owner: zkhattab
--

CREATE TYPE public.user_role AS ENUM (
    'admin',
    'customer'
);


ALTER TYPE public.user_role OWNER TO zkhattab;

--
-- Name: auto_initialize_consumption(); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.auto_initialize_consumption() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
           DECLARE v_period_start DATE;
BEGIN
                   v_period_start := DATE_TRUNC('month', New.start_time )::DATE;
                                  PERFORM initialize_consumption_period(v_period_start);
RETURN NEW;
END;
$$;


ALTER FUNCTION public.auto_initialize_consumption() OWNER TO zkhattab;

--
-- Name: auto_rate_cdr(); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.auto_rate_cdr() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
           IF NEW.service_id IS NOT NULL THEN
              PERFORM rate_cdr(NEW.id);
END IF;
RETURN NEW;
END;
$$;


ALTER FUNCTION public.auto_rate_cdr() OWNER TO zkhattab;

--
-- Name: cancel_addon(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.cancel_addon(p_addon_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.cancel_addon(p_addon_id integer) OWNER TO zkhattab;

--
-- Name: change_contract_rateplan(integer, integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.change_contract_rateplan(p_contract_id integer, p_new_rateplan_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.change_contract_rateplan(p_contract_id integer, p_new_rateplan_id integer) OWNER TO zkhattab;

--
-- Name: change_contract_status(integer, public.contract_status); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.change_contract_status(p_contract_id integer, p_status public.contract_status) RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.change_contract_status(p_contract_id integer, p_status public.contract_status) OWNER TO zkhattab;

--
-- Name: create_admin(character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.create_admin(p_username character varying, p_password character varying, p_name character varying, p_email character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_new_id INTEGER;
BEGIN
    -- Admins don't strictly need a customer profile in the teammate logic, 
    -- but they need a record in user_account.
    INSERT INTO user_account (username, password, role, customer_id)
    VALUES (p_username, p_password, 'admin', NULL)
    RETURNING id INTO v_new_id;

    RETURN v_new_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'create_admin failed: %', SQLERRM;
END;
$$;


ALTER FUNCTION public.create_admin(p_username character varying, p_password character varying, p_name character varying, p_email character varying) OWNER TO zkhattab;

--
-- Name: create_admin(character varying, character varying, character varying, character varying, text, date); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.create_admin(p_username character varying, p_password character varying, p_name character varying, p_email character varying, p_address text, p_birthdate date) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.create_admin(p_username character varying, p_password character varying, p_name character varying, p_email character varying, p_address text, p_birthdate date) OWNER TO zkhattab;

--
-- Name: create_contract(integer, integer, character varying, double precision); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.create_contract(p_user_account_id integer, p_rateplan_id integer, p_msisdn character varying, p_credit_limit double precision) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.create_contract(p_user_account_id integer, p_rateplan_id integer, p_msisdn character varying, p_credit_limit double precision) OWNER TO zkhattab;

--
-- Name: create_customer(character varying, character varying, character varying, character varying, text, date); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.create_customer(p_username character varying, p_password character varying, p_name character varying, p_email character varying, p_address text, p_birthdate date) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.create_customer(p_username character varying, p_password character varying, p_name character varying, p_email character varying, p_address text, p_birthdate date) OWNER TO zkhattab;

--
-- Name: create_file_record(text); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.create_file_record(p_file_path text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
          DECLARE v_new_id INTEGER;
BEGIN
INSERT INTO file (file_path) VALUES (p_file_path)
    RETURNING id INTO v_new_id;
RETURN v_new_id;
EXCEPTION
    WHEN OTHERS THEN
RAISE EXCEPTION 'create_file_record failed for file path %: %', p_file_path, SQLERRM;
END;
$$;


ALTER FUNCTION public.create_file_record(p_file_path text) OWNER TO zkhattab;

--
-- Name: create_service_package(character varying, public.service_type, numeric, integer, numeric, text, boolean); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.create_service_package(p_name character varying, p_type public.service_type, p_amount numeric, p_priority integer, p_price numeric, p_description text, p_is_roaming boolean DEFAULT false) RETURNS TABLE(id integer, name character varying, type public.service_type, amount numeric, priority integer, price numeric, description text, is_roaming boolean)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.create_service_package(p_name character varying, p_type public.service_type, p_amount numeric, p_priority integer, p_price numeric, p_description text, p_is_roaming boolean) OWNER TO zkhattab;

--
-- Name: expire_addons(); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.expire_addons() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE contract_addon
    SET is_active = FALSE
    WHERE expiry_date < CURRENT_DATE
      AND is_active   = TRUE;
END;
$$;


ALTER FUNCTION public.expire_addons() OWNER TO zkhattab;

--
-- Name: generate_all_bills(date); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.generate_all_bills(p_period_start date) RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.generate_all_bills(p_period_start date) OWNER TO zkhattab;

--
-- Name: generate_bill(integer, date); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.generate_bill(p_contract_id integer, p_billing_period_start date) RETURNS integer
    LANGUAGE plpgsql
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
$$;


ALTER FUNCTION public.generate_bill(p_contract_id integer, p_billing_period_start date) OWNER TO zkhattab;

--
-- Name: generate_bulk_missing(text); Type: PROCEDURE; Schema: public; Owner: zkhattab
--

CREATE PROCEDURE public.generate_bulk_missing(IN p_search text)
    LANGUAGE plpgsql
    AS $$
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


ALTER PROCEDURE public.generate_bulk_missing(IN p_search text) OWNER TO zkhattab;

--
-- Name: generate_invoice(integer, text); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.generate_invoice(p_bill_id integer, p_pdf_path text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
INSERT INTO invoice (bill_id, pdf_path)
VALUES (p_bill_id, p_pdf_path);
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'generate_invoice failed for bill id %: %', p_bill_id, SQLERRM;
END;
$$;


ALTER FUNCTION public.generate_invoice(p_bill_id integer, p_pdf_path text) OWNER TO zkhattab;

--
-- Name: get_admin_stats(); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_admin_stats() RETURNS TABLE(customers bigint, contracts bigint, cdrs bigint, revenue numeric, pending_bills bigint)
    LANGUAGE plpgsql
    AS $$ 
BEGIN 
    RETURN QUERY SELECT 
        (SELECT COUNT(*) FROM customer) AS customers, 
        (SELECT COUNT(*) FROM contract) AS contracts, 
        (SELECT COUNT(*) FROM cdr) AS cdrs,
        (SELECT COALESCE(SUM(total_amount), 0) FROM bill WHERE is_paid = TRUE) AS revenue,
        (SELECT COUNT(*) FROM bill WHERE is_paid = FALSE) AS pending_bills; 
END; 
$$;


ALTER FUNCTION public.get_admin_stats() OWNER TO zkhattab;

--
-- Name: get_all_bills(text, integer, integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_all_bills(p_search text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE(id integer, contract_id integer, billing_date date, billing_period_start date, billing_period_end date, total_amount numeric, is_paid boolean, status character varying, voice_usage integer, data_usage integer, sms_usage integer, customer_name character varying, msisdn character varying, total_count bigint)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_all_bills(p_search text, p_limit integer, p_offset integer) OWNER TO zkhattab;

--
-- Name: get_all_contracts(text, integer, integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_all_contracts(p_search text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE(id integer, msisdn character varying, status public.contract_status, available_credit numeric, customer_name character varying, rateplan_name character varying, total_count bigint)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_all_contracts(p_search text, p_limit integer, p_offset integer) OWNER TO zkhattab;

--
-- Name: get_all_customers(text, integer, integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_all_customers(p_search text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE(id integer, username character varying, name character varying, email character varying, role public.user_role, address text, birthdate date, msisdn character varying, total_count bigint)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_all_customers(p_search text, p_limit integer, p_offset integer) OWNER TO zkhattab;

--
-- Name: get_all_rateplans(); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_all_rateplans() RETURNS TABLE(id integer, name character varying, price numeric, ror_voice numeric, ror_data numeric, ror_sms numeric)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_all_rateplans() OWNER TO zkhattab;

--
-- Name: get_all_service_packages(); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_all_service_packages() RETURNS TABLE(id integer, name character varying, type public.service_type, amount numeric, priority integer, price numeric, description text, is_roaming boolean)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_all_service_packages() OWNER TO zkhattab;

--
-- Name: get_available_msisdns(); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_available_msisdns() RETURNS TABLE(id integer, msisdn character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
        SELECT mp.id, mp.msisdn
        FROM msisdn_pool mp
        WHERE mp.is_available = TRUE
        ORDER BY mp.msisdn;
END;
$$;


ALTER FUNCTION public.get_available_msisdns() OWNER TO zkhattab;

--
-- Name: get_bill(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_bill(p_bill_id integer) RETURNS TABLE(contract_id integer, billing_period_start date, billing_period_end date, billing_date date, recurring_fees numeric, one_time_fees numeric, voice_usage integer, data_usage integer, sms_usage integer, ror_charge numeric, taxes numeric, total_amount numeric, status public.bill_status, is_paid boolean)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_bill(p_bill_id integer) OWNER TO zkhattab;

--
-- Name: get_bill_usage_breakdown(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_bill_usage_breakdown(p_bill_id integer) RETURNS TABLE(service_type text, category_label text, quota integer, consumed integer, unit_rate numeric, line_total numeric, is_roaming boolean, is_promotional boolean, notes text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_contract_id INTEGER;
    v_period_start DATE;
BEGIN
    -- Get contract and period for this bill
    SELECT contract_id, billing_period_start INTO v_contract_id, v_period_start
    FROM bill WHERE id = p_bill_id;
    
    -- 1. Bundled usage from contract_consumption (linked by bill_id)
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
            ELSE 'Partial bundle usage'::TEXT
        END AS notes
    FROM contract_consumption cc
    JOIN service_package sp ON cc.service_package_id = sp.id
    WHERE cc.bill_id = p_bill_id
      AND cc.is_billed = TRUE
    
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
$$;


ALTER FUNCTION public.get_bill_usage_breakdown(p_bill_id integer) OWNER TO zkhattab;

--
-- Name: get_bills_by_contract(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_bills_by_contract(p_contract_id integer) RETURNS TABLE(id integer, billing_period_start date, billing_period_end date, billing_date date, total_amount numeric, status public.bill_status)
    LANGUAGE plpgsql
    AS $$
BEGIN
RETURN QUERY
SELECT b.id, b.billing_period_start, billing_period_end, billing_date, total_amount, status
FROM bill b WHERE b.contract_id = p_contract_id
ORDER BY billing_period_start DESC;
END;
$$;


ALTER FUNCTION public.get_bills_by_contract(p_contract_id integer) OWNER TO zkhattab;

--
-- Name: get_cdr_usage_amount(integer, public.service_type); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_cdr_usage_amount(p_duration integer, p_service_type public.service_type) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
BEGIN
RETURN CASE p_service_type
           WHEN 'voice' THEN CEIL(p_duration / 60.0)  -- convert seconds to minutes, round up
           WHEN 'data'  THEN p_duration
           WHEN 'sms'   THEN 1
           WHEN 'free_units' THEN p_duration
    END;
END;
$$;


ALTER FUNCTION public.get_cdr_usage_amount(p_duration integer, p_service_type public.service_type) OWNER TO zkhattab;

--
-- Name: get_cdrs(integer, integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_cdrs(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE(id integer, msisdn character varying, destination character varying, duration integer, "timestamp" timestamp without time zone, rated boolean, type character varying, service_id integer, service_type text)
    LANGUAGE plpgsql
    AS $$
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
 $$;


ALTER FUNCTION public.get_cdrs(p_limit integer, p_offset integer) OWNER TO zkhattab;

--
-- Name: get_contract_addons(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_contract_addons(p_contract_id integer) RETURNS TABLE(id integer, service_package_id integer, package_name character varying, type public.service_type, amount numeric, purchased_date date, expiry_date date, price_paid numeric, is_active boolean)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_contract_addons(p_contract_id integer) OWNER TO zkhattab;

--
-- Name: get_contract_by_id(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_contract_by_id(p_id integer) RETURNS TABLE(id integer, user_account_id integer, rateplan_id integer, msisdn character varying, status public.contract_status, credit_limit numeric, available_credit numeric, customer_name character varying, rateplan_name character varying)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_contract_by_id(p_id integer) OWNER TO zkhattab;

--
-- Name: get_contract_consumption(integer, date); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_contract_consumption(p_contract_id integer, p_period_start date) RETURNS TABLE(service_package_id integer, consumed integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
RETURN QUERY
SELECT service_package_id, consumed
FROM contract_consumption
WHERE contract_id = p_contract_id
  AND starting_date = p_period_start
  AND is_billed = FALSE;
END;
$$;


ALTER FUNCTION public.get_contract_consumption(p_contract_id integer, p_period_start date) OWNER TO zkhattab;

--
-- Name: get_customer_by_id(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_customer_by_id(p_id integer) RETURNS TABLE(id integer, username character varying, name character varying, email character varying, role public.user_role, address text, birthdate date)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_customer_by_id(p_id integer) OWNER TO zkhattab;

--
-- Name: get_dashboard_stats(); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_dashboard_stats() RETURNS TABLE(total_customers bigint, total_contracts bigint, active_contracts bigint, suspended_contracts bigint, suspended_debt_contracts bigint, terminated_contracts bigint, total_cdrs bigint, revenue numeric, pending_bills bigint)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_dashboard_stats() OWNER TO zkhattab;

--
-- Name: get_missing_bills(text, integer, integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_missing_bills(p_search text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE(contract_id integer, msisdn character varying, customer_name character varying, rateplan_name character varying, last_bill_date date, total_count bigint)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_missing_bills(p_search text, p_limit integer, p_offset integer) OWNER TO zkhattab;

--
-- Name: get_rateplan_by_id(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_rateplan_by_id(p_id integer) RETURNS TABLE(id integer, name character varying, ror_voice numeric, ror_data numeric, ror_sms numeric, price numeric)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_rateplan_by_id(p_id integer) OWNER TO zkhattab;

--
-- Name: get_rateplan_data(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_rateplan_data(p_rateplan_id integer) RETURNS TABLE(id integer, name character varying, ror_data numeric, ror_voice numeric, ror_sms numeric, price numeric)
    LANGUAGE plpgsql
    AS $$
 BEGIN
     RETURN QUERY
     SELECT
         r.id,
         r.name,
         r.ror_data,
         r.ror_voice,
         r.ror_sms,
         r.price
     FROM
         rateplan r
     WHERE
         r.id = p_rateplan_id;
 END;
 $$;


ALTER FUNCTION public.get_rateplan_data(p_rateplan_id integer) OWNER TO zkhattab;

--
-- Name: get_service_package_by_id(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_service_package_by_id(p_id integer) RETURNS TABLE(id integer, name character varying, type public.service_type, amount numeric, priority integer, price numeric, description text, is_roaming boolean)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_service_package_by_id(p_id integer) OWNER TO zkhattab;

--
-- Name: get_user_contracts(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_user_contracts(p_user_id integer) RETURNS TABLE(id integer, msisdn character varying, status public.contract_status, available_credit numeric, credit_limit numeric, rateplan_name character varying)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_user_contracts(p_user_id integer) OWNER TO zkhattab;

--
-- Name: get_user_data(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_user_data(p_user_account_id integer) RETURNS TABLE(username character varying, role character varying, name character varying, email character varying, address text, birthdate date)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_user_data(p_user_account_id integer) OWNER TO zkhattab;

--
-- Name: get_user_invoices(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_user_invoices(p_user_id integer) RETURNS TABLE(id integer, contract_id integer, billing_period_start date, billing_period_end date, billing_date date, recurring_fees numeric, one_time_fees numeric, voice_usage integer, data_usage integer, sms_usage integer, ror_charge numeric, taxes numeric, total_amount numeric, status public.bill_status, is_paid boolean, pdf_path text)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_user_invoices(p_user_id integer) OWNER TO zkhattab;

--
-- Name: get_user_msisdn_bill(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.get_user_msisdn_bill(p_contract_id integer) RETURNS TABLE(user_account_id integer, msisdn character varying, bill_id integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.user_account_id,
        c.msisdn,
        b.id AS bill_id
    FROM contract c
    LEFT JOIN bill b ON b.contract_id = c.id
    WHERE c.id = p_contract_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No contract found with id %', p_contract_id;
    END IF;
END;
$$;


ALTER FUNCTION public.get_user_msisdn_bill(p_contract_id integer) OWNER TO zkhattab;

--
-- Name: initialize_consumption_period(date); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.initialize_consumption_period(p_period_start date) RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.initialize_consumption_period(p_period_start date) OWNER TO zkhattab;

--
-- Name: insert_cdr(integer, character varying, character varying, timestamp without time zone, integer, integer, character varying, character varying, numeric); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.insert_cdr(p_file_id integer, p_dial_a character varying, p_dial_b character varying, p_start_time timestamp without time zone, p_duration integer, p_service_id integer, p_hplmn character varying, p_vplmn character varying, p_external_charges numeric) RETURNS integer
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
$$;


ALTER FUNCTION public.insert_cdr(p_file_id integer, p_dial_a character varying, p_dial_b character varying, p_start_time timestamp without time zone, p_duration integer, p_service_id integer, p_hplmn character varying, p_vplmn character varying, p_external_charges numeric) OWNER TO zkhattab;

--
-- Name: login(character varying, character varying); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.login(p_username character varying, p_password character varying) RETURNS TABLE(id integer, username character varying, name character varying, email character varying, role public.user_role)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.login(p_username character varying, p_password character varying) OWNER TO zkhattab;

--
-- Name: mark_bill_paid(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.mark_bill_paid(p_bill_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
UPDATE bill
SET is_paid = TRUE, status = 'paid'
WHERE id = p_bill_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'mark_bill_paid failed for bill id %: %', p_bill_id, SQLERRM;
END;
$$;


ALTER FUNCTION public.mark_bill_paid(p_bill_id integer) OWNER TO zkhattab;

--
-- Name: mark_msisdn_taken(character varying); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.mark_msisdn_taken(p_msisdn character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE msisdn_pool
    SET is_available = FALSE
    WHERE msisdn = p_msisdn;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'MSISDN % not found in pool', p_msisdn;
    END IF;
END;
$$;


ALTER FUNCTION public.mark_msisdn_taken(p_msisdn character varying) OWNER TO zkhattab;

--
-- Name: notify_bill_generation(); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.notify_bill_generation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM pg_notify('generate_bill_event', NEW.id::text);
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.notify_bill_generation() OWNER TO zkhattab;

--
-- Name: pay_bill(integer, text); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.pay_bill(p_bill_id integer, p_pdf_path text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
         -- Mark bill as paid
         PERFORM mark_bill_paid(p_bill_id);
         -- Generate invoice PDF
         PERFORM generate_invoice(p_bill_id, p_pdf_path);
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'pay_bill failed for bill id %: %', p_bill_id, SQLERRM;
END;
$$;


ALTER FUNCTION public.pay_bill(p_bill_id integer, p_pdf_path text) OWNER TO zkhattab;

--
-- Name: purchase_addon(integer, integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.purchase_addon(p_contract_id integer, p_service_package_id integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.purchase_addon(p_contract_id integer, p_service_package_id integer) OWNER TO zkhattab;

--
-- Name: rate_cdr(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.rate_cdr(p_cdr_id integer) RETURNS void
    LANGUAGE plpgsql
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
$$;


ALTER FUNCTION public.rate_cdr(p_cdr_id integer) OWNER TO zkhattab;

--
-- Name: release_msisdn(character varying); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.release_msisdn(p_msisdn character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE msisdn_pool
    SET is_available = TRUE
    WHERE msisdn = p_msisdn;
END;
$$;


ALTER FUNCTION public.release_msisdn(p_msisdn character varying) OWNER TO zkhattab;

--
-- Name: set_file_parsed(integer); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.set_file_parsed(p_file_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
UPDATE file
SET parsed_flag = TRUE
WHERE id = p_file_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'set_file_parsed failed for file id %: %', p_file_id, SQLERRM;
END;
$$;


ALTER FUNCTION public.set_file_parsed(p_file_id integer) OWNER TO zkhattab;

--
-- Name: trg_restore_credit_on_payment(); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.trg_restore_credit_on_payment() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.is_paid = TRUE AND OLD.is_paid = FALSE THEN
UPDATE contract
SET available_credit = credit_limit
WHERE id = NEW.contract_id;
END IF;
RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_restore_credit_on_payment() OWNER TO zkhattab;

--
-- Name: validate_cdr_contract(); Type: FUNCTION; Schema: public; Owner: zkhattab
--

CREATE FUNCTION public.validate_cdr_contract() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.validate_cdr_contract() OWNER TO zkhattab;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: bill; Type: TABLE; Schema: public; Owner: zkhattab
--

CREATE TABLE public.bill (
    id integer NOT NULL,
    contract_id integer NOT NULL,
    billing_period_start date NOT NULL,
    billing_period_end date NOT NULL,
    billing_date date NOT NULL,
    recurring_fees numeric(12,2) DEFAULT 0 NOT NULL,
    one_time_fees numeric(12,2) DEFAULT 0 NOT NULL,
    voice_usage integer DEFAULT 0 NOT NULL,
    data_usage integer DEFAULT 0 NOT NULL,
    sms_usage integer DEFAULT 0 NOT NULL,
    ror_charge numeric(12,2) DEFAULT 0 NOT NULL,
    overage_charge numeric(12,2) DEFAULT 0 NOT NULL,
    roaming_charge numeric(12,2) DEFAULT 0 NOT NULL,
    promotional_discount numeric(12,2) DEFAULT 0 NOT NULL,
    taxes numeric(12,2) DEFAULT 0 NOT NULL,
    total_amount numeric(12,2) DEFAULT 0 NOT NULL,
    status public.bill_status DEFAULT 'draft'::public.bill_status NOT NULL,
    is_paid boolean DEFAULT false NOT NULL
);


ALTER TABLE public.bill OWNER TO zkhattab;

--
-- Name: bill_id_seq; Type: SEQUENCE; Schema: public; Owner: zkhattab
--

CREATE SEQUENCE public.bill_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bill_id_seq OWNER TO zkhattab;

--
-- Name: bill_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: zkhattab
--

ALTER SEQUENCE public.bill_id_seq OWNED BY public.bill.id;


--
-- Name: cdr; Type: TABLE; Schema: public; Owner: zkhattab
--

CREATE TABLE public.cdr (
    id integer NOT NULL,
    file_id integer NOT NULL,
    dial_a character varying(20) NOT NULL,
    dial_b character varying(20) NOT NULL,
    start_time timestamp without time zone NOT NULL,
    duration integer DEFAULT 0 NOT NULL,
    service_id integer,
    hplmn character varying(20),
    vplmn character varying(20),
    external_charges numeric(12,2) DEFAULT 0 NOT NULL,
    rated_flag boolean DEFAULT false NOT NULL,
    rated_service_id integer
);


ALTER TABLE public.cdr OWNER TO zkhattab;

--
-- Name: cdr_id_seq; Type: SEQUENCE; Schema: public; Owner: zkhattab
--

CREATE SEQUENCE public.cdr_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cdr_id_seq OWNER TO zkhattab;

--
-- Name: cdr_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: zkhattab
--

ALTER SEQUENCE public.cdr_id_seq OWNED BY public.cdr.id;


--
-- Name: contract; Type: TABLE; Schema: public; Owner: zkhattab
--

CREATE TABLE public.contract (
    id integer NOT NULL,
    user_account_id integer NOT NULL,
    rateplan_id integer NOT NULL,
    msisdn character varying(20) NOT NULL,
    status public.contract_status DEFAULT 'active'::public.contract_status NOT NULL,
    credit_limit numeric(12,2) DEFAULT 0 NOT NULL,
    available_credit numeric(12,2) DEFAULT 0 NOT NULL
);


ALTER TABLE public.contract OWNER TO zkhattab;

--
-- Name: contract_addon; Type: TABLE; Schema: public; Owner: zkhattab
--

CREATE TABLE public.contract_addon (
    id integer NOT NULL,
    contract_id integer NOT NULL,
    service_package_id integer NOT NULL,
    purchased_date date DEFAULT CURRENT_DATE NOT NULL,
    expiry_date date NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    price_paid numeric(12,2) DEFAULT 0 NOT NULL
);


ALTER TABLE public.contract_addon OWNER TO zkhattab;

--
-- Name: contract_addon_id_seq; Type: SEQUENCE; Schema: public; Owner: zkhattab
--

CREATE SEQUENCE public.contract_addon_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.contract_addon_id_seq OWNER TO zkhattab;

--
-- Name: contract_addon_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: zkhattab
--

ALTER SEQUENCE public.contract_addon_id_seq OWNED BY public.contract_addon.id;


--
-- Name: contract_consumption; Type: TABLE; Schema: public; Owner: zkhattab
--

CREATE TABLE public.contract_consumption (
    contract_id integer NOT NULL,
    service_package_id integer NOT NULL,
    rateplan_id integer NOT NULL,
    starting_date date NOT NULL,
    ending_date date NOT NULL,
    consumed numeric(12,4) DEFAULT 0 NOT NULL,
    quota_limit numeric(12,4) DEFAULT 0 NOT NULL,
    is_billed boolean DEFAULT false NOT NULL,
    bill_id integer
);


ALTER TABLE public.contract_consumption OWNER TO zkhattab;

--
-- Name: contract_id_seq; Type: SEQUENCE; Schema: public; Owner: zkhattab
--

CREATE SEQUENCE public.contract_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.contract_id_seq OWNER TO zkhattab;

--
-- Name: contract_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: zkhattab
--

ALTER SEQUENCE public.contract_id_seq OWNED BY public.contract.id;


--
-- Name: file; Type: TABLE; Schema: public; Owner: zkhattab
--

CREATE TABLE public.file (
    id integer NOT NULL,
    parsed_flag boolean DEFAULT false NOT NULL,
    file_path text NOT NULL
);


ALTER TABLE public.file OWNER TO zkhattab;

--
-- Name: file_id_seq; Type: SEQUENCE; Schema: public; Owner: zkhattab
--

CREATE SEQUENCE public.file_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.file_id_seq OWNER TO zkhattab;

--
-- Name: file_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: zkhattab
--

ALTER SEQUENCE public.file_id_seq OWNED BY public.file.id;


--
-- Name: invoice; Type: TABLE; Schema: public; Owner: zkhattab
--

CREATE TABLE public.invoice (
    id integer NOT NULL,
    bill_id integer NOT NULL,
    pdf_path text,
    generation_date timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.invoice OWNER TO zkhattab;

--
-- Name: invoice_id_seq; Type: SEQUENCE; Schema: public; Owner: zkhattab
--

CREATE SEQUENCE public.invoice_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.invoice_id_seq OWNER TO zkhattab;

--
-- Name: invoice_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: zkhattab
--

ALTER SEQUENCE public.invoice_id_seq OWNED BY public.invoice.id;


--
-- Name: msisdn_pool; Type: TABLE; Schema: public; Owner: zkhattab
--

CREATE TABLE public.msisdn_pool (
    id integer NOT NULL,
    msisdn character varying(20) NOT NULL,
    is_available boolean DEFAULT true NOT NULL
);


ALTER TABLE public.msisdn_pool OWNER TO zkhattab;

--
-- Name: msisdn_pool_id_seq; Type: SEQUENCE; Schema: public; Owner: zkhattab
--

CREATE SEQUENCE public.msisdn_pool_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.msisdn_pool_id_seq OWNER TO zkhattab;

--
-- Name: msisdn_pool_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: zkhattab
--

ALTER SEQUENCE public.msisdn_pool_id_seq OWNED BY public.msisdn_pool.id;


--
-- Name: rateplan; Type: TABLE; Schema: public; Owner: zkhattab
--

CREATE TABLE public.rateplan (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    ror_data numeric(10,2),
    ror_voice numeric(10,2),
    ror_sms numeric(10,2),
    ror_roaming_data numeric(10,2),
    ror_roaming_voice numeric(10,2),
    ror_roaming_sms numeric(10,2),
    price numeric(10,2)
);


ALTER TABLE public.rateplan OWNER TO zkhattab;

--
-- Name: rateplan_id_seq; Type: SEQUENCE; Schema: public; Owner: zkhattab
--

CREATE SEQUENCE public.rateplan_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rateplan_id_seq OWNER TO zkhattab;

--
-- Name: rateplan_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: zkhattab
--

ALTER SEQUENCE public.rateplan_id_seq OWNED BY public.rateplan.id;


--
-- Name: rateplan_service_package; Type: TABLE; Schema: public; Owner: zkhattab
--

CREATE TABLE public.rateplan_service_package (
    rateplan_id integer NOT NULL,
    service_package_id integer NOT NULL
);


ALTER TABLE public.rateplan_service_package OWNER TO zkhattab;

--
-- Name: ror_contract; Type: TABLE; Schema: public; Owner: zkhattab
--

CREATE TABLE public.ror_contract (
    contract_id integer NOT NULL,
    rateplan_id integer NOT NULL,
    starting_date date DEFAULT (date_trunc('month'::text, (CURRENT_DATE)::timestamp with time zone))::date NOT NULL,
    data bigint DEFAULT 0,
    voice numeric(12,2) DEFAULT 0,
    sms bigint DEFAULT 0,
    roaming_voice numeric(12,2) DEFAULT 0.00,
    roaming_data bigint DEFAULT 0,
    roaming_sms bigint DEFAULT 0,
    bill_id integer
);


ALTER TABLE public.ror_contract OWNER TO zkhattab;

--
-- Name: service_package; Type: TABLE; Schema: public; Owner: zkhattab
--

CREATE TABLE public.service_package (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    type public.service_type NOT NULL,
    amount numeric(12,4) NOT NULL,
    priority integer DEFAULT 1 NOT NULL,
    price numeric(12,2),
    is_roaming boolean DEFAULT false NOT NULL,
    description text
);


ALTER TABLE public.service_package OWNER TO zkhattab;

--
-- Name: service_package_id_seq; Type: SEQUENCE; Schema: public; Owner: zkhattab
--

CREATE SEQUENCE public.service_package_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.service_package_id_seq OWNER TO zkhattab;

--
-- Name: service_package_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: zkhattab
--

ALTER SEQUENCE public.service_package_id_seq OWNED BY public.service_package.id;


--
-- Name: user_account; Type: TABLE; Schema: public; Owner: zkhattab
--

CREATE TABLE public.user_account (
    id integer NOT NULL,
    username character varying(255) NOT NULL,
    password character varying(30) NOT NULL,
    role public.user_role NOT NULL,
    name character varying(255) NOT NULL,
    email character varying(255) NOT NULL,
    address text,
    birthdate date
);


ALTER TABLE public.user_account OWNER TO zkhattab;

--
-- Name: user_account_id_seq; Type: SEQUENCE; Schema: public; Owner: zkhattab
--

CREATE SEQUENCE public.user_account_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_account_id_seq OWNER TO zkhattab;

--
-- Name: user_account_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: zkhattab
--

ALTER SEQUENCE public.user_account_id_seq OWNED BY public.user_account.id;


--
-- Name: v_msisdn; Type: TABLE; Schema: public; Owner: zkhattab
--

CREATE TABLE public.v_msisdn (
    msisdn character varying(20)
);


ALTER TABLE public.v_msisdn OWNER TO zkhattab;

--
-- Name: bill id; Type: DEFAULT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.bill ALTER COLUMN id SET DEFAULT nextval('public.bill_id_seq'::regclass);


--
-- Name: cdr id; Type: DEFAULT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.cdr ALTER COLUMN id SET DEFAULT nextval('public.cdr_id_seq'::regclass);


--
-- Name: contract id; Type: DEFAULT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.contract ALTER COLUMN id SET DEFAULT nextval('public.contract_id_seq'::regclass);


--
-- Name: contract_addon id; Type: DEFAULT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.contract_addon ALTER COLUMN id SET DEFAULT nextval('public.contract_addon_id_seq'::regclass);


--
-- Name: file id; Type: DEFAULT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.file ALTER COLUMN id SET DEFAULT nextval('public.file_id_seq'::regclass);


--
-- Name: invoice id; Type: DEFAULT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.invoice ALTER COLUMN id SET DEFAULT nextval('public.invoice_id_seq'::regclass);


--
-- Name: msisdn_pool id; Type: DEFAULT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.msisdn_pool ALTER COLUMN id SET DEFAULT nextval('public.msisdn_pool_id_seq'::regclass);


--
-- Name: rateplan id; Type: DEFAULT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.rateplan ALTER COLUMN id SET DEFAULT nextval('public.rateplan_id_seq'::regclass);


--
-- Name: service_package id; Type: DEFAULT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.service_package ALTER COLUMN id SET DEFAULT nextval('public.service_package_id_seq'::regclass);


--
-- Name: user_account id; Type: DEFAULT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.user_account ALTER COLUMN id SET DEFAULT nextval('public.user_account_id_seq'::regclass);


--
-- Data for Name: bill; Type: TABLE DATA; Schema: public; Owner: zkhattab
--

COPY public.bill (id, contract_id, billing_period_start, billing_period_end, billing_date, recurring_fees, one_time_fees, voice_usage, data_usage, sms_usage, ror_charge, overage_charge, roaming_charge, promotional_discount, taxes, total_amount, status, is_paid) FROM stdin;
1	1	2026-02-01	2026-02-28	2026-03-01	75.00	0.69	280	0	38	0.00	0.00	0.00	0.00	10.50	86.19	paid	t
2	2	2026-02-01	2026-02-28	2026-03-01	370.00	0.69	580	1900	72	0.00	0.00	0.00	0.00	51.80	422.49	paid	t
3	3	2026-02-01	2026-02-28	2026-03-01	75.00	0.69	150	0	18	0.00	0.00	0.00	0.00	10.50	86.19	paid	t
4	4	2026-02-01	2026-02-28	2026-03-01	370.00	0.69	410	1400	50	0.00	0.00	0.00	0.00	51.80	422.49	paid	t
5	5	2026-02-01	2026-02-28	2026-03-01	75.00	0.69	80	0	10	0.00	0.00	0.00	0.00	10.50	86.19	paid	t
6	6	2026-02-01	2026-02-28	2026-03-01	370.00	0.69	690	2800	95	0.00	0.00	0.00	0.00	51.80	422.49	paid	t
7	7	2026-02-01	2026-02-28	2026-03-01	75.00	0.69	190	0	25	0.00	0.00	0.00	0.00	10.50	86.19	paid	t
8	8	2026-02-01	2026-02-28	2026-03-01	370.00	0.69	350	1200	45	0.00	0.00	0.00	0.00	51.80	422.49	paid	t
9	9	2026-02-01	2026-02-28	2026-03-01	75.00	0.69	120	0	15	0.00	0.00	0.00	0.00	10.50	86.19	paid	t
10	10	2026-02-01	2026-02-28	2026-03-01	370.00	0.69	470	1750	62	0.00	0.00	0.00	0.00	51.80	422.49	paid	t
11	11	2026-02-01	2026-02-28	2026-03-01	75.00	0.69	820	0	175	10.00	0.00	0.00	0.00	6.07	66.76	paid	t
12	12	2026-02-01	2026-02-28	2026-03-01	370.00	0.69	260	800	30	0.00	0.00	0.00	0.00	51.80	422.49	paid	t
13	14	2026-02-01	2026-02-28	2026-03-01	370.00	0.69	390	1050	52	0.00	0.00	0.00	0.00	51.80	422.49	paid	t
14	15	2026-02-01	2026-02-28	2026-03-01	950.00	0.69	750	3500	130	0.00	0.00	0.00	0.00	133.00	1083.69	paid	t
15	16	2026-02-01	2026-02-28	2026-03-01	950.00	0.69	880	4200	160	5.00	0.00	0.00	0.00	35.47	390.16	paid	t
16	17	2026-02-01	2026-02-28	2026-03-01	370.00	0.69	310	950	42	0.00	0.00	0.00	0.00	51.80	422.49	paid	t
17	1	2026-03-01	2026-03-31	2026-04-01	75.00	0.69	310	0	42	0.00	0.00	0.00	0.00	10.50	86.19	paid	t
18	2	2026-03-01	2026-03-31	2026-04-01	370.00	0.69	640	2200	80	0.00	0.00	0.00	0.00	51.80	422.49	paid	t
32	17	2026-03-01	2026-03-31	2026-04-01	370.00	0.69	330	980	45	0.00	0.00	0.00	0.00	51.80	422.49	paid	t
31	16	2026-03-01	2026-03-31	2026-04-01	950.00	0.69	920	4800	170	8.00	0.00	0.00	0.00	35.77	393.46	paid	t
30	15	2026-03-01	2026-03-31	2026-04-01	950.00	0.69	800	3700	140	0.00	0.00	0.00	0.00	133.00	1083.69	paid	t
29	14	2026-03-01	2026-03-31	2026-04-01	370.00	0.69	420	1100	55	0.00	0.00	0.00	0.00	51.80	422.49	paid	t
28	12	2026-03-01	2026-03-31	2026-04-01	370.00	0.69	280	850	35	0.00	0.00	0.00	0.00	51.80	422.49	paid	t
27	11	2026-03-01	2026-03-31	2026-04-01	75.00	0.69	900	0	195	14.50	0.00	0.00	0.00	6.52	71.71	paid	t
26	10	2026-03-01	2026-03-31	2026-04-01	370.00	0.69	500	1900	68	0.00	0.00	0.00	0.00	51.80	422.49	paid	t
25	9	2026-03-01	2026-03-31	2026-04-01	75.00	0.69	130	0	16	0.00	0.00	0.00	0.00	10.50	86.19	paid	t
24	8	2026-03-01	2026-03-31	2026-04-01	370.00	0.69	380	1350	50	0.00	0.00	0.00	0.00	51.80	422.49	paid	t
23	7	2026-03-01	2026-03-31	2026-04-01	75.00	0.69	200	0	28	0.00	0.00	0.00	0.00	10.50	86.19	paid	t
22	6	2026-03-01	2026-03-31	2026-04-01	370.00	0.69	720	3100	105	0.00	0.00	0.00	0.00	51.80	422.49	paid	t
21	5	2026-03-01	2026-03-31	2026-04-01	75.00	0.69	90	0	11	0.00	0.00	0.00	0.00	10.50	86.19	paid	t
20	4	2026-03-01	2026-03-31	2026-04-01	370.00	0.69	450	1600	58	0.00	0.00	0.00	0.00	51.80	422.49	paid	t
19	3	2026-03-01	2026-03-31	2026-04-01	75.00	0.69	170	0	20	0.00	0.00	0.00	0.00	10.50	86.19	paid	t
33	10	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	510	2400	75	0.00	2.34	0.00	0.00	52.13	424.47	issued	f
34	9	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	140	0	8	0.00	1.30	0.00	0.00	10.68	86.98	issued	f
35	8	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	390	1500	55	0.00	1.94	0.00	0.00	52.07	424.01	issued	f
36	7	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	210	0	18	0.00	2.10	0.00	0.00	10.79	87.89	issued	f
37	6	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	750	3200	110	0.00	4.06	0.00	0.00	52.37	426.43	issued	f
38	5	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	95	0	12	0.00	1.50	0.00	0.00	10.71	87.21	issued	f
39	4	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	480	1800	65	0.00	2.24	0.00	0.00	52.11	424.35	issued	f
40	3	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	180	0	22	0.00	2.30	0.00	0.00	10.82	88.12	issued	f
42	2	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	740	2500	115	0.00	3.18	0.52	0.00	52.32	426.02	issued	f
43	19	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
44	20	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
45	21	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
46	22	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
47	23	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
48	24	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
49	25	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
50	26	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
51	27	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
52	28	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
53	29	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
62	38	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t
61	37	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t
60	36	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t
59	35	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t
58	34	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t
57	33	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t
56	32	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t
55	31	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t
54	30	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t
41	1	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	350	0	45	0.00	8.90	0.00	0.00	11.75	95.65	paid	t
78	11	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	980	0	190	0.00	7.00	0.00	0.00	11.48	93.48	paid	t
77	12	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	290	900	35	0.00	1.12	0.00	0.00	51.96	423.08	paid	t
76	14	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	430	1200	60	0.00	1.54	0.00	0.00	52.02	423.56	paid	t
75	15	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	900	4120	165	0.00	1.52	0.21	0.00	133.24	1084.97	paid	t
74	16	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	950	4900	180	0.00	1.87	0.00	0.00	133.26	1085.13	paid	t
73	17	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	340	1100	48	0.00	1.24	0.00	0.00	51.97	423.21	paid	t
72	48	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t
71	47	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t
70	46	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t
69	45	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t
68	44	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t
67	43	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t
66	42	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t
65	41	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t
64	40	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t
63	39	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t
91	13	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
96	19	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
97	20	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
98	21	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
99	22	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
100	23	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
101	24	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
102	25	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
103	26	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
104	27	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
105	28	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
106	29	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
107	30	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
108	31	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
109	32	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
110	33	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
111	34	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
112	35	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
113	36	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
114	37	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
115	38	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
116	39	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
117	40	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
118	41	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
119	42	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
120	43	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
121	44	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
122	45	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
123	46	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
124	47	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
125	48	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
126	49	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
127	50	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
128	51	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
129	52	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
130	53	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
131	54	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
132	55	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
133	56	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
134	57	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
135	58	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
136	59	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
137	60	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
138	61	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
139	62	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
140	63	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
141	64	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
142	66	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
143	67	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
144	68	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
145	69	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
146	70	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
147	71	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
148	72	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
149	73	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
150	74	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
151	75	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
152	76	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
153	77	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
154	78	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
155	79	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
156	80	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
157	81	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
158	82	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
159	83	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
160	84	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
161	85	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
162	86	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
163	87	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
164	88	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
165	89	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
166	90	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
167	91	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
168	92	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
169	93	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
170	94	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
171	95	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
172	96	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
173	97	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
174	98	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
175	99	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
176	100	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
177	101	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
178	102	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
179	103	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
180	104	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
181	105	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
182	106	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
183	107	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
184	108	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
185	109	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
186	110	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
187	112	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
188	113	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
189	114	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
190	115	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
191	116	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
192	118	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
193	119	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
194	120	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
195	122	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
196	123	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
197	124	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
198	125	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
199	126	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
200	127	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
201	128	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
202	129	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
203	130	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
204	131	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
205	132	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
206	133	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
207	134	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
208	135	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
209	136	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
210	137	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
211	138	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
212	139	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
213	140	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
214	141	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
215	142	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
216	143	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
217	144	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
218	145	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
219	146	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
220	147	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
221	148	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
222	149	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
223	150	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
224	151	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
225	152	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
226	153	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
227	154	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
228	155	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
229	156	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
230	157	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
231	158	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
232	159	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
233	160	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
234	161	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
235	162	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
236	163	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
237	164	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
238	165	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
239	166	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
240	167	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
241	168	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
242	169	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
243	170	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
244	171	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
245	172	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
246	173	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
247	174	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
248	175	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
249	176	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
250	177	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
251	178	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
252	179	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
253	180	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
254	181	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
255	182	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
256	183	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
257	184	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
258	185	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
259	186	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
260	187	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
261	188	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
262	189	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
263	190	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
264	191	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
265	192	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
266	193	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
267	194	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
268	195	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
269	196	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
270	197	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
271	198	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
272	13	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
273	49	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
274	50	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
275	51	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
276	52	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
277	53	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
278	54	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
279	55	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
280	56	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
281	57	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
282	58	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
283	59	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
284	60	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
285	61	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
286	62	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
287	63	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
288	64	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
289	66	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
290	67	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
291	68	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
292	69	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
293	70	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
294	71	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
295	72	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
296	73	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
297	74	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
298	75	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
299	76	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
300	77	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
301	78	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
302	79	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
303	80	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
304	81	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
305	82	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
306	83	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
307	84	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
308	85	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
309	86	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
310	87	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
311	88	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
312	89	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
313	90	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
314	91	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
315	92	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
316	93	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
317	94	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
318	95	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
319	96	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
320	97	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
321	98	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
322	99	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
323	100	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
324	101	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
325	102	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
326	103	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
327	104	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
328	105	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
329	106	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
330	107	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
331	108	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
332	109	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
333	110	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
334	112	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
335	113	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
336	114	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
337	115	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
338	116	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
339	118	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
340	119	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
341	120	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
342	122	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
343	123	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
344	124	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
345	125	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
346	126	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
347	127	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
348	128	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
349	129	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
350	130	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
351	131	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
352	132	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
353	133	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
354	134	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
355	135	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
356	136	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
357	137	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
358	138	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
359	139	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
360	140	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
361	141	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
362	142	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
363	143	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
364	144	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
365	145	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
366	146	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
367	147	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
368	148	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
369	149	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
370	150	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
371	151	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
372	152	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
373	153	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
374	154	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
375	155	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
376	156	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
377	157	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
378	158	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
379	159	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
380	160	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
381	161	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
382	162	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
383	163	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
384	164	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
385	165	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
386	166	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
387	167	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
388	168	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
389	169	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
390	170	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
391	171	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
392	172	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
393	173	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
394	174	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
395	175	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
396	176	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
397	177	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
398	178	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
399	179	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
400	180	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
401	181	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
402	182	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
403	183	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
404	184	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
\.


--
-- Data for Name: cdr; Type: TABLE DATA; Schema: public; Owner: zkhattab
--

COPY public.cdr (id, file_id, dial_a, dial_b, start_time, duration, service_id, hplmn, vplmn, external_charges, rated_flag, rated_service_id) FROM stdin;
230	1	201929443681	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
231	1	201929443681	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
232	1	201929443681	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
233	1	201413480521	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
234	1	201413480521	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
235	1	201413480521	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
236	1	201100488135	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
237	1	201100488135	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
238	1	201100488135	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
239	1	201921537400	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
240	1	201921537400	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
241	1	201921537400	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
242	1	201766068173	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
243	1	201766068173	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
244	1	201766068173	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
245	1	201577029209	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
246	1	201577029209	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
247	1	201577029209	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
248	1	201807868584	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
249	1	201807868584	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
250	1	201807868584	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
251	1	201971560057	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
252	1	201971560057	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
253	1	201971560057	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
254	1	201840246205	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
255	1	201840246205	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
256	1	201840246205	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
257	1	201684075608	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
258	1	201684075608	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
259	1	201684075608	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
260	1	201974393501	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
261	1	201974393501	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
262	1	201974393501	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
263	1	201198754346	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
264	1	201198754346	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
265	1	201198754346	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
266	1	201407381378	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
267	1	201407381378	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
268	1	201407381378	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
269	1	201526237308	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
270	1	201526237308	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
271	1	201526237308	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
272	1	201554543248	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
273	1	201554543248	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
274	1	201554543248	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
275	1	201776684616	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
276	1	201776684616	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
277	1	201776684616	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
278	1	201718702362	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
279	1	201718702362	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
280	1	201718702362	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
281	1	201232465204	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
282	1	201232465204	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
283	1	201232465204	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
284	1	201659706181	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
285	1	201659706181	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
286	1	201659706181	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
287	1	201649117498	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
288	1	201649117498	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
289	1	201649117498	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
290	1	201653069004	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
291	1	201653069004	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
292	1	201653069004	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
293	1	201779264035	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
1	1	201000000001	201000000002	2026-04-01 09:15:00	180	1	EGYVO	\N	0.60	t	\N
2	1	201000000001	201000000003	2026-04-01 14:30:00	1	3	EGYVO	\N	0.05	t	\N
3	1	201000000001	201000000005	2026-04-02 08:00:00	300	1	EGYVO	\N	1.00	t	\N
4	1	201000000001	201000000007	2026-04-03 11:20:00	1	3	EGYVO	\N	0.05	t	\N
5	1	201000000001	201000000009	2026-04-04 10:05:00	240	1	EGYVO	\N	0.80	t	\N
6	1	201000000001	201000000002	2026-04-05 16:45:00	1	3	EGYVO	\N	0.05	t	\N
7	1	201000000001	201000000011	2026-04-07 09:30:00	420	1	EGYVO	\N	1.40	t	\N
8	1	201000000001	201000000013	2026-04-08 13:00:00	1	3	EGYVO	\N	0.05	t	\N
9	1	201000000001	201000000015	2026-04-09 17:20:00	150	1	EGYVO	\N	0.60	t	\N
10	1	201000000001	201000000002	2026-04-10 08:45:00	360	1	EGYVO	\N	1.20	t	\N
11	1	201000000001	201000000003	2026-04-12 12:10:00	1	3	EGYVO	\N	0.05	t	\N
12	1	201000000001	201000000017	2026-04-14 15:30:00	210	1	EGYVO	\N	0.80	t	\N
13	1	201000000001	201000000004	2026-04-16 09:00:00	270	1	EGYVO	\N	1.00	t	\N
14	1	201000000001	201000000006	2026-04-18 14:00:00	1	3	EGYVO	\N	0.05	t	\N
15	1	201000000001	201000000008	2026-04-20 10:30:00	330	1	EGYVO	\N	1.20	t	\N
16	1	201000000002	201000000001	2026-04-01 08:30:00	300	1	EGYVO	\N	0.50	t	\N
17	1	201000000002	201000000004	2026-04-01 10:00:00	500	2	EGYVO	\N	0.00	t	\N
18	1	201000000002	201000000006	2026-04-01 12:00:00	1	3	EGYVO	\N	0.02	t	\N
19	1	201000000002	201000000008	2026-04-02 09:15:00	450	1	EGYVO	\N	0.80	t	\N
20	1	201000000002	201000000010	2026-04-02 14:30:00	750	2	EGYVO	\N	0.00	t	\N
21	1	201000000002	201000000012	2026-04-03 08:00:00	1	3	EGYVO	\N	0.02	t	\N
22	1	201000000002	201000000001	2026-04-04 11:45:00	600	1	EGYVO	\N	1.00	t	\N
23	1	201000000002	201000000014	2026-04-05 15:00:00	1000	2	EGYVO	\N	0.00	t	\N
24	1	201000000002	201000000016	2026-04-06 09:30:00	1	3	EGYVO	\N	0.02	t	\N
25	1	201000000002	201000000018	2026-04-07 13:20:00	480	1	EGYVO	\N	0.80	t	\N
26	1	201000000002	201000000001	2026-04-08 17:00:00	800	2	EGYVO	\N	0.00	t	\N
27	1	201000000002	201000000003	2026-04-09 10:15:00	1	3	EGYVO	\N	0.02	t	\N
28	2	201000000002	201000000001	2026-04-15 10:00:00	180	5	EGYVO	DEUTS	0.00	t	\N
29	2	201000000002	201000000004	2026-04-15 14:30:00	200	6	EGYVO	DEUTS	0.00	t	\N
30	2	201000000002	201000000006	2026-04-16 09:00:00	1	7	EGYVO	DEUTS	0.00	t	\N
31	2	201000000002	201000000008	2026-04-16 15:45:00	120	5	EGYVO	DEUTS	0.00	t	\N
32	2	201000000002	201000000001	2026-04-17 11:00:00	300	6	EGYVO	DEUTS	0.00	t	\N
33	1	201000000003	201000000001	2026-04-01 09:00:00	120	1	EGYVO	\N	0.40	t	\N
34	1	201000000003	201000000005	2026-04-02 11:30:00	1	3	EGYVO	\N	0.05	t	\N
35	1	201000000003	201000000007	2026-04-04 14:00:00	240	1	EGYVO	\N	0.80	t	\N
36	1	201000000003	201000000009	2026-04-06 16:30:00	1	3	EGYVO	\N	0.05	t	\N
37	1	201000000003	201000000001	2026-04-08 10:15:00	180	1	EGYVO	\N	0.60	t	\N
38	1	201000000003	201000000011	2026-04-10 13:45:00	90	1	EGYVO	\N	0.40	t	\N
39	1	201000000004	201000000002	2026-04-01 08:00:00	360	1	EGYVO	\N	0.60	t	\N
40	1	201000000004	201000000006	2026-04-01 13:00:00	600	2	EGYVO	\N	0.00	t	\N
41	1	201000000004	201000000008	2026-04-02 10:30:00	1	3	EGYVO	\N	0.02	t	\N
42	1	201000000004	201000000010	2026-04-03 15:00:00	420	1	EGYVO	\N	0.70	t	\N
43	1	201000000004	201000000012	2026-04-05 09:45:00	800	2	EGYVO	\N	0.00	t	\N
44	1	201000000004	201000000002	2026-04-07 14:00:00	1	3	EGYVO	\N	0.02	t	\N
45	1	201000000004	201000000014	2026-04-09 11:30:00	540	1	EGYVO	\N	0.90	t	\N
46	1	201000000004	201000000016	2026-04-11 16:00:00	700	2	EGYVO	\N	0.00	t	\N
47	1	201000000005	201000000001	2026-04-01 10:00:00	90	1	EGYVO	\N	0.40	t	\N
48	1	201000000005	201000000003	2026-04-03 12:30:00	1	3	EGYVO	\N	0.05	t	\N
49	1	201000000005	201000000007	2026-04-05 15:45:00	150	1	EGYVO	\N	0.60	t	\N
50	1	201000000005	201000000009	2026-04-08 09:00:00	1	3	EGYVO	\N	0.05	t	\N
51	1	201000000005	201000000001	2026-04-11 11:15:00	120	1	EGYVO	\N	0.40	t	\N
52	2	201000000006	201000000002	2026-04-01 09:30:00	540	1	EGYVO	\N	0.90	t	\N
53	2	201000000006	201000000008	2026-04-01 13:00:00	900	2	EGYVO	\N	0.00	t	\N
54	2	201000000006	201000000010	2026-04-02 08:15:00	1	3	EGYVO	\N	0.02	t	\N
55	2	201000000006	201000000012	2026-04-02 14:00:00	480	1	EGYVO	\N	0.80	t	\N
56	2	201000000006	201000000014	2026-04-03 10:30:00	1100	2	EGYVO	\N	0.00	t	\N
57	2	201000000006	201000000002	2026-04-04 15:45:00	1	3	EGYVO	\N	0.02	t	\N
58	2	201000000006	201000000016	2026-04-05 09:00:00	660	1	EGYVO	\N	1.10	t	\N
59	2	201000000006	201000000018	2026-04-06 12:30:00	850	2	EGYVO	\N	0.00	t	\N
60	2	201000000006	201000000002	2026-04-07 16:00:00	1	3	EGYVO	\N	0.02	t	\N
61	2	201000000006	201000000004	2026-04-08 10:15:00	720	1	EGYVO	\N	1.20	t	\N
62	2	201000000007	201000000001	2026-04-01 08:45:00	60	1	EGYVO	\N	0.20	t	\N
63	2	201000000007	201000000009	2026-04-03 13:30:00	1	3	EGYVO	\N	0.05	t	\N
64	2	201000000007	201000000011	2026-04-05 16:00:00	120	1	EGYVO	\N	0.40	t	\N
65	2	201000000007	201000000001	2026-04-08 10:00:00	180	1	EGYVO	\N	0.60	t	\N
66	2	201000000007	201000000003	2026-04-11 14:15:00	1	3	EGYVO	\N	0.05	t	\N
67	2	201000000007	201000000005	2026-04-14 09:30:00	240	1	EGYVO	\N	0.80	t	\N
68	2	201000000008	201000000002	2026-04-01 10:15:00	300	1	EGYVO	\N	0.50	t	\N
69	2	201000000008	201000000004	2026-04-02 12:00:00	650	2	EGYVO	\N	0.00	t	\N
70	2	201000000008	201000000006	2026-04-03 15:30:00	1	3	EGYVO	\N	0.02	t	\N
71	2	201000000008	201000000010	2026-04-04 09:00:00	420	1	EGYVO	\N	0.70	t	\N
72	2	201000000008	201000000012	2026-04-05 13:45:00	750	2	EGYVO	\N	0.00	t	\N
73	2	201000000008	201000000002	2026-04-07 11:00:00	1	3	EGYVO	\N	0.02	t	\N
74	2	201000000008	201000000014	2026-04-09 16:30:00	390	1	EGYVO	\N	0.70	t	\N
75	2	201000000009	201000000001	2026-04-01 11:00:00	180	1	EGYVO	\N	0.60	t	\N
76	2	201000000009	201000000003	2026-04-03 14:00:00	1	3	EGYVO	\N	0.05	t	\N
77	2	201000000009	201000000005	2026-04-06 09:30:00	150	1	EGYVO	\N	0.60	t	\N
78	2	201000000009	201000000007	2026-04-09 12:45:00	1	3	EGYVO	\N	0.05	t	\N
79	2	201000000010	201000000002	2026-04-01 09:45:00	360	1	EGYVO	\N	0.60	t	\N
80	2	201000000010	201000000004	2026-04-02 13:15:00	700	2	EGYVO	\N	0.00	t	\N
81	2	201000000010	201000000006	2026-04-03 16:00:00	1	3	EGYVO	\N	0.02	t	\N
82	2	201000000010	201000000008	2026-04-04 10:30:00	480	1	EGYVO	\N	0.80	t	\N
83	2	201000000010	201000000012	2026-04-05 14:00:00	900	2	EGYVO	\N	0.00	t	\N
84	2	201000000010	201000000002	2026-04-07 09:15:00	1	3	EGYVO	\N	0.02	t	\N
85	2	201000000010	201000000014	2026-04-09 15:45:00	540	1	EGYVO	\N	0.90	t	\N
86	2	201000000010	201000000016	2026-04-11 11:00:00	800	2	EGYVO	\N	0.00	t	\N
87	1	201000000011	201000000001	2026-04-01 08:00:00	600	1	EGYVO	\N	2.00	t	\N
88	1	201000000011	201000000003	2026-04-02 10:30:00	1	3	EGYVO	\N	0.05	t	\N
89	1	201000000011	201000000005	2026-04-03 14:15:00	480	1	EGYVO	\N	1.60	t	\N
90	1	201000000011	201000000007	2026-04-04 16:45:00	1	3	EGYVO	\N	0.05	t	\N
91	1	201000000011	201000000009	2026-04-05 09:30:00	540	1	EGYVO	\N	1.80	t	\N
92	1	201000000011	201000000001	2026-04-07 13:00:00	1	3	EGYVO	\N	0.05	t	\N
93	1	201000000011	201000000003	2026-04-09 10:15:00	420	1	EGYVO	\N	1.40	t	\N
94	1	201000000011	201000000005	2026-04-11 15:30:00	1	3	EGYVO	\N	0.05	t	\N
95	1	201000000012	201000000002	2026-04-01 11:30:00	270	1	EGYVO	\N	0.50	t	\N
96	1	201000000012	201000000004	2026-04-03 09:00:00	550	2	EGYVO	\N	0.00	t	\N
97	1	201000000012	201000000006	2026-04-05 13:45:00	1	3	EGYVO	\N	0.02	t	\N
98	1	201000000012	201000000008	2026-04-07 16:00:00	330	1	EGYVO	\N	0.60	t	\N
99	1	201000000014	201000000002	2026-04-01 09:00:00	390	1	EGYVO	\N	0.70	t	\N
100	1	201000000014	201000000004	2026-04-02 11:30:00	650	2	EGYVO	\N	0.00	t	\N
101	1	201000000014	201000000006	2026-04-03 14:00:00	1	3	EGYVO	\N	0.02	t	\N
102	1	201000000014	201000000008	2026-04-05 16:30:00	450	1	EGYVO	\N	0.80	t	\N
103	1	201000000014	201000000010	2026-04-07 10:15:00	700	2	EGYVO	\N	0.00	t	\N
104	1	201000000014	201000000002	2026-04-09 13:45:00	1	3	EGYVO	\N	0.02	t	\N
105	2	201000000015	201000000002	2026-04-01 08:00:00	480	1	EGYVO	\N	0.40	t	\N
106	2	201000000015	201000000004	2026-04-01 10:30:00	1200	2	EGYVO	\N	0.00	t	\N
107	2	201000000015	201000000006	2026-04-01 13:00:00	1	3	EGYVO	\N	0.01	t	\N
108	2	201000000015	201000000008	2026-04-02 09:00:00	600	1	EGYVO	\N	0.50	t	\N
109	2	201000000015	201000000010	2026-04-02 14:00:00	1500	2	EGYVO	\N	0.00	t	\N
110	2	201000000015	201000000012	2026-04-03 10:15:00	1	3	EGYVO	\N	0.01	t	\N
111	2	201000000015	201000000002	2026-04-04 15:30:00	720	1	EGYVO	\N	0.60	t	\N
112	2	201000000015	201000000016	2026-04-05 09:45:00	1800	2	EGYVO	\N	0.00	t	\N
113	2	201000000015	201000000002	2026-04-20 10:00:00	240	5	EGYVO	FRANC	0.00	t	\N
114	2	201000000015	201000000004	2026-04-20 14:30:00	400	6	EGYVO	FRANC	0.00	t	\N
115	2	201000000015	201000000006	2026-04-21 09:00:00	1	7	EGYVO	FRANC	0.00	t	\N
116	2	201000000016	201000000002	2026-04-01 09:30:00	600	1	EGYVO	\N	0.50	t	\N
117	2	201000000016	201000000004	2026-04-01 12:00:00	1400	2	EGYVO	\N	0.00	t	\N
118	2	201000000016	201000000006	2026-04-01 15:30:00	1	3	EGYVO	\N	0.01	t	\N
119	2	201000000016	201000000008	2026-04-02 08:30:00	780	1	EGYVO	\N	0.65	t	\N
120	2	201000000016	201000000010	2026-04-02 13:00:00	1600	2	EGYVO	\N	0.00	t	\N
121	2	201000000016	201000000012	2026-04-03 10:00:00	1	3	EGYVO	\N	0.01	t	\N
122	2	201000000016	201000000014	2026-04-03 16:00:00	840	1	EGYVO	\N	0.70	t	\N
123	2	201000000016	201000000002	2026-04-04 11:30:00	1800	2	EGYVO	\N	0.00	t	\N
124	2	201000000017	201000000002	2026-04-01 10:00:00	300	1	EGYVO	\N	0.50	t	\N
125	2	201000000017	201000000004	2026-04-02 12:30:00	600	2	EGYVO	\N	0.00	t	\N
126	2	201000000017	201000000006	2026-04-03 15:00:00	1	3	EGYVO	\N	0.02	t	\N
127	2	201000000017	201000000008	2026-04-05 09:30:00	420	1	EGYVO	\N	0.70	t	\N
128	2	201000000017	201000000010	2026-04-07 14:00:00	750	2	EGYVO	\N	0.00	t	\N
129	2	201000000017	201000000002	2026-04-09 11:15:00	1	3	EGYVO	\N	0.02	t	\N
294	1	201779264035	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
295	1	201779264035	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
296	1	201470237935	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
297	1	201470237935	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
298	1	201470237935	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
299	1	201802917632	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
300	1	201802917632	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
301	1	201802917632	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
302	1	201835042990	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
303	1	201835042990	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
304	1	201835042990	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
305	1	201462099679	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
306	1	201462099679	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
307	1	201462099679	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
308	1	201711745398	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
309	1	201711745398	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
310	1	201711745398	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
311	1	201273640490	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
312	1	201273640490	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
313	1	201273640490	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
314	1	201804307139	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
315	1	201804307139	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
316	1	201804307139	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
317	1	201659605961	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
318	1	201659605961	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
319	1	201659605961	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
320	1	201342567152	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
321	1	201342567152	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
322	1	201342567152	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
323	1	201301312298	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
324	1	201301312298	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
325	1	201301312298	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
326	1	201694166136	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
327	1	201694166136	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
328	1	201694166136	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
329	1	201825521770	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
330	1	201825521770	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
331	1	201825521770	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
332	1	201568724886	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
333	1	201568724886	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
334	1	201568724886	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
335	1	201330199728	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
336	1	201330199728	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
337	1	201330199728	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
338	1	201611131414	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
339	1	201611131414	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
340	1	201611131414	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
341	1	201949566929	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
342	1	201949566929	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
343	1	201949566929	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
344	1	201836162878	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
345	1	201836162878	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
346	1	201836162878	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
347	1	201984327233	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
348	1	201984327233	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
349	1	201984327233	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
350	1	201753036489	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
351	1	201753036489	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
352	1	201753036489	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
353	1	201233997401	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
354	1	201233997401	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
355	1	201233997401	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
356	1	201255851063	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
357	1	201255851063	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
358	1	201255851063	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
359	1	201211097847	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
360	1	201211097847	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
361	1	201211097847	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
362	1	201294741054	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
363	1	201294741054	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
364	1	201294741054	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
365	1	201988892685	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
366	1	201988892685	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
367	1	201988892685	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
368	1	201717769502	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
369	1	201717769502	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
370	1	201717769502	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
371	1	201656715920	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
372	1	201656715920	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
373	1	201656715920	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
374	1	201186352421	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
375	1	201186352421	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
376	1	201186352421	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
377	1	201420871936	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
378	1	201420871936	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
379	1	201420871936	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
380	1	201777264317	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
381	1	201777264317	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
382	1	201777264317	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
383	1	201362708743	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
384	1	201362708743	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
385	1	201362708743	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
386	1	201358767975	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
387	1	201358767975	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
388	1	201358767975	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
389	1	201758547932	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
390	1	201758547932	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
391	1	201758547932	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
392	1	201288445442	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
393	1	201288445442	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
394	1	201288445442	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
395	1	201419739858	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
396	1	201419739858	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
397	1	201419739858	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
398	1	201570066932	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
399	1	201570066932	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
400	1	201570066932	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
401	1	201198229833	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
402	1	201198229833	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
403	1	201198229833	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
404	1	201599166808	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
405	1	201599166808	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
406	1	201599166808	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
407	1	201947919413	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
408	1	201947919413	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
409	1	201947919413	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
410	1	201624427143	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
411	1	201624427143	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
412	1	201624427143	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
413	1	201274207034	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
414	1	201274207034	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
415	1	201274207034	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
416	1	201733342762	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
417	1	201733342762	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
418	1	201733342762	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
419	1	201311169287	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
420	1	201311169287	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
421	1	201311169287	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
422	1	201767489862	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
423	1	201767489862	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
424	1	201767489862	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
425	1	201903689006	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
426	1	201903689006	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
427	1	201903689006	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
428	1	201437218906	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
429	1	201437218906	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
430	1	201437218906	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
431	1	201828797537	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
432	1	201828797537	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
433	1	201828797537	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
434	1	201582165582	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
435	1	201582165582	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
436	1	201582165582	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
437	1	201443434524	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
438	1	201443434524	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
439	1	201443434524	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
440	1	201180758537	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
441	1	201180758537	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
442	1	201180758537	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
443	1	201251619033	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
444	1	201251619033	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
445	1	201251619033	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
446	1	201462924192	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
447	1	201462924192	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
448	1	201462924192	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
449	1	201000000001	201000000002	2026-04-01 10:00:00	120	1	EGYVO	\N	0.40	t	\N
\.


--
-- Data for Name: contract; Type: TABLE DATA; Schema: public; Owner: zkhattab
--

COPY public.contract (id, user_account_id, rateplan_id, msisdn, status, credit_limit, available_credit) FROM stdin;
49	50	3	201929443681	active	1000.00	1000.00
50	51	1	201429981367	suspended	200.00	200.00
13	14	1	201000000013	suspended	200.00	200.00
51	52	3	201413480521	active	1000.00	1000.00
52	53	3	201385628459	suspended	1000.00	1000.00
53	54	1	201213799908	suspended	200.00	200.00
54	55	2	201732646622	suspended	500.00	500.00
18	19	1	201000000018	terminated	200.00	200.00
10	11	2	201000000010	active	500.00	500.00
9	10	1	201000000009	active	200.00	200.00
8	9	2	201000000008	active	500.00	500.00
7	8	1	201000000007	active	200.00	200.00
6	7	2	201000000006	active	500.00	500.00
5	6	1	201000000005	active	200.00	200.00
4	5	2	201000000004	active	500.00	500.00
3	4	1	201000000003	active	200.00	200.00
55	56	1	201544098306	suspended	200.00	200.00
56	57	2	201100488135	active	500.00	500.00
57	58	1	201619259144	suspended	200.00	200.00
58	59	3	201921537400	active	1000.00	1000.00
59	60	2	201766068173	active	500.00	500.00
60	61	1	201596567886	suspended_debt	200.00	200.00
61	62	1	201577029209	active	200.00	200.00
62	63	1	201807282720	suspended	200.00	200.00
63	64	2	201286932142	active	500.00	500.00
64	65	2	201164642038	suspended	500.00	500.00
65	66	1	201676533855	terminated	200.00	200.00
66	67	2	201383276193	suspended	500.00	500.00
67	68	1	201570152514	suspended	200.00	200.00
68	69	1	201807868584	active	200.00	200.00
69	70	2	201971560057	active	500.00	500.00
70	71	3	201840246205	active	1000.00	1000.00
71	72	2	201684075608	active	500.00	500.00
72	73	2	201577199236	suspended	500.00	500.00
73	74	1	201974393501	active	200.00	200.00
74	75	2	201198754346	active	500.00	500.00
75	76	2	201407381378	active	500.00	500.00
76	77	1	201937787633	suspended	200.00	200.00
2	3	2	201000000002	active	500.00	496.82
77	78	2	201612484713	suspended	500.00	500.00
78	79	2	201323801663	suspended	500.00	500.00
79	80	3	201526237308	active	1000.00	1000.00
80	81	3	201554543248	active	1000.00	1000.00
81	82	1	201776684616	active	200.00	200.00
82	83	1	201367791331	active	200.00	200.00
83	84	1	201718702362	active	200.00	200.00
84	85	3	201212911963	active	1000.00	1000.00
85	86	2	201220083435	suspended	500.00	500.00
86	87	3	201232465204	active	1000.00	1000.00
87	88	1	201998010690	active	200.00	200.00
88	89	1	201659706181	active	200.00	200.00
89	90	2	201547174916	active	500.00	500.00
90	91	1	201252951019	suspended	200.00	200.00
91	92	2	201710876578	suspended	500.00	500.00
92	93	3	201590865366	suspended_debt	1000.00	1000.00
93	94	1	201471555986	active	200.00	200.00
94	95	2	201649117498	active	500.00	500.00
95	96	1	201264979417	suspended	200.00	200.00
96	97	1	201653069004	active	200.00	200.00
97	98	2	201779264035	active	500.00	500.00
98	99	1	201470237935	active	200.00	200.00
99	100	2	201802917632	active	500.00	500.00
100	101	2	201835042990	active	500.00	500.00
101	102	1	201462099679	active	200.00	200.00
102	103	2	201411625546	active	500.00	500.00
103	104	3	201829056999	suspended	1000.00	1000.00
104	105	2	201711745398	active	500.00	500.00
105	106	1	201267326529	suspended	200.00	200.00
106	107	2	201135432749	suspended	500.00	500.00
107	108	2	201495133161	suspended	500.00	500.00
108	109	1	201273640490	active	200.00	200.00
109	110	3	201934864215	suspended_debt	1000.00	1000.00
110	111	1	201836494481	active	200.00	200.00
111	112	2	201763896489	terminated	500.00	500.00
112	113	1	201804307139	active	200.00	200.00
113	114	2	201659605961	active	500.00	500.00
114	115	2	201958741292	active	500.00	500.00
115	116	2	201342567152	active	500.00	500.00
116	117	2	201301312298	active	500.00	500.00
117	118	1	201722845880	terminated	200.00	200.00
118	119	1	201694166136	active	200.00	200.00
119	120	2	201837084004	suspended	500.00	500.00
120	121	2	201825521770	active	500.00	500.00
121	122	3	201874881544	terminated	1000.00	1000.00
122	123	1	201568724886	active	200.00	200.00
123	124	1	201330199728	active	200.00	200.00
124	125	2	201611131414	active	500.00	500.00
125	126	2	201949566929	active	500.00	500.00
126	127	2	201836162878	active	500.00	500.00
127	128	1	201369118737	active	200.00	200.00
128	129	3	201813057806	suspended_debt	1000.00	1000.00
129	130	2	201984327233	active	500.00	500.00
130	131	1	201753036489	active	200.00	200.00
131	132	1	201110623838	active	200.00	200.00
132	133	2	201233997401	active	500.00	500.00
133	134	1	201250407138	suspended_debt	200.00	200.00
134	135	2	201924975793	suspended	500.00	500.00
135	136	1	201671686439	suspended	200.00	200.00
136	137	2	201255851063	active	500.00	500.00
137	138	2	201529398002	suspended	500.00	500.00
138	139	2	201670552123	suspended	500.00	500.00
139	140	2	201211097847	active	500.00	500.00
140	141	1	201729276105	suspended	200.00	200.00
141	142	1	201294741054	active	200.00	200.00
142	143	2	201988892685	active	500.00	500.00
33	34	1	201000000033	active	300.00	300.00
32	33	3	201000000032	active	300.00	300.00
31	32	2	201000000031	active	300.00	300.00
30	31	2	201000000030	active	300.00	300.00
143	144	1	201717769502	active	200.00	200.00
144	145	2	201239535883	suspended	500.00	500.00
145	146	2	201656715920	active	500.00	500.00
146	147	2	201186352421	active	500.00	500.00
147	148	2	201960970378	suspended	500.00	500.00
148	149	2	201923881590	suspended	500.00	500.00
149	150	2	201420871936	active	500.00	500.00
150	151	3	201253193055	suspended	1000.00	1000.00
151	152	3	201777264317	active	1000.00	1000.00
152	153	3	201362708743	active	1000.00	1000.00
153	154	1	201358767975	active	200.00	200.00
154	155	1	201703206322	suspended_debt	200.00	200.00
155	156	2	201758547932	active	500.00	500.00
156	157	2	201608773241	suspended	500.00	500.00
157	158	2	201564960450	suspended	500.00	500.00
158	159	1	201946970409	suspended	200.00	200.00
159	160	3	201558289515	suspended	1000.00	1000.00
160	161	1	201288445442	active	200.00	200.00
161	162	2	201419739858	active	500.00	500.00
162	163	2	201720430298	suspended	500.00	500.00
163	164	2	201667897495	suspended	500.00	500.00
164	165	2	201570066932	active	500.00	500.00
165	166	3	201198229833	active	1000.00	1000.00
166	167	2	201976853507	suspended	500.00	500.00
167	168	2	201161552590	suspended	500.00	500.00
168	169	2	201599166808	active	500.00	500.00
169	170	2	201947919413	active	500.00	500.00
170	171	2	201624427143	active	500.00	500.00
171	172	3	201121918717	active	1000.00	1000.00
172	173	1	201868108276	suspended_debt	200.00	200.00
19	20	3	201000000019	active	300.00	300.00
20	21	3	201000000020	active	300.00	300.00
21	22	2	201000000021	active	300.00	300.00
22	23	2	201000000022	active	300.00	300.00
23	24	2	201000000023	active	300.00	300.00
24	25	3	201000000024	active	300.00	300.00
25	26	3	201000000025	active	300.00	300.00
26	27	3	201000000026	active	300.00	300.00
27	28	3	201000000027	active	300.00	300.00
28	29	3	201000000028	active	300.00	300.00
29	30	3	201000000029	active	300.00	300.00
173	174	1	201274207034	active	200.00	200.00
174	175	1	201130706955	suspended	200.00	200.00
175	176	2	201733342762	active	500.00	500.00
176	177	2	201311169287	active	500.00	500.00
177	178	1	201820941846	suspended_debt	200.00	200.00
178	179	1	201767489862	active	200.00	200.00
11	12	1	201000000011	active	200.00	200.00
12	13	2	201000000012	active	500.00	500.00
14	15	2	201000000014	active	500.00	500.00
15	16	3	201000000015	active	1000.00	1000.00
16	17	3	201000000016	active	1000.00	1000.00
17	18	2	201000000017	active	500.00	500.00
48	49	1	201000000048	active	300.00	300.00
47	48	1	201000000047	active	300.00	300.00
46	47	2	201000000046	active	300.00	300.00
45	46	3	201000000045	active	300.00	300.00
44	45	2	201000000044	active	300.00	300.00
43	44	3	201000000043	active	300.00	300.00
42	43	3	201000000042	active	300.00	300.00
41	42	3	201000000041	active	300.00	300.00
40	41	2	201000000040	active	300.00	300.00
39	40	3	201000000039	active	300.00	300.00
38	39	2	201000000038	active	300.00	300.00
37	38	1	201000000037	active	300.00	300.00
36	37	1	201000000036	active	300.00	300.00
35	36	3	201000000035	active	300.00	300.00
34	35	1	201000000034	active	300.00	300.00
179	180	2	201359892851	suspended	500.00	500.00
180	181	1	201903689006	active	200.00	200.00
181	182	1	201225081536	suspended	200.00	200.00
182	183	1	201113312729	suspended	200.00	200.00
183	184	3	201651964318	suspended_debt	1000.00	1000.00
184	185	3	201437218906	active	1000.00	1000.00
185	186	1	201455334792	active	200.00	200.00
186	187	3	201828797537	active	1000.00	1000.00
187	188	2	201560098469	suspended	500.00	500.00
188	189	3	201582165582	active	1000.00	1000.00
189	190	1	201299910713	suspended	200.00	200.00
190	191	3	201443434524	active	1000.00	1000.00
191	192	2	201180758537	active	500.00	500.00
192	193	1	201251619033	active	200.00	200.00
193	194	2	201908287013	suspended_debt	500.00	500.00
194	195	3	201374939723	suspended	1000.00	1000.00
195	196	2	201529519265	suspended	500.00	500.00
196	197	1	201462924192	active	200.00	200.00
197	198	2	201378613554	suspended	500.00	500.00
198	199	2	201291077573	suspended	500.00	500.00
1	2	1	201000000001	active	200.00	199.60
\.


--
-- Data for Name: contract_addon; Type: TABLE DATA; Schema: public; Owner: zkhattab
--

COPY public.contract_addon (id, contract_id, service_package_id, purchased_date, expiry_date, is_active, price_paid) FROM stdin;
\.


--
-- Data for Name: contract_consumption; Type: TABLE DATA; Schema: public; Owner: zkhattab
--

COPY public.contract_consumption (contract_id, service_package_id, rateplan_id, starting_date, ending_date, consumed, quota_limit, is_billed, bill_id) FROM stdin;
10	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	33
10	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	33
10	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	33
10	1	2	2026-04-01	2026-04-30	510.0000	2000.0000	t	33
9	1	1	2026-04-01	2026-04-30	140.0000	2000.0000	t	34
8	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	35
8	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	35
8	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	35
8	1	2	2026-04-01	2026-04-30	390.0000	2000.0000	t	35
7	1	1	2026-04-01	2026-04-30	210.0000	2000.0000	t	36
6	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	37
6	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	37
6	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	37
6	1	2	2026-04-01	2026-04-30	750.0000	2000.0000	t	37
5	1	1	2026-04-01	2026-04-30	95.0000	2000.0000	t	38
4	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	39
4	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	39
4	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	39
4	1	2	2026-04-01	2026-04-30	480.0000	2000.0000	t	39
3	1	1	2026-04-01	2026-04-30	180.0000	2000.0000	t	40
17	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	73
17	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	73
17	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	73
17	1	2	2026-04-01	2026-04-30	340.0000	2000.0000	t	73
16	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	74
16	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	74
16	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	74
16	1	3	2026-04-01	2026-04-30	950.0000	2000.0000	t	74
15	1	3	2026-04-01	2026-04-30	820.0000	2000.0000	t	75
14	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	76
14	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	76
14	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	76
14	1	2	2026-04-01	2026-04-30	430.0000	2000.0000	t	76
12	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	77
12	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	77
12	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	77
12	1	2	2026-04-01	2026-04-30	290.0000	2000.0000	t	77
11	1	1	2026-04-01	2026-04-30	980.0000	2000.0000	t	78
33	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
33	3	1	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
32	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
32	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
32	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
32	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
32	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
32	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
32	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
31	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
31	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
31	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
31	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
31	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
31	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
31	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
30	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
30	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
30	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
30	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
1	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
1	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
2	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
2	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
2	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
2	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
2	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
2	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
2	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
3	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
3	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
4	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
4	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
4	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
4	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
4	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
4	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
4	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
5	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
5	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
6	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
6	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
6	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
6	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
6	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
6	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
6	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
7	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
7	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
8	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
8	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
8	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
8	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
8	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
8	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
8	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
9	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
9	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
30	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
30	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
30	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
19	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
19	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
19	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
19	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
19	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
19	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
19	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
20	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
20	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
20	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
20	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
20	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
20	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
20	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
21	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
21	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
21	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
21	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
21	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
10	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
10	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
10	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
10	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
10	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
10	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
10	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
11	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
11	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
12	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
12	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
12	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
12	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
12	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
12	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
12	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
14	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
14	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
14	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
14	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
14	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
14	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
14	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
15	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
15	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
15	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
15	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
15	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
15	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
15	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
16	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
16	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
16	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
16	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
16	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
16	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
16	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
17	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
17	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
17	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
17	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
17	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
17	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
17	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
19	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
19	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
19	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
19	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
19	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
19	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
19	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
20	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
20	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
20	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
20	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
20	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
20	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
20	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
21	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
21	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
21	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
21	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
21	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
21	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
21	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
22	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
22	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
22	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
22	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
22	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
22	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
22	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
23	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
23	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
23	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
23	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
23	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
23	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
23	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
24	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
24	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
24	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
24	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
24	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
24	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
24	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
25	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
25	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
25	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
25	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
25	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
25	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
25	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
26	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
26	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
26	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
26	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
26	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
26	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
26	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
27	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
27	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
27	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
27	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
27	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
27	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
27	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
28	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
28	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
28	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
28	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
28	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
28	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
28	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
29	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
29	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
29	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
29	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
29	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
29	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
29	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
30	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
30	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
30	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
30	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
30	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
30	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
30	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
31	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
31	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
31	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
31	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
31	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
31	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
31	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
32	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
32	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
32	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
32	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
32	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
32	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
32	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
33	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
33	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
34	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
34	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
35	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
35	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
35	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
35	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
35	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
35	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
35	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
36	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
36	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
37	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
37	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
38	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
38	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
38	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
38	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
38	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
38	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
38	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
39	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
39	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
39	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
39	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
39	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
39	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
39	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
40	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
40	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
40	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
40	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
40	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
40	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
40	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
41	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
41	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
41	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
41	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
41	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
41	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
41	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
42	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
42	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
42	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
42	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
42	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
42	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
42	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
43	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
43	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
43	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
43	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
43	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
43	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
43	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
44	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
44	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
44	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
44	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
44	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
44	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
44	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
45	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
45	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
45	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
45	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
45	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
45	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
45	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
46	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
46	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
46	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
46	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
46	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
46	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
46	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
47	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
47	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
48	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
48	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
1	1	1	2026-03-01	2026-03-31	310.0000	1000.0000	t	17
1	3	1	2026-03-01	2026-03-31	42.0000	100.0000	t	17
21	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
21	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
22	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
22	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
22	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
22	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
22	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
22	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
22	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
23	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
23	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
23	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
23	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
23	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
10	2	2	2026-04-01	2026-04-30	2400.0000	10000.0000	t	33
10	3	2	2026-04-01	2026-04-30	75.0000	500.0000	t	33
10	4	2	2026-04-01	2026-04-30	40.0000	10000.0000	t	33
9	3	1	2026-04-01	2026-04-30	8.0000	500.0000	t	34
8	2	2	2026-04-01	2026-04-30	1500.0000	10000.0000	t	35
8	3	2	2026-04-01	2026-04-30	55.0000	500.0000	t	35
8	4	2	2026-04-01	2026-04-30	20.0000	10000.0000	t	35
7	3	1	2026-04-01	2026-04-30	18.0000	500.0000	t	36
6	2	2	2026-04-01	2026-04-30	3200.0000	10000.0000	t	37
6	3	2	2026-04-01	2026-04-30	110.0000	500.0000	t	37
6	4	2	2026-04-01	2026-04-30	50.0000	10000.0000	t	37
5	3	1	2026-04-01	2026-04-30	12.0000	500.0000	t	38
4	2	2	2026-04-01	2026-04-30	1800.0000	10000.0000	t	39
4	3	2	2026-04-01	2026-04-30	65.0000	500.0000	t	39
4	4	2	2026-04-01	2026-04-30	30.0000	10000.0000	t	39
3	3	1	2026-04-01	2026-04-30	22.0000	500.0000	t	40
1	1	1	2026-04-01	2026-04-30	350.0000	2000.0000	t	41
1	3	1	2026-04-01	2026-04-30	45.0000	500.0000	t	41
2	1	2	2026-04-01	2026-04-30	620.0000	2000.0000	t	42
2	2	2	2026-04-01	2026-04-30	2100.0000	10000.0000	t	42
2	3	2	2026-04-01	2026-04-30	85.0000	500.0000	t	42
2	4	2	2026-04-01	2026-04-30	50.0000	10000.0000	t	42
2	5	2	2026-04-01	2026-04-30	120.0000	100.0000	t	42
2	6	2	2026-04-01	2026-04-30	400.0000	2000.0000	t	42
2	7	2	2026-04-01	2026-04-30	30.0000	100.0000	t	42
17	2	2	2026-04-01	2026-04-30	1100.0000	10000.0000	t	73
17	3	2	2026-04-01	2026-04-30	48.0000	500.0000	t	73
17	4	2	2026-04-01	2026-04-30	10.0000	10000.0000	t	73
16	2	3	2026-04-01	2026-04-30	4900.0000	10000.0000	t	74
16	3	3	2026-04-01	2026-04-30	180.0000	500.0000	t	74
16	4	3	2026-04-01	2026-04-30	50.0000	10000.0000	t	74
15	2	3	2026-04-01	2026-04-30	3800.0000	10000.0000	t	75
15	3	3	2026-04-01	2026-04-30	145.0000	500.0000	t	75
15	4	3	2026-04-01	2026-04-30	50.0000	10000.0000	t	75
15	5	3	2026-04-01	2026-04-30	80.0000	100.0000	t	75
15	6	3	2026-04-01	2026-04-30	320.0000	2000.0000	t	75
15	7	3	2026-04-01	2026-04-30	20.0000	100.0000	t	75
14	2	2	2026-04-01	2026-04-30	1200.0000	10000.0000	t	76
14	3	2	2026-04-01	2026-04-30	60.0000	500.0000	t	76
14	4	2	2026-04-01	2026-04-30	25.0000	10000.0000	t	76
12	2	2	2026-04-01	2026-04-30	900.0000	10000.0000	t	77
12	3	2	2026-04-01	2026-04-30	35.0000	500.0000	t	77
12	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	77
11	3	1	2026-04-01	2026-04-30	190.0000	500.0000	t	78
23	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
23	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
24	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
24	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
24	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
24	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
24	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
24	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
24	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
25	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
25	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
25	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
25	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
25	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
25	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
25	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
26	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
26	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
26	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
26	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
26	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
26	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
26	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
27	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
27	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
27	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
27	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
27	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
27	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
27	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
28	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
28	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
28	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
28	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
28	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
28	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
28	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
29	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
29	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
29	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
29	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
29	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
29	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
29	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
48	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
48	3	1	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
47	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
47	3	1	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
46	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
46	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
46	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
46	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
46	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
46	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
46	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
45	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
45	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
45	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
45	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
45	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
45	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
45	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
44	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
44	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
44	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
44	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
44	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
44	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
44	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
43	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
43	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
43	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
43	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
43	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
43	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
43	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
42	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
42	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
42	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
42	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
42	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
42	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
42	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
41	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
41	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
41	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
41	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
41	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
41	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
41	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
40	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
40	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
40	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
40	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
40	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
40	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
40	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
39	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
39	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
39	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
39	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
39	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
39	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
39	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
38	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
38	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
38	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
38	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
38	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
38	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
38	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
37	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
37	3	1	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
36	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
36	3	1	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
35	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
35	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
35	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
35	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
35	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
35	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
35	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
34	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
34	3	1	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
49	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	273
49	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	273
49	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	273
49	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	273
49	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	273
49	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	273
49	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	273
51	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	275
51	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	275
51	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	275
51	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	275
51	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	275
51	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	275
51	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	275
56	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	280
56	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	280
56	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	280
56	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	280
56	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	280
56	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	280
69	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	292
69	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	292
69	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	292
69	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	292
69	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	292
70	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	293
70	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	293
70	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	293
70	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	293
70	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	293
70	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	293
70	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	293
71	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	294
71	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	294
71	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	294
71	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	294
71	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	294
71	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	294
71	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	294
73	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	296
73	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	296
74	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	297
74	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	297
74	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	297
74	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	297
74	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	297
74	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	297
74	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	297
75	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	298
75	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	298
75	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	298
75	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	298
75	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	298
75	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	298
75	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	298
94	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	317
94	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	317
94	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	317
94	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	317
94	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	317
96	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	319
96	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	319
97	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	320
97	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	320
97	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	320
97	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	320
97	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	320
97	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	320
97	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	320
98	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	321
98	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	321
99	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	322
99	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	322
99	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	322
99	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	322
99	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	322
99	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	322
99	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	322
100	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	323
100	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	323
100	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	323
100	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	323
100	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	323
100	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	323
100	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	323
101	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	324
101	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	324
102	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	325
102	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	325
102	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	325
102	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	325
102	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	325
102	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	325
102	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	325
118	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	339
118	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	339
120	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	341
120	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	341
120	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	341
120	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	341
120	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	341
120	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	341
120	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	341
122	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	342
122	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	342
123	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	343
123	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	343
124	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	344
124	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	344
124	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	344
124	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	344
124	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	344
124	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	344
124	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	344
125	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	345
125	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	345
125	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	345
125	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	345
125	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	345
125	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	345
125	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	345
126	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	346
126	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	346
126	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	346
126	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	346
126	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	346
126	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	346
126	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	346
127	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	347
127	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	347
129	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	349
129	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	349
129	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	349
129	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	349
129	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	349
143	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	363
145	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	365
145	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	365
145	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	365
145	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	365
145	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	365
145	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	365
145	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	365
146	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	366
146	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	366
146	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	366
146	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	366
146	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	366
146	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	366
146	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	366
149	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	369
149	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	369
149	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	369
149	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	369
149	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	369
149	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	369
149	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	369
151	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	371
151	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	371
151	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	371
151	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	371
151	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	371
151	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	371
151	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	371
152	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	372
152	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	372
152	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	372
152	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	372
152	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	372
152	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	372
152	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	372
153	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	373
153	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	373
56	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	280
58	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	282
58	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	282
58	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	282
58	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	282
58	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	282
58	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	282
58	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	282
59	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	283
59	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	283
59	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	283
59	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	283
59	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	283
59	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	283
59	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	283
185	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
185	3	1	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
186	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
186	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
186	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
186	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
186	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
186	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
61	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	285
61	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	285
186	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	f	\N
188	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
188	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
188	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
188	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
188	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
188	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
63	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	287
63	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	287
188	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	f	\N
190	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
190	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
190	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
190	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
190	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
190	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
63	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	287
63	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	287
190	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	f	\N
191	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
191	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
191	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
191	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
191	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
191	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
63	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	287
63	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	287
191	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	f	\N
192	3	1	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
63	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	287
68	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	291
192	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	f	\N
196	3	1	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
68	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	291
69	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	292
196	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	f	\N
69	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	292
79	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	302
79	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	302
79	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	302
79	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	302
79	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	302
79	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	302
79	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	302
80	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	303
80	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	303
80	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	303
80	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	303
80	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	303
80	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	303
80	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	303
81	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	304
81	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	304
82	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	305
82	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	305
83	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	306
83	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	306
84	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	307
84	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	307
84	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	307
84	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	307
84	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	307
84	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	307
84	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	307
86	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	309
86	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	309
86	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	309
86	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	309
86	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	309
86	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	309
86	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	309
87	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	310
87	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	310
88	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	311
88	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	311
89	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	312
89	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	312
89	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	312
89	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	312
89	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	312
89	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	312
89	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	312
93	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	316
93	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	316
94	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	317
94	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	317
104	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	327
104	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	327
104	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	327
104	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	327
104	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	327
104	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	327
104	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	327
108	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	331
108	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	331
110	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	333
110	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	333
112	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	334
112	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	334
113	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	335
113	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	335
113	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	335
113	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	335
113	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	335
113	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	335
113	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	335
114	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	336
114	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	336
114	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	336
114	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	336
114	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	336
114	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	336
114	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	336
115	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	337
115	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	337
115	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	337
115	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	337
115	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	337
115	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	337
115	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	337
116	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	338
116	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	338
116	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	338
116	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	338
116	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	338
116	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	338
116	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	338
129	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	349
129	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	349
130	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	350
130	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	350
131	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	351
131	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	351
132	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	352
132	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	352
132	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	352
132	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	352
132	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	352
132	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	352
132	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	352
136	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	356
136	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	356
136	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	356
136	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	356
136	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	356
136	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	356
136	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	356
139	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	359
139	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	359
139	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	359
139	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	359
139	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	359
139	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	359
139	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	359
141	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	361
141	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	361
142	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	362
142	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	362
142	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	362
142	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	362
142	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	362
142	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	362
142	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	362
143	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	363
155	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	375
155	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	375
155	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	375
155	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	375
155	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	375
155	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	375
155	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	375
160	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	380
160	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	380
161	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	381
161	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	381
161	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	381
161	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	381
161	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	381
161	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	381
161	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	381
164	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	384
164	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	384
164	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	384
164	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	384
164	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	384
164	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	384
164	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	384
165	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	385
165	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	385
165	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	385
165	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	385
165	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	385
165	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	385
165	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	385
168	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	388
168	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	388
168	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	388
168	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	388
168	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	388
168	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	388
168	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	388
169	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	389
169	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	389
169	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	389
169	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	389
169	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	389
169	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	389
169	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	389
170	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	390
170	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	390
170	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	390
170	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	390
170	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	390
170	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	390
170	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	390
171	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	391
171	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	391
171	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	391
171	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	391
171	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	391
171	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	391
171	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	391
173	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	393
173	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	393
175	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	395
175	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	395
175	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	395
175	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	395
175	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	395
175	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	395
175	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	395
176	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	396
176	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	396
176	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	396
176	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	396
176	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	396
176	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	396
176	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	396
178	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	398
178	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	398
180	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	400
180	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	400
184	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	404
184	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	404
184	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	404
184	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	404
184	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	404
184	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	404
184	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	404
\.


--
-- Data for Name: file; Type: TABLE DATA; Schema: public; Owner: zkhattab
--

COPY public.file (id, parsed_flag, file_path) FROM stdin;
1	t	/tmp/cdr_april_batch1.csv
2	t	/tmp/cdr_april_batch2.csv
6	t	master_test.cdr
\.


--
-- Data for Name: invoice; Type: TABLE DATA; Schema: public; Owner: zkhattab
--

COPY public.invoice (id, bill_id, pdf_path, generation_date) FROM stdin;
1	1	/invoices/feb26_contract1.pdf	2026-04-29 07:41:23.397932
2	2	/invoices/feb26_contract2.pdf	2026-04-29 07:41:23.397932
3	3	/invoices/feb26_contract3.pdf	2026-04-29 07:41:23.397932
4	4	/invoices/feb26_contract4.pdf	2026-04-29 07:41:23.397932
5	5	/invoices/feb26_contract5.pdf	2026-04-29 07:41:23.397932
6	6	/invoices/feb26_contract6.pdf	2026-04-29 07:41:23.397932
7	7	/invoices/feb26_contract7.pdf	2026-04-29 07:41:23.397932
8	8	/invoices/feb26_contract8.pdf	2026-04-29 07:41:23.397932
9	9	/invoices/feb26_contract9.pdf	2026-04-29 07:41:23.397932
10	10	/invoices/feb26_contract10.pdf	2026-04-29 07:41:23.397932
11	11	/invoices/feb26_contract11.pdf	2026-04-29 07:41:23.397932
12	12	/invoices/feb26_contract12.pdf	2026-04-29 07:41:23.397932
13	13	/invoices/feb26_contract14.pdf	2026-04-29 07:41:23.397932
14	14	/invoices/feb26_contract15.pdf	2026-04-29 07:41:23.397932
15	15	/invoices/feb26_contract16.pdf	2026-04-29 07:41:23.397932
16	16	/invoices/feb26_contract17.pdf	2026-04-29 07:41:23.397932
17	17	/invoices/mar26_contract1.pdf	2026-04-29 07:41:23.397932
18	18	/invoices/mar26_contract2.pdf	2026-04-29 07:41:23.397932
19	33	/app/processed/invoices/Bill_33.pdf	2026-04-29 04:53:40.383916
20	34	/app/processed/invoices/Bill_34.pdf	2026-04-29 04:53:40.466212
21	35	/app/processed/invoices/Bill_35.pdf	2026-04-29 04:53:40.549582
22	36	/app/processed/invoices/Bill_36.pdf	2026-04-29 04:53:40.608886
23	37	/app/processed/invoices/Bill_37.pdf	2026-04-29 04:53:40.68567
24	38	/app/processed/invoices/Bill_38.pdf	2026-04-29 04:53:40.735917
25	39	/app/processed/invoices/Bill_39.pdf	2026-04-29 04:53:40.794805
26	40	/app/processed/invoices/Bill_40.pdf	2026-04-29 04:53:40.837967
27	41	/app/processed/invoices/Bill_41.pdf	2026-04-29 04:53:40.898779
28	43	/app/processed/invoices/Bill_43.pdf	2026-04-29 04:53:40.971321
29	44	/app/processed/invoices/Bill_44.pdf	2026-04-29 04:53:41.010237
30	45	/app/processed/invoices/Bill_45.pdf	2026-04-29 04:53:41.039811
31	46	/app/processed/invoices/Bill_46.pdf	2026-04-29 04:53:41.073356
32	47	/app/processed/invoices/Bill_47.pdf	2026-04-29 04:53:41.105977
33	48	/app/processed/invoices/Bill_48.pdf	2026-04-29 04:53:41.144319
34	49	/app/processed/invoices/Bill_49.pdf	2026-04-29 04:53:41.188514
35	50	/app/processed/invoices/Bill_50.pdf	2026-04-29 04:53:41.225143
36	51	/app/processed/invoices/Bill_51.pdf	2026-04-29 04:53:41.267669
37	52	/app/processed/invoices/Bill_52.pdf	2026-04-29 04:53:41.302365
38	53	/app/processed/invoices/Bill_53.pdf	2026-04-29 04:53:41.338945
39	54	/app/processed/invoices/Bill_54.pdf	2026-04-29 04:53:41.374701
40	55	/app/processed/invoices/Bill_55.pdf	2026-04-29 04:53:41.406937
41	56	/app/processed/invoices/Bill_56.pdf	2026-04-29 04:53:41.437227
42	57	/app/processed/invoices/Bill_57.pdf	2026-04-29 04:53:41.471572
43	58	/app/processed/invoices/Bill_58.pdf	2026-04-29 04:53:41.502378
44	59	/app/processed/invoices/Bill_59.pdf	2026-04-29 04:53:41.540069
45	60	/app/processed/invoices/Bill_60.pdf	2026-04-29 04:53:41.571358
46	61	/app/processed/invoices/Bill_61.pdf	2026-04-29 04:53:41.604397
47	62	/app/processed/invoices/Bill_62.pdf	2026-04-29 04:53:41.636951
48	63	/app/processed/invoices/Bill_63.pdf	2026-04-29 04:53:41.675199
49	64	/app/processed/invoices/Bill_64.pdf	2026-04-29 04:53:41.705227
50	65	/app/processed/invoices/Bill_65.pdf	2026-04-29 04:53:41.738729
51	66	/app/processed/invoices/Bill_66.pdf	2026-04-29 04:53:41.764964
52	67	/app/processed/invoices/Bill_67.pdf	2026-04-29 04:53:41.812597
53	68	/app/processed/invoices/Bill_68.pdf	2026-04-29 04:53:41.840545
54	69	/app/processed/invoices/Bill_69.pdf	2026-04-29 04:53:41.869658
55	70	/app/processed/invoices/Bill_70.pdf	2026-04-29 04:53:41.899492
56	71	/app/processed/invoices/Bill_71.pdf	2026-04-29 04:53:41.925865
57	72	/app/processed/invoices/Bill_72.pdf	2026-04-29 04:53:41.954581
58	73	/app/processed/invoices/Bill_73.pdf	2026-04-29 04:53:41.993719
59	74	/app/processed/invoices/Bill_74.pdf	2026-04-29 04:53:42.026813
60	76	/app/processed/invoices/Bill_76.pdf	2026-04-29 04:53:42.074693
61	77	/app/processed/invoices/Bill_77.pdf	2026-04-29 04:53:42.107802
62	78	/app/processed/invoices/Bill_78.pdf	2026-04-29 04:53:42.137677
\.


--
-- Data for Name: msisdn_pool; Type: TABLE DATA; Schema: public; Owner: zkhattab
--

COPY public.msisdn_pool (id, msisdn, is_available) FROM stdin;
49	201000000049	t
50	201000000050	t
51	201000000051	t
52	201000000052	t
53	201000000053	t
54	201000000054	t
55	201000000055	t
56	201000000056	t
57	201000000057	t
58	201000000058	t
59	201000000059	t
60	201000000060	t
61	201000000061	t
62	201000000062	t
63	201000000063	t
64	201000000064	t
65	201000000065	t
66	201000000066	t
67	201000000067	t
68	201000000068	t
69	201000000069	t
70	201000000070	t
71	201000000071	t
72	201000000072	t
73	201000000073	t
74	201000000074	t
75	201000000075	t
76	201000000076	t
77	201000000077	t
78	201000000078	t
79	201000000079	t
80	201000000080	t
81	201000000081	t
82	201000000082	t
83	201000000083	t
84	201000000084	t
85	201000000085	t
86	201000000086	t
87	201000000087	t
88	201000000088	t
89	201000000089	t
90	201000000090	t
91	201000000091	t
92	201000000092	t
93	201000000093	t
94	201000000094	t
95	201000000095	t
96	201000000096	t
97	201000000097	t
98	201000000098	t
99	201000000099	t
1	201000000001	f
2	201000000002	f
3	201000000003	f
4	201000000004	f
5	201000000005	f
6	201000000006	f
7	201000000007	f
8	201000000008	f
9	201000000009	f
10	201000000010	f
11	201000000011	f
12	201000000012	f
13	201000000013	f
14	201000000014	f
15	201000000015	f
16	201000000016	f
17	201000000017	f
18	201000000018	f
19	201000000019	f
20	201000000020	f
21	201000000021	f
22	201000000022	f
23	201000000023	f
24	201000000024	f
25	201000000025	f
26	201000000026	f
27	201000000027	f
28	201000000028	f
29	201000000029	f
30	201000000030	f
31	201000000031	f
32	201000000032	f
33	201000000033	f
34	201000000034	f
35	201000000035	f
36	201000000036	f
37	201000000037	f
38	201000000038	f
39	201000000039	f
40	201000000040	f
41	201000000041	f
42	201000000042	f
43	201000000043	f
44	201000000044	f
45	201000000045	f
46	201000000046	f
47	201000000047	f
48	201000000048	f
100	201929443681	f
101	201429981367	f
102	201413480521	f
103	201385628459	f
104	201213799908	f
105	201732646622	f
106	201544098306	f
107	201100488135	f
108	201619259144	f
109	201921537400	f
110	201766068173	f
111	201596567886	f
112	201577029209	f
113	201807282720	f
114	201286932142	f
115	201164642038	f
116	201676533855	f
117	201383276193	f
118	201570152514	f
119	201807868584	f
120	201971560057	f
121	201840246205	f
122	201684075608	f
123	201577199236	f
124	201974393501	f
125	201198754346	f
126	201407381378	f
127	201937787633	f
128	201612484713	f
129	201323801663	f
130	201526237308	f
131	201554543248	f
132	201776684616	f
133	201367791331	f
134	201718702362	f
135	201212911963	f
136	201220083435	f
137	201232465204	f
138	201998010690	f
139	201659706181	f
140	201547174916	f
141	201252951019	f
142	201710876578	f
143	201590865366	f
144	201471555986	f
145	201649117498	f
146	201264979417	f
147	201653069004	f
148	201779264035	f
149	201470237935	f
150	201802917632	f
151	201835042990	f
152	201462099679	f
153	201411625546	f
154	201829056999	f
155	201711745398	f
156	201267326529	f
157	201135432749	f
158	201495133161	f
159	201273640490	f
160	201934864215	f
161	201836494481	f
162	201763896489	f
163	201804307139	f
164	201659605961	f
165	201958741292	f
166	201342567152	f
167	201301312298	f
168	201722845880	f
169	201694166136	f
170	201837084004	f
171	201825521770	f
172	201874881544	f
173	201568724886	f
174	201330199728	f
175	201611131414	f
176	201949566929	f
177	201836162878	f
178	201369118737	f
179	201813057806	f
180	201984327233	f
181	201753036489	f
182	201110623838	f
183	201233997401	f
184	201250407138	f
185	201924975793	f
186	201671686439	f
187	201255851063	f
188	201529398002	f
189	201670552123	f
190	201211097847	f
191	201729276105	f
192	201294741054	f
193	201988892685	f
194	201717769502	f
195	201239535883	f
196	201656715920	f
197	201186352421	f
198	201960970378	f
199	201923881590	f
200	201420871936	f
201	201253193055	f
202	201777264317	f
203	201362708743	f
204	201358767975	f
205	201703206322	f
206	201758547932	f
207	201608773241	f
208	201564960450	f
209	201946970409	f
210	201558289515	f
211	201288445442	f
212	201419739858	f
213	201720430298	f
214	201667897495	f
215	201570066932	f
216	201198229833	f
217	201976853507	f
218	201161552590	f
219	201599166808	f
220	201947919413	f
221	201624427143	f
222	201121918717	f
223	201868108276	f
224	201274207034	f
225	201130706955	f
226	201733342762	f
227	201311169287	f
228	201820941846	f
229	201767489862	f
230	201359892851	f
231	201903689006	f
232	201225081536	f
233	201113312729	f
234	201651964318	f
235	201437218906	f
236	201455334792	f
237	201828797537	f
238	201560098469	f
239	201582165582	f
240	201299910713	f
241	201443434524	f
242	201180758537	f
243	201251619033	f
244	201908287013	f
245	201374939723	f
246	201529519265	f
247	201462924192	f
248	201378613554	f
249	201291077573	f
\.


--
-- Data for Name: rateplan; Type: TABLE DATA; Schema: public; Owner: zkhattab
--

COPY public.rateplan (id, name, ror_data, ror_voice, ror_sms, ror_roaming_data, ror_roaming_voice, ror_roaming_sms, price) FROM stdin;
1	Basic	0.10	0.20	0.05	\N	\N	\N	75.00
2	Premium Gold	0.05	0.10	0.02	\N	\N	\N	370.00
3	Elite Enterprise	0.02	0.05	0.01	\N	\N	\N	950.00
\.


--
-- Data for Name: rateplan_service_package; Type: TABLE DATA; Schema: public; Owner: zkhattab
--

COPY public.rateplan_service_package (rateplan_id, service_package_id) FROM stdin;
1	1
1	3
2	1
2	2
2	3
2	4
2	5
2	6
2	7
3	1
3	2
3	3
3	4
3	5
3	6
3	7
\.


--
-- Data for Name: ror_contract; Type: TABLE DATA; Schema: public; Owner: zkhattab
--

COPY public.ror_contract (contract_id, rateplan_id, starting_date, data, voice, sms, roaming_voice, roaming_data, roaming_sms, bill_id) FROM stdin;
6	2	2026-04-01	2850	40.00	3	0.00	0	0	37
5	1	2026-04-01	0	7.00	2	0.00	0	0	38
4	2	2026-04-01	2100	22.00	2	0.00	0	0	39
3	1	2026-04-01	0	11.00	2	0.00	0	0	40
2	2	2026-04-01	3050	31.00	4	5.00	500	1	42
1	1	2026-04-01	0	45.00	6	0.00	0	0	41
13	1	2026-04-01	0	0.00	0	0.00	0	0	272
18	1	2026-04-01	0	0.00	0	0.00	0	0	\N
10	2	2026-04-01	2400	23.00	2	0.00	0	0	33
9	1	2026-04-01	0	6.00	2	0.00	0	0	34
8	2	2026-04-01	1400	19.00	2	0.00	0	0	35
7	1	2026-04-01	0	10.00	2	0.00	0	0	36
17	2	2026-04-01	1350	12.00	2	0.00	0	0	73
16	3	2026-04-01	4820	37.00	2	0.00	0	0	74
15	3	2026-04-01	4500	30.00	2	4.00	400	1	75
14	2	2026-04-01	1350	15.00	2	0.00	0	0	76
12	2	2026-04-01	550	11.00	1	0.00	0	0	77
11	1	2026-04-01	0	34.00	4	0.00	0	0	78
\.


--
-- Data for Name: service_package; Type: TABLE DATA; Schema: public; Owner: zkhattab
--

COPY public.service_package (id, name, type, amount, priority, price, is_roaming, description) FROM stdin;
1	Voice Pack	voice	2000.0000	2	75.00	f	2000 local minutes per month
2	Data Pack	data	10000.0000	2	150.00	f	10GB data per month
3	SMS Pack	sms	500.0000	2	25.00	f	500 SMS per month
4	🎁 Welcome Gift	free_units	10000.0000	1	0.00	f	10GB free data for new customers
5	Roaming Voice Pack	voice	100.0000	2	250.00	t	100 roaming minutes
6	Roaming Data Pack	data	2000.0000	2	500.00	t	2GB roaming data
7	Roaming SMS Pack	sms	100.0000	2	100.00	t	100 roaming SMS
\.


--
-- Data for Name: user_account; Type: TABLE DATA; Schema: public; Owner: zkhattab
--

COPY public.user_account (id, username, password, role, name, email, address, birthdate) FROM stdin;
1	admin	123456	admin	System Admin	admin@fmrz.com	HQ Cairo	1985-01-01
2	alice	123456	customer	Alice Smith	alice@gmail.com	123 Main St	1990-01-01
3	bob	123456	customer	Bob Johnson	bob@gmail.com	456 Elm St	1985-05-15
4	carol	123456	customer	Carol White	carol@gmail.com	789 Oak Ave	1992-03-10
5	david	123456	customer	David Brown	david@gmail.com	321 Pine Rd	1988-07-22
6	eva	123456	customer	Eva Green	eva@gmail.com	654 Maple Dr	1995-11-05
7	frank	123456	customer	Frank Miller	frank@gmail.com	987 Cedar Ln	1983-02-18
8	grace	123456	customer	Grace Lee	grace@gmail.com	147 Birch Blvd	1991-09-30
9	henry	123456	customer	Henry Wilson	henry@gmail.com	258 Walnut St	1987-04-14
10	iris	123456	customer	Iris Taylor	iris@gmail.com	369 Spruce Ave	1993-06-25
11	jack	123456	customer	Jack Davis	jack@gmail.com	741 Ash Ct	1986-12-03
12	karen	123456	customer	Karen Martinez	karen@gmail.com	852 Elm Pl	1994-08-17
13	leo	123456	customer	Leo Anderson	leo@gmail.com	963 Oak St	1989-01-29
14	mia	123456	customer	Mia Thomas	mia@gmail.com	159 Pine Ave	1996-05-08
15	noah	123456	customer	Noah Jackson	noah@gmail.com	267 Maple Rd	1984-10-21
16	olivia	123456	customer	Olivia Harris	olivia@gmail.com	348 Cedar Dr	1997-03-15
17	paul	123456	customer	Paul Clark	paul@gmail.com	426 Birch Ln	1982-07-04
18	quinn	123456	customer	Quinn Lewis	quinn@gmail.com	537 Walnut Blvd	1998-11-19
19	rachel	123456	customer	Rachel Walker	rachel@gmail.com	648 Spruce St	1981-02-27
20	mariam_101	123456	customer	Mariam Hassan	mariam.hassan11@fmrz-telecom.com	70 El-Nasr St, Cairo	2009-12-29
21	sara_102	123456	customer	Sara Hassan	sara.hassan12@fmrz-telecom.com	44 Cornish Rd, Suez	2009-08-25
22	amir_103	123456	customer	Amir Mansour	amir.mansour13@fmrz-telecom.com	38 Tahrir Sq, Cairo	1990-08-12
23	hassan_104	123456	customer	Hassan Soliman	hassan.soliman14@fmrz-telecom.com	32 Gameat El Dowal, Giza	1986-05-25
24	layla_105	123456	customer	Layla Hassan	layla.hassan15@fmrz-telecom.com	49 Makram Ebeid, Cairo	2005-12-29
25	hassan_106	123456	customer	Hassan Khattab	hassan.khattab16@fmrz-telecom.com	52 Tahrir Sq, Suez	2003-08-23
26	fatma_107	123456	customer	Fatma Wahba	fatma.wahba17@fmrz-telecom.com	83 9th Street, Luxor	2008-12-23
27	ahmed_108	123456	customer	Ahmed Said	ahmed.said18@fmrz-telecom.com	44 Cornish Rd, Mansoura	2000-10-04
28	youssef_109	123456	customer	Youssef Gaber	youssef.gaber19@fmrz-telecom.com	13 Tahrir Sq, Giza	1992-08-23
29	nour_110	123456	customer	Nour Gaber	nour.gaber20@fmrz-telecom.com	45 El-Nasr St, Cairo	1986-06-10
30	mariam_111	123456	customer	Mariam Hassan	mariam.hassan21@fmrz-telecom.com	33 9th Street, Luxor	1990-05-10
31	salma_112	123456	customer	Salma Fouad	salma.fouad22@fmrz-telecom.com	61 9th Street, Cairo	1988-11-04
32	fatma_113	123456	customer	Fatma Wahba	fatma.wahba23@fmrz-telecom.com	15 Tahrir Sq, Cairo	1991-04-01
33	hassan_114	123456	customer	Hassan Gaber	hassan.gaber24@fmrz-telecom.com	71 Cornish Rd, Alexandria	2010-03-05
34	sara_115	123456	customer	Sara Nasr	sara.nasr25@fmrz-telecom.com	56 El-Nasr St, Cairo	2010-08-14
35	omar_116	123456	customer	Omar Zaki	omar.zaki26@fmrz-telecom.com	52 Cornish Rd, Cairo	2009-12-30
36	mohamed_117	123456	customer	Mohamed Wahba	mohamed.wahba27@fmrz-telecom.com	25 Cornish Rd, Cairo	2002-05-19
37	mohamed_118	123456	customer	Mohamed Gaber	mohamed.gaber28@fmrz-telecom.com	52 Abbas El Akkad, Giza	1994-10-29
38	omar_119	123456	customer	Omar Fouad	omar.fouad29@fmrz-telecom.com	94 Makram Ebeid, Mansoura	1997-10-03
39	ziad_120	123456	customer	Ziad Zaki	ziad.zaki30@fmrz-telecom.com	69 Abbas El Akkad, Alexandria	1986-06-22
40	mohamed_121	123456	customer	Mohamed Said	mohamed.said31@fmrz-telecom.com	51 Makram Ebeid, Mansoura	2000-10-13
41	youssef_122	123456	customer	Youssef Mansour	youssef.mansour32@fmrz-telecom.com	57 Gameat El Dowal, Luxor	1986-08-06
42	ziad_123	123456	customer	Ziad Ezzat	ziad.ezzat33@fmrz-telecom.com	18 Gameat El Dowal, Luxor	1985-01-22
43	salma_124	123456	customer	Salma Nasr	salma.nasr34@fmrz-telecom.com	10 Cornish Rd, Alexandria	1996-12-23
44	sara_125	123456	customer	Sara Khattab	sara.khattab35@fmrz-telecom.com	76 Cornish Rd, Mansoura	1999-04-19
45	ziad_126	123456	customer	Ziad Ezzat	ziad.ezzat36@fmrz-telecom.com	44 Gameat El Dowal, Suez	1997-01-20
46	ibrahim_127	123456	customer	Ibrahim Fouad	ibrahim.fouad37@fmrz-telecom.com	67 Tahrir Sq, Cairo	1999-11-08
47	amir_128	123456	customer	Amir Salem	amir.salem38@fmrz-telecom.com	13 Abbas El Akkad, Cairo	1998-10-30
48	ibrahim_129	123456	customer	Ibrahim Ezzat	ibrahim.ezzat39@fmrz-telecom.com	93 Gameat El Dowal, Luxor	2001-05-05
49	omar_130	123456	customer	Omar Zaki	omar.zaki40@fmrz-telecom.com	10 Cornish Rd, Alexandria	1994-03-04
50	ibrahim_1_3525	123456	customer	Ibrahim Nasr	ibrahim_1_3525@fmrz-telecom.com	45 Zamalek Dr, Alexandria	1976-07-02
51	fatma_2_8697	123456	customer	Fatma Mansour	fatma_2_8697@fmrz-telecom.com	68 El-Nasr St, Alexandria	2009-09-24
52	sameh_3_1930	123456	customer	Sameh Hamad	sameh_3_1930@fmrz-telecom.com	37 Cornish Rd, Alexandria	1988-10-08
53	nour_4_4435	123456	customer	Nour Khattab	nour_4_4435@fmrz-telecom.com	96 Tahrir Sq, Aswan	1972-02-12
54	tarek_5_1871	123456	customer	Tarek Fouad	tarek_5_1871@fmrz-telecom.com	66 Cornish Rd, Cairo	1979-05-10
55	fatma_6_6120	123456	customer	Fatma Wahba	fatma_6_6120@fmrz-telecom.com	41 Gameat El Dowal, Aswan	2001-10-24
56	mona_7_3194	123456	customer	Mona Said	mona_7_3194@fmrz-telecom.com	23 9th Street, Suez	1983-09-04
57	nour_8_4436	123456	customer	Nour Fouad	nour_8_4436@fmrz-telecom.com	87 Zamalek Dr, Alexandria	1989-03-05
58	mohamed_9_7332	123456	customer	Mohamed Ezzat	mohamed_9_7332@fmrz-telecom.com	11 Gameat El Dowal, Hurghada	1984-11-26
59	ibrahim_10_8724	123456	customer	Ibrahim Khattab	ibrahim_10_8724@fmrz-telecom.com	76 Maadi St, Mansoura	1983-05-02
60	hala_11_1501	123456	customer	Hala Hamad	hala_11_1501@fmrz-telecom.com	35 Tahrir Sq, Mansoura	1997-03-28
61	tarek_12_6137	123456	customer	Tarek Hamad	tarek_12_6137@fmrz-telecom.com	93 Cornish Rd, Mansoura	2003-07-02
62	ahmed_13_5784	123456	customer	Ahmed Salem	ahmed_13_5784@fmrz-telecom.com	32 Maadi St, Hurghada	1990-06-14
63	mona_14_5706	123456	customer	Mona Khattab	mona_14_5706@fmrz-telecom.com	84 Zamalek Dr, Aswan	1985-07-19
64	amir_15_7104	123456	customer	Amir Soliman	amir_15_7104@fmrz-telecom.com	41 El-Nasr St, Suez	1996-06-29
65	salma_16_9030	123456	customer	Salma Salem	salma_16_9030@fmrz-telecom.com	15 Tahrir Sq, Suez	1985-07-16
66	dina_17_1929	123456	customer	Dina Gaber	dina_17_1929@fmrz-telecom.com	35 Abbas El Akkad, Mansoura	2006-11-30
67	layla_18_3453	123456	customer	Layla Soliman	layla_18_3453@fmrz-telecom.com	44 Maadi St, Giza	1993-10-16
68	hassan_19_9307	123456	customer	Hassan Wahba	hassan_19_9307@fmrz-telecom.com	78 Tahrir Sq, Luxor	2010-07-01
69	fatma_20_8705	123456	customer	Fatma Gaber	fatma_20_8705@fmrz-telecom.com	51 9th Street, Mansoura	1998-08-29
70	hala_21_6029	123456	customer	Hala Hassan	hala_21_6029@fmrz-telecom.com	43 Zamalek Dr, Cairo	1975-11-23
71	tarek_22_4121	123456	customer	Tarek Fouad	tarek_22_4121@fmrz-telecom.com	17 Abbas El Akkad, Mansoura	2002-04-21
72	hala_23_2424	123456	customer	Hala Badawi	hala_23_2424@fmrz-telecom.com	43 El-Nasr St, Giza	1986-02-27
73	sara_24_3625	123456	customer	Sara Fouad	sara_24_3625@fmrz-telecom.com	97 Cornish Rd, Luxor	1973-12-31
74	nour_25_1457	123456	customer	Nour Fouad	nour_25_1457@fmrz-telecom.com	84 Zamalek Dr, Luxor	1974-09-27
75	amir_26_6229	123456	customer	Amir Hassan	amir_26_6229@fmrz-telecom.com	64 Zamalek Dr, Aswan	2003-07-03
76	fatma_27_7307	123456	customer	Fatma Nasr	fatma_27_7307@fmrz-telecom.com	60 Cornish Rd, Hurghada	1996-09-13
77	mohamed_28_8092	123456	customer	Mohamed Salem	mohamed_28_8092@fmrz-telecom.com	88 Abbas El Akkad, Mansoura	1983-01-12
78	ibrahim_29_1687	123456	customer	Ibrahim Nasr	ibrahim_29_1687@fmrz-telecom.com	48 Maadi St, Hurghada	1984-02-07
79	dina_30_9602	123456	customer	Dina Fouad	dina_30_9602@fmrz-telecom.com	35 El-Nasr St, Cairo	1990-02-06
80	mariam_31_3716	123456	customer	Mariam Badawi	mariam_31_3716@fmrz-telecom.com	43 Gameat El Dowal, Cairo	2007-12-11
81	omar_32_9321	123456	customer	Omar Moussa	omar_32_9321@fmrz-telecom.com	62 9th Street, Giza	2009-08-06
82	mohamed_33_1576	123456	customer	Mohamed Badawi	mohamed_33_1576@fmrz-telecom.com	49 Tahrir Sq, Aswan	1985-11-10
83	dina_34_7244	123456	customer	Dina Soliman	dina_34_7244@fmrz-telecom.com	20 Gameat El Dowal, Alexandria	1998-10-08
84	sara_35_7060	123456	customer	Sara Zaki	sara_35_7060@fmrz-telecom.com	10 Abbas El Akkad, Giza	1997-01-18
85	ahmed_36_6304	123456	customer	Ahmed Wahba	ahmed_36_6304@fmrz-telecom.com	77 Makram Ebeid, Mansoura	1979-08-03
86	omar_37_8299	123456	customer	Omar Soliman	omar_37_8299@fmrz-telecom.com	21 El-Nasr St, Mansoura	2004-11-21
87	mariam_38_1699	123456	customer	Mariam Zaki	mariam_38_1699@fmrz-telecom.com	44 Gameat El Dowal, Suez	1998-12-05
88	sameh_39_1263	123456	customer	Sameh Khattab	sameh_39_1263@fmrz-telecom.com	22 Maadi St, Suez	1984-11-25
89	hala_40_9534	123456	customer	Hala Salem	hala_40_9534@fmrz-telecom.com	70 Zamalek Dr, Alexandria	2004-10-25
90	sara_41_6447	123456	customer	Sara Moussa	sara_41_6447@fmrz-telecom.com	24 Cornish Rd, Aswan	1980-08-22
91	youssef_42_4718	123456	customer	Youssef Hassan	youssef_42_4718@fmrz-telecom.com	96 Abbas El Akkad, Cairo	1999-03-06
92	hala_43_8895	123456	customer	Hala Said	hala_43_8895@fmrz-telecom.com	29 Cornish Rd, Mansoura	1971-01-10
93	tarek_44_6238	123456	customer	Tarek Hamad	tarek_44_6238@fmrz-telecom.com	73 Maadi St, Luxor	1972-11-20
94	mohamed_45_3772	123456	customer	Mohamed Moussa	mohamed_45_3772@fmrz-telecom.com	34 Gameat El Dowal, Aswan	2009-01-15
95	mohamed_46_6346	123456	customer	Mohamed Fouad	mohamed_46_6346@fmrz-telecom.com	48 9th Street, Hurghada	1982-12-03
96	salma_47_8366	123456	customer	Salma Said	salma_47_8366@fmrz-telecom.com	97 Gameat El Dowal, Hurghada	1976-12-11
97	nour_48_4755	123456	customer	Nour Hassan	nour_48_4755@fmrz-telecom.com	84 Tahrir Sq, Aswan	1975-10-19
98	dina_49_7775	123456	customer	Dina Badawi	dina_49_7775@fmrz-telecom.com	17 Maadi St, Alexandria	1981-01-24
99	ziad_50_3862	123456	customer	Ziad Moussa	ziad_50_3862@fmrz-telecom.com	93 Cornish Rd, Suez	1976-01-08
100	youssef_51_8718	123456	customer	Youssef Soliman	youssef_51_8718@fmrz-telecom.com	24 Maadi St, Luxor	1976-12-24
101	ibrahim_52_2582	123456	customer	Ibrahim Nasr	ibrahim_52_2582@fmrz-telecom.com	37 Makram Ebeid, Cairo	1990-03-02
102	mariam_53_1069	123456	customer	Mariam Zaki	mariam_53_1069@fmrz-telecom.com	91 El-Nasr St, Mansoura	1971-11-13
103	amir_54_5984	123456	customer	Amir Zaki	amir_54_5984@fmrz-telecom.com	27 Abbas El Akkad, Alexandria	1995-08-11
104	sameh_55_1992	123456	customer	Sameh Mansour	sameh_55_1992@fmrz-telecom.com	71 Gameat El Dowal, Mansoura	2001-07-31
105	youssef_56_5287	123456	customer	Youssef Gaber	youssef_56_5287@fmrz-telecom.com	12 Maadi St, Aswan	2008-02-15
106	amir_57_7608	123456	customer	Amir Hamad	amir_57_7608@fmrz-telecom.com	23 Gameat El Dowal, Aswan	1999-02-15
107	ibrahim_58_6723	123456	customer	Ibrahim Fouad	ibrahim_58_6723@fmrz-telecom.com	24 Abbas El Akkad, Alexandria	2008-11-03
108	omar_59_1757	123456	customer	Omar Moussa	omar_59_1757@fmrz-telecom.com	66 Zamalek Dr, Giza	2008-01-26
109	hassan_60_4251	123456	customer	Hassan Salem	hassan_60_4251@fmrz-telecom.com	80 Cornish Rd, Alexandria	2007-03-11
110	ziad_61_7037	123456	customer	Ziad Said	ziad_61_7037@fmrz-telecom.com	18 Maadi St, Luxor	1975-12-31
111	tarek_62_6738	123456	customer	Tarek Moussa	tarek_62_6738@fmrz-telecom.com	39 Zamalek Dr, Giza	1977-04-27
112	youssef_63_7881	123456	customer	Youssef Khattab	youssef_63_7881@fmrz-telecom.com	46 Maadi St, Aswan	1998-02-07
113	layla_64_4905	123456	customer	Layla Said	layla_64_4905@fmrz-telecom.com	77 9th Street, Mansoura	2000-06-12
114	youssef_65_5969	123456	customer	Youssef Hassan	youssef_65_5969@fmrz-telecom.com	64 Abbas El Akkad, Hurghada	2005-10-19
115	tarek_66_8915	123456	customer	Tarek Ezzat	tarek_66_8915@fmrz-telecom.com	77 Tahrir Sq, Luxor	2000-11-01
116	sameh_67_2439	123456	customer	Sameh Gaber	sameh_67_2439@fmrz-telecom.com	46 Tahrir Sq, Alexandria	2003-06-28
117	tarek_68_6104	123456	customer	Tarek Mansour	tarek_68_6104@fmrz-telecom.com	54 Gameat El Dowal, Aswan	1986-01-28
118	omar_69_9442	123456	customer	Omar Fouad	omar_69_9442@fmrz-telecom.com	42 Cornish Rd, Alexandria	1973-06-02
119	layla_70_8631	123456	customer	Layla Said	layla_70_8631@fmrz-telecom.com	80 Abbas El Akkad, Suez	1983-03-03
120	nour_71_4592	123456	customer	Nour Fouad	nour_71_4592@fmrz-telecom.com	50 Cornish Rd, Luxor	1992-02-20
121	layla_72_3804	123456	customer	Layla Hamad	layla_72_3804@fmrz-telecom.com	91 9th Street, Giza	2001-06-10
122	fatma_73_1550	123456	customer	Fatma Khattab	fatma_73_1550@fmrz-telecom.com	44 Zamalek Dr, Cairo	1983-07-11
123	mona_74_1775	123456	customer	Mona Salem	mona_74_1775@fmrz-telecom.com	24 Gameat El Dowal, Luxor	1998-02-14
124	dina_75_5832	123456	customer	Dina Soliman	dina_75_5832@fmrz-telecom.com	52 9th Street, Suez	1991-12-19
125	hala_76_2976	123456	customer	Hala Badawi	hala_76_2976@fmrz-telecom.com	35 Tahrir Sq, Alexandria	1973-11-08
126	salma_77_7765	123456	customer	Salma Soliman	salma_77_7765@fmrz-telecom.com	40 Tahrir Sq, Aswan	1979-03-27
127	nour_78_9767	123456	customer	Nour Ezzat	nour_78_9767@fmrz-telecom.com	81 El-Nasr St, Alexandria	1986-12-09
128	sameh_79_2950	123456	customer	Sameh Soliman	sameh_79_2950@fmrz-telecom.com	82 9th Street, Luxor	1992-11-23
129	fatma_80_4277	123456	customer	Fatma Mansour	fatma_80_4277@fmrz-telecom.com	89 Cornish Rd, Alexandria	1971-12-19
130	khaled_81_2897	123456	customer	Khaled Said	khaled_81_2897@fmrz-telecom.com	63 Gameat El Dowal, Mansoura	2008-04-22
131	amir_82_2007	123456	customer	Amir Moussa	amir_82_2007@fmrz-telecom.com	29 Zamalek Dr, Hurghada	1983-08-23
132	sara_83_1265	123456	customer	Sara Fouad	sara_83_1265@fmrz-telecom.com	51 Cornish Rd, Giza	1988-08-13
133	omar_84_8080	123456	customer	Omar Mansour	omar_84_8080@fmrz-telecom.com	57 Cornish Rd, Hurghada	1997-11-10
134	mohamed_85_9426	123456	customer	Mohamed Said	mohamed_85_9426@fmrz-telecom.com	98 Gameat El Dowal, Mansoura	1992-09-16
135	sameh_86_2604	123456	customer	Sameh Hamad	sameh_86_2604@fmrz-telecom.com	59 Maadi St, Giza	2004-03-10
136	layla_87_8647	123456	customer	Layla Ezzat	layla_87_8647@fmrz-telecom.com	91 Abbas El Akkad, Luxor	1987-07-19
137	ibrahim_88_9578	123456	customer	Ibrahim Badawi	ibrahim_88_9578@fmrz-telecom.com	96 9th Street, Mansoura	1978-02-28
138	mohamed_89_1171	123456	customer	Mohamed Wahba	mohamed_89_1171@fmrz-telecom.com	54 El-Nasr St, Alexandria	1991-07-28
139	layla_90_1644	123456	customer	Layla Salem	layla_90_1644@fmrz-telecom.com	71 Maadi St, Hurghada	1999-11-19
140	ziad_91_2690	123456	customer	Ziad Ezzat	ziad_91_2690@fmrz-telecom.com	26 9th Street, Alexandria	1993-06-17
141	amir_92_4580	123456	customer	Amir Fouad	amir_92_4580@fmrz-telecom.com	61 El-Nasr St, Mansoura	1972-10-21
142	hala_93_4119	123456	customer	Hala Wahba	hala_93_4119@fmrz-telecom.com	10 Cornish Rd, Giza	1987-02-02
143	sara_94_8093	123456	customer	Sara Said	sara_94_8093@fmrz-telecom.com	41 Cornish Rd, Mansoura	1975-06-11
144	layla_95_3389	123456	customer	Layla Wahba	layla_95_3389@fmrz-telecom.com	55 Cornish Rd, Mansoura	2011-01-06
145	ahmed_96_5481	123456	customer	Ahmed Khattab	ahmed_96_5481@fmrz-telecom.com	52 Maadi St, Hurghada	2008-04-25
146	mohamed_97_1987	123456	customer	Mohamed Hamad	mohamed_97_1987@fmrz-telecom.com	30 Makram Ebeid, Giza	1973-03-16
147	mohamed_98_8694	123456	customer	Mohamed Zaki	mohamed_98_8694@fmrz-telecom.com	74 El-Nasr St, Suez	1974-08-04
148	sara_99_1155	123456	customer	Sara Hassan	sara_99_1155@fmrz-telecom.com	81 Abbas El Akkad, Suez	1997-04-29
149	hassan_100_2472	123456	customer	Hassan Salem	hassan_100_2472@fmrz-telecom.com	81 Makram Ebeid, Luxor	1986-12-15
150	ibrahim_101_8140	123456	customer	Ibrahim Fouad	ibrahim_101_8140@fmrz-telecom.com	94 Makram Ebeid, Hurghada	1991-01-06
151	mohamed_102_4463	123456	customer	Mohamed Salem	mohamed_102_4463@fmrz-telecom.com	33 Cornish Rd, Suez	1973-01-15
152	layla_103_7870	123456	customer	Layla Hamad	layla_103_7870@fmrz-telecom.com	71 Zamalek Dr, Suez	1971-09-08
153	mariam_104_5953	123456	customer	Mariam Mansour	mariam_104_5953@fmrz-telecom.com	23 Gameat El Dowal, Luxor	1970-04-05
154	nour_105_2416	123456	customer	Nour Khattab	nour_105_2416@fmrz-telecom.com	10 Maadi St, Mansoura	2004-03-26
155	tarek_106_9854	123456	customer	Tarek Mansour	tarek_106_9854@fmrz-telecom.com	40 Cornish Rd, Mansoura	1988-10-11
156	amir_107_7835	123456	customer	Amir Soliman	amir_107_7835@fmrz-telecom.com	74 Abbas El Akkad, Mansoura	1985-07-04
157	khaled_108_7898	123456	customer	Khaled Wahba	khaled_108_7898@fmrz-telecom.com	28 Cornish Rd, Mansoura	2006-08-04
158	nour_109_1301	123456	customer	Nour Soliman	nour_109_1301@fmrz-telecom.com	19 Tahrir Sq, Cairo	1996-07-31
159	ahmed_110_3678	123456	customer	Ahmed Said	ahmed_110_3678@fmrz-telecom.com	51 El-Nasr St, Aswan	1980-05-13
160	mona_111_8967	123456	customer	Mona Mansour	mona_111_8967@fmrz-telecom.com	20 Cornish Rd, Suez	2001-12-25
161	youssef_112_3279	123456	customer	Youssef Ezzat	youssef_112_3279@fmrz-telecom.com	91 Cornish Rd, Suez	1993-09-13
162	mona_113_7915	123456	customer	Mona Fouad	mona_113_7915@fmrz-telecom.com	45 Zamalek Dr, Aswan	2004-03-20
163	fatma_114_4522	123456	customer	Fatma Mansour	fatma_114_4522@fmrz-telecom.com	34 9th Street, Mansoura	1991-01-14
164	salma_115_3081	123456	customer	Salma Soliman	salma_115_3081@fmrz-telecom.com	58 Zamalek Dr, Alexandria	1979-12-31
165	mona_116_6306	123456	customer	Mona Wahba	mona_116_6306@fmrz-telecom.com	93 Gameat El Dowal, Suez	2006-08-13
166	sara_117_4054	123456	customer	Sara Fouad	sara_117_4054@fmrz-telecom.com	75 9th Street, Aswan	1988-08-10
167	amir_118_6453	123456	customer	Amir Salem	amir_118_6453@fmrz-telecom.com	67 Makram Ebeid, Cairo	1991-01-14
168	nour_119_9616	123456	customer	Nour Said	nour_119_9616@fmrz-telecom.com	49 Gameat El Dowal, Mansoura	1988-05-21
169	sameh_120_7479	123456	customer	Sameh Moussa	sameh_120_7479@fmrz-telecom.com	84 Tahrir Sq, Hurghada	1970-10-16
170	mona_121_4784	123456	customer	Mona Moussa	mona_121_4784@fmrz-telecom.com	93 Zamalek Dr, Mansoura	2007-11-08
171	omar_122_3388	123456	customer	Omar Soliman	omar_122_3388@fmrz-telecom.com	69 Tahrir Sq, Aswan	1999-06-20
172	youssef_123_6807	123456	customer	Youssef Mansour	youssef_123_6807@fmrz-telecom.com	43 Makram Ebeid, Suez	1976-04-26
173	ziad_124_2642	123456	customer	Ziad Hassan	ziad_124_2642@fmrz-telecom.com	13 Zamalek Dr, Cairo	2008-01-29
174	dina_125_2842	123456	customer	Dina Wahba	dina_125_2842@fmrz-telecom.com	61 Makram Ebeid, Alexandria	1996-08-18
175	hassan_126_9755	123456	customer	Hassan Khattab	hassan_126_9755@fmrz-telecom.com	50 9th Street, Luxor	2002-12-28
176	fatma_127_9045	123456	customer	Fatma Salem	fatma_127_9045@fmrz-telecom.com	81 El-Nasr St, Luxor	1974-10-19
177	mohamed_128_1487	123456	customer	Mohamed Zaki	mohamed_128_1487@fmrz-telecom.com	94 Makram Ebeid, Luxor	1989-10-21
178	mariam_129_1852	123456	customer	Mariam Soliman	mariam_129_1852@fmrz-telecom.com	37 Zamalek Dr, Suez	2004-08-20
179	salma_130_5259	123456	customer	Salma Ezzat	salma_130_5259@fmrz-telecom.com	26 9th Street, Giza	2006-10-03
180	mariam_131_7163	123456	customer	Mariam Said	mariam_131_7163@fmrz-telecom.com	54 Maadi St, Cairo	2005-04-21
181	mohamed_132_9495	123456	customer	Mohamed Wahba	mohamed_132_9495@fmrz-telecom.com	97 El-Nasr St, Mansoura	1988-10-22
182	tarek_133_1780	123456	customer	Tarek Moussa	tarek_133_1780@fmrz-telecom.com	85 Zamalek Dr, Hurghada	1973-01-05
183	dina_134_8006	123456	customer	Dina Fouad	dina_134_8006@fmrz-telecom.com	34 Zamalek Dr, Suez	1994-10-20
184	omar_135_8315	123456	customer	Omar Hamad	omar_135_8315@fmrz-telecom.com	44 Tahrir Sq, Mansoura	2007-06-21
185	khaled_136_1124	123456	customer	Khaled Zaki	khaled_136_1124@fmrz-telecom.com	77 Maadi St, Luxor	1973-06-02
186	dina_137_8574	123456	customer	Dina Said	dina_137_8574@fmrz-telecom.com	70 Cornish Rd, Mansoura	1998-03-04
187	mohamed_138_7743	123456	customer	Mohamed Nasr	mohamed_138_7743@fmrz-telecom.com	22 Zamalek Dr, Aswan	2003-02-09
188	sameh_139_5888	123456	customer	Sameh Khattab	sameh_139_5888@fmrz-telecom.com	59 Cornish Rd, Suez	2007-10-09
189	youssef_140_4328	123456	customer	Youssef Ezzat	youssef_140_4328@fmrz-telecom.com	74 Makram Ebeid, Suez	1998-12-14
190	nour_141_1442	123456	customer	Nour Moussa	nour_141_1442@fmrz-telecom.com	14 9th Street, Suez	2003-11-30
191	layla_142_1029	123456	customer	Layla Zaki	layla_142_1029@fmrz-telecom.com	94 9th Street, Alexandria	1994-09-30
192	khaled_143_8884	123456	customer	Khaled Salem	khaled_143_8884@fmrz-telecom.com	79 Zamalek Dr, Cairo	1990-05-30
193	nour_144_4948	123456	customer	Nour Moussa	nour_144_4948@fmrz-telecom.com	17 Tahrir Sq, Mansoura	1997-07-19
194	omar_145_1130	123456	customer	Omar Hassan	omar_145_1130@fmrz-telecom.com	52 Zamalek Dr, Giza	1981-01-22
195	ziad_146_3232	123456	customer	Ziad Ezzat	ziad_146_3232@fmrz-telecom.com	43 9th Street, Hurghada	2000-12-11
196	fatma_147_9993	123456	customer	Fatma Badawi	fatma_147_9993@fmrz-telecom.com	83 Makram Ebeid, Alexandria	1977-02-09
197	sara_148_4702	123456	customer	Sara Nasr	sara_148_4702@fmrz-telecom.com	27 El-Nasr St, Hurghada	2010-05-23
198	amir_149_4518	123456	customer	Amir Hassan	amir_149_4518@fmrz-telecom.com	76 El-Nasr St, Cairo	1984-08-02
199	hassan_150_6297	123456	customer	Hassan Hamad	hassan_150_6297@fmrz-telecom.com	89 Gameat El Dowal, Suez	2002-02-24
\.


--
-- Data for Name: v_msisdn; Type: TABLE DATA; Schema: public; Owner: zkhattab
--

COPY public.v_msisdn (msisdn) FROM stdin;
\.


--
-- Name: bill_id_seq; Type: SEQUENCE SET; Schema: public; Owner: zkhattab
--

SELECT pg_catalog.setval('public.bill_id_seq', 404, true);


--
-- Name: cdr_id_seq; Type: SEQUENCE SET; Schema: public; Owner: zkhattab
--

SELECT pg_catalog.setval('public.cdr_id_seq', 449, true);


--
-- Name: contract_addon_id_seq; Type: SEQUENCE SET; Schema: public; Owner: zkhattab
--

SELECT pg_catalog.setval('public.contract_addon_id_seq', 1, false);


--
-- Name: contract_id_seq; Type: SEQUENCE SET; Schema: public; Owner: zkhattab
--

SELECT pg_catalog.setval('public.contract_id_seq', 199, true);


--
-- Name: file_id_seq; Type: SEQUENCE SET; Schema: public; Owner: zkhattab
--

SELECT pg_catalog.setval('public.file_id_seq', 6, true);


--
-- Name: invoice_id_seq; Type: SEQUENCE SET; Schema: public; Owner: zkhattab
--

SELECT pg_catalog.setval('public.invoice_id_seq', 62, true);


--
-- Name: msisdn_pool_id_seq; Type: SEQUENCE SET; Schema: public; Owner: zkhattab
--

SELECT pg_catalog.setval('public.msisdn_pool_id_seq', 249, true);


--
-- Name: rateplan_id_seq; Type: SEQUENCE SET; Schema: public; Owner: zkhattab
--

SELECT pg_catalog.setval('public.rateplan_id_seq', 3, true);


--
-- Name: service_package_id_seq; Type: SEQUENCE SET; Schema: public; Owner: zkhattab
--

SELECT pg_catalog.setval('public.service_package_id_seq', 7, true);


--
-- Name: user_account_id_seq; Type: SEQUENCE SET; Schema: public; Owner: zkhattab
--

SELECT pg_catalog.setval('public.user_account_id_seq', 200, true);


--
-- Name: bill bill_contract_id_billing_period_start_key; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.bill
    ADD CONSTRAINT bill_contract_id_billing_period_start_key UNIQUE (contract_id, billing_period_start);


--
-- Name: bill bill_pkey; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.bill
    ADD CONSTRAINT bill_pkey PRIMARY KEY (id);


--
-- Name: cdr cdr_pkey; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.cdr
    ADD CONSTRAINT cdr_pkey PRIMARY KEY (id);


--
-- Name: contract_addon contract_addon_pkey; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.contract_addon
    ADD CONSTRAINT contract_addon_pkey PRIMARY KEY (id);


--
-- Name: contract_consumption contract_consumption_pkey; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.contract_consumption
    ADD CONSTRAINT contract_consumption_pkey PRIMARY KEY (contract_id, service_package_id, rateplan_id, starting_date, ending_date);


--
-- Name: contract contract_pkey; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.contract
    ADD CONSTRAINT contract_pkey PRIMARY KEY (id);


--
-- Name: file file_pkey; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.file
    ADD CONSTRAINT file_pkey PRIMARY KEY (id);


--
-- Name: invoice invoice_bill_id_key; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_bill_id_key UNIQUE (bill_id);


--
-- Name: invoice invoice_pkey; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_pkey PRIMARY KEY (id);


--
-- Name: msisdn_pool msisdn_pool_msisdn_key; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.msisdn_pool
    ADD CONSTRAINT msisdn_pool_msisdn_key UNIQUE (msisdn);


--
-- Name: msisdn_pool msisdn_pool_pkey; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.msisdn_pool
    ADD CONSTRAINT msisdn_pool_pkey PRIMARY KEY (id);


--
-- Name: rateplan rateplan_pkey; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.rateplan
    ADD CONSTRAINT rateplan_pkey PRIMARY KEY (id);


--
-- Name: rateplan_service_package rateplan_service_package_pkey; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.rateplan_service_package
    ADD CONSTRAINT rateplan_service_package_pkey PRIMARY KEY (rateplan_id, service_package_id);


--
-- Name: ror_contract ror_contract_pkey; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.ror_contract
    ADD CONSTRAINT ror_contract_pkey PRIMARY KEY (contract_id, rateplan_id, starting_date);


--
-- Name: service_package service_package_pkey; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.service_package
    ADD CONSTRAINT service_package_pkey PRIMARY KEY (id);


--
-- Name: user_account user_account_email_key; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.user_account
    ADD CONSTRAINT user_account_email_key UNIQUE (email);


--
-- Name: user_account user_account_pkey; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.user_account
    ADD CONSTRAINT user_account_pkey PRIMARY KEY (id);


--
-- Name: user_account user_account_username_key; Type: CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.user_account
    ADD CONSTRAINT user_account_username_key UNIQUE (username);


--
-- Name: contract_msisdn_active_idx; Type: INDEX; Schema: public; Owner: zkhattab
--

CREATE UNIQUE INDEX contract_msisdn_active_idx ON public.contract USING btree (msisdn) WHERE (status <> 'terminated'::public.contract_status);


--
-- Name: idx_addon_active; Type: INDEX; Schema: public; Owner: zkhattab
--

CREATE INDEX idx_addon_active ON public.contract_addon USING btree (contract_id, is_active);


--
-- Name: idx_addon_contract; Type: INDEX; Schema: public; Owner: zkhattab
--

CREATE INDEX idx_addon_contract ON public.contract_addon USING btree (contract_id);


--
-- Name: idx_bill_billing_date; Type: INDEX; Schema: public; Owner: zkhattab
--

CREATE INDEX idx_bill_billing_date ON public.bill USING btree (billing_date);


--
-- Name: idx_bill_contract; Type: INDEX; Schema: public; Owner: zkhattab
--

CREATE INDEX idx_bill_contract ON public.bill USING btree (contract_id);


--
-- Name: idx_cdr_dial_a; Type: INDEX; Schema: public; Owner: zkhattab
--

CREATE INDEX idx_cdr_dial_a ON public.cdr USING btree (dial_a);


--
-- Name: idx_cdr_file_id; Type: INDEX; Schema: public; Owner: zkhattab
--

CREATE INDEX idx_cdr_file_id ON public.cdr USING btree (file_id);


--
-- Name: idx_cdr_rated_flag; Type: INDEX; Schema: public; Owner: zkhattab
--

CREATE INDEX idx_cdr_rated_flag ON public.cdr USING btree (rated_flag);


--
-- Name: idx_contract_user_account; Type: INDEX; Schema: public; Owner: zkhattab
--

CREATE INDEX idx_contract_user_account ON public.contract USING btree (user_account_id);


--
-- Name: idx_invoice_bill; Type: INDEX; Schema: public; Owner: zkhattab
--

CREATE INDEX idx_invoice_bill ON public.invoice USING btree (bill_id);


--
-- Name: cdr trg_auto_initialize_consumption; Type: TRIGGER; Schema: public; Owner: zkhattab
--

CREATE TRIGGER trg_auto_initialize_consumption BEFORE INSERT ON public.cdr FOR EACH ROW EXECUTE FUNCTION public.auto_initialize_consumption();


--
-- Name: cdr trg_auto_rate_cdr; Type: TRIGGER; Schema: public; Owner: zkhattab
--

CREATE TRIGGER trg_auto_rate_cdr AFTER INSERT ON public.cdr FOR EACH ROW EXECUTE FUNCTION public.auto_rate_cdr();


--
-- Name: bill trg_bill_inserted; Type: TRIGGER; Schema: public; Owner: zkhattab
--

CREATE TRIGGER trg_bill_inserted AFTER INSERT ON public.bill FOR EACH ROW EXECUTE FUNCTION public.notify_bill_generation();


--
-- Name: bill trg_bill_payment; Type: TRIGGER; Schema: public; Owner: zkhattab
--

CREATE TRIGGER trg_bill_payment AFTER UPDATE ON public.bill FOR EACH ROW EXECUTE FUNCTION public.trg_restore_credit_on_payment();


--
-- Name: cdr trg_cdr_validate_contract; Type: TRIGGER; Schema: public; Owner: zkhattab
--

CREATE TRIGGER trg_cdr_validate_contract BEFORE INSERT ON public.cdr FOR EACH ROW EXECUTE FUNCTION public.validate_cdr_contract();


--
-- Name: bill bill_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.bill
    ADD CONSTRAINT bill_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contract(id);


--
-- Name: cdr cdr_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.cdr
    ADD CONSTRAINT cdr_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.file(id);


--
-- Name: cdr cdr_service_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.cdr
    ADD CONSTRAINT cdr_service_id_fkey FOREIGN KEY (service_id) REFERENCES public.service_package(id);


--
-- Name: contract_addon contract_addon_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.contract_addon
    ADD CONSTRAINT contract_addon_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contract(id);


--
-- Name: contract_addon contract_addon_service_package_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.contract_addon
    ADD CONSTRAINT contract_addon_service_package_id_fkey FOREIGN KEY (service_package_id) REFERENCES public.service_package(id);


--
-- Name: contract_consumption contract_consumption_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.contract_consumption
    ADD CONSTRAINT contract_consumption_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bill(id);


--
-- Name: contract_consumption contract_consumption_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.contract_consumption
    ADD CONSTRAINT contract_consumption_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contract(id);


--
-- Name: contract_consumption contract_consumption_rateplan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.contract_consumption
    ADD CONSTRAINT contract_consumption_rateplan_id_fkey FOREIGN KEY (rateplan_id) REFERENCES public.rateplan(id);


--
-- Name: contract_consumption contract_consumption_service_package_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.contract_consumption
    ADD CONSTRAINT contract_consumption_service_package_id_fkey FOREIGN KEY (service_package_id) REFERENCES public.service_package(id);


--
-- Name: contract contract_rateplan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.contract
    ADD CONSTRAINT contract_rateplan_id_fkey FOREIGN KEY (rateplan_id) REFERENCES public.rateplan(id);


--
-- Name: contract contract_user_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.contract
    ADD CONSTRAINT contract_user_account_id_fkey FOREIGN KEY (user_account_id) REFERENCES public.user_account(id);


--
-- Name: invoice invoice_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bill(id);


--
-- Name: rateplan_service_package rateplan_service_package_rateplan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.rateplan_service_package
    ADD CONSTRAINT rateplan_service_package_rateplan_id_fkey FOREIGN KEY (rateplan_id) REFERENCES public.rateplan(id);


--
-- Name: rateplan_service_package rateplan_service_package_service_package_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.rateplan_service_package
    ADD CONSTRAINT rateplan_service_package_service_package_id_fkey FOREIGN KEY (service_package_id) REFERENCES public.service_package(id);


--
-- Name: ror_contract ror_contract_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.ror_contract
    ADD CONSTRAINT ror_contract_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contract(id);


--
-- Name: ror_contract ror_contract_rateplan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: zkhattab
--

ALTER TABLE ONLY public.ror_contract
    ADD CONSTRAINT ror_contract_rateplan_id_fkey FOREIGN KEY (rateplan_id) REFERENCES public.rateplan(id);


--
-- PostgreSQL database dump complete
--

\unrestrict nCQtnlw3KbRt5p5DQAOzkHaVCTWYZBzfPnj8E1eWGfoqfMgfbij0BJfuaJ2c1qC

