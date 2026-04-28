--
-- PostgreSQL database dump
--

\restrict hDrA9KLAeL6NJDDhSN5hnKMn9gdlF9LDTfyzMztteaQ5cYCV8m0C0Flap7AgpWo

-- Dumped from database version 17.8 (130b160)
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
-- Name: bill_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.bill_status AS ENUM (
    'draft',
    'issued',
    'paid',
    'overdue',
    'cancelled'
);


--
-- Name: contract_recurring_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.contract_recurring_status AS ENUM (
    'Active',
    'Suspended',
    'Cancelled',
    'Completed'
);


--
-- Name: contract_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.contract_status AS ENUM (
    'active',
    'suspended',
    'terminated'
);


--
-- Name: contract_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.contract_status_enum AS ENUM (
    'Active',
    'Suspended',
    'Terminated',
    'Credit_Blocked'
);


--
-- Name: cot_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.cot_status_enum AS ENUM (
    'Active',
    'Expired',
    'Cancelled'
);


--
-- Name: cr_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.cr_status_enum AS ENUM (
    'Active',
    'Suspended',
    'Cancelled',
    'Completed'
);


--
-- Name: customer_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.customer_type AS ENUM (
    'Individual',
    'Corporate'
);


--
-- Name: one_time_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.one_time_status AS ENUM (
    'Active',
    'Expired',
    'Cancelled'
);


--
-- Name: rateplan_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.rateplan_status AS ENUM (
    'Active',
    'Inactive'
);


--
-- Name: rateplan_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.rateplan_status_enum AS ENUM (
    'Active',
    'Inactive'
);


--
-- Name: service_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.service_type AS ENUM (
    'voice',
    'data',
    'sms',
    'free_units'
);


--
-- Name: service_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.service_type_enum AS ENUM (
    'Voice',
    'Data',
    'SMS',
    'Roaming',
    'VAS',
    'Other'
);


--
-- Name: service_uom; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.service_uom AS ENUM (
    'Minute',
    'MB',
    'GB',
    'SMS',
    'Event'
);


--
-- Name: service_uom_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.service_uom_enum AS ENUM (
    'Minute',
    'MB',
    'GB',
    'SMS',
    'Event'
);


--
-- Name: user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_role AS ENUM (
    'admin',
    'customer'
);


--
-- Name: add_new_service_package(character varying, public.service_type, numeric, integer, numeric, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_new_service_package(p_name character varying, p_type public.service_type, p_amount numeric, p_priority integer, p_price numeric, p_description text DEFAULT NULL::text, p_is_roaming boolean DEFAULT false) RETURNS integer
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


--
-- Name: auto_initialize_consumption(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: auto_rate_cdr(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: cancel_addon(integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: change_contract_rateplan(integer, integer); Type: FUNCTION; Schema: public; Owner: -
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
$$;


--
-- Name: change_contract_status(integer, public.contract_status); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: create_admin(character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: create_admin(character varying, character varying, character varying, character varying, text, date); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: create_contract(integer, integer, character varying, double precision); Type: FUNCTION; Schema: public; Owner: -
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
        starting_date, ending_date, consumed, is_billed
    )
    SELECT v_contract_id, rsp.service_package_id, p_rateplan_id,
           v_period_start, v_period_end, 0, FALSE
    FROM rateplan_service_package rsp
    WHERE rsp.rateplan_id = p_rateplan_id
    ON CONFLICT DO NOTHING;

    RETURN v_contract_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'create_contract failed: %', SQLERRM;
END;
$$;


--
-- Name: create_customer(character varying, character varying, character varying, character varying, text, date); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: create_file_record(text); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: create_rateplan_with_packages(character varying, numeric, numeric, numeric, numeric, integer[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_rateplan_with_packages(p_name character varying, p_ror_voice numeric, p_ror_data numeric, p_ror_sms numeric, p_price numeric, p_service_package_ids integer[]) RETURNS integer
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


--
-- Name: create_service_package(character varying, public.service_type, numeric, integer, numeric, text, boolean); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: delete_service_package(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_service_package(p_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: expire_addons(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: generate_all_bills(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_all_bills(p_period_start date) RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: generate_bill(integer, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_bill(p_contract_id integer, p_billing_period_start date) RETURNS void
    LANGUAGE plpgsql
    AS $$
       DECLARE 
               v_billing_period_end DATE;
               v_recurring_fees NUMERIC(12,2);
               v_one_time_fees NUMERIC(12,2);
               -- FIX 1: Explicitly initialize to 0 to prevent NULL + 5 = NULL errors
               v_voice_usage INTEGER := 0;
               v_data_usage INTEGER := 0;
               v_sms_usage INTEGER := 0;
               v_ROR_charge NUMERIC(12,2);
               v_taxes NUMERIC(12,2);
               v_total_amount NUMERIC(12,2);
               v_rateplan_id INTEGER;
               v_bill_id INTEGER;
BEGIN
    -- Standardize the billing month end (e.g., April 1 to April 30)
    v_billing_period_end := (DATE_TRUNC('month', p_billing_period_start) + INTERVAL '1 month - 1 day')::DATE;
    
    -- Retrieve the subscriber's Rate Plan details
    SELECT rateplan_id INTO v_rateplan_id FROM contract WHERE id = p_contract_id;
    SELECT price INTO v_recurring_fees FROM rateplan WHERE id = v_rateplan_id;

    -- FIX 2: BUNDLE USAGE
    -- This pulls usage from "Voice Packs" or "Data Packs" (Add-ons).
    -- Solves: Displaying usage for subscribers who have pre-paid packages.
    SELECT COALESCE(SUM(CASE WHEN sp.type = 'voice' THEN cc.consumed ELSE 0 END), 0),
           COALESCE(SUM(CASE WHEN sp.type = 'data' THEN cc.consumed ELSE 0 END), 0),
           COALESCE(SUM(CASE WHEN sp.type = 'sms' THEN cc.consumed ELSE 0 END), 0)
    INTO v_voice_usage, v_data_usage, v_sms_usage
    FROM contract_consumption cc
    JOIN service_package sp ON sp.id = cc.service_package_id
    WHERE cc.contract_id = p_contract_id 
      AND cc.starting_date = p_billing_period_start 
      AND cc.is_billed = FALSE;

    -- FIX 3: PAY-AS-YOU-GO (ROR) INTEGRATION
    -- This is the critical fix. It adds "Out-of-Bundle" usage to the totals above.
    -- Solves: The "Too many zeros" issue in the Usage (V/D/S) dashboard column.
    SELECT 
        v_voice_usage + COALESCE(rc.voice, 0), -- Adds ROR minutes to Bundle minutes
        v_data_usage + COALESCE(rc.data, 0),   -- Adds ROR MBs to Bundle MBs
        v_sms_usage + COALESCE(rc.sms, 0),     -- Adds ROR SMS to Bundle SMS
        -- Correctly calculates the financial cost based on the specific Rate Plan ROR rates
        COALESCE((rc.data * rp.ror_data) + (rc.voice * rp.ror_voice) + (rc.sms * rp.ror_sms), 0)
    INTO v_voice_usage, v_data_usage, v_sms_usage, v_ROR_charge
    FROM ror_contract rc
    JOIN rateplan rp ON rp.id = rc.rateplan_id
    WHERE rc.contract_id = p_contract_id AND rc.bill_id IS NULL;

    -- Financial Totals (Includes fixed 15% tax on recurring + usage)
    v_one_time_fees := 0.69; -- Compliance/Admin fee
    v_taxes := 0.15 * (v_recurring_fees + v_ROR_charge);
    v_total_amount := v_recurring_fees + v_one_time_fees + v_ROR_charge + v_taxes;

    -- Final insertion into the Bill table for the Admin UI to read
    INSERT INTO bill (
        contract_id, billing_period_start, billing_period_end, billing_date, 
        recurring_fees, one_time_fees, voice_usage, data_usage, sms_usage, 
        ROR_charge, taxes, total_amount, status, is_paid
    )
    VALUES (
        p_contract_id, p_billing_period_start, v_billing_period_end, CURRENT_DATE, 
        v_recurring_fees, v_one_time_fees, v_voice_usage, v_data_usage, v_sms_usage, 
        v_ROR_charge, v_taxes, v_total_amount, 'issued', FALSE
    )
    RETURNING id INTO v_bill_id;

    -- FIX 4: STATE MANAGEMENT
    -- Solves: Double-billing. Marks all processed records as "Billed" so they 
    -- aren't added to the next month's invoice.
    UPDATE contract_consumption SET is_billed = TRUE, bill_id = v_bill_id 
    WHERE contract_id = p_contract_id AND is_billed = FALSE;
    
    UPDATE ror_contract SET bill_id = v_bill_id 
    WHERE contract_id = p_contract_id AND bill_id IS NULL;
END;
$$;


--
-- Name: generate_invoice(integer, text); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_admin_stats(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_all_contracts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_all_contracts() RETURNS TABLE(id integer, msisdn character varying, status public.contract_status, available_credit numeric, customer_name character varying, rateplan_name character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
        SELECT
            c.id,
            c.msisdn,
            c.status,
            c.available_credit,
            u.name  AS customer_name,
            r.name  AS rateplan_name
        FROM contract c
                 JOIN user_account u ON c.user_account_id = u.id
                 LEFT JOIN rateplan r ON c.rateplan_id = r.id
        ORDER BY c.id DESC;
END;
$$;


--
-- Name: get_all_customers(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_all_customers() RETURNS TABLE(id integer, username character varying, name character varying, email character varying, role public.user_role, address text, birthdate date, msisdn character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
        SELECT
            ua.id, ua.username, ua.name, ua.email, ua.role, ua.address, ua.birthdate,
            c.msisdn -- This was missing!
        FROM user_account ua
        LEFT JOIN contract c ON ua.id = c.user_account_id
        WHERE ua.role = 'customer'
        ORDER BY ua.id DESC;
END;
$$;


--
-- Name: get_all_rateplans(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_all_service_packages(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_available_msisdns(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_bill(integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_bill_usage_breakdown(integer); Type: FUNCTION; Schema: public; Owner: -
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
        'Domestic Overage - Voice'::TEXT AS category_label,
        NULL::INTEGER AS quota,
        NULL::INTEGER AS consumed,
        rp.ror_voice AS unit_rate,
        ROUND(rc.voice::NUMERIC, 2) AS line_total,
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
        'Domestic Overage - Data'::TEXT AS category_label,
        NULL::INTEGER, NULL::INTEGER, rp.ror_data,
        ROUND(rc.data::NUMERIC, 2), FALSE, FALSE,
        'Overage data beyond bundle allowance'::TEXT
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.contract_id = v_contract_id AND rc.bill_id = p_bill_id AND rc.data > 0
    
    UNION ALL
    SELECT 
        'sms'::TEXT AS service_type,
        'Domestic Overage - SMS'::TEXT AS category_label,
        NULL::INTEGER, NULL::INTEGER, rp.ror_sms,
        ROUND(rc.sms::NUMERIC, 2), FALSE, FALSE,
        'Overage SMS beyond bundle allowance'::TEXT
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.contract_id = v_contract_id AND rc.bill_id = p_bill_id AND rc.sms > 0
    
    UNION ALL
    
    -- 3. Roaming charges (from ror_contract roaming columns)
    SELECT 
        'roaming_voice'::TEXT AS service_type,
        'Roaming - Voice'::TEXT AS category_label,
        NULL::INTEGER, NULL::INTEGER, rp.ror_voice,
        ROUND(rc.roaming_voice::NUMERIC, 2), TRUE, FALSE,
        'Voice usage while roaming'::TEXT
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.contract_id = v_contract_id AND rc.bill_id = p_bill_id AND rc.roaming_voice > 0
    
    UNION ALL
    SELECT 
        'roaming_data'::TEXT AS service_type,
        'Roaming - Data'::TEXT AS category_label,
        NULL::INTEGER, NULL::INTEGER, rp.ror_data,
        ROUND(rc.roaming_data::NUMERIC, 2), TRUE, FALSE,
        'Data usage while roaming'::TEXT
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.contract_id = v_contract_id AND rc.bill_id = p_bill_id AND rc.roaming_data > 0
    
    UNION ALL
    SELECT 
        'roaming_sms'::TEXT AS service_type,
        'Roaming - SMS'::TEXT AS category_label,
        NULL::INTEGER, NULL::INTEGER, rp.ror_sms,
        ROUND(rc.roaming_sms::NUMERIC, 2), TRUE, FALSE,
        'SMS usage while roaming'::TEXT
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.contract_id = v_contract_id AND rc.bill_id = p_bill_id AND rc.roaming_sms > 0
    
    UNION ALL
    
    -- 4. Promotional discounts (attributed to service packages with promotional names)
    SELECT 
        sp.type::TEXT AS service_type,
        sp.name::TEXT AS category_label,
        cc.quota_limit::INTEGER AS quota,
        cc.consumed::INTEGER AS consumed,
        0::NUMERIC(12,4) AS unit_rate,
        0::NUMERIC(12,2) AS line_total,
        sp.is_roaming,
        TRUE AS is_promotional,
        'Promotional rate applied'::TEXT AS notes
    FROM contract_consumption cc
    JOIN service_package sp ON cc.service_package_id = sp.id
    WHERE cc.bill_id = p_bill_id
      AND cc.is_billed = TRUE
      AND sp.name ~* 'Welcome|Gift|Bonus'
    
    ORDER BY service_type, is_roaming DESC, category_label;
END;
$$;


--
-- Name: get_bills_by_contract(integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_cdr_usage_amount(integer, public.service_type); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_cdrs(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_cdrs(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE(id integer, msisdn character varying, destination character varying, duration integer, "timestamp" timestamp without time zone, type integer, rated boolean)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
        SELECT
            c.id,
            c.dial_a   AS msisdn,
            c.dial_b   AS destination,
            c.duration,
            c.start_time AS timestamp,
            c.service_id AS type,
            c.rated_flag AS rated
        FROM cdr c
        ORDER BY c.start_time DESC
        LIMIT p_limit OFFSET p_offset;
END;
$$;


--
-- Name: get_contract_addons(integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_contract_by_id(integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_contract_consumption(integer, date); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_customer_by_id(integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_dashboard_stats(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_dashboard_stats() RETURNS TABLE(total_customers bigint, total_contracts bigint, active_contracts bigint, total_cdrs bigint, total_revenue numeric, pending_bills bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
        SELECT
            (SELECT COUNT(*) FROM user_account WHERE role = 'customer'),
            (SELECT COUNT(*) FROM contract),
            (SELECT COUNT(*) FROM contract     WHERE status = 'active'),
            (SELECT COUNT(*) FROM cdr),
            (SELECT COALESCE(SUM(total_amount), 0) FROM bill WHERE is_paid = TRUE),
            (SELECT COUNT(*) FROM bill WHERE is_paid = FALSE);
END;
$$;


--
-- Name: get_missing_bills(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_missing_bills() RETURNS TABLE(contract_id integer, msisdn character varying, customer_name character varying, rateplan_name character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_period_start DATE := DATE_TRUNC('month', CURRENT_DATE)::DATE;
BEGIN
    RETURN QUERY
        SELECT
            c.id           AS contract_id,
            c.msisdn,
            u.name         AS customer_name,
            r.name         AS rateplan_name
        FROM contract c
                 JOIN user_account u ON c.user_account_id = u.id
                 LEFT JOIN rateplan r ON c.rateplan_id = r.id
        WHERE c.status = 'active'
          AND NOT EXISTS (
            SELECT 1 FROM bill b
            WHERE b.contract_id = c.id
              AND b.billing_period_start = v_period_start
        )
        ORDER BY c.id;
END;
$$;


--
-- Name: get_rateplan_by_id(integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_rateplan_data(integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_service_package_by_id(integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_user_contracts(integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_user_data(integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_user_invoices(integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: get_user_msisdn_bill(integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: initialize_consumption_period(date); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: insert_cdr(integer, character varying, character varying, timestamp without time zone, integer, integer, character varying, character varying, numeric); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: login(character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: mark_bill_paid(integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: mark_msisdn_taken(character varying); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: notify_bill_generation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_bill_generation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM pg_notify('generate_bill_event', NEW.id::text);
    RETURN NEW;
END;
$$;


--
-- Name: pay_bill(integer, text); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: purchase_addon(integer, integer); Type: FUNCTION; Schema: public; Owner: -
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
        WHERE sp.id = p_service_package_id AND sp.name = 'Welcome Bonus'
    ) AND EXISTS (
        SELECT 1 FROM contract_addon ca
        JOIN service_package sp ON ca.service_package_id = sp.id
        JOIN contract c ON ca.contract_id = c.id
        WHERE c.user_account_id = (SELECT user_account_id FROM contract WHERE id = p_contract_id)
          AND sp.name = 'Welcome Bonus'
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


--
-- Name: rate_cdr(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rate_cdr(p_cdr_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
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

    -- Normalise usage
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
    cc.quota_limit, 
    sp.priority,
    cc.consumed
FROM contract_consumption cc
         JOIN service_package sp ON sp.id = cc.service_package_id
WHERE cc.contract_id   = v_contract.id
  AND cc.starting_date = v_period_start
  AND cc.ending_date   = v_period_end
  AND cc.is_billed     = FALSE
  AND sp.type          = v_service_type
ORDER BY sp.priority ASC
    LOOP
        EXIT WHEN v_remaining <= 0;

        v_available := v_bundle.quota_limit - v_bundle.consumed;

        IF v_available <= 0 THEN
            CONTINUE;
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

    -- Handle overage
    IF v_remaining > 0 AND v_service_type != 'free_units' THEN
SELECT CASE v_service_type
           WHEN 'voice' THEN ror_voice
           WHEN 'data'  THEN ror_data
           WHEN 'sms'   THEN ror_sms
           END INTO v_ror_rate
FROM rateplan
WHERE id = v_contract.rateplan_id;

v_overage_charge := v_remaining * COALESCE(v_ror_rate, 0);

INSERT INTO ror_contract (contract_id, rateplan_id, voice, data, sms)
        VALUES (v_contract.id, v_contract.rateplan_id,
                CASE WHEN v_service_type='voice' THEN v_remaining ELSE 0 END,
                CASE WHEN v_service_type='data'  THEN v_remaining ELSE 0 END,
                CASE WHEN v_service_type='sms'   THEN v_remaining ELSE 0 END)
        ON CONFLICT (contract_id, rateplan_id)
        DO UPDATE SET
            voice = ror_contract.voice + EXCLUDED.voice,
            data  = ror_contract.data  + EXCLUDED.data,
            sms   = ror_contract.sms   + EXCLUDED.sms;
END IF;

UPDATE cdr
SET rated_flag       = TRUE,
    external_charges = v_overage_charge
WHERE id = p_cdr_id;

END;
$$;


--
-- Name: release_msisdn(character varying); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: set_file_parsed(integer); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: trg_restore_credit_on_payment(); Type: FUNCTION; Schema: public; Owner: -
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


--
-- Name: validate_cdr_contract(); Type: FUNCTION; Schema: public; Owner: -
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


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: bill; Type: TABLE; Schema: public; Owner: -
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
    taxes numeric(12,2) DEFAULT 0 NOT NULL,
    total_amount numeric(12,2) DEFAULT 0 NOT NULL,
    status public.bill_status DEFAULT 'draft'::public.bill_status NOT NULL,
    is_paid boolean DEFAULT false NOT NULL
);


--
-- Name: bill_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bill_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bill_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bill_id_seq OWNED BY public.bill.id;


--
-- Name: cdr; Type: TABLE; Schema: public; Owner: -
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
    rated_flag boolean DEFAULT false NOT NULL
);


--
-- Name: cdr_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cdr_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cdr_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cdr_id_seq OWNED BY public.cdr.id;


--
-- Name: contract; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: contract_addon; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: contract_addon_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contract_addon_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contract_addon_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contract_addon_id_seq OWNED BY public.contract_addon.id;


--
-- Name: contract_consumption; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contract_consumption (
    contract_id integer NOT NULL,
    service_package_id integer NOT NULL,
    rateplan_id integer NOT NULL,
    starting_date date NOT NULL,
    ending_date date NOT NULL,
    consumed integer DEFAULT 0 NOT NULL,
    is_billed boolean DEFAULT false NOT NULL,
    bill_id integer,
    quota_limit numeric(12,4) DEFAULT 0 NOT NULL
);


--
-- Name: contract_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contract_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contract_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contract_id_seq OWNED BY public.contract.id;


--
-- Name: file; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.file (
    id integer NOT NULL,
    parsed_flag boolean DEFAULT false NOT NULL,
    file_path text NOT NULL
);


--
-- Name: file_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.file_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: file_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.file_id_seq OWNED BY public.file.id;


--
-- Name: invoice; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice (
    id integer NOT NULL,
    bill_id integer NOT NULL,
    pdf_path text,
    generation_date timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: invoice_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.invoice_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: invoice_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.invoice_id_seq OWNED BY public.invoice.id;


--
-- Name: msisdn_pool; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.msisdn_pool (
    id integer NOT NULL,
    msisdn character varying(20) NOT NULL,
    is_available boolean DEFAULT true NOT NULL
);


--
-- Name: msisdn_pool_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.msisdn_pool_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: msisdn_pool_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.msisdn_pool_id_seq OWNED BY public.msisdn_pool.id;


--
-- Name: rateplan; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rateplan (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    ror_data numeric(10,2),
    ror_voice numeric(10,2),
    ror_sms numeric(10,2),
    price numeric(10,2)
);


--
-- Name: rateplan_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.rateplan_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rateplan_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.rateplan_id_seq OWNED BY public.rateplan.id;


--
-- Name: rateplan_service_package; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rateplan_service_package (
    rateplan_id integer NOT NULL,
    service_package_id integer NOT NULL
);


--
-- Name: ror_contract; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ror_contract (
    contract_id integer NOT NULL,
    rateplan_id integer NOT NULL,
    data integer,
    voice integer,
    sms integer,
    bill_id integer
);


--
-- Name: service_package; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: service_package_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.service_package_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: service_package_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.service_package_id_seq OWNED BY public.service_package.id;


--
-- Name: user_account; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: user_account_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_account_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_account_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_account_id_seq OWNED BY public.user_account.id;


--
-- Name: v_msisdn; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.v_msisdn (
    msisdn character varying(20)
);


--
-- Name: bill id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill ALTER COLUMN id SET DEFAULT nextval('public.bill_id_seq'::regclass);


--
-- Name: cdr id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cdr ALTER COLUMN id SET DEFAULT nextval('public.cdr_id_seq'::regclass);


--
-- Name: contract id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract ALTER COLUMN id SET DEFAULT nextval('public.contract_id_seq'::regclass);


--
-- Name: contract_addon id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_addon ALTER COLUMN id SET DEFAULT nextval('public.contract_addon_id_seq'::regclass);


--
-- Name: file id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.file ALTER COLUMN id SET DEFAULT nextval('public.file_id_seq'::regclass);


--
-- Name: invoice id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice ALTER COLUMN id SET DEFAULT nextval('public.invoice_id_seq'::regclass);


--
-- Name: msisdn_pool id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.msisdn_pool ALTER COLUMN id SET DEFAULT nextval('public.msisdn_pool_id_seq'::regclass);


--
-- Name: rateplan id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rateplan ALTER COLUMN id SET DEFAULT nextval('public.rateplan_id_seq'::regclass);


--
-- Name: service_package id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_package ALTER COLUMN id SET DEFAULT nextval('public.service_package_id_seq'::regclass);


--
-- Name: user_account id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_account ALTER COLUMN id SET DEFAULT nextval('public.user_account_id_seq'::regclass);


--
-- Data for Name: bill; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.bill (id, contract_id, billing_period_start, billing_period_end, billing_date, recurring_fees, one_time_fees, voice_usage, data_usage, sms_usage, ror_charge, taxes, total_amount, status, is_paid) FROM stdin;
1	1	2026-02-01	2026-02-28	2026-03-01	50.00	0.69	280	0	38	0.00	5.07	55.76	paid	t
2	2	2026-02-01	2026-02-28	2026-03-01	120.00	0.69	580	1900	72	0.00	12.07	132.76	paid	t
3	3	2026-02-01	2026-02-28	2026-03-01	50.00	0.69	150	0	18	0.00	5.07	55.76	paid	t
4	4	2026-02-01	2026-02-28	2026-03-01	120.00	0.69	410	1400	50	0.00	12.07	132.76	paid	t
5	5	2026-02-01	2026-02-28	2026-03-01	50.00	0.69	80	0	10	0.00	5.07	55.76	paid	t
6	6	2026-02-01	2026-02-28	2026-03-01	120.00	0.69	690	2800	95	0.00	12.07	132.76	paid	t
7	7	2026-02-01	2026-02-28	2026-03-01	50.00	0.69	190	0	25	0.00	5.07	55.76	paid	t
8	8	2026-02-01	2026-02-28	2026-03-01	120.00	0.69	350	1200	45	0.00	12.07	132.76	paid	t
9	9	2026-02-01	2026-02-28	2026-03-01	50.00	0.69	120	0	15	0.00	5.07	55.76	paid	t
10	10	2026-02-01	2026-02-28	2026-03-01	120.00	0.69	470	1750	62	0.00	12.07	132.76	paid	t
11	11	2026-02-01	2026-02-28	2026-03-01	50.00	0.69	820	0	175	10.00	6.07	66.76	paid	t
12	12	2026-02-01	2026-02-28	2026-03-01	120.00	0.69	260	800	30	0.00	12.07	132.76	paid	t
13	14	2026-02-01	2026-02-28	2026-03-01	120.00	0.69	390	1050	52	0.00	12.07	132.76	paid	t
14	15	2026-02-01	2026-02-28	2026-03-01	349.00	0.69	750	3500	130	0.00	34.97	384.66	paid	t
15	16	2026-02-01	2026-02-28	2026-03-01	349.00	0.69	880	4200	160	5.00	35.47	390.16	paid	t
16	17	2026-02-01	2026-02-28	2026-03-01	120.00	0.69	310	950	42	0.00	12.07	132.76	paid	t
17	1	2026-03-01	2026-03-31	2026-04-01	50.00	0.69	310	0	42	0.00	5.07	55.76	paid	t
18	2	2026-03-01	2026-03-31	2026-04-01	120.00	0.69	640	2200	80	0.00	12.07	132.76	paid	t
19	3	2026-03-01	2026-03-31	2026-04-01	50.00	0.69	170	0	20	0.00	5.07	55.76	issued	f
20	4	2026-03-01	2026-03-31	2026-04-01	120.00	0.69	450	1600	58	0.00	12.07	132.76	issued	f
21	5	2026-03-01	2026-03-31	2026-04-01	50.00	0.69	90	0	11	0.00	5.07	55.76	issued	f
22	6	2026-03-01	2026-03-31	2026-04-01	120.00	0.69	720	3100	105	0.00	12.07	132.76	issued	f
23	7	2026-03-01	2026-03-31	2026-04-01	50.00	0.69	200	0	28	0.00	5.07	55.76	issued	f
24	8	2026-03-01	2026-03-31	2026-04-01	120.00	0.69	380	1350	50	0.00	12.07	132.76	issued	f
25	9	2026-03-01	2026-03-31	2026-04-01	50.00	0.69	130	0	16	0.00	5.07	55.76	issued	f
26	10	2026-03-01	2026-03-31	2026-04-01	120.00	0.69	500	1900	68	0.00	12.07	132.76	issued	f
27	11	2026-03-01	2026-03-31	2026-04-01	50.00	0.69	900	0	195	14.50	6.52	71.71	issued	f
28	12	2026-03-01	2026-03-31	2026-04-01	120.00	0.69	280	850	35	0.00	12.07	132.76	issued	f
29	14	2026-03-01	2026-03-31	2026-04-01	120.00	0.69	420	1100	55	0.00	12.07	132.76	issued	f
30	15	2026-03-01	2026-03-31	2026-04-01	349.00	0.69	800	3700	140	0.00	34.97	384.66	issued	f
31	16	2026-03-01	2026-03-31	2026-04-01	349.00	0.69	920	4800	170	8.00	35.77	393.46	issued	f
32	17	2026-03-01	2026-03-31	2026-04-01	120.00	0.69	330	980	45	0.00	12.07	132.76	issued	f
33	1	2026-04-01	2026-04-30	2026-04-28	75.00	0.69	350	0	45	0.00	11.25	86.94	issued	f
34	2	2026-04-01	2026-04-30	2026-04-28	350.00	0.69	740	2500	115	0.00	52.50	403.19	issued	f
35	3	2026-04-01	2026-04-30	2026-04-28	75.00	0.69	180	0	22	0.00	11.25	86.94	issued	f
36	4	2026-04-01	2026-04-30	2026-04-28	350.00	0.69	480	1800	65	0.00	52.50	403.19	issued	f
37	5	2026-04-01	2026-04-30	2026-04-28	75.00	0.69	95	0	12	0.00	11.25	86.94	issued	f
38	6	2026-04-01	2026-04-30	2026-04-28	350.00	0.69	750	3200	110	0.00	52.50	403.19	issued	f
39	7	2026-04-01	2026-04-30	2026-04-28	75.00	0.69	210	0	18	0.00	11.25	86.94	issued	f
40	8	2026-04-01	2026-04-30	2026-04-28	350.00	0.69	390	1500	55	0.00	52.50	403.19	issued	f
41	9	2026-04-01	2026-04-30	2026-04-28	75.00	0.69	140	0	8	0.00	11.25	86.94	issued	f
42	10	2026-04-01	2026-04-30	2026-04-28	350.00	0.69	510	2400	75	0.00	52.50	403.19	issued	f
43	11	2026-04-01	2026-04-30	2026-04-28	75.00	0.69	980	0	190	0.00	11.25	86.94	issued	f
44	12	2026-04-01	2026-04-30	2026-04-28	350.00	0.69	290	900	35	0.00	52.50	403.19	issued	f
45	15	2026-04-01	2026-04-30	2026-04-28	950.00	0.69	900	4120	165	0.00	142.50	1093.19	issued	f
46	16	2026-04-01	2026-04-30	2026-04-28	950.00	0.69	950	4920	180	0.40	142.56	1093.65	issued	f
47	17	2026-04-01	2026-04-30	2026-04-28	350.00	0.69	340	1100	48	0.00	52.50	403.19	issued	f
48	14	2026-04-01	2026-04-30	2026-04-28	350.00	0.69	430	1200	60	0.00	52.50	403.19	paid	t
\.


--
-- Data for Name: cdr; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cdr (id, file_id, dial_a, dial_b, start_time, duration, service_id, hplmn, vplmn, external_charges, rated_flag) FROM stdin;
1	1	201000000001	201000000002	2026-04-01 09:15:00	180	1	EGYVO	\N	0.00	t
2	1	201000000001	201000000003	2026-04-01 14:30:00	1	3	EGYVO	\N	0.00	t
3	1	201000000001	201000000005	2026-04-02 08:00:00	300	1	EGYVO	\N	0.00	t
4	1	201000000001	201000000007	2026-04-03 11:20:00	1	3	EGYVO	\N	0.00	t
5	1	201000000001	201000000009	2026-04-04 10:05:00	240	1	EGYVO	\N	0.00	t
6	1	201000000001	201000000002	2026-04-05 16:45:00	1	3	EGYVO	\N	0.00	t
7	1	201000000001	201000000011	2026-04-07 09:30:00	420	1	EGYVO	\N	0.00	t
8	1	201000000001	201000000013	2026-04-08 13:00:00	1	3	EGYVO	\N	0.00	t
9	1	201000000001	201000000015	2026-04-09 17:20:00	150	1	EGYVO	\N	0.00	t
10	1	201000000001	201000000002	2026-04-10 08:45:00	360	1	EGYVO	\N	0.00	t
11	1	201000000001	201000000003	2026-04-12 12:10:00	1	3	EGYVO	\N	0.00	t
12	1	201000000001	201000000017	2026-04-14 15:30:00	210	1	EGYVO	\N	0.00	t
13	1	201000000001	201000000004	2026-04-16 09:00:00	270	1	EGYVO	\N	0.00	t
14	1	201000000001	201000000006	2026-04-18 14:00:00	1	3	EGYVO	\N	0.00	t
15	1	201000000001	201000000008	2026-04-20 10:30:00	330	1	EGYVO	\N	0.00	t
16	1	201000000002	201000000001	2026-04-01 08:30:00	300	1	EGYVO	\N	0.00	t
17	1	201000000002	201000000004	2026-04-01 10:00:00	500	2	EGYVO	\N	0.00	t
18	1	201000000002	201000000006	2026-04-01 12:00:00	1	3	EGYVO	\N	0.00	t
19	1	201000000002	201000000008	2026-04-02 09:15:00	450	1	EGYVO	\N	0.00	t
20	1	201000000002	201000000010	2026-04-02 14:30:00	750	2	EGYVO	\N	0.00	t
21	1	201000000002	201000000012	2026-04-03 08:00:00	1	3	EGYVO	\N	0.00	t
22	1	201000000002	201000000001	2026-04-04 11:45:00	600	1	EGYVO	\N	0.00	t
23	1	201000000002	201000000014	2026-04-05 15:00:00	1000	2	EGYVO	\N	0.00	t
24	1	201000000002	201000000016	2026-04-06 09:30:00	1	3	EGYVO	\N	0.00	t
25	1	201000000002	201000000018	2026-04-07 13:20:00	480	1	EGYVO	\N	0.00	t
26	1	201000000002	201000000001	2026-04-08 17:00:00	800	2	EGYVO	\N	0.00	t
27	1	201000000002	201000000003	2026-04-09 10:15:00	1	3	EGYVO	\N	0.00	t
28	2	201000000002	201000000001	2026-04-15 10:00:00	180	5	EGYVO	DEUTS	0.00	t
29	2	201000000002	201000000004	2026-04-15 14:30:00	200	6	EGYVO	DEUTS	0.00	t
30	2	201000000002	201000000006	2026-04-16 09:00:00	1	7	EGYVO	DEUTS	0.00	t
31	2	201000000002	201000000008	2026-04-16 15:45:00	120	5	EGYVO	DEUTS	0.00	t
32	2	201000000002	201000000001	2026-04-17 11:00:00	300	6	EGYVO	DEUTS	0.00	t
33	1	201000000003	201000000001	2026-04-01 09:00:00	120	1	EGYVO	\N	0.00	t
34	1	201000000003	201000000005	2026-04-02 11:30:00	1	3	EGYVO	\N	0.00	t
35	1	201000000003	201000000007	2026-04-04 14:00:00	240	1	EGYVO	\N	0.00	t
36	1	201000000003	201000000009	2026-04-06 16:30:00	1	3	EGYVO	\N	0.00	t
37	1	201000000003	201000000001	2026-04-08 10:15:00	180	1	EGYVO	\N	0.00	t
38	1	201000000003	201000000011	2026-04-10 13:45:00	90	1	EGYVO	\N	0.00	t
39	1	201000000004	201000000002	2026-04-01 08:00:00	360	1	EGYVO	\N	0.00	t
40	1	201000000004	201000000006	2026-04-01 13:00:00	600	2	EGYVO	\N	0.00	t
41	1	201000000004	201000000008	2026-04-02 10:30:00	1	3	EGYVO	\N	0.00	t
42	1	201000000004	201000000010	2026-04-03 15:00:00	420	1	EGYVO	\N	0.00	t
43	1	201000000004	201000000012	2026-04-05 09:45:00	800	2	EGYVO	\N	0.00	t
44	1	201000000004	201000000002	2026-04-07 14:00:00	1	3	EGYVO	\N	0.00	t
45	1	201000000004	201000000014	2026-04-09 11:30:00	540	1	EGYVO	\N	0.00	t
46	1	201000000004	201000000016	2026-04-11 16:00:00	700	2	EGYVO	\N	0.00	t
47	1	201000000005	201000000001	2026-04-01 10:00:00	90	1	EGYVO	\N	0.00	t
48	1	201000000005	201000000003	2026-04-03 12:30:00	1	3	EGYVO	\N	0.00	t
49	1	201000000005	201000000007	2026-04-05 15:45:00	150	1	EGYVO	\N	0.00	t
50	1	201000000005	201000000009	2026-04-08 09:00:00	1	3	EGYVO	\N	0.00	t
51	1	201000000005	201000000001	2026-04-11 11:15:00	120	1	EGYVO	\N	0.00	t
52	2	201000000006	201000000002	2026-04-01 09:30:00	540	1	EGYVO	\N	0.00	t
53	2	201000000006	201000000008	2026-04-01 13:00:00	900	2	EGYVO	\N	0.00	t
54	2	201000000006	201000000010	2026-04-02 08:15:00	1	3	EGYVO	\N	0.00	t
55	2	201000000006	201000000012	2026-04-02 14:00:00	480	1	EGYVO	\N	0.00	t
56	2	201000000006	201000000014	2026-04-03 10:30:00	1100	2	EGYVO	\N	0.00	t
57	2	201000000006	201000000002	2026-04-04 15:45:00	1	3	EGYVO	\N	0.00	t
58	2	201000000006	201000000016	2026-04-05 09:00:00	660	1	EGYVO	\N	0.00	t
59	2	201000000006	201000000018	2026-04-06 12:30:00	850	2	EGYVO	\N	0.00	t
60	2	201000000006	201000000002	2026-04-07 16:00:00	1	3	EGYVO	\N	0.00	t
61	2	201000000006	201000000004	2026-04-08 10:15:00	720	1	EGYVO	\N	0.00	t
62	2	201000000007	201000000001	2026-04-01 08:45:00	60	1	EGYVO	\N	0.00	t
63	2	201000000007	201000000009	2026-04-03 13:30:00	1	3	EGYVO	\N	0.00	t
64	2	201000000007	201000000011	2026-04-05 16:00:00	120	1	EGYVO	\N	0.00	t
65	2	201000000007	201000000001	2026-04-08 10:00:00	180	1	EGYVO	\N	0.00	t
66	2	201000000007	201000000003	2026-04-11 14:15:00	1	3	EGYVO	\N	0.00	t
67	2	201000000007	201000000005	2026-04-14 09:30:00	240	1	EGYVO	\N	0.00	t
68	2	201000000008	201000000002	2026-04-01 10:15:00	300	1	EGYVO	\N	0.00	t
69	2	201000000008	201000000004	2026-04-02 12:00:00	650	2	EGYVO	\N	0.00	t
70	2	201000000008	201000000006	2026-04-03 15:30:00	1	3	EGYVO	\N	0.00	t
71	2	201000000008	201000000010	2026-04-04 09:00:00	420	1	EGYVO	\N	0.00	t
72	2	201000000008	201000000012	2026-04-05 13:45:00	750	2	EGYVO	\N	0.00	t
73	2	201000000008	201000000002	2026-04-07 11:00:00	1	3	EGYVO	\N	0.00	t
74	2	201000000008	201000000014	2026-04-09 16:30:00	390	1	EGYVO	\N	0.00	t
75	2	201000000009	201000000001	2026-04-01 11:00:00	180	1	EGYVO	\N	0.00	t
76	2	201000000009	201000000003	2026-04-03 14:00:00	1	3	EGYVO	\N	0.00	t
77	2	201000000009	201000000005	2026-04-06 09:30:00	150	1	EGYVO	\N	0.00	t
78	2	201000000009	201000000007	2026-04-09 12:45:00	1	3	EGYVO	\N	0.00	t
79	2	201000000010	201000000002	2026-04-01 09:45:00	360	1	EGYVO	\N	0.00	t
80	2	201000000010	201000000004	2026-04-02 13:15:00	700	2	EGYVO	\N	0.00	t
81	2	201000000010	201000000006	2026-04-03 16:00:00	1	3	EGYVO	\N	0.00	t
82	2	201000000010	201000000008	2026-04-04 10:30:00	480	1	EGYVO	\N	0.00	t
83	2	201000000010	201000000012	2026-04-05 14:00:00	900	2	EGYVO	\N	0.00	t
84	2	201000000010	201000000002	2026-04-07 09:15:00	1	3	EGYVO	\N	0.00	t
85	2	201000000010	201000000014	2026-04-09 15:45:00	540	1	EGYVO	\N	0.00	t
86	2	201000000010	201000000016	2026-04-11 11:00:00	800	2	EGYVO	\N	0.00	t
87	1	201000000011	201000000001	2026-04-01 08:00:00	600	1	EGYVO	\N	0.00	t
88	1	201000000011	201000000003	2026-04-02 10:30:00	1	3	EGYVO	\N	0.00	t
89	1	201000000011	201000000005	2026-04-03 14:15:00	480	1	EGYVO	\N	0.00	t
90	1	201000000011	201000000007	2026-04-04 16:45:00	1	3	EGYVO	\N	0.00	t
91	1	201000000011	201000000009	2026-04-05 09:30:00	540	1	EGYVO	\N	0.00	t
92	1	201000000011	201000000001	2026-04-07 13:00:00	1	3	EGYVO	\N	0.00	t
93	1	201000000011	201000000003	2026-04-09 10:15:00	420	1	EGYVO	\N	0.00	t
94	1	201000000011	201000000005	2026-04-11 15:30:00	1	3	EGYVO	\N	0.00	t
95	1	201000000012	201000000002	2026-04-01 11:30:00	270	1	EGYVO	\N	0.00	t
96	1	201000000012	201000000004	2026-04-03 09:00:00	550	2	EGYVO	\N	0.00	t
97	1	201000000012	201000000006	2026-04-05 13:45:00	1	3	EGYVO	\N	0.00	t
98	1	201000000012	201000000008	2026-04-07 16:00:00	330	1	EGYVO	\N	0.00	t
99	1	201000000014	201000000002	2026-04-01 09:00:00	390	1	EGYVO	\N	0.00	t
100	1	201000000014	201000000004	2026-04-02 11:30:00	650	2	EGYVO	\N	0.00	t
101	1	201000000014	201000000006	2026-04-03 14:00:00	1	3	EGYVO	\N	0.00	t
102	1	201000000014	201000000008	2026-04-05 16:30:00	450	1	EGYVO	\N	0.00	t
103	1	201000000014	201000000010	2026-04-07 10:15:00	700	2	EGYVO	\N	0.00	t
104	1	201000000014	201000000002	2026-04-09 13:45:00	1	3	EGYVO	\N	0.00	t
105	2	201000000015	201000000002	2026-04-01 08:00:00	480	1	EGYVO	\N	0.00	t
106	2	201000000015	201000000004	2026-04-01 10:30:00	1200	2	EGYVO	\N	0.00	t
107	2	201000000015	201000000006	2026-04-01 13:00:00	1	3	EGYVO	\N	0.00	t
108	2	201000000015	201000000008	2026-04-02 09:00:00	600	1	EGYVO	\N	0.00	t
109	2	201000000015	201000000010	2026-04-02 14:00:00	1500	2	EGYVO	\N	0.00	t
110	2	201000000015	201000000012	2026-04-03 10:15:00	1	3	EGYVO	\N	0.00	t
111	2	201000000015	201000000002	2026-04-04 15:30:00	720	1	EGYVO	\N	0.00	t
112	2	201000000015	201000000016	2026-04-05 09:45:00	1800	2	EGYVO	\N	0.00	t
113	2	201000000015	201000000002	2026-04-20 10:00:00	240	5	EGYVO	FRANC	0.00	t
114	2	201000000015	201000000004	2026-04-20 14:30:00	400	6	EGYVO	FRANC	0.00	t
115	2	201000000015	201000000006	2026-04-21 09:00:00	1	7	EGYVO	FRANC	0.00	t
116	2	201000000016	201000000002	2026-04-01 09:30:00	600	1	EGYVO	\N	0.00	t
117	2	201000000016	201000000004	2026-04-01 12:00:00	1400	2	EGYVO	\N	0.00	t
118	2	201000000016	201000000006	2026-04-01 15:30:00	1	3	EGYVO	\N	0.00	t
119	2	201000000016	201000000008	2026-04-02 08:30:00	780	1	EGYVO	\N	0.00	t
120	2	201000000016	201000000010	2026-04-02 13:00:00	1600	2	EGYVO	\N	0.00	t
121	2	201000000016	201000000012	2026-04-03 10:00:00	1	3	EGYVO	\N	0.00	t
122	2	201000000016	201000000014	2026-04-03 16:00:00	840	1	EGYVO	\N	0.00	t
123	2	201000000016	201000000002	2026-04-04 11:30:00	1800	2	EGYVO	\N	0.00	t
124	2	201000000017	201000000002	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t
125	2	201000000017	201000000004	2026-04-02 12:30:00	600	2	EGYVO	\N	0.00	t
126	2	201000000017	201000000006	2026-04-03 15:00:00	1	3	EGYVO	\N	0.00	t
127	2	201000000017	201000000008	2026-04-05 09:30:00	420	1	EGYVO	\N	0.00	t
128	2	201000000017	201000000010	2026-04-07 14:00:00	750	2	EGYVO	\N	0.00	t
129	2	201000000017	201000000002	2026-04-09 11:15:00	1	3	EGYVO	\N	0.00	t
\.


--
-- Data for Name: contract; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.contract (id, user_account_id, rateplan_id, msisdn, status, credit_limit, available_credit) FROM stdin;
1	2	1	201000000001	active	200.00	200.00
3	4	1	201000000003	active	200.00	200.00
4	5	2	201000000004	active	500.00	500.00
5	6	1	201000000005	active	200.00	200.00
6	7	2	201000000006	active	500.00	500.00
7	8	1	201000000007	active	200.00	200.00
8	9	2	201000000008	active	500.00	500.00
9	10	1	201000000009	active	200.00	200.00
10	11	2	201000000010	active	500.00	500.00
11	12	1	201000000011	active	200.00	150.00
12	13	2	201000000012	active	500.00	420.00
13	14	1	201000000013	suspended	200.00	200.00
15	16	3	201000000015	active	1000.00	1000.00
16	17	3	201000000016	active	1000.00	980.00
17	18	2	201000000017	active	500.00	500.00
18	19	1	201000000018	terminated	200.00	200.00
14	15	2	201000000014	active	500.00	500.00
2	3	2	201000000002	active	500.00	500.00
\.


--
-- Data for Name: contract_addon; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.contract_addon (id, contract_id, service_package_id, purchased_date, expiry_date, is_active, price_paid) FROM stdin;
1	14	1	2026-04-27	2026-04-30	t	0.00
2	2	1	2026-04-28	2026-04-30	t	0.00
3	2	1	2026-04-28	2026-04-30	t	0.00
\.


--
-- Data for Name: contract_consumption; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.contract_consumption (contract_id, service_package_id, rateplan_id, starting_date, ending_date, consumed, is_billed, bill_id, quota_limit) FROM stdin;
2	1	2	2026-04-01	2026-04-30	620	t	34	5000.0000
1	1	1	2026-04-01	2026-04-30	350	t	33	1000.0000
1	3	1	2026-04-01	2026-04-30	45	t	33	200.0000
2	2	2	2026-04-01	2026-04-30	2100	t	34	5000.0000
2	3	2	2026-04-01	2026-04-30	85	t	34	200.0000
2	4	2	2026-04-01	2026-04-30	50	t	34	50.0000
2	5	2	2026-04-01	2026-04-30	120	t	34	200.0000
2	6	2	2026-04-01	2026-04-30	400	t	34	1000.0000
2	7	2	2026-04-01	2026-04-30	30	t	34	50.0000
3	1	1	2026-04-01	2026-04-30	180	t	35	1000.0000
3	3	1	2026-04-01	2026-04-30	22	t	35	200.0000
4	1	2	2026-04-01	2026-04-30	480	t	36	1000.0000
4	2	2	2026-04-01	2026-04-30	1800	t	36	5000.0000
4	3	2	2026-04-01	2026-04-30	65	t	36	200.0000
4	4	2	2026-04-01	2026-04-30	30	t	36	50.0000
5	1	1	2026-04-01	2026-04-30	95	t	37	1000.0000
5	3	1	2026-04-01	2026-04-30	12	t	37	200.0000
6	1	2	2026-04-01	2026-04-30	750	t	38	1000.0000
6	2	2	2026-04-01	2026-04-30	3200	t	38	5000.0000
6	3	2	2026-04-01	2026-04-30	110	t	38	200.0000
6	4	2	2026-04-01	2026-04-30	50	t	38	50.0000
7	1	1	2026-04-01	2026-04-30	210	t	39	1000.0000
7	3	1	2026-04-01	2026-04-30	18	t	39	200.0000
8	1	2	2026-04-01	2026-04-30	390	t	40	1000.0000
8	2	2	2026-04-01	2026-04-30	1500	t	40	5000.0000
8	3	2	2026-04-01	2026-04-30	55	t	40	200.0000
8	4	2	2026-04-01	2026-04-30	20	t	40	50.0000
9	1	1	2026-04-01	2026-04-30	140	t	41	1000.0000
9	3	1	2026-04-01	2026-04-30	8	t	41	200.0000
10	1	2	2026-04-01	2026-04-30	510	t	42	1000.0000
10	2	2	2026-04-01	2026-04-30	2400	t	42	5000.0000
10	3	2	2026-04-01	2026-04-30	75	t	42	200.0000
10	4	2	2026-04-01	2026-04-30	40	t	42	50.0000
11	1	1	2026-04-01	2026-04-30	980	t	43	1000.0000
11	3	1	2026-04-01	2026-04-30	190	t	43	200.0000
12	1	2	2026-04-01	2026-04-30	290	t	44	1000.0000
12	2	2	2026-04-01	2026-04-30	900	t	44	5000.0000
12	3	2	2026-04-01	2026-04-30	35	t	44	200.0000
12	4	2	2026-04-01	2026-04-30	15	t	44	50.0000
15	1	3	2026-04-01	2026-04-30	820	t	45	1000.0000
15	2	3	2026-04-01	2026-04-30	3800	t	45	5000.0000
15	3	3	2026-04-01	2026-04-30	145	t	45	200.0000
15	4	3	2026-04-01	2026-04-30	50	t	45	50.0000
14	2	2	2026-04-01	2026-04-30	1200	t	48	5000.0000
14	3	2	2026-04-01	2026-04-30	60	t	48	200.0000
14	4	2	2026-04-01	2026-04-30	25	t	48	50.0000
14	1	2	2026-04-01	2026-04-30	430	t	48	2000.0000
4	5	2	2026-04-01	2026-04-30	0	t	36	200.0000
4	6	2	2026-04-01	2026-04-30	0	t	36	1000.0000
4	7	2	2026-04-01	2026-04-30	0	t	36	50.0000
6	5	2	2026-04-01	2026-04-30	0	t	38	200.0000
6	6	2	2026-04-01	2026-04-30	0	t	38	1000.0000
6	7	2	2026-04-01	2026-04-30	0	t	38	50.0000
8	5	2	2026-04-01	2026-04-30	0	t	40	200.0000
8	6	2	2026-04-01	2026-04-30	0	t	40	1000.0000
8	7	2	2026-04-01	2026-04-30	0	t	40	50.0000
10	5	2	2026-04-01	2026-04-30	0	t	42	200.0000
10	6	2	2026-04-01	2026-04-30	0	t	42	1000.0000
10	7	2	2026-04-01	2026-04-30	0	t	42	50.0000
12	5	2	2026-04-01	2026-04-30	0	t	44	200.0000
12	6	2	2026-04-01	2026-04-30	0	t	44	1000.0000
12	7	2	2026-04-01	2026-04-30	0	t	44	50.0000
15	5	3	2026-04-01	2026-04-30	80	t	45	200.0000
15	6	3	2026-04-01	2026-04-30	320	t	45	1000.0000
15	7	3	2026-04-01	2026-04-30	20	t	45	50.0000
16	1	3	2026-04-01	2026-04-30	950	t	46	1000.0000
16	2	3	2026-04-01	2026-04-30	4900	t	46	5000.0000
16	3	3	2026-04-01	2026-04-30	180	t	46	200.0000
16	4	3	2026-04-01	2026-04-30	50	t	46	50.0000
16	5	3	2026-04-01	2026-04-30	0	t	46	200.0000
16	6	3	2026-04-01	2026-04-30	0	t	46	1000.0000
16	7	3	2026-04-01	2026-04-30	0	t	46	50.0000
17	1	2	2026-04-01	2026-04-30	340	t	47	1000.0000
17	2	2	2026-04-01	2026-04-30	1100	t	47	5000.0000
17	3	2	2026-04-01	2026-04-30	48	t	47	200.0000
17	4	2	2026-04-01	2026-04-30	10	t	47	50.0000
17	5	2	2026-04-01	2026-04-30	0	t	47	200.0000
17	6	2	2026-04-01	2026-04-30	0	t	47	1000.0000
17	7	2	2026-04-01	2026-04-30	0	t	47	50.0000
14	5	2	2026-04-01	2026-04-30	0	t	48	200.0000
14	6	2	2026-04-01	2026-04-30	0	t	48	1000.0000
14	7	2	2026-04-01	2026-04-30	0	t	48	50.0000
\.


--
-- Data for Name: file; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.file (id, parsed_flag, file_path) FROM stdin;
1	t	/tmp/cdr_april_batch1.csv
2	t	/tmp/cdr_april_batch2.csv
\.


--
-- Data for Name: invoice; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.invoice (id, bill_id, pdf_path, generation_date) FROM stdin;
1	1	/invoices/feb26_contract1.pdf	2026-04-27 20:51:41.179203
2	2	/invoices/feb26_contract2.pdf	2026-04-27 20:51:41.179203
3	3	/invoices/feb26_contract3.pdf	2026-04-27 20:51:41.179203
4	4	/invoices/feb26_contract4.pdf	2026-04-27 20:51:41.179203
5	5	/invoices/feb26_contract5.pdf	2026-04-27 20:51:41.179203
6	6	/invoices/feb26_contract6.pdf	2026-04-27 20:51:41.179203
7	7	/invoices/feb26_contract7.pdf	2026-04-27 20:51:41.179203
8	8	/invoices/feb26_contract8.pdf	2026-04-27 20:51:41.179203
9	9	/invoices/feb26_contract9.pdf	2026-04-27 20:51:41.179203
10	10	/invoices/feb26_contract10.pdf	2026-04-27 20:51:41.179203
11	11	/invoices/feb26_contract11.pdf	2026-04-27 20:51:41.179203
12	12	/invoices/feb26_contract12.pdf	2026-04-27 20:51:41.179203
13	13	/invoices/feb26_contract14.pdf	2026-04-27 20:51:41.179203
14	14	/invoices/feb26_contract15.pdf	2026-04-27 20:51:41.179203
15	15	/invoices/feb26_contract16.pdf	2026-04-27 20:51:41.179203
16	16	/invoices/feb26_contract17.pdf	2026-04-27 20:51:41.179203
17	17	/invoices/mar26_contract1.pdf	2026-04-27 20:51:41.179203
18	18	/invoices/mar26_contract2.pdf	2026-04-27 20:51:41.179203
\.


--
-- Data for Name: msisdn_pool; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.msisdn_pool (id, msisdn, is_available) FROM stdin;
19	201000000019	t
20	201000000020	t
21	201000000021	t
22	201000000022	t
23	201000000023	t
24	201000000024	t
25	201000000025	t
26	201000000026	t
27	201000000027	t
28	201000000028	t
29	201000000029	t
30	201000000030	t
31	201000000031	t
32	201000000032	t
33	201000000033	t
34	201000000034	t
35	201000000035	t
36	201000000036	t
37	201000000037	t
38	201000000038	t
39	201000000039	t
40	201000000040	t
41	201000000041	t
42	201000000042	t
43	201000000043	t
44	201000000044	t
45	201000000045	t
46	201000000046	t
47	201000000047	t
48	201000000048	t
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
\.


--
-- Data for Name: rateplan; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.rateplan (id, name, ror_data, ror_voice, ror_sms, price) FROM stdin;
1	Basic	0.10	0.20	0.05	75.00
2	Premium Gold	0.05	0.10	0.02	350.00
3	Elite Enterprise	0.02	0.05	0.01	950.00
\.


--
-- Data for Name: rateplan_service_package; Type: TABLE DATA; Schema: public; Owner: -
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
-- Data for Name: ror_contract; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ror_contract (contract_id, rateplan_id, data, voice, sms, bill_id) FROM stdin;
13	1	0	0	0	\N
18	1	0	0	0	\N
1	1	0	0	0	33
2	2	0	0	0	34
3	1	0	0	0	35
4	2	0	0	0	36
5	1	0	0	0	37
6	2	0	0	0	38
7	1	0	0	0	39
8	2	0	0	0	40
9	1	0	0	0	41
10	2	0	0	0	42
11	1	0	0	0	43
12	2	0	0	0	44
15	3	0	0	0	45
16	3	20	0	0	46
17	2	0	0	0	47
14	2	0	0	0	48
\.


--
-- Data for Name: service_package; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.service_package (id, name, type, amount, priority, price, is_roaming, description) FROM stdin;
4	Welcome Bonus	free_units	50.0000	2	0.00	f	Free units for new customers
1	Voice Pack	voice	2000.0000	1	0.00	f	2000 local minutes per month
2	Data Pack	data	10000.0000	1	0.00	f	10GB data per month
3	SMS Pack	sms	500.0000	1	0.00	f	500 SMS per month
5	Roaming Voice Pack	voice	100.0000	1	250.00	t	100 roaming minutes
6	Roaming Data Pack	data	2000.0000	1	500.00	t	2GB roaming data
7	Roaming SMS Pack	sms	50.0000	1	50.00	t	50 roaming SMS
\.


--
-- Data for Name: user_account; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_account (id, username, password, role, name, email, address, birthdate) FROM stdin;
1	admin	admin123	admin	System Admin	admin@fmrz.com	HQ Cairo	1985-01-01
2	alice	password1	customer	Alice Smith	alice@gmail.com	123 Main St	1990-01-01
3	bob	password2	customer	Bob Johnson	bob@gmail.com	456 Elm St	1985-05-15
4	carol	password3	customer	Carol White	carol@gmail.com	789 Oak Ave	1992-03-10
5	david	password4	customer	David Brown	david@gmail.com	321 Pine Rd	1988-07-22
6	eva	password5	customer	Eva Green	eva@gmail.com	654 Maple Dr	1995-11-05
7	frank	password6	customer	Frank Miller	frank@gmail.com	987 Cedar Ln	1983-02-18
8	grace	password7	customer	Grace Lee	grace@gmail.com	147 Birch Blvd	1991-09-30
9	henry	password8	customer	Henry Wilson	henry@gmail.com	258 Walnut St	1987-04-14
10	iris	password9	customer	Iris Taylor	iris@gmail.com	369 Spruce Ave	1993-06-25
11	jack	password10	customer	Jack Davis	jack@gmail.com	741 Ash Ct	1986-12-03
12	karen	password11	customer	Karen Martinez	karen@gmail.com	852 Elm Pl	1994-08-17
13	leo	password12	customer	Leo Anderson	leo@gmail.com	963 Oak St	1989-01-29
14	mia	password13	customer	Mia Thomas	mia@gmail.com	159 Pine Ave	1996-05-08
15	noah	password14	customer	Noah Jackson	noah@gmail.com	267 Maple Rd	1984-10-21
16	olivia	password15	customer	Olivia Harris	olivia@gmail.com	348 Cedar Dr	1997-03-15
17	paul	password16	customer	Paul Clark	paul@gmail.com	426 Birch Ln	1982-07-04
18	quinn	password17	customer	Quinn Lewis	quinn@gmail.com	537 Walnut Blvd	1998-11-19
19	rachel	password18	customer	Rachel Walker	rachel@gmail.com	648 Spruce St	1981-02-27
\.


--
-- Data for Name: v_msisdn; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.v_msisdn (msisdn) FROM stdin;
\.


--
-- Name: bill_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.bill_id_seq', 158, true);


--
-- Name: cdr_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.cdr_id_seq', 713, true);


--
-- Name: contract_addon_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.contract_addon_id_seq', 35, true);


--
-- Name: contract_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.contract_id_seq', 152, true);


--
-- Name: file_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.file_id_seq', 2, true);


--
-- Name: invoice_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.invoice_id_seq', 19, true);


--
-- Name: msisdn_pool_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.msisdn_pool_id_seq', 199, true);


--
-- Name: rateplan_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.rateplan_id_seq', 3, true);


--
-- Name: service_package_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.service_package_id_seq', 7, true);


--
-- Name: user_account_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.user_account_id_seq', 152, true);


--
-- Name: bill bill_contract_id_billing_period_start_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill
    ADD CONSTRAINT bill_contract_id_billing_period_start_key UNIQUE (contract_id, billing_period_start);


--
-- Name: bill bill_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill
    ADD CONSTRAINT bill_pkey PRIMARY KEY (id);


--
-- Name: cdr cdr_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cdr
    ADD CONSTRAINT cdr_pkey PRIMARY KEY (id);


--
-- Name: contract_addon contract_addon_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_addon
    ADD CONSTRAINT contract_addon_pkey PRIMARY KEY (id);


--
-- Name: contract_consumption contract_consumption_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_consumption
    ADD CONSTRAINT contract_consumption_pkey PRIMARY KEY (contract_id, service_package_id, rateplan_id, starting_date, ending_date);


--
-- Name: contract contract_msisdn_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract
    ADD CONSTRAINT contract_msisdn_key UNIQUE (msisdn);


--
-- Name: contract contract_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract
    ADD CONSTRAINT contract_pkey PRIMARY KEY (id);


--
-- Name: file file_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.file
    ADD CONSTRAINT file_pkey PRIMARY KEY (id);


--
-- Name: invoice invoice_bill_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_bill_id_unique UNIQUE (bill_id);


--
-- Name: invoice invoice_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_pkey PRIMARY KEY (id);


--
-- Name: msisdn_pool msisdn_pool_msisdn_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.msisdn_pool
    ADD CONSTRAINT msisdn_pool_msisdn_key UNIQUE (msisdn);


--
-- Name: msisdn_pool msisdn_pool_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.msisdn_pool
    ADD CONSTRAINT msisdn_pool_pkey PRIMARY KEY (id);


--
-- Name: rateplan rateplan_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rateplan
    ADD CONSTRAINT rateplan_pkey PRIMARY KEY (id);


--
-- Name: rateplan_service_package rateplan_service_package_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rateplan_service_package
    ADD CONSTRAINT rateplan_service_package_pkey PRIMARY KEY (rateplan_id, service_package_id);


--
-- Name: ror_contract ror_contract_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ror_contract
    ADD CONSTRAINT ror_contract_pkey PRIMARY KEY (contract_id, rateplan_id);


--
-- Name: service_package service_package_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_package
    ADD CONSTRAINT service_package_pkey PRIMARY KEY (id);


--
-- Name: invoice unique_bill_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT unique_bill_id UNIQUE (bill_id);


--
-- Name: user_account user_account_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_account
    ADD CONSTRAINT user_account_email_key UNIQUE (email);


--
-- Name: user_account user_account_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_account
    ADD CONSTRAINT user_account_pkey PRIMARY KEY (id);


--
-- Name: user_account user_account_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_account
    ADD CONSTRAINT user_account_username_key UNIQUE (username);


--
-- Name: contract_msisdn_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contract_msisdn_active_idx ON public.contract USING btree (msisdn) WHERE (status <> 'terminated'::public.contract_status);


--
-- Name: idx_addon_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_addon_active ON public.contract_addon USING btree (contract_id, is_active);


--
-- Name: idx_addon_contract; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_addon_contract ON public.contract_addon USING btree (contract_id);


--
-- Name: idx_bill_billing_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bill_billing_date ON public.bill USING btree (billing_date);


--
-- Name: idx_bill_contract; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bill_contract ON public.bill USING btree (contract_id);


--
-- Name: idx_cdr_dial_a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cdr_dial_a ON public.cdr USING btree (dial_a);


--
-- Name: idx_cdr_file_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cdr_file_id ON public.cdr USING btree (file_id);


--
-- Name: idx_cdr_rated_flag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cdr_rated_flag ON public.cdr USING btree (rated_flag);


--
-- Name: idx_contract_msisdn; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contract_msisdn ON public.contract USING btree (msisdn);


--
-- Name: idx_contract_user_account; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contract_user_account ON public.contract USING btree (user_account_id);


--
-- Name: idx_invoice_bill; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoice_bill ON public.invoice USING btree (bill_id);


--
-- Name: cdr trg_auto_initialize_consumption; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_auto_initialize_consumption BEFORE INSERT ON public.cdr FOR EACH ROW EXECUTE FUNCTION public.auto_initialize_consumption();


--
-- Name: cdr trg_auto_rate_cdr; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_auto_rate_cdr AFTER INSERT ON public.cdr FOR EACH ROW EXECUTE FUNCTION public.auto_rate_cdr();


--
-- Name: bill trg_bill_inserted; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_bill_inserted AFTER INSERT ON public.bill FOR EACH ROW EXECUTE FUNCTION public.notify_bill_generation();


--
-- Name: bill trg_bill_payment; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_bill_payment AFTER UPDATE ON public.bill FOR EACH ROW EXECUTE FUNCTION public.trg_restore_credit_on_payment();


--
-- Name: cdr trg_cdr_validate_contract; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cdr_validate_contract BEFORE INSERT ON public.cdr FOR EACH ROW EXECUTE FUNCTION public.validate_cdr_contract();


--
-- Name: bill bill_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill
    ADD CONSTRAINT bill_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contract(id);


--
-- Name: cdr cdr_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cdr
    ADD CONSTRAINT cdr_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.file(id);


--
-- Name: cdr cdr_service_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cdr
    ADD CONSTRAINT cdr_service_id_fkey FOREIGN KEY (service_id) REFERENCES public.service_package(id);


--
-- Name: contract_addon contract_addon_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_addon
    ADD CONSTRAINT contract_addon_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contract(id);


--
-- Name: contract_addon contract_addon_service_package_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_addon
    ADD CONSTRAINT contract_addon_service_package_id_fkey FOREIGN KEY (service_package_id) REFERENCES public.service_package(id);


--
-- Name: contract_consumption contract_consumption_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_consumption
    ADD CONSTRAINT contract_consumption_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bill(id);


--
-- Name: contract_consumption contract_consumption_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_consumption
    ADD CONSTRAINT contract_consumption_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contract(id);


--
-- Name: contract_consumption contract_consumption_rateplan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_consumption
    ADD CONSTRAINT contract_consumption_rateplan_id_fkey FOREIGN KEY (rateplan_id) REFERENCES public.rateplan(id);


--
-- Name: contract_consumption contract_consumption_service_package_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract_consumption
    ADD CONSTRAINT contract_consumption_service_package_id_fkey FOREIGN KEY (service_package_id) REFERENCES public.service_package(id);


--
-- Name: contract contract_rateplan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract
    ADD CONSTRAINT contract_rateplan_id_fkey FOREIGN KEY (rateplan_id) REFERENCES public.rateplan(id);


--
-- Name: contract contract_user_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contract
    ADD CONSTRAINT contract_user_account_id_fkey FOREIGN KEY (user_account_id) REFERENCES public.user_account(id);


--
-- Name: invoice invoice_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bill(id);


--
-- Name: rateplan_service_package rateplan_service_package_rateplan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rateplan_service_package
    ADD CONSTRAINT rateplan_service_package_rateplan_id_fkey FOREIGN KEY (rateplan_id) REFERENCES public.rateplan(id);


--
-- Name: rateplan_service_package rateplan_service_package_service_package_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rateplan_service_package
    ADD CONSTRAINT rateplan_service_package_service_package_id_fkey FOREIGN KEY (service_package_id) REFERENCES public.service_package(id);


--
-- Name: ror_contract ror_contract_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ror_contract
    ADD CONSTRAINT ror_contract_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bill(id);


--
-- Name: ror_contract ror_contract_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ror_contract
    ADD CONSTRAINT ror_contract_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contract(id);


--
-- Name: ror_contract ror_contract_rateplan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ror_contract
    ADD CONSTRAINT ror_contract_rateplan_id_fkey FOREIGN KEY (rateplan_id) REFERENCES public.rateplan(id);


--
-- PostgreSQL database dump complete
--

\unrestrict hDrA9KLAeL6NJDDhSN5hnKMn9gdlF9LDTfyzMztteaQ5cYCV8m0C0Flap7AgpWo

