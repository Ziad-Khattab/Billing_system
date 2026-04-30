--
-- PostgreSQL database dump
--

\restrict QAhNCqjh3AGJ9KcbuZQe0xSAD8cDvjtzYAttFGnM6hKGtZ2zQCxWX96gZzcgopG

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
-- Name: public; Type: SCHEMA; Schema: -; Owner: neondb_owner
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO neondb_owner;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: neondb_owner
--

COMMENT ON SCHEMA public IS '';


--
-- Name: bill_status; Type: TYPE; Schema: public; Owner: neondb_owner
--

CREATE TYPE public.bill_status AS ENUM (
    'draft',
    'issued',
    'paid',
    'overdue',
    'cancelled'
);


ALTER TYPE public.bill_status OWNER TO neondb_owner;

--
-- Name: contract_status; Type: TYPE; Schema: public; Owner: neondb_owner
--

CREATE TYPE public.contract_status AS ENUM (
    'active',
    'suspended',
    'suspended_debt',
    'terminated'
);


ALTER TYPE public.contract_status OWNER TO neondb_owner;

--
-- Name: service_type; Type: TYPE; Schema: public; Owner: neondb_owner
--

CREATE TYPE public.service_type AS ENUM (
    'voice',
    'data',
    'sms',
    'free_units'
);


ALTER TYPE public.service_type OWNER TO neondb_owner;

--
-- Name: user_role; Type: TYPE; Schema: public; Owner: neondb_owner
--

CREATE TYPE public.user_role AS ENUM (
    'admin',
    'customer'
);


ALTER TYPE public.user_role OWNER TO neondb_owner;

--
-- Name: add_new_service_package(character varying, public.service_type, numeric, integer, numeric, text, boolean); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.add_new_service_package(p_name character varying, p_type public.service_type, p_amount numeric, p_priority integer, p_price numeric, p_description text, p_is_roaming boolean) OWNER TO neondb_owner;

--
-- Name: auto_initialize_consumption(); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.auto_initialize_consumption() OWNER TO neondb_owner;

--
-- Name: auto_rate_cdr(); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.auto_rate_cdr() OWNER TO neondb_owner;

--
-- Name: cancel_addon(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.cancel_addon(p_addon_id integer) OWNER TO neondb_owner;

--
-- Name: change_contract_rateplan(integer, integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.change_contract_rateplan(p_contract_id integer, p_new_rateplan_id integer) OWNER TO neondb_owner;

--
-- Name: change_contract_status(integer, public.contract_status); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.change_contract_status(p_contract_id integer, p_status public.contract_status) OWNER TO neondb_owner;

--
-- Name: create_admin(character varying, character varying, character varying, character varying, text, date); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.create_admin(p_username character varying, p_password character varying, p_name character varying, p_email character varying, p_address text, p_birthdate date) OWNER TO neondb_owner;

--
-- Name: create_contract(integer, integer, character varying, double precision); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.create_contract(p_user_account_id integer, p_rateplan_id integer, p_msisdn character varying, p_credit_limit double precision) OWNER TO neondb_owner;

--
-- Name: create_customer(character varying, character varying, character varying, character varying, text, date); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.create_customer(p_username character varying, p_password character varying, p_name character varying, p_email character varying, p_address text, p_birthdate date) OWNER TO neondb_owner;

--
-- Name: create_file_record(text); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.create_file_record(p_file_path text) OWNER TO neondb_owner;

--
-- Name: create_rateplan_with_packages(character varying, numeric, numeric, numeric, numeric, integer[]); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.create_rateplan_with_packages(p_name character varying, p_ror_voice numeric, p_ror_data numeric, p_ror_sms numeric, p_price numeric, p_service_package_ids integer[]) OWNER TO neondb_owner;

--
-- Name: create_service_package(character varying, public.service_type, numeric, integer, numeric, text, boolean); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.create_service_package(p_name character varying, p_type public.service_type, p_amount numeric, p_priority integer, p_price numeric, p_description text, p_is_roaming boolean) OWNER TO neondb_owner;

--
-- Name: delete_rateplan(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
--

CREATE FUNCTION public.delete_rateplan(p_rateplan_id integer) RETURNS void
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


ALTER FUNCTION public.delete_rateplan(p_rateplan_id integer) OWNER TO neondb_owner;

--
-- Name: delete_service_package(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.delete_service_package(p_id integer) OWNER TO neondb_owner;

--
-- Name: expire_addons(); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.expire_addons() OWNER TO neondb_owner;

--
-- Name: generate_all_bills(date); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.generate_all_bills(p_period_start date) OWNER TO neondb_owner;

--
-- Name: generate_bill(integer, date); Type: FUNCTION; Schema: public; Owner: neondb_owner
--

CREATE FUNCTION public.generate_bill(p_contract_id integer, p_billing_period_start date) RETURNS integer
    LANGUAGE plpgsql
    AS $$
    DECLARE
        v_bill_id INTEGER;
        v_rateplan_id INTEGER;
        v_msisdn VARCHAR;
        v_recurring_fees NUMERIC(12,2);
        v_ror_rate_v NUMERIC(12,4);
        v_ror_rate_d NUMERIC(12,4);
        v_ror_rate_s NUMERIC(12,4);
        v_ror_roaming_v NUMERIC(12,4);
        v_ror_roaming_d NUMERIC(12,4);
        v_ror_roaming_s NUMERIC(12,4);
        v_voice_bundled BIGINT;
        v_data_bundled BIGINT;
        v_sms_bundled BIGINT;
        v_voice_ror BIGINT;
        v_data_ror BIGINT;
        v_sms_ror BIGINT;
        v_overage_charge NUMERIC(12,2) := 0;
        v_roaming_charge NUMERIC(12,2) := 0;
        v_ot_fees NUMERIC(12,2) := 0;
        v_promo_discount NUMERIC(12,2) := 0;
        v_subtotal NUMERIC(12,2);
        v_taxes NUMERIC(12,2);
        v_total_amount NUMERIC(12,2);
        v_billing_period_end DATE;
        v_due_date DATE;
    BEGIN
        v_billing_period_end := (DATE_TRUNC('month', p_billing_period_start) + INTERVAL '1 month - 1 day')::DATE;
        v_due_date := CURRENT_DATE + INTERVAL '14 days';
        
        SELECT rateplan_id, msisdn INTO v_rateplan_id, v_msisdn FROM contract WHERE id = p_contract_id;
        
        SELECT price, ror_voice, ror_data, ror_sms, ror_roaming_voice, ror_roaming_data, ror_roaming_sms 
        INTO v_recurring_fees, v_ror_rate_v, v_ror_rate_d, v_ror_rate_s, v_ror_roaming_v, v_ror_roaming_d, v_ror_roaming_s
        FROM rateplan WHERE id = v_rateplan_id;

        -- 1. Calculate Bundled Usage
        SELECT 
            COALESCE(SUM(CASE WHEN sp.type::TEXT = 'voice' THEN cc.consumed ELSE 0 END), 0)::BIGINT,
            COALESCE(SUM(CASE WHEN sp.type::TEXT = 'data' THEN cc.consumed ELSE 0 END), 0)::BIGINT,
            COALESCE(SUM(CASE WHEN sp.type::TEXT = 'sms' THEN cc.consumed ELSE 0 END), 0)::BIGINT
        INTO v_voice_bundled, v_data_bundled, v_sms_bundled
        FROM contract_consumption cc JOIN service_package sp ON cc.service_package_id = sp.id
        WHERE cc.contract_id = p_contract_id AND cc.starting_date = p_billing_period_start;

        -- 2. Calculate ROR Usage and Charges
        SELECT 
            COALESCE(SUM(voice + roaming_voice), 0)::BIGINT,
            COALESCE(SUM(data + roaming_data), 0)::BIGINT,
            COALESCE(SUM(sms + roaming_sms), 0)::BIGINT,
            COALESCE(SUM((voice / 60.0 * v_ror_rate_v) + (data / 1073741824.0 * v_ror_rate_d) + (sms * v_ror_rate_s)), 0),
            COALESCE(SUM((roaming_voice / 60.0 * v_ror_roaming_v) + (roaming_data / 1073741824.0 * v_ror_roaming_d) + (roaming_sms * v_ror_roaming_s)), 0)
        INTO v_voice_ror, v_data_ror, v_sms_ror, v_overage_charge, v_roaming_charge
        FROM ror_contract WHERE contract_id = p_contract_id AND starting_date = p_billing_period_start AND bill_id IS NULL;

        -- 3. One-time Fees
        SELECT COALESCE(SUM(amount), 0) INTO v_ot_fees FROM onetime_fee WHERE contract_id = p_contract_id AND bill_id IS NULL;

        v_subtotal := (v_recurring_fees + v_overage_charge + v_roaming_charge + v_ot_fees - v_promo_discount);
        v_taxes := ROUND(0.14 * v_subtotal, 2);
        v_total_amount := v_subtotal + v_taxes;

        INSERT INTO bill (
            contract_id, billing_period_start, billing_period_end, billing_date, due_date,
            recurring_fees, voice_usage, data_usage, sms_usage,
            overage_charge, roaming_charge, one_time_fees, promotional_discount, taxes, total_amount, status
        ) VALUES (
            p_contract_id, p_billing_period_start, v_billing_period_end, CURRENT_DATE, v_due_date,
            v_recurring_fees, (v_voice_bundled + v_voice_ror), (v_data_bundled + v_data_ror), (v_sms_bundled + v_sms_ror),
            v_overage_charge, v_roaming_charge, v_ot_fees, v_promo_discount, v_taxes, v_total_amount, 'issued'
        ) RETURNING id INTO v_bill_id;

        UPDATE ror_contract SET bill_id = v_bill_id WHERE contract_id = p_contract_id AND starting_date = p_billing_period_start AND bill_id IS NULL;
        UPDATE contract_consumption SET bill_id = v_bill_id, is_billed = TRUE WHERE contract_id = p_contract_id AND starting_date = p_billing_period_start;
        UPDATE onetime_fee SET bill_id = v_bill_id WHERE contract_id = p_contract_id AND bill_id IS NULL;

        RETURN v_bill_id;
    END;
$$;


ALTER FUNCTION public.generate_bill(p_contract_id integer, p_billing_period_start date) OWNER TO neondb_owner;

--
-- Name: generate_bulk_missing(text); Type: PROCEDURE; Schema: public; Owner: neondb_owner
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


ALTER PROCEDURE public.generate_bulk_missing(IN p_search text) OWNER TO neondb_owner;

--
-- Name: generate_invoice(integer, text); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.generate_invoice(p_bill_id integer, p_pdf_path text) OWNER TO neondb_owner;

--
-- Name: get_all_bills(text, integer, integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
--

CREATE FUNCTION public.get_all_bills(p_search text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0) RETURNS TABLE(id integer, contract_id integer, billing_date date, billing_period_start date, billing_period_end date, total_amount numeric, is_paid boolean, status character varying, voice_usage bigint, data_usage bigint, sms_usage bigint, customer_name character varying, msisdn character varying, total_count bigint)
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
            ua.name::VARCHAR AS customer_name,
            c.msisdn::VARCHAR,
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


ALTER FUNCTION public.get_all_bills(p_search text, p_limit integer, p_offset integer) OWNER TO neondb_owner;

--
-- Name: get_all_contracts(text, integer, integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_all_contracts(p_search text, p_limit integer, p_offset integer) OWNER TO neondb_owner;

--
-- Name: get_all_customers(text, integer, integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_all_customers(p_search text, p_limit integer, p_offset integer) OWNER TO neondb_owner;

--
-- Name: get_all_rateplans(); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_all_rateplans() OWNER TO neondb_owner;

--
-- Name: get_all_service_packages(); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_all_service_packages() OWNER TO neondb_owner;

--
-- Name: get_available_msisdns(); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_available_msisdns() OWNER TO neondb_owner;

--
-- Name: get_bill(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_bill(p_bill_id integer) OWNER TO neondb_owner;

--
-- Name: get_bill_usage_breakdown(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
--

CREATE FUNCTION public.get_bill_usage_breakdown(p_bill_id integer) RETURNS TABLE(service_type text, category_label text, quota bigint, consumed bigint, unit_rate numeric, line_total numeric, is_roaming boolean, is_promotional boolean, notes text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_contract_id INTEGER;
BEGIN
    SELECT contract_id INTO v_contract_id FROM bill WHERE id = p_bill_id;
    
    RETURN QUERY
    -- 1. Bundled usage
    SELECT 
        sp.type::TEXT, sp.name::TEXT, cc.quota_limit::BIGINT, cc.consumed::BIGINT,
        0::NUMERIC(12,4), 0::NUMERIC(12,2), sp.is_roaming, (sp.name ~* 'Welcome|Gift|Bonus'),
        'Bundle item'::TEXT
    FROM contract_consumption cc JOIN service_package sp ON cc.service_package_id = sp.id
    WHERE cc.bill_id = p_bill_id
    
    UNION ALL
    -- 2. Voice Overage
    SELECT 'voice', 'Overage - Voice', NULL, rc.voice::BIGINT, rp.ror_voice,
           ROUND((rc.voice / 60.0 * rp.ror_voice)::NUMERIC, 2), FALSE, FALSE, 'Overage min'
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.bill_id = p_bill_id AND rc.voice > 0
    
    UNION ALL
    -- 3. Data Overage
    SELECT 'data', 'Overage - Data', NULL, (rc.data / 1048576)::BIGINT, rp.ror_data,
           ROUND((rc.data / 1073741824.0 * rp.ror_data)::NUMERIC, 2), FALSE, FALSE, 'Overage MB'
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.bill_id = p_bill_id AND rc.data > 0

    UNION ALL
    -- 4. SMS Overage
    SELECT 'sms', 'Overage - SMS', NULL, rc.sms::BIGINT, rp.ror_sms,
           ROUND((rc.sms * rp.ror_sms)::NUMERIC, 2), FALSE, FALSE, 'Overage msgs'
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.bill_id = p_bill_id AND rc.sms > 0

    UNION ALL
    -- 5. Roaming Voice
    SELECT 'voice', 'Roaming - Voice', NULL, rc.roaming_voice::BIGINT, rp.ror_roaming_voice,
           ROUND((rc.roaming_voice / 60.0 * rp.ror_roaming_voice)::NUMERIC, 2), TRUE, FALSE, 'Roaming min'
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.bill_id = p_bill_id AND rc.roaming_voice > 0

    UNION ALL
    -- 6. Roaming Data
    SELECT 'data', 'Roaming - Data', NULL, (rc.roaming_data / 1048576)::BIGINT, rp.ror_roaming_data,
           ROUND((rc.roaming_data / 1073741824.0 * rp.ror_roaming_data)::NUMERIC, 2), TRUE, FALSE, 'Roaming MB'
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.bill_id = p_bill_id AND rc.roaming_data > 0

    UNION ALL
    -- 7. Roaming SMS
    SELECT 'sms', 'Roaming - SMS', NULL, rc.roaming_sms::BIGINT, rp.ror_roaming_sms,
           ROUND((rc.roaming_sms * rp.ror_roaming_sms)::NUMERIC, 2), TRUE, FALSE, 'Roaming msgs'
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.bill_id = p_bill_id AND rc.roaming_sms > 0

    UNION ALL
    -- 8. One-time Fees
    SELECT 'fee', fee_type, NULL, 1::BIGINT, amount,
           amount, FALSE, FALSE, description
    FROM onetime_fee WHERE bill_id = p_bill_id;
END;
$$;


ALTER FUNCTION public.get_bill_usage_breakdown(p_bill_id integer) OWNER TO neondb_owner;

--
-- Name: get_bills_by_contract(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_bills_by_contract(p_contract_id integer) OWNER TO neondb_owner;

--
-- Name: get_cdr_usage_amount(integer, public.service_type); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_cdr_usage_amount(p_duration integer, p_service_type public.service_type) OWNER TO neondb_owner;

--
-- Name: get_cdrs(integer, integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_cdrs(p_limit integer, p_offset integer) OWNER TO neondb_owner;

--
-- Name: get_contract_addons(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_contract_addons(p_contract_id integer) OWNER TO neondb_owner;

--
-- Name: get_contract_by_id(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_contract_by_id(p_id integer) OWNER TO neondb_owner;

--
-- Name: get_contract_consumption(integer, date); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_contract_consumption(p_contract_id integer, p_period_start date) OWNER TO neondb_owner;

--
-- Name: get_customer_by_id(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_customer_by_id(p_id integer) OWNER TO neondb_owner;

--
-- Name: get_dashboard_stats(); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_dashboard_stats() OWNER TO neondb_owner;

--
-- Name: get_missing_bills(text, integer, integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_missing_bills(p_search text, p_limit integer, p_offset integer) OWNER TO neondb_owner;

--
-- Name: get_rateplan_by_id(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_rateplan_by_id(p_id integer) OWNER TO neondb_owner;

--
-- Name: get_rateplan_data(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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
        FROM rateplan r
        WHERE r.id = p_rateplan_id;
END;
$$;


ALTER FUNCTION public.get_rateplan_data(p_rateplan_id integer) OWNER TO neondb_owner;

--
-- Name: get_service_package_by_id(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_service_package_by_id(p_id integer) OWNER TO neondb_owner;

--
-- Name: get_user_contracts(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_user_contracts(p_user_id integer) OWNER TO neondb_owner;

--
-- Name: get_user_data(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_user_data(p_user_account_id integer) OWNER TO neondb_owner;

--
-- Name: get_user_invoices(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.get_user_invoices(p_user_id integer) OWNER TO neondb_owner;

--
-- Name: initialize_consumption_period(date); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.initialize_consumption_period(p_period_start date) OWNER TO neondb_owner;

--
-- Name: insert_cdr(integer, character varying, character varying, timestamp without time zone, integer, integer, character varying, character varying, numeric); Type: FUNCTION; Schema: public; Owner: neondb_owner
--

CREATE FUNCTION public.insert_cdr(p_file_id integer, p_dial_a character varying, p_dial_b character varying, p_start_time timestamp without time zone, p_duration integer, p_service_id integer, p_hplmn character varying, p_vplmn character varying, p_external_charges numeric) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.insert_cdr(p_file_id integer, p_dial_a character varying, p_dial_b character varying, p_start_time timestamp without time zone, p_duration integer, p_service_id integer, p_hplmn character varying, p_vplmn character varying, p_external_charges numeric) OWNER TO neondb_owner;

--
-- Name: login(character varying, character varying); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.login(p_username character varying, p_password character varying) OWNER TO neondb_owner;

--
-- Name: mark_bill_paid(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.mark_bill_paid(p_bill_id integer) OWNER TO neondb_owner;

--
-- Name: mark_msisdn_taken(character varying); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.mark_msisdn_taken(p_msisdn character varying) OWNER TO neondb_owner;

--
-- Name: notify_bill_generation(); Type: FUNCTION; Schema: public; Owner: neondb_owner
--

CREATE FUNCTION public.notify_bill_generation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM pg_notify('generate_bill_event', NEW.id::text);
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.notify_bill_generation() OWNER TO neondb_owner;

--
-- Name: pay_bill(integer, text); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.pay_bill(p_bill_id integer, p_pdf_path text) OWNER TO neondb_owner;

--
-- Name: purchase_addon(integer, integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.purchase_addon(p_contract_id integer, p_service_package_id integer) OWNER TO neondb_owner;

--
-- Name: rate_cdr(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.rate_cdr(p_cdr_id integer) OWNER TO neondb_owner;

--
-- Name: release_msisdn(character varying); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.release_msisdn(p_msisdn character varying) OWNER TO neondb_owner;

--
-- Name: set_file_parsed(integer); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.set_file_parsed(p_file_id integer) OWNER TO neondb_owner;

--
-- Name: trg_restore_credit_on_payment(); Type: FUNCTION; Schema: public; Owner: neondb_owner
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


ALTER FUNCTION public.trg_restore_credit_on_payment() OWNER TO neondb_owner;

--
-- Name: update_rateplan(integer, character varying, numeric, numeric, numeric, numeric, integer[]); Type: FUNCTION; Schema: public; Owner: neondb_owner
--

CREATE FUNCTION public.update_rateplan(p_rateplan_id integer, p_name character varying DEFAULT NULL::character varying, p_ror_voice numeric DEFAULT NULL::numeric, p_ror_data numeric DEFAULT NULL::numeric, p_ror_sms numeric DEFAULT NULL::numeric, p_price numeric DEFAULT NULL::numeric, p_service_package_ids integer[] DEFAULT NULL::integer[]) RETURNS void
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


ALTER FUNCTION public.update_rateplan(p_rateplan_id integer, p_name character varying, p_ror_voice numeric, p_ror_data numeric, p_ror_sms numeric, p_price numeric, p_service_package_ids integer[]) OWNER TO neondb_owner;

--
-- Name: update_service_package(integer, character varying, public.service_type, numeric, integer, numeric, text, boolean); Type: FUNCTION; Schema: public; Owner: neondb_owner
--

CREATE FUNCTION public.update_service_package(p_id integer, p_name character varying, p_type public.service_type, p_amount numeric, p_priority integer, p_price numeric, p_description text, p_is_roaming boolean DEFAULT false) RETURNS TABLE(id integer, name character varying, type public.service_type, amount numeric, priority integer, price numeric, description text, is_roaming boolean)
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.update_service_package(p_id integer, p_name character varying, p_type public.service_type, p_amount numeric, p_priority integer, p_price numeric, p_description text, p_is_roaming boolean) OWNER TO neondb_owner;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.audit_log (
    id integer NOT NULL,
    action character varying(100) NOT NULL,
    actor character varying(100),
    details text,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.audit_log OWNER TO neondb_owner;

--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.audit_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.audit_log_id_seq OWNER TO neondb_owner;

--
-- Name: audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.audit_log_id_seq OWNED BY public.audit_log.id;


--
-- Name: bill; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.bill (
    id integer NOT NULL,
    contract_id integer NOT NULL,
    billing_period_start date NOT NULL,
    billing_period_end date NOT NULL,
    billing_date date NOT NULL,
    recurring_fees numeric(12,2) DEFAULT 0 NOT NULL,
    one_time_fees numeric(12,2) DEFAULT 0 NOT NULL,
    voice_usage bigint DEFAULT 0 NOT NULL,
    data_usage bigint DEFAULT 0 NOT NULL,
    sms_usage bigint DEFAULT 0 NOT NULL,
    ror_charge numeric(12,2) DEFAULT 0 NOT NULL,
    overage_charge numeric(12,2) DEFAULT 0 NOT NULL,
    roaming_charge numeric(12,2) DEFAULT 0 NOT NULL,
    promotional_discount numeric(12,2) DEFAULT 0 NOT NULL,
    taxes numeric(12,2) DEFAULT 0 NOT NULL,
    total_amount numeric(12,2) DEFAULT 0 NOT NULL,
    status public.bill_status DEFAULT 'draft'::public.bill_status NOT NULL,
    is_paid boolean DEFAULT false NOT NULL,
    due_date date,
    paid_amount numeric(12,2) DEFAULT 0.00
);


ALTER TABLE public.bill OWNER TO neondb_owner;

--
-- Name: bill_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.bill_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bill_id_seq OWNER TO neondb_owner;

--
-- Name: bill_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.bill_id_seq OWNED BY public.bill.id;


--
-- Name: cdr; Type: TABLE; Schema: public; Owner: neondb_owner
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


ALTER TABLE public.cdr OWNER TO neondb_owner;

--
-- Name: cdr_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.cdr_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cdr_id_seq OWNER TO neondb_owner;

--
-- Name: cdr_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.cdr_id_seq OWNED BY public.cdr.id;


--
-- Name: contract; Type: TABLE; Schema: public; Owner: neondb_owner
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


ALTER TABLE public.contract OWNER TO neondb_owner;

--
-- Name: contract_addon; Type: TABLE; Schema: public; Owner: neondb_owner
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


ALTER TABLE public.contract_addon OWNER TO neondb_owner;

--
-- Name: contract_addon_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.contract_addon_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.contract_addon_id_seq OWNER TO neondb_owner;

--
-- Name: contract_addon_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.contract_addon_id_seq OWNED BY public.contract_addon.id;


--
-- Name: contract_consumption; Type: TABLE; Schema: public; Owner: neondb_owner
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


ALTER TABLE public.contract_consumption OWNER TO neondb_owner;

--
-- Name: contract_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.contract_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.contract_id_seq OWNER TO neondb_owner;

--
-- Name: contract_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.contract_id_seq OWNED BY public.contract.id;


--
-- Name: file; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.file (
    id integer NOT NULL,
    parsed_flag boolean DEFAULT false NOT NULL,
    file_path text NOT NULL
);


ALTER TABLE public.file OWNER TO neondb_owner;

--
-- Name: file_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.file_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.file_id_seq OWNER TO neondb_owner;

--
-- Name: file_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.file_id_seq OWNED BY public.file.id;


--
-- Name: invoice; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.invoice (
    id integer NOT NULL,
    bill_id integer NOT NULL,
    pdf_path text,
    generation_date timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.invoice OWNER TO neondb_owner;

--
-- Name: invoice_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.invoice_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.invoice_id_seq OWNER TO neondb_owner;

--
-- Name: invoice_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.invoice_id_seq OWNED BY public.invoice.id;


--
-- Name: msisdn_pool; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.msisdn_pool (
    id integer NOT NULL,
    msisdn character varying(20) NOT NULL,
    is_available boolean DEFAULT true NOT NULL
);


ALTER TABLE public.msisdn_pool OWNER TO neondb_owner;

--
-- Name: msisdn_pool_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.msisdn_pool_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.msisdn_pool_id_seq OWNER TO neondb_owner;

--
-- Name: msisdn_pool_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.msisdn_pool_id_seq OWNED BY public.msisdn_pool.id;


--
-- Name: onetime_fee; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.onetime_fee (
    id integer NOT NULL,
    contract_id integer,
    fee_type character varying(50) NOT NULL,
    amount numeric(12,2) NOT NULL,
    description text,
    applied_date date DEFAULT CURRENT_DATE,
    bill_id integer
);


ALTER TABLE public.onetime_fee OWNER TO neondb_owner;

--
-- Name: onetime_fee_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.onetime_fee_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.onetime_fee_id_seq OWNER TO neondb_owner;

--
-- Name: onetime_fee_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.onetime_fee_id_seq OWNED BY public.onetime_fee.id;


--
-- Name: payment; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.payment (
    id integer NOT NULL,
    bill_id integer,
    amount numeric(12,2) NOT NULL,
    payment_method character varying(50),
    payment_date timestamp without time zone DEFAULT now(),
    transaction_id character varying(100)
);


ALTER TABLE public.payment OWNER TO neondb_owner;

--
-- Name: payment_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.payment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.payment_id_seq OWNER TO neondb_owner;

--
-- Name: payment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.payment_id_seq OWNED BY public.payment.id;


--
-- Name: rateplan; Type: TABLE; Schema: public; Owner: neondb_owner
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


ALTER TABLE public.rateplan OWNER TO neondb_owner;

--
-- Name: rateplan_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.rateplan_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rateplan_id_seq OWNER TO neondb_owner;

--
-- Name: rateplan_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.rateplan_id_seq OWNED BY public.rateplan.id;


--
-- Name: rateplan_service_package; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.rateplan_service_package (
    rateplan_id integer NOT NULL,
    service_package_id integer NOT NULL
);


ALTER TABLE public.rateplan_service_package OWNER TO neondb_owner;

--
-- Name: rejected_cdr; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.rejected_cdr (
    id integer NOT NULL,
    file_id integer,
    dial_a character varying(20),
    dial_b character varying(20),
    start_time timestamp without time zone,
    duration integer,
    service_id integer,
    rejection_reason character varying(255),
    rejected_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.rejected_cdr OWNER TO neondb_owner;

--
-- Name: rejected_cdr_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.rejected_cdr_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rejected_cdr_id_seq OWNER TO neondb_owner;

--
-- Name: rejected_cdr_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.rejected_cdr_id_seq OWNED BY public.rejected_cdr.id;


--
-- Name: ror_contract; Type: TABLE; Schema: public; Owner: neondb_owner
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


ALTER TABLE public.ror_contract OWNER TO neondb_owner;

--
-- Name: service_package; Type: TABLE; Schema: public; Owner: neondb_owner
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


ALTER TABLE public.service_package OWNER TO neondb_owner;

--
-- Name: service_package_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.service_package_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.service_package_id_seq OWNER TO neondb_owner;

--
-- Name: service_package_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.service_package_id_seq OWNED BY public.service_package.id;


--
-- Name: user_account; Type: TABLE; Schema: public; Owner: neondb_owner
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


ALTER TABLE public.user_account OWNER TO neondb_owner;

--
-- Name: user_account_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.user_account_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_account_id_seq OWNER TO neondb_owner;

--
-- Name: user_account_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.user_account_id_seq OWNED BY public.user_account.id;


--
-- Name: audit_log id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.audit_log ALTER COLUMN id SET DEFAULT nextval('public.audit_log_id_seq'::regclass);


--
-- Name: bill id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.bill ALTER COLUMN id SET DEFAULT nextval('public.bill_id_seq'::regclass);


--
-- Name: cdr id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.cdr ALTER COLUMN id SET DEFAULT nextval('public.cdr_id_seq'::regclass);


--
-- Name: contract id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.contract ALTER COLUMN id SET DEFAULT nextval('public.contract_id_seq'::regclass);


--
-- Name: contract_addon id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.contract_addon ALTER COLUMN id SET DEFAULT nextval('public.contract_addon_id_seq'::regclass);


--
-- Name: file id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.file ALTER COLUMN id SET DEFAULT nextval('public.file_id_seq'::regclass);


--
-- Name: invoice id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.invoice ALTER COLUMN id SET DEFAULT nextval('public.invoice_id_seq'::regclass);


--
-- Name: msisdn_pool id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.msisdn_pool ALTER COLUMN id SET DEFAULT nextval('public.msisdn_pool_id_seq'::regclass);


--
-- Name: onetime_fee id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.onetime_fee ALTER COLUMN id SET DEFAULT nextval('public.onetime_fee_id_seq'::regclass);


--
-- Name: payment id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.payment ALTER COLUMN id SET DEFAULT nextval('public.payment_id_seq'::regclass);


--
-- Name: rateplan id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.rateplan ALTER COLUMN id SET DEFAULT nextval('public.rateplan_id_seq'::regclass);


--
-- Name: rejected_cdr id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.rejected_cdr ALTER COLUMN id SET DEFAULT nextval('public.rejected_cdr_id_seq'::regclass);


--
-- Name: service_package id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.service_package ALTER COLUMN id SET DEFAULT nextval('public.service_package_id_seq'::regclass);


--
-- Name: user_account id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.user_account ALTER COLUMN id SET DEFAULT nextval('public.user_account_id_seq'::regclass);


--
-- Data for Name: audit_log; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.audit_log (id, action, actor, details, created_at) FROM stdin;
1	BILL_GENERATED	SYSTEM	Generated bill #358 for MSISDN 201000000001	2026-04-30 01:31:45.158197
2	BILL_GENERATED	SYSTEM	Generated bill #359 for MSISDN 201000000002	2026-04-30 01:41:17.551872
3	BILL_GENERATED	SYSTEM	Generated bill #361 for MSISDN 201000000001	2026-04-30 01:43:53.797958
\.


--
-- Data for Name: bill; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.bill (id, contract_id, billing_period_start, billing_period_end, billing_date, recurring_fees, one_time_fees, voice_usage, data_usage, sms_usage, ror_charge, overage_charge, roaming_charge, promotional_discount, taxes, total_amount, status, is_paid, due_date, paid_amount) FROM stdin;
349	200	2026-04-01	2026-04-30	2026-04-30	950.00	0.00	229	298	12	0.00	58.74	275.09	0.00	179.74	1463.57	paid	t	2026-05-14	0.00
185	21	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
186	22	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
187	23	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
188	24	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
189	25	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
190	26	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
191	27	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
192	28	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
193	29	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
194	30	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
195	31	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
196	32	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
197	33	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
198	34	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
199	35	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
200	36	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
201	37	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
202	38	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
203	39	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
204	40	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
205	41	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
206	42	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
207	43	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
208	44	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
209	45	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
210	46	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
211	47	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
212	48	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
213	49	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
214	50	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
215	51	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
216	52	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
217	53	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
218	54	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
219	55	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
220	56	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
221	57	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
222	58	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
223	59	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
224	60	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
225	61	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
226	62	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
227	63	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
228	64	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
229	65	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
230	66	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
231	67	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
232	68	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
233	69	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
234	70	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
235	71	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
236	72	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
237	73	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
238	74	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
239	75	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
240	76	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
241	77	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
242	78	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
243	79	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
244	80	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
245	81	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
246	82	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
247	83	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
248	84	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
249	85	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
250	86	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
251	87	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
319	184	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	461	3736	73	0.00	131.53	207.77	0.00	99.30	808.60	paid	t	2026-05-13	0.00
320	185	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	129	2569	45	0.00	80.86	353.99	0.00	112.68	917.53	paid	t	2026-05-13	0.00
321	186	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	452	3142	77	0.00	126.40	291.56	0.00	69.01	561.97	paid	t	2026-05-13	0.00
322	187	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	317	4645	78	0.00	4.97	288.95	0.00	174.15	1418.07	paid	t	2026-05-13	0.00
323	188	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	383	2113	100	0.00	130.61	20.99	0.00	31.72	258.32	paid	t	2026-05-13	0.00
324	189	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	57	1642	70	0.00	108.51	269.89	0.00	104.78	853.18	paid	t	2026-05-13	0.00
325	190	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	243	3029	87	0.00	73.47	300.33	0.00	62.83	511.63	paid	t	2026-05-13	0.00
326	191	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	486	128	93	0.00	61.11	235.70	0.00	93.35	760.16	paid	t	2026-05-13	0.00
327	192	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	156	4730	16	0.00	21.49	51.48	0.00	20.72	168.69	paid	t	2026-05-13	0.00
328	193	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	401	2938	88	0.00	50.63	59.37	0.00	67.20	547.20	paid	t	2026-05-13	0.00
329	194	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	453	151	40	0.00	104.52	239.06	0.00	58.60	477.18	paid	t	2026-05-13	0.00
330	195	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	332	2074	81	0.00	1.41	343.97	0.00	100.15	815.53	paid	t	2026-05-13	0.00
331	196	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	142	3711	36	0.00	49.21	79.76	0.00	69.86	568.83	paid	t	2026-05-13	0.00
332	197	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	99	2115	73	0.00	30.82	99.58	0.00	70.06	570.46	paid	t	2026-05-13	0.00
333	198	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	317	949	30	0.00	88.99	243.88	0.00	98.40	801.27	paid	t	2026-05-13	0.00
334	199	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	350	2644	70	0.00	50.89	33.30	0.00	144.79	1178.98	paid	t	2026-05-13	0.00
335	170	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	278	2949	88	0.00	35.18	63.92	0.00	65.67	534.77	paid	t	2026-05-13	0.00
336	171	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	79	794	67	0.00	123.15	190.46	0.00	95.71	779.32	paid	t	2026-05-13	0.00
337	172	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	129	4945	76	0.00	36.38	183.14	0.00	82.53	672.05	paid	t	2026-05-13	0.00
338	173	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	152	805	28	0.00	11.30	372.81	0.00	105.58	859.69	paid	t	2026-05-13	0.00
339	174	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	237	2466	30	0.00	35.23	264.50	0.00	52.46	427.19	paid	t	2026-05-13	0.00
340	175	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	401	1995	60	0.00	75.23	303.75	0.00	63.56	517.54	paid	t	2026-05-13	0.00
341	176	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	375	4702	88	0.00	48.86	110.51	0.00	155.31	1264.68	paid	t	2026-05-13	0.00
342	177	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	173	3600	97	0.00	119.37	217.05	0.00	98.90	805.32	paid	t	2026-05-13	0.00
343	178	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	242	3068	95	0.00	11.91	286.63	0.00	93.60	762.14	paid	t	2026-05-13	0.00
344	179	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	322	4807	10	0.00	85.91	271.04	0.00	182.97	1489.92	paid	t	2026-05-13	0.00
345	180	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	160	354	88	0.00	108.96	396.40	0.00	203.75	1659.11	paid	t	2026-05-13	0.00
346	181	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	275	1463	92	0.00	60.55	301.42	0.00	102.48	834.45	paid	t	2026-05-13	0.00
347	182	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	260	1040	34	0.00	25.83	363.31	0.00	64.98	529.12	paid	t	2026-05-13	0.00
348	110	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	336	1397	47	0.00	146.09	50.20	0.00	160.48	1306.77	paid	t	2026-05-13	0.00
34	50	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
35	52	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
36	53	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
37	54	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
38	56	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
39	57	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
40	59	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
41	60	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
42	61	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
43	62	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
44	63	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
45	65	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
46	66	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
47	67	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
48	68	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
49	69	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
50	70	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
51	71	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
52	72	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
53	73	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
54	74	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
55	75	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
56	77	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
57	79	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
58	80	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
59	82	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
60	84	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
61	85	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
62	86	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
63	87	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
64	88	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
65	92	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
66	93	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
67	94	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
68	95	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
69	96	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
70	97	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
71	100	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
72	101	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
73	102	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
74	103	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
75	104	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
76	105	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
77	106	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
78	107	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
79	108	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
80	109	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
81	110	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
82	111	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
83	112	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
84	113	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
85	115	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
86	116	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
87	118	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
88	120	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
89	121	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
90	122	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
91	123	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
92	124	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
93	125	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
94	126	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
95	131	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
96	132	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
97	133	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
98	135	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
99	136	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
100	137	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
101	139	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
271	1	2026-02-01	2026-02-28	2026-03-01	75.00	0.69	280	0	38	0.00	0.00	0.00	0.00	10.50	86.19	paid	t	2026-03-15	0.00
272	2	2026-02-01	2026-02-28	2026-03-01	370.00	0.69	580	1900	72	0.00	0.00	0.00	0.00	51.80	422.49	paid	t	2026-03-15	0.00
273	3	2026-02-01	2026-02-28	2026-03-01	75.00	0.69	150	0	18	0.00	0.00	0.00	0.00	10.50	86.19	paid	t	2026-03-15	0.00
274	4	2026-02-01	2026-02-28	2026-03-01	370.00	0.69	410	1400	50	0.00	0.00	0.00	0.00	51.80	422.49	paid	t	2026-03-15	0.00
275	5	2026-02-01	2026-02-28	2026-03-01	75.00	0.69	80	0	10	0.00	0.00	0.00	0.00	10.50	86.19	paid	t	2026-03-15	0.00
276	6	2026-02-01	2026-02-28	2026-03-01	370.00	0.69	690	2800	95	0.00	0.00	0.00	0.00	51.80	422.49	paid	t	2026-03-15	0.00
277	7	2026-02-01	2026-02-28	2026-03-01	75.00	0.69	190	0	25	0.00	0.00	0.00	0.00	10.50	86.19	paid	t	2026-03-15	0.00
278	8	2026-02-01	2026-02-28	2026-03-01	370.00	0.69	350	1200	45	0.00	0.00	0.00	0.00	51.80	422.49	paid	t	2026-03-15	0.00
279	9	2026-02-01	2026-02-28	2026-03-01	75.00	0.69	120	0	15	0.00	0.00	0.00	0.00	10.50	86.19	paid	t	2026-03-15	0.00
280	10	2026-02-01	2026-02-28	2026-03-01	370.00	0.69	470	1750	62	0.00	0.00	0.00	0.00	51.80	422.49	paid	t	2026-03-15	0.00
281	11	2026-02-01	2026-02-28	2026-03-01	75.00	0.69	820	0	175	10.00	0.00	0.00	0.00	6.07	66.76	paid	t	2026-03-15	0.00
282	12	2026-02-01	2026-02-28	2026-03-01	370.00	0.69	260	800	30	0.00	0.00	0.00	0.00	51.80	422.49	paid	t	2026-03-15	0.00
283	14	2026-02-01	2026-02-28	2026-03-01	370.00	0.69	390	1050	52	0.00	0.00	0.00	0.00	51.80	422.49	paid	t	2026-03-15	0.00
284	15	2026-02-01	2026-02-28	2026-03-01	950.00	0.69	750	3500	130	0.00	0.00	0.00	0.00	133.00	1083.69	paid	t	2026-03-15	0.00
285	16	2026-02-01	2026-02-28	2026-03-01	950.00	0.69	880	4200	160	5.00	0.00	0.00	0.00	35.47	390.16	paid	t	2026-03-15	0.00
286	17	2026-02-01	2026-02-28	2026-03-01	370.00	0.69	310	950	42	0.00	0.00	0.00	0.00	51.80	422.49	paid	t	2026-03-15	0.00
102	140	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
103	141	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
104	142	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
105	144	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
106	145	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
107	147	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
108	148	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
109	149	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
111	151	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
112	152	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
113	153	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
114	154	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
115	155	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
116	156	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
117	157	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
118	158	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
119	160	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
120	162	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
121	163	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
122	164	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
123	165	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
124	166	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
125	167	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
127	7	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
128	9	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
129	12	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
130	15	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
131	16	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
132	17	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
133	20	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
134	25	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
135	28	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
136	31	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
137	46	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
138	47	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
139	51	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
140	55	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
141	64	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
142	76	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
143	78	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
2	3	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
3	4	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
4	5	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
5	6	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
6	8	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
7	11	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
8	13	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
9	14	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
10	19	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
11	21	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
12	22	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
13	23	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
14	24	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
15	26	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
16	27	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
17	29	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
18	30	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
19	32	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
20	33	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
21	34	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
22	35	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
23	36	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
24	37	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
25	38	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
26	39	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
27	40	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
28	41	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
29	43	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
30	44	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
31	45	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
32	48	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
33	49	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
144	81	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
145	83	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
146	89	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
147	98	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
148	99	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
149	114	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
150	117	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
151	119	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
110	150	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
152	127	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
153	128	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
154	130	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
155	134	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
156	143	2026-03-01	2026-03-31	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
157	159	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
158	161	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
159	168	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
160	58	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
161	90	2026-03-01	2026-03-31	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
162	10	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
163	42	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
164	129	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
165	146	2026-03-01	2026-03-31	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
166	1	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
167	2	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
168	3	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
169	4	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
170	5	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
171	6	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
172	7	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
173	8	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
174	9	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
175	10	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
176	11	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
177	12	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
178	13	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
179	14	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
180	15	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
181	16	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
182	17	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
183	19	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
184	20	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
252	88	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
253	89	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
254	90	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
255	92	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
256	93	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
257	94	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
258	95	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
259	96	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
260	97	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
261	98	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
262	99	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
263	100	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
264	101	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
265	102	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
266	103	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
267	104	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
268	105	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
269	106	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
270	107	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
288	108	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
289	109	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
290	111	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
291	116	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
292	122	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
293	123	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
294	124	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
295	131	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
296	136	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
297	137	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
298	139	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
299	149	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
300	151	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
301	152	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
302	162	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
303	164	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
304	165	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
305	114	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
306	117	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
307	119	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
308	127	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
309	128	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t	2026-05-13	0.00
310	130	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-13	0.00
311	134	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	15	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t	2026-05-13	0.00
312	143	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	233	524	24	0.00	16.81	365.14	0.00	63.97	520.92	paid	t	2026-05-13	0.00
313	159	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	476	3761	79	0.00	11.96	289.49	0.00	175.20	1426.65	paid	t	2026-05-13	0.00
314	161	2026-04-01	2026-04-30	2026-04-29	950.00	0.00	289	1804	73	0.00	4.98	156.34	0.00	155.58	1266.90	paid	t	2026-05-13	0.00
315	168	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	231	2676	30	0.00	13.08	154.91	0.00	75.32	613.31	paid	t	2026-05-13	0.00
316	129	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	404	1203	48	0.00	78.50	131.61	0.00	81.22	661.33	paid	t	2026-05-13	0.00
317	146	2026-04-01	2026-04-30	2026-04-29	370.00	0.00	403	2429	75	0.00	88.57	93.27	0.00	77.26	629.10	paid	t	2026-05-13	0.00
318	183	2026-04-01	2026-04-30	2026-04-29	75.00	0.00	178	3224	88	0.00	20.66	105.69	0.00	28.19	229.54	paid	t	2026-05-13	0.00
364	2	2026-03-01	2026-03-31	2026-04-30	370.00	0.00	1500	76251151872	151	0.00	5.35	1640.94	0.00	282.28	2298.57	issued	f	2026-05-14	0.00
365	112	2026-04-01	2026-04-30	2026-04-30	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f	2026-05-14	0.00
363	1	2026-03-01	2026-03-31	2026-04-30	75.00	150.00	9900	18790481920	63	0.00	28.00	900.00	0.00	161.42	1314.42	paid	t	2026-05-14	0.00
366	113	2026-04-01	2026-04-30	2026-04-30	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t	2026-05-14	0.00
\.


--
-- Data for Name: cdr; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.cdr (id, file_id, dial_a, dial_b, start_time, duration, service_id, hplmn, vplmn, external_charges, rated_flag, rated_service_id) FROM stdin;
1	1	201193975708	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
313	4	201000000039	facebook.com	2026-04-05 11:03:15	1	2	\N	\N	0.00	t	\N
2	1	201193975708	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
528	9	201000000048	201090000001	2026-04-12 19:41:46	1408	1	\N	\N	0.00	t	4
3	1	201193975708	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
314	4	201000000011	whatsapp.net	2026-04-20 07:16:15	1	2	\N	\N	0.00	t	\N
4	1	201291490356	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
782	1	201000000002	201090000001	2026-04-27 02:27:08	1492	5	EGYVO	USA01	0.00	t	\N
5	1	201291490356	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
315	4	201000000016	facebook.com	2026-04-05 12:28:15	1	2	\N	\N	0.00	t	\N
6	1	201291490356	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
529	9	201000000048	201090000002	2026-04-11 21:47:46	3199	1	\N	\N	0.00	t	4
7	1	201573560989	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
316	4	201000000040	201090000002	2026-04-11 17:55:15	1910	1	\N	\N	0.00	t	4
8	1	201573560989	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
1093	12	201000000001	201090000001	2026-04-18 23:48:24	4977	1	\N	\N	16.60	t	\N
9	1	201573560989	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
317	4	201000000015	201090000002	2026-04-19 08:45:15	1545	1	\N	\N	1.30	t	\N
10	1	201568820914	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
530	9	201000000026	201000000008	2026-04-14 18:13:46	1	3	\N	\N	0.00	t	4
11	1	201568820914	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
318	4	201000000019	201223344556	2026-04-09 03:41:15	42	1	\N	\N	0.00	t	4
12	1	201568820914	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
783	1	201000000002	201090000002	2026-04-27 06:35:08	2582	1	EGYVO		4.40	t	\N
13	1	201690095272	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
319	4	201000000014	201000000008	2026-04-25 11:56:15	3168	1	\N	\N	5.30	t	\N
14	1	201690095272	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
531	9	201000000025	201223344556	2026-04-29 17:11:46	1	3	\N	\N	0.00	t	4
15	1	201690095272	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
320	4	201000000012	youtube.com	2026-04-16 22:43:15	1	2	\N	\N	0.00	t	\N
16	1	201538007758	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
1425	16	201000000032	201090000001	2026-04-04 19:32:42	1	3	\N	\N	0.00	t	3
17	1	201538007758	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
321	4	201000000021	whatsapp.net	2026-04-07 01:38:15	1	2	\N	\N	0.00	t	4
18	1	201538007758	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
532	9	201130026448	facebook.com	2026-04-20 16:41:46	1	2	\N	\N	0.00	t	\N
19	1	201313455535	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
322	4	201000000021	youtube.com	2026-04-04 10:17:15	1	2	\N	\N	0.00	t	4
20	1	201313455535	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
784	1	201000000002	fmrz-telecom.net	2026-04-06 20:29:08	854391012	6	EGYVO	GER01	0.00	t	\N
21	1	201313455535	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
323	4	201000000041	google.com	2026-04-29 03:54:15	1	2	\N	\N	0.00	t	\N
22	1	201336493947	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
533	9	201456036855	201090000001	2026-04-15 08:48:46	2125	1	\N	\N	3.60	t	\N
23	1	201336493947	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
324	4	201000000039	google.com	2026-04-25 16:13:15	1	2	\N	\N	0.00	t	\N
24	1	201336493947	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
1094	12	201000000001	whatsapp.net	2026-04-14 16:43:24	1868	2	\N	\N	0.00	t	\N
25	1	201236262234	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
325	4	201000000009	201090000003	2026-04-04 06:29:15	599	1	\N	\N	2.00	t	\N
26	1	201236262234	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
534	9	201884002998	201090000001	2026-03-30 22:51:46	2640	1	\N	\N	0.00	t	1
27	1	201236262234	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
326	4	201000000002	fmrz-telecom.net	2026-04-18 17:21:15	1	2	\N	\N	0.00	t	\N
28	1	201946234738	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
785	1	201000000002	google.com	2026-04-26 12:42:08	1855195000	2	EGYVO		0.09	t	\N
29	1	201946234738	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
327	4	201000000029	youtube.com	2026-04-02 09:42:15	1	2	\N	\N	0.00	t	4
30	1	201946234738	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
535	9	201000000037	201223344556	2026-04-17 08:01:46	1639	1	\N	\N	0.00	t	1
31	1	201972954141	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
328	4	201000000004	facebook.com	2026-04-13 19:20:15	1	2	\N	\N	0.00	t	\N
32	1	201972954141	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
33	1	201972954141	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
329	4	201000000016	201090000002	2026-04-21 19:52:15	1	3	\N	\N	0.01	t	\N
34	1	201393015335	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
536	9	201000000003	201090000002	2026-04-21 09:02:46	3582	1	\N	\N	12.00	t	\N
35	1	201393015335	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
330	4	201000000023	fmrz-telecom.net	2026-04-23 03:18:15	1	2	\N	\N	0.00	t	\N
36	1	201393015335	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
786	1	201000000002	201000000008	2026-04-14 16:26:08	5463	1	EGYVO		9.20	t	\N
37	1	201130026448	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
331	4	201000000039	201090000002	2026-04-26 02:17:15	2487	1	\N	\N	0.00	t	1
537	9	201000000001	201090000001	2026-04-15 09:33:46	1456	1	\N	\N	5.00	t	\N
332	4	201000000001	google.com	2026-04-05 05:26:15	1	2	\N	\N	0.00	t	\N
333	4	201000000034	fmrz-telecom.net	2026-04-24 01:41:15	1	2	\N	\N	0.00	t	4
38	1	201130026448	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
1095	12	201000000001	201000000008	2026-04-03 05:34:24	1	3	\N	\N	0.05	t	\N
39	1	201130026448	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
334	4	201000000005	201223344556	2026-04-08 11:51:15	2303	1	\N	\N	7.80	t	\N
40	1	201924767903	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
538	9	201259012646	201090000001	2026-04-23 12:53:46	1361	1	\N	\N	2.30	t	\N
41	1	201924767903	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
335	4	201000000016	201223344556	2026-04-01 17:50:15	1	3	\N	\N	0.01	t	\N
42	1	201924767903	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
787	1	201000000002	201090000001	2026-04-20 07:13:08	1	7	EGYVO	UK01	0.00	t	\N
43	1	201818037329	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
336	4	201000000004	201000000008	2026-04-24 16:13:15	1812	1	\N	\N	3.10	t	\N
44	1	201818037329	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
539	9	201000000019	whatsapp.net	2026-04-23 09:22:46	1	2	\N	\N	0.00	t	4
45	1	201818037329	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
337	4	201000000019	201223344556	2026-03-31 17:54:15	3344	1	\N	\N	0.00	t	4
46	1	201277676035	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
1426	16	201000000043	201000000008	2026-04-01 09:55:42	1	3	\N	\N	0.00	t	3
47	1	201277676035	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
338	4	201000000043	201223344556	2026-04-18 05:55:15	1	3	\N	\N	0.00	t	3
48	1	201277676035	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
540	9	201229447201	201223344556	2026-04-05 21:38:46	1	3	\N	\N	0.05	t	\N
49	1	201542776578	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
339	4	201000000048	201000000008	2026-04-16 04:50:15	1	3	\N	\N	0.00	t	4
50	1	201542776578	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
788	1	201000000002	201223344556	2026-04-18 11:29:08	1	3	EGYVO		0.02	t	\N
51	1	201542776578	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
340	4	201000000041	201090000003	2026-04-18 10:02:15	3195	1	\N	\N	0.00	t	1
52	1	201912929712	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
541	9	201229447201	201090000001	2026-04-14 22:39:46	1	3	\N	\N	0.05	t	\N
53	1	201912929712	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
485	8	201650751254	201090000002	2026-04-26 10:02:52	1	3	\N	\N	0.01	t	\N
54	1	201912929712	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
1096	12	201000000001	201223344556	2026-04-05 14:59:24	2677	1	\N	\N	9.00	t	\N
55	1	201772327638	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
486	8	201173680950	201090000001	2026-04-25 14:47:52	492	1	\N	\N	0.90	t	\N
56	1	201772327638	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
542	9	201000000001	201090000002	2026-04-16 02:33:46	2600	1	\N	\N	8.80	t	\N
57	1	201772327638	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
487	8	201633386447	201090000003	2026-04-10 18:49:52	1	3	\N	\N	0.02	t	\N
58	1	201173680950	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
789	1	201000000002	201090000001	2026-04-05 08:19:08	1	7	EGYVO	GER01	0.00	t	\N
59	1	201173680950	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
488	8	201000000015	whatsapp.net	2026-04-02 12:16:52	1	2	\N	\N	0.00	t	\N
60	1	201173680950	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
543	9	201405070503	201000000008	2026-04-15 16:30:46	1506	1	\N	\N	1.30	t	\N
61	1	201807409782	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
489	8	201573560989	whatsapp.net	2026-04-24 19:08:52	1	2	\N	\N	0.00	t	\N
62	1	201807409782	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
63	1	201807409782	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
490	8	201679439439	201000000008	2026-04-25 12:07:52	2060	1	\N	\N	1.75	t	\N
64	1	201456036855	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
544	9	201544739530	fmrz-telecom.net	2026-04-28 21:40:46	1	2	\N	\N	0.00	t	\N
65	1	201456036855	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
491	8	201880747142	201090000002	2026-04-05 03:49:52	2592	1	\N	\N	8.80	t	\N
66	1	201456036855	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
790	1	201000000001	201090000002	2026-04-04 08:01:24	1865	5	EGYVO	UK01	0.00	t	\N
67	1	201420731899	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
492	8	201000000021	201090000001	2026-04-14 01:29:52	1	3	\N	\N	0.00	t	4
68	1	201420731899	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
545	9	201772327638	201090000003	2026-04-11 07:29:46	1	3	\N	\N	0.02	t	\N
69	1	201420731899	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
493	8	201173680950	201090000001	2026-03-31 05:09:52	2918	1	\N	\N	0.00	t	4
70	1	201470072023	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
71	1	201470072023	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
494	8	201690095272	facebook.com	2026-04-16 05:32:52	1	2	\N	\N	0.00	t	\N
72	1	201470072023	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
546	9	201851881403	201223344556	2026-04-21 06:16:46	1	3	\N	\N	0.02	t	\N
73	1	201892594062	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
495	8	201000000036	201090000001	2026-04-27 03:44:52	2917	1	\N	\N	0.00	t	4
74	1	201892594062	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
791	1	201000000001	youtube.com	2026-04-29 02:22:24	910169114	2	EGYVO		0.08	t	\N
75	1	201892594062	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
496	8	201256368244	201090000002	2026-04-17 16:55:52	1	3	\N	\N	0.02	t	\N
547	9	201912929712	201090000002	2026-04-26 19:38:46	2562	1	\N	\N	4.30	t	\N
497	8	201000000015	facebook.com	2026-03-30 21:45:52	1	2	\N	\N	0.00	t	4
792	1	201000000001	201090000001	2026-04-12 16:26:24	1	3	EGYVO		0.05	t	\N
1097	12	201000000001	201223344556	2026-04-17 13:42:24	1	3	\N	\N	0.05	t	\N
76	1	201326784672	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
341	6	201000000039	facebook.com	2026-04-05 11:03:15	1	2	\N	\N	0.00	t	\N
77	1	201326784672	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
548	9	201399521241	201090000001	2026-04-18 01:11:46	1452	1	\N	\N	5.00	t	\N
78	1	201326784672	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
342	6	201000000011	whatsapp.net	2026-04-20 07:16:15	1	2	\N	\N	0.00	t	\N
79	1	201731509325	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
793	1	201000000001	201090000003	2026-04-24 17:36:24	1	7	EGYVO	FRA01	0.00	t	\N
80	1	201731509325	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
343	6	201000000016	facebook.com	2026-04-05 12:28:15	1	2	\N	\N	0.00	t	\N
81	1	201731509325	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
549	9	201665180852	201090000002	2026-04-29 19:30:46	1	3	\N	\N	0.02	t	\N
82	1	201421638665	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
344	6	201000000040	201090000002	2026-04-11 17:55:15	1910	1	\N	\N	0.00	t	4
83	1	201421638665	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
1427	16	201000000014	201090000002	2026-04-28 20:10:42	2838	1	\N	\N	4.80	t	\N
84	1	201421638665	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
345	6	201000000015	201090000002	2026-04-19 08:45:15	1545	1	\N	\N	1.30	t	\N
85	1	201637467208	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
550	9	201399521241	201090000002	2026-04-08 06:46:46	951	1	\N	\N	3.20	t	\N
86	1	201637467208	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
346	6	201000000019	201223344556	2026-04-09 03:41:15	42	1	\N	\N	0.00	t	4
87	1	201637467208	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
794	1	201000000001	201223344556	2026-04-03 06:50:24	1	3	EGYVO		0.05	t	\N
88	1	201742482326	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
347	6	201000000014	201000000008	2026-04-25 11:56:15	3168	1	\N	\N	5.30	t	\N
89	1	201742482326	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
551	9	201470072023	201090000002	2026-04-11 10:51:46	1293	1	\N	\N	1.10	t	\N
90	1	201742482326	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
348	6	201000000012	youtube.com	2026-04-16 22:43:15	1	2	\N	\N	0.00	t	\N
91	1	201529549288	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
1098	12	201000000001	fmrz-telecom.net	2026-04-08 09:27:24	2082	6	\N	\N	0.00	t	\N
92	1	201529549288	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
349	6	201000000021	whatsapp.net	2026-04-07 01:38:15	1	2	\N	\N	0.00	t	4
93	1	201529549288	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
552	9	201544739530	youtube.com	2026-04-29 03:33:46	1	2	\N	\N	0.00	t	\N
94	1	201837344300	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
350	6	201000000021	youtube.com	2026-04-04 10:17:15	1	2	\N	\N	0.00	t	4
95	1	201837344300	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
795	1	201000000001	google.com	2026-04-02 05:58:24	925471084	6	EGYVO	FRA01	0.00	t	\N
96	1	201837344300	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
351	6	201000000041	google.com	2026-04-29 03:54:15	1	2	\N	\N	0.00	t	\N
97	1	201405070503	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
553	9	201742482326	fmrz-telecom.net	2026-04-16 00:06:46	1	2	\N	\N	0.00	t	\N
98	1	201405070503	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
352	6	201000000039	google.com	2026-04-25 16:13:15	1	2	\N	\N	0.00	t	\N
99	1	201405070503	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
100	1	201481351069	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
353	6	201000000009	201090000003	2026-04-04 06:29:15	599	1	\N	\N	2.00	t	\N
101	1	201481351069	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
554	9	201639748141	youtube.com	2026-04-13 00:56:46	1	2	\N	\N	0.00	t	\N
102	1	201481351069	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
354	6	201000000002	fmrz-telecom.net	2026-04-18 17:21:15	1	2	\N	\N	0.00	t	\N
103	1	201880747142	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
796	1	201000000001	201090000003	2026-04-14 16:47:24	2959	1	EGYVO		10.00	t	\N
104	1	201880747142	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
355	6	201000000029	youtube.com	2026-04-02 09:42:15	1	2	\N	\N	0.00	t	4
105	1	201880747142	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
555	9	201277676035	201090000003	2026-04-15 02:24:46	1	3	\N	\N	0.02	t	\N
106	1	201511068195	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
356	6	201000000004	facebook.com	2026-04-13 19:20:15	1	2	\N	\N	0.00	t	\N
107	1	201511068195	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
1099	12	201000000002	201000000008	2026-04-06 23:04:24	810	1	\N	\N	1.40	t	\N
108	1	201511068195	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
357	6	201000000016	201090000002	2026-04-21 19:52:15	1	3	\N	\N	0.01	t	\N
109	1	201193577939	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
556	9	201000000047	whatsapp.net	2026-04-25 18:14:46	1	2	\N	\N	0.00	t	4
110	1	201193577939	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
358	6	201000000023	fmrz-telecom.net	2026-04-23 03:18:15	1	2	\N	\N	0.00	t	\N
111	1	201193577939	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
797	1	201000000001	201090000001	2026-04-07 02:51:24	1	7	EGYVO	USA01	0.00	t	\N
112	1	201905415497	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
359	6	201000000039	201090000002	2026-04-26 02:17:15	2487	1	\N	\N	0.00	t	1
557	9	201650751254	201090000002	2026-04-02 14:15:46	1066	1	\N	\N	0.90	t	\N
360	6	201000000001	google.com	2026-04-05 05:26:15	1	2	\N	\N	0.00	t	\N
361	6	201000000034	fmrz-telecom.net	2026-04-24 01:41:15	1	2	\N	\N	0.00	t	4
113	1	201905415497	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
1428	16	201000000043	201090000001	2026-04-16 23:31:42	2266	1	\N	\N	0.00	t	1
114	1	201905415497	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
362	6	201000000005	201223344556	2026-04-08 11:51:15	2303	1	\N	\N	7.80	t	\N
115	1	201725767736	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
558	9	201432260526	201090000002	2026-04-26 16:38:46	441	1	\N	\N	1.60	t	\N
116	1	201725767736	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
363	6	201000000016	201223344556	2026-04-01 17:50:15	1	3	\N	\N	0.01	t	\N
117	1	201725767736	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
798	1	201000000001	201223344556	2026-04-04 06:58:24	1	3	EGYVO		0.05	t	\N
118	1	201851881403	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
364	6	201000000004	201000000008	2026-04-24 16:13:15	1812	1	\N	\N	3.10	t	\N
119	1	201851881403	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
559	9	201639909693	201090000002	2026-04-22 14:37:46	1237	1	\N	\N	4.20	t	\N
120	1	201851881403	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
365	6	201000000019	201223344556	2026-03-31 17:54:15	3344	1	\N	\N	0.00	t	4
121	1	201399521241	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
1100	12	201000000002	201090000001	2026-04-29 10:06:24	5913	1	\N	\N	9.90	t	\N
122	1	201399521241	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
366	6	201000000043	201223344556	2026-04-18 05:55:15	1	3	\N	\N	0.00	t	3
123	1	201399521241	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
560	9	201000000029	201223344556	2026-04-20 00:42:46	1	3	\N	\N	0.00	t	4
124	1	201850051553	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
367	6	201000000048	201000000008	2026-04-16 04:50:15	1	3	\N	\N	0.00	t	4
125	1	201850051553	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
799	1	201000000001	201000000008	2026-03-31 11:15:24	1	3	EGYVO		0.00	t	3
126	1	201850051553	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
368	6	201000000041	201090000003	2026-04-18 10:02:15	3195	1	\N	\N	0.00	t	1
127	1	201367143168	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
561	9	201529549288	fmrz-telecom.net	2026-04-10 03:51:46	1	2	\N	\N	0.00	t	\N
128	1	201367143168	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
498	8	201000000038	201223344556	2026-04-19 22:53:52	1	3	\N	\N	0.00	t	4
129	1	201367143168	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
130	1	201649032416	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
499	8	201000000008	201000000008	2026-04-11 23:36:52	1	3	\N	\N	0.02	t	\N
131	1	201649032416	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
562	9	201000000026	whatsapp.net	2026-04-03 00:09:46	1	2	\N	\N	0.00	t	4
132	1	201649032416	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
500	8	201000000042	201090000002	2026-04-13 12:16:52	1	3	\N	\N	0.00	t	4
133	1	201373685722	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
800	1	201000000001	201090000001	2026-03-31 08:04:24	1	3	EGYVO		0.00	t	3
134	1	201373685722	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
501	8	201725767736	201090000002	2026-04-11 01:26:52	1	3	\N	\N	0.01	t	\N
135	1	201373685722	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
563	9	201000000034	201000000008	2026-04-17 09:10:46	482	1	\N	\N	0.00	t	4
136	1	201650751254	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
502	8	201000000038	201000000008	2026-04-24 00:13:52	1	3	\N	\N	0.00	t	4
137	1	201650751254	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
138	1	201650751254	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
503	8	201905415497	201090000003	2026-04-25 01:11:52	982	1	\N	\N	1.70	t	\N
139	1	201747010017	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
564	9	201480812037	201090000001	2026-04-19 05:55:46	1	3	\N	\N	0.02	t	\N
140	1	201747010017	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
504	8	201000000010	201000000008	2026-04-21 03:25:52	1828	1	\N	\N	3.10	t	\N
141	1	201747010017	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
801	1	201000000001	201090000003	2026-04-03 09:32:24	49	1	EGYVO		0.20	t	\N
142	1	201806374057	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
505	8	201000000036	201090000001	2026-04-24 18:47:52	1690	1	\N	\N	0.00	t	4
143	1	201806374057	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
565	9	201000000028	whatsapp.net	2026-04-22 23:32:46	1	2	\N	\N	0.00	t	4
144	1	201806374057	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
506	8	201590288456	201000000008	2026-04-05 06:06:52	2678	1	\N	\N	4.50	t	\N
145	1	201699129335	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
146	1	201699129335	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
507	8	201000000028	whatsapp.net	2026-04-08 02:42:52	1	2	\N	\N	0.00	t	4
147	1	201699129335	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
566	9	201511068195	youtube.com	2026-04-17 06:58:46	1	2	\N	\N	0.00	t	\N
148	1	201763359068	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
508	8	201699129335	201000000008	2026-04-12 16:35:52	1	3	\N	\N	0.02	t	\N
149	1	201763359068	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
150	1	201763359068	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
509	8	201000000043	whatsapp.net	2026-04-21 14:25:52	1	2	\N	\N	0.00	t	\N
567	9	201000000019	youtube.com	2026-04-29 06:25:46	1	2	\N	\N	0.00	t	4
510	8	201259012646	201223344556	2026-04-29 02:54:52	1	3	\N	\N	0.02	t	\N
873	10	201000000032	201090000001	2026-04-04 19:32:42	1	3	\N	\N	0.00	t	3
874	10	201000000043	201000000008	2026-04-01 09:55:42	1	3	\N	\N	0.00	t	3
875	10	201000000014	201090000002	2026-04-28 20:10:42	2838	1	\N	\N	4.80	t	\N
802	1	201000000001	201223344556	2026-04-27 17:10:24	4988	5	EGYVO	FRA01	0.00	t	\N
151	1	201639909693	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
369	7	201000000032	201090000001	2026-04-04 19:32:42	1	3	\N	\N	0.00	t	3
152	1	201639909693	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
568	9	201193975708	201000000008	2026-04-28 08:16:46	2790	1	\N	\N	4.70	t	\N
153	1	201639909693	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
370	7	201000000043	201000000008	2026-04-01 09:55:42	1	3	\N	\N	0.00	t	3
154	1	201256368244	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
1101	12	201000000002	facebook.com	2026-04-15 07:54:24	827	2	\N	\N	0.00	t	\N
155	1	201256368244	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
371	7	201000000014	201090000002	2026-04-28 20:10:42	2838	1	\N	\N	4.80	t	\N
156	1	201256368244	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
569	9	201481351069	201223344556	2026-04-28 18:36:46	1636	1	\N	\N	1.40	t	\N
157	1	201639748141	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
372	7	201000000043	201090000001	2026-04-16 23:31:42	2266	1	\N	\N	0.00	t	1
158	1	201639748141	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
803	1	201000000001	201090000002	2026-04-23 21:17:24	1	3	EGYVO		0.05	t	\N
159	1	201639748141	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
373	7	201000000006	whatsapp.net	2026-04-14 05:07:42	1	2	\N	\N	0.00	t	\N
160	1	201544739530	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
570	9	201000000005	facebook.com	2026-04-24 15:40:46	1	2	\N	\N	0.00	t	\N
161	1	201544739530	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
374	7	201000000042	201090000002	2026-04-05 01:14:42	3089	1	\N	\N	0.00	t	4
162	1	201544739530	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
1429	16	201000000006	whatsapp.net	2026-04-14 05:07:42	1	2	\N	\N	0.00	t	\N
163	1	201122438398	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
375	7	201000000029	201090000002	2026-04-15 23:00:42	346	1	\N	\N	0.00	t	4
164	1	201122438398	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
571	9	201259012646	whatsapp.net	2026-04-07 15:52:46	1	2	\N	\N	0.00	t	\N
165	1	201122438398	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
376	7	201000000007	201090000003	2026-04-24 11:41:42	1	3	\N	\N	0.05	t	\N
166	1	201590834655	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
804	1	201000000001	201000000008	2026-04-28 10:13:24	1	3	EGYVO		0.05	t	\N
167	1	201590834655	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
377	7	201000000032	201090000002	2026-04-02 00:20:42	1729	1	\N	\N	0.00	t	1
168	1	201590834655	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
572	9	201000000027	youtube.com	2026-04-09 02:38:46	1	2	\N	\N	0.00	t	4
169	1	201987728795	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
378	7	201000000047	201090000002	2026-04-01 18:56:42	2901	1	\N	\N	0.00	t	4
170	1	201987728795	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
1102	12	201000000002	google.com	2026-04-15 01:40:24	3549	2	\N	\N	0.00	t	\N
171	1	201987728795	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
379	7	201000000047	201090000001	2026-04-13 16:02:42	1	3	\N	\N	0.00	t	4
172	1	201590288456	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
573	9	201731509325	201000000008	2026-03-31 13:26:46	1	3	\N	\N	0.00	t	3
173	1	201590288456	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
380	7	201000000008	201090000003	2026-04-13 03:00:42	453	1	\N	\N	0.80	t	\N
174	1	201590288456	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
805	1	201000000001	201090000002	2026-04-01 01:56:24	1	7	EGYVO	FRA01	0.00	t	\N
175	1	201814479848	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
381	7	201000000042	201223344556	2026-04-18 17:39:42	1	3	\N	\N	0.00	t	4
176	1	201814479848	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
574	9	201000000015	youtube.com	2026-04-11 10:58:46	1	2	\N	\N	0.00	t	\N
177	1	201814479848	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	1
382	7	201000000017	201223344556	2026-04-23 21:53:42	1	3	\N	\N	0.02	t	\N
178	1	201974222870	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
179	1	201974222870	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
383	7	201000000046	fmrz-telecom.net	2026-04-19 18:42:42	1	2	\N	\N	0.00	t	4
180	1	201974222870	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
575	9	201000000022	201090000002	2026-04-25 21:28:46	1	3	\N	\N	0.00	t	4
181	1	201633386447	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
384	7	201000000033	google.com	2026-04-16 22:38:42	1	2	\N	\N	0.00	t	4
182	1	201633386447	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
806	1	201000000001	whatsapp.net	2026-04-25 19:39:24	1151489384	2	EGYVO		0.11	t	\N
183	1	201633386447	201090000000	2026-04-01 10:00:00	300	1	EGYVO	\N	0.00	t	4
385	7	201000000043	201090000003	2026-04-05 12:34:42	2311	1	\N	\N	0.00	t	1
576	9	201000000023	201090000002	2026-04-02 18:43:46	1081	1	\N	\N	0.00	t	1
386	7	201000000029	201090000001	2026-04-07 08:20:42	1766	1	\N	\N	0.00	t	4
1103	12	201000000002	201000000008	2026-04-25 09:50:24	1	7	\N	\N	0.02	t	\N
387	7	201000000025	201090000003	2026-04-17 08:42:42	1	3	\N	\N	0.00	t	4
577	9	201000000003	facebook.com	2026-04-16 22:03:46	1	2	\N	\N	0.00	t	\N
388	7	201000000033	201000000008	2026-04-04 07:50:42	1039	1	\N	\N	0.00	t	4
807	1	201000000001	201000000008	2026-04-28 17:08:24	1	3	EGYVO		0.05	t	\N
389	7	201000000030	201090000001	2026-04-21 06:55:42	1617	1	\N	\N	0.00	t	4
578	9	201772327638	201090000003	2026-04-18 18:26:46	169	1	\N	\N	0.30	t	\N
390	7	201000000026	youtube.com	2026-04-05 04:40:42	1	2	\N	\N	0.00	t	4
391	7	201000000031	201090000003	2026-04-08 02:15:42	1042	1	\N	\N	0.00	t	1
579	9	201000000023	201090000001	2026-04-22 17:25:46	1974	1	\N	\N	0.00	t	1
392	7	201000000038	201090000003	2026-04-18 01:39:42	1	3	\N	\N	0.00	t	4
1430	16	201000000042	201090000002	2026-04-05 01:14:42	3089	1	\N	\N	0.00	t	4
393	7	201000000015	201090000003	2026-04-04 23:02:42	1	3	\N	\N	0.01	t	\N
580	9	201000000024	201090000002	2026-04-09 05:27:46	1	3	\N	\N	0.00	t	3
394	7	201000000035	201090000003	2026-04-21 00:42:42	489	1	\N	\N	0.00	t	1
808	1	201000000001	201000000008	2026-04-17 02:54:24	1	3	EGYVO		0.05	t	\N
395	7	201000000039	201000000008	2026-04-28 13:31:42	1	3	\N	\N	0.00	t	3
581	9	201542776578	google.com	2026-04-17 11:43:46	1	2	\N	\N	0.00	t	\N
396	7	201000000014	201090000002	2026-04-06 00:58:42	1	3	\N	\N	0.02	t	\N
1104	12	201000000002	201223344556	2026-04-07 22:40:24	1	3	\N	\N	0.02	t	\N
397	7	201000000002	201223344556	2026-03-31 07:55:42	877	1	\N	\N	0.00	t	4
582	9	201000000042	201223344556	2026-04-07 15:00:46	1705	1	\N	\N	0.00	t	4
398	7	201000000020	201090000002	2026-04-21 04:26:42	2286	1	\N	\N	0.00	t	4
809	1	201000000001	201223344556	2026-04-09 20:51:24	1	3	EGYVO		0.05	t	\N
399	7	201000000001	201090000002	2026-03-30 22:11:42	1	3	\N	\N	0.00	t	3
583	9	201811678129	201223344556	2026-04-26 09:23:46	1	3	\N	\N	0.05	t	\N
400	7	201000000009	201090000001	2026-04-19 02:03:42	2766	1	\N	\N	9.40	t	\N
401	7	201000000021	fmrz-telecom.net	2026-04-22 08:37:42	1	2	\N	\N	0.00	t	4
584	9	201811678129	201090000003	2026-04-23 21:20:46	1	3	\N	\N	0.05	t	\N
402	7	201000000039	google.com	2026-04-15 04:07:42	1	2	\N	\N	0.00	t	\N
810	1	201000000001	201090000002	2026-04-15 04:12:24	5369	5	EGYVO	USA01	0.00	t	\N
403	8	201742482326	201223344556	2026-04-29 21:05:52	2001	1	\N	\N	1.70	t	\N
585	9	201637467208	201090000002	2026-04-29 04:37:46	1	3	\N	\N	0.01	t	\N
404	8	201573560989	201090000001	2026-04-03 18:18:52	3260	1	\N	\N	5.50	t	\N
1105	12	201000000002	fmrz-telecom.net	2026-04-09 00:44:24	3069	6	\N	\N	0.00	t	\N
405	8	201742482326	201090000001	2026-04-15 11:51:52	2089	1	\N	\N	1.75	t	\N
586	9	201637467208	youtube.com	2026-04-05 16:19:46	1	2	\N	\N	0.00	t	\N
406	8	201000000019	201090000003	2026-04-10 03:30:52	1	3	\N	\N	0.00	t	4
811	1	201000000001	201090000001	2026-04-28 21:43:24	1	7	EGYVO	GER01	0.00	t	\N
407	8	201639748141	201000000008	2026-04-15 14:30:52	2258	1	\N	\N	3.80	t	\N
587	9	201892594062	201223344556	2026-04-19 03:42:46	3283	1	\N	\N	11.00	t	\N
408	8	201000000010	201223344556	2026-04-12 05:31:52	1	3	\N	\N	0.02	t	\N
1431	16	201000000029	201090000002	2026-04-15 23:00:42	346	1	\N	\N	0.00	t	4
409	8	201880747142	201223344556	2026-04-14 15:28:52	3560	1	\N	\N	12.00	t	\N
588	9	201807409782	201090000002	2026-04-17 18:40:46	1	3	\N	\N	0.05	t	\N
410	8	201845026506	201090000001	2026-04-29 07:29:52	1449	1	\N	\N	2.50	t	\N
812	1	201000000001	201090000001	2026-04-03 10:19:24	1	7	EGYVO	FRA01	0.00	t	\N
411	8	201193577939	201090000003	2026-04-08 18:41:52	1	3	\N	\N	0.02	t	\N
589	9	201000000009	201090000003	2026-04-05 23:13:46	1	3	\N	\N	0.05	t	\N
412	8	201814479848	201223344556	2026-04-25 00:52:52	880	1	\N	\N	3.00	t	\N
1106	12	201000000002	youtube.com	2026-04-28 19:51:24	2239	2	\N	\N	0.00	t	\N
413	8	201000000007	201090000003	2026-04-25 11:39:52	1	3	\N	\N	0.05	t	\N
590	9	201538007758	201090000003	2026-04-27 03:22:46	1	3	\N	\N	0.01	t	\N
414	8	201974222870	201000000008	2026-04-22 21:42:52	1	3	\N	\N	0.02	t	\N
813	1	201000000001	201223344556	2026-04-16 13:28:24	1	3	EGYVO		0.05	t	\N
415	8	201818037329	201090000001	2026-04-28 23:27:52	1	3	\N	\N	0.05	t	\N
591	9	201814479848	201090000001	2026-04-06 00:39:46	1	3	\N	\N	0.05	t	\N
416	8	201747010017	201090000002	2026-04-23 05:07:52	1	3	\N	\N	0.02	t	\N
417	8	201529549288	facebook.com	2026-04-03 00:18:52	1	2	\N	\N	0.00	t	\N
592	9	201000000020	201090000002	2026-04-17 04:12:46	1366	1	\N	\N	0.00	t	4
418	8	201000000006	201090000003	2026-04-11 01:15:52	1	3	\N	\N	0.02	t	\N
814	1	201000000001	201000000008	2026-04-03 00:41:24	1	3	EGYVO		0.05	t	\N
419	8	201000000015	201000000008	2026-04-05 17:29:52	1275	1	\N	\N	1.10	t	\N
593	9	201924767903	201090000002	2026-03-31 06:10:46	2832	1	\N	\N	0.00	t	4
420	8	201122438398	facebook.com	2026-04-03 01:43:52	1	2	\N	\N	0.00	t	\N
1107	12	201000000002	google.com	2026-04-15 09:42:24	5097	2	\N	\N	0.00	t	\N
421	8	201130026448	201223344556	2026-04-11 21:09:52	3138	1	\N	\N	10.60	t	\N
594	9	201000000036	201090000002	2026-04-21 01:57:46	1	3	\N	\N	0.00	t	4
422	8	201665180852	facebook.com	2026-04-21 08:22:52	1	2	\N	\N	0.00	t	\N
815	1	201000000001	201090000001	2026-04-26 18:47:24	1	7	EGYVO	UAE01	0.00	t	\N
423	8	201000000003	201090000002	2026-04-26 14:55:52	1	3	\N	\N	0.05	t	\N
595	9	201000000024	201000000008	2026-04-18 19:27:46	1233	1	\N	\N	0.00	t	1
424	8	201486313285	google.com	2026-04-28 03:33:52	1	2	\N	\N	0.00	t	\N
1432	16	201000000007	201090000003	2026-04-24 11:41:42	1	3	\N	\N	0.05	t	\N
425	8	201837344300	201090000003	2026-04-26 00:56:52	1	3	\N	\N	0.01	t	\N
596	9	201000000005	201090000002	2026-04-19 02:56:46	2730	1	\N	\N	9.20	t	\N
426	8	201000000015	google.com	2026-04-13 17:59:52	1	2	\N	\N	0.00	t	\N
816	1	201000000001	201090000001	2026-04-25 16:41:24	1	3	EGYVO		0.05	t	\N
427	8	201807409782	whatsapp.net	2026-04-27 15:16:52	1	2	\N	\N	0.00	t	\N
597	9	201000000028	201090000002	2026-04-15 23:09:46	1736	1	\N	\N	0.00	t	4
428	8	201538007758	google.com	2026-03-31 23:10:52	1	2	\N	\N	0.00	t	4
1108	12	201000000002	youtube.com	2026-04-28 07:25:24	2865	2	\N	\N	0.00	t	\N
429	8	201529549288	youtube.com	2026-04-25 02:20:52	1	2	\N	\N	0.00	t	\N
598	9	201000000001	youtube.com	2026-04-02 12:08:46	1	2	\N	\N	0.00	t	\N
430	8	201000000020	fmrz-telecom.net	2026-04-18 19:10:52	1	2	\N	\N	0.00	t	4
431	8	201742482326	201090000001	2026-04-21 20:06:52	1	3	\N	\N	0.01	t	\N
599	9	201486313285	201090000003	2026-04-07 09:52:46	3042	1	\N	\N	10.20	t	\N
432	8	201481789330	201090000003	2026-04-08 21:08:52	1	3	\N	\N	0.01	t	\N
433	8	201000000025	201000000008	2026-04-10 00:29:52	1	3	\N	\N	0.00	t	4
600	9	201313455535	201090000002	2026-04-22 18:31:46	1	3	\N	\N	0.02	t	\N
434	8	201000000004	201090000003	2026-04-16 01:31:52	1614	1	\N	\N	2.70	t	\N
817	1	201000000001	201000000008	2026-04-29 19:20:24	1	3	EGYVO		0.05	t	\N
435	8	201811678129	201000000008	2026-04-22 07:59:52	1	3	\N	\N	0.05	t	\N
601	9	201130026448	201090000002	2026-04-14 05:57:46	51	1	\N	\N	0.20	t	\N
436	8	201690095272	201223344556	2026-04-28 21:31:52	1	3	\N	\N	0.05	t	\N
1109	12	201000000002	201090000003	2026-03-31 05:25:24	1	3	\N	\N	0.02	t	\N
437	8	201818037329	201090000002	2026-04-27 16:33:52	2773	1	\N	\N	9.40	t	\N
602	9	201000000008	201090000002	2026-04-04 19:34:46	1402	1	\N	\N	2.40	t	\N
438	8	201000000029	201090000003	2026-04-07 22:45:52	3103	1	\N	\N	0.00	t	4
818	1	201000000001	201090000002	2026-04-10 00:43:24	2377	1	EGYVO		8.00	t	\N
439	8	201000000048	201000000008	2026-04-17 09:09:52	1	3	\N	\N	0.00	t	4
603	9	201000000028	201000000008	2026-04-05 08:38:46	1311	1	\N	\N	0.00	t	4
440	8	201000000019	201090000003	2026-04-12 17:12:52	3278	1	\N	\N	0.00	t	4
1433	16	201000000032	201090000002	2026-04-02 00:20:42	1729	1	\N	\N	0.00	t	1
441	8	201193577939	fmrz-telecom.net	2026-04-04 03:59:52	1	2	\N	\N	0.00	t	\N
604	9	201529549288	201090000002	2026-04-24 13:38:46	1949	1	\N	\N	3.30	t	\N
442	8	201000000012	youtube.com	2026-04-12 18:22:52	1	2	\N	\N	0.00	t	\N
819	1	201000000001	201090000003	2026-04-17 14:09:24	1	3	EGYVO		0.05	t	\N
443	8	201000000028	201000000008	2026-04-27 07:47:52	1	3	\N	\N	0.00	t	4
605	9	201000000030	whatsapp.net	2026-04-01 02:23:46	1	2	\N	\N	0.00	t	4
444	8	201590834655	201090000001	2026-04-02 23:24:52	1	3	\N	\N	0.01	t	\N
1110	12	201000000002	201090000002	2026-04-22 18:34:24	4604	1	\N	\N	7.70	t	\N
445	8	201972954141	google.com	2026-04-20 07:51:52	1	2	\N	\N	0.00	t	\N
606	9	201987728795	whatsapp.net	2026-04-07 07:05:46	1	2	\N	\N	0.00	t	\N
446	8	201818037329	201090000003	2026-04-24 11:39:52	983	1	\N	\N	3.40	t	\N
820	1	201000000001	201090000003	2026-04-04 01:22:24	6027	5	EGYVO	UK01	0.00	t	\N
447	8	201639748141	201223344556	2026-04-15 08:54:52	857	1	\N	\N	1.50	t	\N
607	9	201000000038	201090000001	2026-03-31 02:19:46	2995	1	\N	\N	0.00	t	4
448	8	201690095272	google.com	2026-04-21 03:30:52	1	2	\N	\N	0.00	t	\N
449	8	201000000015	whatsapp.net	2026-04-09 04:25:52	1	2	\N	\N	0.00	t	\N
608	9	201000000041	201090000002	2026-04-03 16:46:46	3146	1	\N	\N	0.00	t	1
450	8	201742482326	201090000001	2026-04-09 22:01:52	1951	1	\N	\N	1.65	t	\N
821	1	201000000001	201223344556	2026-04-14 11:42:24	1	3	EGYVO		0.05	t	\N
451	8	201236262234	whatsapp.net	2026-04-17 11:25:52	1	2	\N	\N	0.00	t	\N
609	9	201000000021	youtube.com	2026-04-12 14:14:46	1	2	\N	\N	0.00	t	4
452	8	201851881403	201090000003	2026-04-08 19:14:52	1	3	\N	\N	0.02	t	\N
1111	12	201000000002	201090000002	2026-04-03 22:44:24	5402	1	\N	\N	9.10	t	\N
453	8	201000000021	201000000008	2026-04-19 07:12:52	1	3	\N	\N	0.00	t	4
610	9	201725767736	google.com	2026-04-01 07:30:46	1	2	\N	\N	0.00	t	\N
454	8	201000000021	201090000003	2026-04-12 13:28:52	2422	1	\N	\N	0.00	t	4
822	1	201000000001	youtube.com	2026-04-11 00:46:24	1090195291	2	EGYVO		0.10	t	\N
184	1	201000000001	201000000002	2026-04-01 09:15:00	180	1	EGYVO	\N	0.60	t	\N
185	1	201000000001	201000000003	2026-04-01 14:30:00	1	3	EGYVO	\N	0.05	t	\N
186	1	201000000001	201000000005	2026-04-02 08:00:00	300	1	EGYVO	\N	1.00	t	\N
187	1	201000000001	201000000007	2026-04-03 11:20:00	1	3	EGYVO	\N	0.05	t	\N
188	1	201000000001	201000000009	2026-04-04 10:05:00	240	1	EGYVO	\N	0.80	t	\N
189	1	201000000001	201000000002	2026-04-05 16:45:00	1	3	EGYVO	\N	0.05	t	\N
190	1	201000000001	201000000011	2026-04-07 09:30:00	420	1	EGYVO	\N	1.40	t	\N
191	1	201000000001	201000000013	2026-04-08 13:00:00	1	3	EGYVO	\N	0.05	t	\N
192	1	201000000001	201000000015	2026-04-09 17:20:00	150	1	EGYVO	\N	0.60	t	\N
193	1	201000000001	201000000002	2026-04-10 08:45:00	360	1	EGYVO	\N	1.20	t	\N
194	1	201000000001	201000000003	2026-04-12 12:10:00	1	3	EGYVO	\N	0.05	t	\N
195	1	201000000001	201000000017	2026-04-14 15:30:00	210	1	EGYVO	\N	0.80	t	\N
196	1	201000000001	201000000004	2026-04-16 09:00:00	270	1	EGYVO	\N	1.00	t	\N
197	1	201000000001	201000000006	2026-04-18 14:00:00	1	3	EGYVO	\N	0.05	t	\N
198	1	201000000001	201000000008	2026-04-20 10:30:00	330	1	EGYVO	\N	1.20	t	\N
199	1	201000000002	201000000001	2026-04-01 08:30:00	300	1	EGYVO	\N	0.50	t	\N
200	1	201000000002	201000000004	2026-04-01 10:00:00	500	2	EGYVO	\N	0.00	t	\N
201	1	201000000002	201000000006	2026-04-01 12:00:00	1	3	EGYVO	\N	0.02	t	\N
202	1	201000000002	201000000008	2026-04-02 09:15:00	450	1	EGYVO	\N	0.80	t	\N
203	1	201000000002	201000000010	2026-04-02 14:30:00	750	2	EGYVO	\N	0.00	t	\N
204	1	201000000002	201000000012	2026-04-03 08:00:00	1	3	EGYVO	\N	0.02	t	\N
205	1	201000000002	201000000001	2026-04-04 11:45:00	600	1	EGYVO	\N	1.00	t	\N
206	1	201000000002	201000000014	2026-04-05 15:00:00	1000	2	EGYVO	\N	0.00	t	\N
207	1	201000000002	201000000016	2026-04-06 09:30:00	1	3	EGYVO	\N	0.02	t	\N
208	1	201000000002	201000000018	2026-04-07 13:20:00	480	1	EGYVO	\N	0.80	t	\N
209	1	201000000002	201000000001	2026-04-08 17:00:00	800	2	EGYVO	\N	0.00	t	\N
210	1	201000000002	201000000003	2026-04-09 10:15:00	1	3	EGYVO	\N	0.02	t	\N
211	2	201000000002	201000000001	2026-04-15 10:00:00	180	5	EGYVO	DEUTS	0.00	t	\N
212	2	201000000002	201000000004	2026-04-15 14:30:00	200	6	EGYVO	DEUTS	0.00	t	\N
213	2	201000000002	201000000006	2026-04-16 09:00:00	1	7	EGYVO	DEUTS	0.00	t	\N
455	8	201880747142	google.com	2026-04-08 05:20:52	1	2	\N	\N	0.00	t	\N
611	9	201000000020	201090000003	2026-04-12 06:45:46	1	3	\N	\N	0.00	t	4
456	8	201772327638	201090000002	2026-04-14 07:25:52	2241	1	\N	\N	3.80	t	\N
1434	16	201000000047	201090000002	2026-04-01 18:56:42	2901	1	\N	\N	0.00	t	4
214	2	201000000002	201000000008	2026-04-16 15:45:00	120	5	EGYVO	DEUTS	0.00	t	\N
215	2	201000000002	201000000001	2026-04-17 11:00:00	300	6	EGYVO	DEUTS	0.00	t	\N
216	1	201000000003	201000000001	2026-04-01 09:00:00	120	1	EGYVO	\N	0.40	t	\N
217	1	201000000003	201000000005	2026-04-02 11:30:00	1	3	EGYVO	\N	0.05	t	\N
218	1	201000000003	201000000007	2026-04-04 14:00:00	240	1	EGYVO	\N	0.80	t	\N
219	1	201000000003	201000000009	2026-04-06 16:30:00	1	3	EGYVO	\N	0.05	t	\N
220	1	201000000003	201000000001	2026-04-08 10:15:00	180	1	EGYVO	\N	0.60	t	\N
221	1	201000000003	201000000011	2026-04-10 13:45:00	90	1	EGYVO	\N	0.40	t	\N
222	1	201000000004	201000000002	2026-04-01 08:00:00	360	1	EGYVO	\N	0.60	t	\N
223	1	201000000004	201000000006	2026-04-01 13:00:00	600	2	EGYVO	\N	0.00	t	\N
224	1	201000000004	201000000008	2026-04-02 10:30:00	1	3	EGYVO	\N	0.02	t	\N
225	1	201000000004	201000000010	2026-04-03 15:00:00	420	1	EGYVO	\N	0.70	t	\N
226	1	201000000004	201000000012	2026-04-05 09:45:00	800	2	EGYVO	\N	0.00	t	\N
227	1	201000000004	201000000002	2026-04-07 14:00:00	1	3	EGYVO	\N	0.02	t	\N
228	1	201000000004	201000000014	2026-04-09 11:30:00	540	1	EGYVO	\N	0.90	t	\N
229	1	201000000004	201000000016	2026-04-11 16:00:00	700	2	EGYVO	\N	0.00	t	\N
230	1	201000000005	201000000001	2026-04-01 10:00:00	90	1	EGYVO	\N	0.40	t	\N
231	1	201000000005	201000000003	2026-04-03 12:30:00	1	3	EGYVO	\N	0.05	t	\N
232	1	201000000005	201000000007	2026-04-05 15:45:00	150	1	EGYVO	\N	0.60	t	\N
233	1	201000000005	201000000009	2026-04-08 09:00:00	1	3	EGYVO	\N	0.05	t	\N
234	1	201000000005	201000000001	2026-04-11 11:15:00	120	1	EGYVO	\N	0.40	t	\N
235	2	201000000006	201000000002	2026-04-01 09:30:00	540	1	EGYVO	\N	0.90	t	\N
236	2	201000000006	201000000008	2026-04-01 13:00:00	900	2	EGYVO	\N	0.00	t	\N
237	2	201000000006	201000000010	2026-04-02 08:15:00	1	3	EGYVO	\N	0.02	t	\N
238	2	201000000006	201000000012	2026-04-02 14:00:00	480	1	EGYVO	\N	0.80	t	\N
239	2	201000000006	201000000014	2026-04-03 10:30:00	1100	2	EGYVO	\N	0.00	t	\N
240	2	201000000006	201000000002	2026-04-04 15:45:00	1	3	EGYVO	\N	0.02	t	\N
241	2	201000000006	201000000016	2026-04-05 09:00:00	660	1	EGYVO	\N	1.10	t	\N
242	2	201000000006	201000000018	2026-04-06 12:30:00	850	2	EGYVO	\N	0.00	t	\N
243	2	201000000006	201000000002	2026-04-07 16:00:00	1	3	EGYVO	\N	0.02	t	\N
244	2	201000000006	201000000004	2026-04-08 10:15:00	720	1	EGYVO	\N	1.20	t	\N
245	2	201000000007	201000000001	2026-04-01 08:45:00	60	1	EGYVO	\N	0.20	t	\N
246	2	201000000007	201000000009	2026-04-03 13:30:00	1	3	EGYVO	\N	0.05	t	\N
247	2	201000000007	201000000011	2026-04-05 16:00:00	120	1	EGYVO	\N	0.40	t	\N
248	2	201000000007	201000000001	2026-04-08 10:00:00	180	1	EGYVO	\N	0.60	t	\N
249	2	201000000007	201000000003	2026-04-11 14:15:00	1	3	EGYVO	\N	0.05	t	\N
250	2	201000000007	201000000005	2026-04-14 09:30:00	240	1	EGYVO	\N	0.80	t	\N
251	2	201000000008	201000000002	2026-04-01 10:15:00	300	1	EGYVO	\N	0.50	t	\N
252	2	201000000008	201000000004	2026-04-02 12:00:00	650	2	EGYVO	\N	0.00	t	\N
253	2	201000000008	201000000006	2026-04-03 15:30:00	1	3	EGYVO	\N	0.02	t	\N
254	2	201000000008	201000000010	2026-04-04 09:00:00	420	1	EGYVO	\N	0.70	t	\N
255	2	201000000008	201000000012	2026-04-05 13:45:00	750	2	EGYVO	\N	0.00	t	\N
256	2	201000000008	201000000002	2026-04-07 11:00:00	1	3	EGYVO	\N	0.02	t	\N
257	2	201000000008	201000000014	2026-04-09 16:30:00	390	1	EGYVO	\N	0.70	t	\N
258	2	201000000009	201000000001	2026-04-01 11:00:00	180	1	EGYVO	\N	0.60	t	\N
259	2	201000000009	201000000003	2026-04-03 14:00:00	1	3	EGYVO	\N	0.05	t	\N
260	2	201000000009	201000000005	2026-04-06 09:30:00	150	1	EGYVO	\N	0.60	t	\N
261	2	201000000009	201000000007	2026-04-09 12:45:00	1	3	EGYVO	\N	0.05	t	\N
262	2	201000000010	201000000002	2026-04-01 09:45:00	360	1	EGYVO	\N	0.60	t	\N
263	2	201000000010	201000000004	2026-04-02 13:15:00	700	2	EGYVO	\N	0.00	t	\N
264	2	201000000010	201000000006	2026-04-03 16:00:00	1	3	EGYVO	\N	0.02	t	\N
265	2	201000000010	201000000008	2026-04-04 10:30:00	480	1	EGYVO	\N	0.80	t	\N
266	2	201000000010	201000000012	2026-04-05 14:00:00	900	2	EGYVO	\N	0.00	t	\N
267	2	201000000010	201000000002	2026-04-07 09:15:00	1	3	EGYVO	\N	0.02	t	\N
268	2	201000000010	201000000014	2026-04-09 15:45:00	540	1	EGYVO	\N	0.90	t	\N
269	2	201000000010	201000000016	2026-04-11 11:00:00	800	2	EGYVO	\N	0.00	t	\N
270	1	201000000011	201000000001	2026-04-01 08:00:00	600	1	EGYVO	\N	2.00	t	\N
271	1	201000000011	201000000003	2026-04-02 10:30:00	1	3	EGYVO	\N	0.05	t	\N
272	1	201000000011	201000000005	2026-04-03 14:15:00	480	1	EGYVO	\N	1.60	t	\N
273	1	201000000011	201000000007	2026-04-04 16:45:00	1	3	EGYVO	\N	0.05	t	\N
274	1	201000000011	201000000009	2026-04-05 09:30:00	540	1	EGYVO	\N	1.80	t	\N
275	1	201000000011	201000000001	2026-04-07 13:00:00	1	3	EGYVO	\N	0.05	t	\N
276	1	201000000011	201000000003	2026-04-09 10:15:00	420	1	EGYVO	\N	1.40	t	\N
277	1	201000000011	201000000005	2026-04-11 15:30:00	1	3	EGYVO	\N	0.05	t	\N
278	1	201000000012	201000000002	2026-04-01 11:30:00	270	1	EGYVO	\N	0.50	t	\N
279	1	201000000012	201000000004	2026-04-03 09:00:00	550	2	EGYVO	\N	0.00	t	\N
280	1	201000000012	201000000006	2026-04-05 13:45:00	1	3	EGYVO	\N	0.02	t	\N
281	1	201000000012	201000000008	2026-04-07 16:00:00	330	1	EGYVO	\N	0.60	t	\N
282	1	201000000014	201000000002	2026-04-01 09:00:00	390	1	EGYVO	\N	0.70	t	\N
283	1	201000000014	201000000004	2026-04-02 11:30:00	650	2	EGYVO	\N	0.00	t	\N
284	1	201000000014	201000000006	2026-04-03 14:00:00	1	3	EGYVO	\N	0.02	t	\N
285	1	201000000014	201000000008	2026-04-05 16:30:00	450	1	EGYVO	\N	0.80	t	\N
286	1	201000000014	201000000010	2026-04-07 10:15:00	700	2	EGYVO	\N	0.00	t	\N
287	1	201000000014	201000000002	2026-04-09 13:45:00	1	3	EGYVO	\N	0.02	t	\N
288	2	201000000015	201000000002	2026-04-01 08:00:00	480	1	EGYVO	\N	0.40	t	\N
289	2	201000000015	201000000004	2026-04-01 10:30:00	1200	2	EGYVO	\N	0.00	t	\N
290	2	201000000015	201000000006	2026-04-01 13:00:00	1	3	EGYVO	\N	0.01	t	\N
291	2	201000000015	201000000008	2026-04-02 09:00:00	600	1	EGYVO	\N	0.50	t	\N
292	2	201000000015	201000000010	2026-04-02 14:00:00	1500	2	EGYVO	\N	0.00	t	\N
293	2	201000000015	201000000012	2026-04-03 10:15:00	1	3	EGYVO	\N	0.01	t	\N
294	2	201000000015	201000000002	2026-04-04 15:30:00	720	1	EGYVO	\N	0.60	t	\N
295	2	201000000015	201000000016	2026-04-05 09:45:00	1800	2	EGYVO	\N	0.00	t	\N
296	2	201000000015	201000000002	2026-04-20 10:00:00	240	5	EGYVO	FRANC	0.00	t	\N
297	2	201000000015	201000000004	2026-04-20 14:30:00	400	6	EGYVO	FRANC	0.00	t	\N
298	2	201000000015	201000000006	2026-04-21 09:00:00	1	7	EGYVO	FRANC	0.00	t	\N
299	2	201000000016	201000000002	2026-04-01 09:30:00	600	1	EGYVO	\N	0.50	t	\N
300	2	201000000016	201000000004	2026-04-01 12:00:00	1400	2	EGYVO	\N	0.00	t	\N
301	2	201000000016	201000000006	2026-04-01 15:30:00	1	3	EGYVO	\N	0.01	t	\N
302	2	201000000016	201000000008	2026-04-02 08:30:00	780	1	EGYVO	\N	0.65	t	\N
303	2	201000000016	201000000010	2026-04-02 13:00:00	1600	2	EGYVO	\N	0.00	t	\N
304	2	201000000016	201000000012	2026-04-03 10:00:00	1	3	EGYVO	\N	0.01	t	\N
305	2	201000000016	201000000014	2026-04-03 16:00:00	840	1	EGYVO	\N	0.70	t	\N
306	2	201000000016	201000000002	2026-04-04 11:30:00	1800	2	EGYVO	\N	0.00	t	\N
307	2	201000000017	201000000002	2026-04-01 10:00:00	300	1	EGYVO	\N	0.50	t	\N
308	2	201000000017	201000000004	2026-04-02 12:30:00	600	2	EGYVO	\N	0.00	t	\N
309	2	201000000017	201000000006	2026-04-03 15:00:00	1	3	EGYVO	\N	0.02	t	\N
310	2	201000000017	201000000008	2026-04-05 09:30:00	420	1	EGYVO	\N	0.70	t	\N
311	2	201000000017	201000000010	2026-04-07 14:00:00	750	2	EGYVO	\N	0.00	t	\N
312	2	201000000017	201000000002	2026-04-09 11:15:00	1	3	EGYVO	\N	0.02	t	\N
457	8	201851881403	201000000008	2026-04-25 22:00:52	3160	1	\N	\N	5.30	t	\N
612	9	201884002998	201090000001	2026-04-21 06:36:46	2593	1	\N	\N	8.80	t	\N
458	8	201851881403	201090000002	2026-04-01 18:41:52	120	1	\N	\N	0.20	t	\N
1112	12	201000000002	201090000001	2026-04-09 07:58:24	1	3	\N	\N	0.02	t	\N
459	8	201336493947	201090000003	2026-04-06 05:53:52	1943	1	\N	\N	3.30	t	\N
613	9	201456036855	201090000001	2026-04-18 21:33:46	1927	1	\N	\N	3.30	t	\N
460	8	201000000031	whatsapp.net	2026-04-20 22:33:52	1	2	\N	\N	0.00	t	\N
823	1	201000000001	201223344556	2026-04-26 15:48:24	5385	5	EGYVO	UK01	0.00	t	\N
461	8	201229447201	whatsapp.net	2026-04-17 20:59:52	1	2	\N	\N	0.00	t	\N
614	9	201193577939	whatsapp.net	2026-04-07 21:53:46	1	2	\N	\N	0.00	t	\N
462	8	201946234738	fmrz-telecom.net	2026-04-07 16:24:52	1	2	\N	\N	0.00	t	\N
463	8	201000000014	201090000002	2026-04-27 19:27:52	1	3	\N	\N	0.02	t	\N
615	9	201731509325	201090000002	2026-04-27 20:37:46	2062	1	\N	\N	7.00	t	\N
464	8	201845026506	201000000008	2026-04-12 23:32:52	1	3	\N	\N	0.02	t	\N
824	1	201000000001	201090000001	2026-04-04 12:49:24	1	3	EGYVO		0.05	t	\N
465	8	201000000033	facebook.com	2026-04-24 14:32:52	1	2	\N	\N	0.00	t	4
616	9	201837344300	201090000002	2026-04-24 08:52:46	1	3	\N	\N	0.01	t	\N
466	8	201000000019	201090000002	2026-04-25 20:51:52	1	3	\N	\N	0.00	t	4
1113	12	201000000002	whatsapp.net	2026-04-21 13:20:24	2335	2	\N	\N	0.00	t	\N
467	8	201000000028	whatsapp.net	2026-03-31 22:05:52	1	2	\N	\N	0.00	t	4
617	9	201000000044	youtube.com	2026-04-29 06:28:46	1	2	\N	\N	0.00	t	4
468	8	201639748141	201090000003	2026-04-01 05:22:52	1101	1	\N	\N	1.90	t	\N
825	1	201000000001	201000000008	2026-04-22 15:57:24	1	3	EGYVO		0.05	t	\N
469	8	201912929712	201000000008	2026-04-04 06:50:52	1	3	\N	\N	0.02	t	\N
618	9	201000000002	201223344556	2026-04-22 12:30:46	1	3	\N	\N	0.02	t	\N
470	8	201573560989	fmrz-telecom.net	2026-04-23 22:44:52	1	2	\N	\N	0.00	t	\N
1435	16	201000000047	201090000001	2026-04-13 16:02:42	1	3	\N	\N	0.00	t	4
471	8	201818037329	201090000001	2026-04-17 00:39:52	1	3	\N	\N	0.05	t	\N
619	9	201000000014	facebook.com	2026-04-02 23:53:46	1	2	\N	\N	0.00	t	\N
472	8	201000000022	201090000003	2026-04-19 08:33:52	739	1	\N	\N	0.00	t	4
826	1	201000000001	facebook.com	2026-04-23 13:06:24	1836016071	6	EGYVO	USA01	0.00	t	\N
473	8	201000000028	facebook.com	2026-04-16 19:40:52	1	2	\N	\N	0.00	t	4
620	9	201880747142	facebook.com	2026-04-29 07:19:46	1	2	\N	\N	0.00	t	\N
474	8	201650751254	fmrz-telecom.net	2026-04-23 21:57:52	1	2	\N	\N	0.00	t	\N
1114	12	201000000002	201090000002	2026-04-03 06:48:24	1	3	\N	\N	0.02	t	\N
475	8	201544739530	201090000002	2026-04-05 10:06:52	1	3	\N	\N	0.02	t	\N
621	9	201639909693	facebook.com	2026-04-14 14:31:46	1	2	\N	\N	0.00	t	\N
476	8	201972954141	201000000008	2026-04-26 09:05:52	3432	1	\N	\N	11.60	t	\N
827	1	201000000001	201000000008	2026-04-08 13:15:24	5266	5	EGYVO	UK01	0.00	t	\N
477	8	201000000032	201090000003	2026-04-19 05:33:52	1	3	\N	\N	0.00	t	3
622	9	201000000019	201223344556	2026-04-01 22:50:46	2025	1	\N	\N	0.00	t	4
478	8	201000000016	201090000001	2026-04-08 04:58:52	1	3	\N	\N	0.01	t	\N
479	8	201000000001	201090000002	2026-04-01 18:48:52	1752	1	\N	\N	6.00	t	\N
623	9	201884002998	201223344556	2026-04-11 13:25:46	1	3	\N	\N	0.05	t	\N
480	8	201000000043	youtube.com	2026-04-19 11:14:52	1	2	\N	\N	0.00	t	\N
828	1	201000000001	201090000001	2026-04-18 23:48:24	4977	1	EGYVO		16.60	t	\N
481	8	201772327638	whatsapp.net	2026-04-28 10:04:52	1	2	\N	\N	0.00	t	\N
624	9	201972954141	201090000003	2026-03-31 19:21:46	3411	1	\N	\N	0.00	t	1
482	8	201193975708	201223344556	2026-04-03 21:56:52	3383	1	\N	\N	5.70	t	\N
1115	12	201000000002	201090000001	2026-04-04 18:44:24	1	7	\N	\N	0.02	t	\N
483	8	201924767903	201223344556	2026-04-12 16:37:52	2959	1	\N	\N	5.00	t	\N
625	9	201229447201	201090000002	2026-04-06 11:46:46	3026	1	\N	\N	10.20	t	\N
484	8	201615922194	201090000003	2026-04-28 09:46:52	2654	1	\N	\N	4.50	t	\N
1436	16	201000000008	201090000003	2026-04-13 03:00:42	453	1	\N	\N	0.80	t	\N
511	8	201122438398	201223344556	2026-04-24 15:36:52	1	3	\N	\N	0.02	t	\N
626	9	201511068195	facebook.com	2026-03-31 19:02:46	1	2	\N	\N	0.00	t	4
512	8	201905415497	201090000001	2026-04-03 02:11:52	1	3	\N	\N	0.02	t	\N
829	1	201000000001	whatsapp.net	2026-04-14 16:43:24	1958113216	2	EGYVO		0.18	t	\N
513	8	201974222870	201090000003	2026-04-06 11:52:52	934	1	\N	\N	1.60	t	\N
627	9	201000000017	201090000003	2026-03-31 02:17:46	182	1	\N	\N	0.00	t	4
514	8	201568820914	201223344556	2026-04-20 14:52:52	55	1	\N	\N	0.05	t	\N
1116	12	201000000002	201090000002	2026-04-11 11:34:24	3793	1	\N	\N	6.40	t	\N
515	8	201000000005	201090000003	2026-04-27 03:26:52	1	3	\N	\N	0.05	t	\N
628	9	201639909693	201090000002	2026-04-01 19:37:46	1330	1	\N	\N	4.60	t	\N
516	8	201000000027	201090000002	2026-04-26 13:27:52	1079	1	\N	\N	0.00	t	4
830	1	201000000001	201000000008	2026-04-03 05:34:24	1	3	EGYVO		0.05	t	\N
517	8	201193577939	google.com	2026-04-16 23:38:52	1	2	\N	\N	0.00	t	\N
629	9	201000000023	fmrz-telecom.net	2026-03-31 05:57:46	1	2	\N	\N	0.00	t	\N
518	8	201432260526	201090000003	2026-04-03 03:59:52	722	1	\N	\N	2.60	t	\N
519	8	201000000005	201090000001	2026-04-18 10:10:52	3207	1	\N	\N	10.80	t	\N
630	9	201915057234	facebook.com	2026-04-21 19:33:46	1	2	\N	\N	0.00	t	\N
520	8	201679439439	201090000003	2026-04-04 02:14:52	580	1	\N	\N	0.50	t	\N
831	1	201000000001	201223344556	2026-04-05 14:59:24	2677	1	EGYVO		9.00	t	\N
521	8	201884002998	201090000001	2026-04-04 04:32:52	1	3	\N	\N	0.05	t	\N
631	9	201851881403	201223344556	2026-04-26 14:23:46	1	3	\N	\N	0.02	t	\N
522	8	201946234738	201090000001	2026-04-09 14:47:52	1	3	\N	\N	0.05	t	\N
1117	12	201000000002	201000000008	2026-04-20 07:24:24	4769	1	\N	\N	8.00	t	\N
523	8	201000000037	whatsapp.net	2026-04-27 12:06:52	1	2	\N	\N	0.00	t	\N
632	9	201742482326	whatsapp.net	2026-04-12 09:29:46	1	2	\N	\N	0.00	t	\N
524	8	201000000048	201090000002	2026-04-19 01:46:52	1	3	\N	\N	0.00	t	4
832	1	201000000001	201223344556	2026-04-17 13:42:24	1	3	EGYVO		0.05	t	\N
525	8	201000000044	201090000002	2026-04-07 17:52:52	1445	1	\N	\N	0.00	t	4
633	9	201000000041	201223344556	2026-04-19 07:51:46	1	3	\N	\N	0.00	t	3
526	8	201000000032	201090000003	2026-04-12 18:54:52	180	1	\N	\N	0.00	t	1
1437	16	201000000042	201223344556	2026-04-18 17:39:42	1	3	\N	\N	0.00	t	4
527	8	201000000021	201090000001	2026-04-12 23:02:52	1	3	\N	\N	0.00	t	4
634	9	201481789330	facebook.com	2026-04-19 11:14:46	1	2	\N	\N	0.00	t	\N
833	1	201000000002	201000000008	2026-04-06 23:04:24	810	1	EGYVO		1.40	t	\N
635	9	201915057234	201090000002	2026-04-19 17:10:46	3549	1	\N	\N	3.00	t	\N
1118	12	201000000002	201090000003	2026-04-18 00:45:24	5789	5	\N	\N	9.70	t	\N
636	9	201000000028	whatsapp.net	2026-04-05 00:43:46	1	2	\N	\N	0.00	t	4
834	1	201000000002	201090000001	2026-04-29 10:06:24	5913	1	EGYVO		9.90	t	\N
637	9	201421638665	201090000001	2026-04-18 13:26:46	3177	1	\N	\N	10.60	t	\N
638	9	201393015335	whatsapp.net	2026-04-07 15:33:46	1	2	\N	\N	0.00	t	\N
835	1	201000000002	facebook.com	2026-04-15 07:54:24	866273430	2	EGYVO		0.04	t	\N
639	9	201811678129	201090000002	2026-04-22 13:02:46	2977	1	\N	\N	10.00	t	\N
1119	12	201000000002	201223344556	2026-04-27 07:36:24	1	3	\N	\N	0.02	t	\N
640	9	201000000010	201090000001	2026-04-23 19:45:46	777	1	\N	\N	1.30	t	\N
1438	16	201000000017	201223344556	2026-04-23 21:53:42	1	3	\N	\N	0.02	t	\N
641	9	201845026506	201090000003	2026-04-19 17:43:46	1	3	\N	\N	0.02	t	\N
642	9	201590834655	201090000001	2026-04-07 15:25:46	2459	1	\N	\N	2.05	t	\N
643	9	201000000010	google.com	2026-04-23 07:11:46	1	2	\N	\N	0.00	t	\N
644	9	201665180852	201000000008	2026-03-31 04:49:46	1	3	\N	\N	0.00	t	4
645	9	201763359068	whatsapp.net	2026-04-15 00:48:46	1	2	\N	\N	0.00	t	\N
646	9	201000000016	201223344556	2026-04-01 19:03:46	1472	1	\N	\N	1.25	t	\N
647	9	201000000016	facebook.com	2026-04-05 22:50:46	1	2	\N	\N	0.00	t	\N
648	9	201690095272	youtube.com	2026-04-21 03:46:46	1	2	\N	\N	0.00	t	\N
649	9	201000000037	201000000008	2026-04-20 10:50:46	2571	1	\N	\N	0.00	t	1
650	9	201193577939	201000000008	2026-04-01 20:28:46	1	3	\N	\N	0.02	t	\N
651	9	201850051553	201090000001	2026-04-07 11:44:46	1501	1	\N	\N	2.60	t	\N
652	9	201000000032	youtube.com	2026-04-14 09:34:46	1	2	\N	\N	0.00	t	\N
653	9	201000000003	201090000002	2026-04-14 23:29:46	2299	1	\N	\N	7.80	t	\N
654	9	201818037329	201090000003	2026-04-25 10:03:46	1	3	\N	\N	0.05	t	\N
655	9	201845026506	facebook.com	2026-04-27 20:08:46	1	2	\N	\N	0.00	t	\N
656	9	201000000006	facebook.com	2026-04-08 13:58:46	1	2	\N	\N	0.00	t	\N
657	1	201000000046	201000000008	2026-04-27 15:03:08	1	3	EGYVO		0.00	t	4
658	1	201421638665	youtube.com	2026-04-18 00:24:08	35136117	2	EGYVO		0.00	t	\N
659	1	201000000022	youtube.com	2026-04-19 01:37:08	42068301	6	EGYVO	USA01	0.00	t	6
660	1	201742482326	201223344556	2026-04-10 05:45:08	1	3	EGYVO		0.01	t	\N
661	1	201277676035	whatsapp.net	2026-04-04 13:51:08	33586217	2	EGYVO		0.00	t	\N
662	1	201000000035	201223344556	2026-04-12 01:19:08	1	3	EGYVO		0.00	t	3
663	1	201000000023	facebook.com	2026-04-12 06:34:08	40393074	2	EGYVO		0.00	t	\N
664	1	201420731899	201090000003	2026-04-05 15:43:08	2753	1	EGYVO		4.60	t	\N
665	1	201590288456	facebook.com	2026-04-04 06:52:08	26102646	2	EGYVO		0.00	t	\N
666	1	201399521241	201223344556	2026-04-12 15:00:08	1	7	EGYVO	GER01	0.00	t	\N
667	1	201000000002	google.com	2026-04-29 17:13:08	48999735	2	EGYVO		0.00	t	\N
668	1	201725767736	facebook.com	2026-04-26 14:43:08	26442596	6	EGYVO	FRA01	0.00	t	\N
669	1	201892594062	201223344556	2026-04-10 12:28:08	6102	5	EGYVO	USA01	0.00	t	\N
670	1	201807409782	fmrz-telecom.net	2026-04-29 08:36:08	32235916	2	EGYVO		0.00	t	\N
671	1	201480812037	201090000003	2026-04-29 02:20:08	1	7	EGYVO	UK01	0.00	t	\N
836	1	201000000002	201000000008	2026-04-25 09:50:24	1	7	EGYVO	FRA01	0.00	t	\N
672	1	201731509325	201223344556	2026-04-27 09:22:08	4206	5	EGYVO	UAE01	0.00	t	\N
1120	12	201000000002	201090000002	2026-04-28 17:18:24	5534	1	\N	\N	9.30	t	\N
673	1	201000000063	201090000003	2026-04-07 22:18:08	1830	5	EGYVO	UAE01	0.00	t	4
837	1	201000000002	201223344556	2026-04-07 22:40:24	1	3	EGYVO		0.02	t	\N
674	1	201639909693	facebook.com	2026-04-19 08:29:08	49309530	2	EGYVO		0.00	t	\N
675	1	201000000033	201090000002	2026-04-24 19:14:08	1	3	EGYVO		0.00	t	4
838	1	201000000002	201090000003	2026-03-31 05:25:24	1	3	EGYVO		0.02	t	\N
676	1	201000000002	google.com	2026-04-02 03:48:08	45658229	2	EGYVO		0.00	t	\N
1121	12	201000000002	201223344556	2026-04-06 16:45:24	1	3	\N	\N	0.02	t	\N
677	1	201373685722	201223344556	2026-04-15 16:39:08	1	3	EGYVO		0.02	t	\N
839	1	201000000002	201090000002	2026-04-22 18:34:24	4604	1	EGYVO		7.70	t	\N
678	1	201544739530	201090000003	2026-04-07 09:46:08	1	7	EGYVO	USA01	0.00	t	\N
1439	16	201000000046	fmrz-telecom.net	2026-04-19 18:42:42	1	2	\N	\N	0.00	t	4
679	1	201000000044	201090000002	2026-04-22 05:36:08	4244	1	EGYVO		0.00	t	4
840	1	201000000002	201090000002	2026-04-03 22:44:24	5402	1	EGYVO		9.10	t	\N
680	1	201884002998	201090000002	2026-04-18 09:15:08	6772	5	EGYVO	GER01	0.00	t	\N
1122	12	201000000002	201090000001	2026-04-28 14:47:24	2804	5	\N	\N	4.70	t	\N
681	1	201590288456	201000000008	2026-04-25 15:44:08	4781	1	EGYVO		8.00	t	\N
682	1	201615922194	201000000008	2026-04-12 21:43:08	6691	1	EGYVO		11.20	t	\N
683	1	201699129335	201090000002	2026-04-15 00:35:08	1	3	EGYVO		0.02	t	\N
684	1	201573560989	fmrz-telecom.net	2026-04-08 15:31:08	7744282	2	EGYVO		0.00	t	\N
685	1	201542776578	201090000003	2026-04-29 14:55:08	1	3	EGYVO		0.05	t	\N
686	1	201814479848	201090000001	2026-04-11 15:30:08	1	3	EGYVO		0.05	t	\N
687	1	201000000035	whatsapp.net	2026-04-26 14:45:08	36563003	6	EGYVO	USA01	0.00	t	\N
688	1	201542776578	201090000003	2026-04-11 13:42:08	7096	1	EGYVO		23.80	t	\N
689	1	201000000021	facebook.com	2026-04-19 05:15:08	12398825	2	EGYVO		0.00	t	2
690	1	201912929712	201090000002	2026-04-09 10:39:08	1	7	EGYVO	FRA01	0.00	t	\N
691	1	201000000011	201000000008	2026-04-02 05:53:08	1	7	EGYVO	UK01	0.00	t	\N
692	1	201000000012	fmrz-telecom.net	2026-04-28 20:52:08	49880443	2	EGYVO		0.00	t	\N
693	1	201649032416	201223344556	2026-04-09 20:04:08	1	3	EGYVO		0.02	t	\N
694	1	201000000029	201000000008	2026-04-08 05:38:08	2931	5	EGYVO	GER01	0.00	t	4
695	1	201806374057	201090000002	2026-04-02 17:59:08	1	3	EGYVO		0.02	t	\N
696	1	201000000035	201090000002	2026-04-27 09:13:08	5548	1	EGYVO		0.00	t	1
697	1	201000000019	201223344556	2026-04-06 16:29:08	1	3	EGYVO		0.00	t	4
698	1	201000000042	201000000008	2026-04-01 03:01:08	1	3	EGYVO		0.00	t	4
699	1	201915057234	google.com	2026-03-30 18:10:08	30435048	2	EGYVO		0.00	t	2
700	1	201884002998	youtube.com	2026-04-16 20:00:08	48392457	2	EGYVO		0.00	t	\N
701	1	201000000045	youtube.com	2026-04-07 04:05:08	10560348	2	EGYVO		0.00	t	2
702	1	201291490356	facebook.com	2026-04-12 03:19:08	28527777	2	EGYVO		0.00	t	\N
703	1	201000000028	201000000008	2026-04-29 04:06:08	1	3	EGYVO		0.00	t	4
704	1	201974222870	youtube.com	2026-03-30 16:51:08	51839859	2	EGYVO		0.00	t	2
705	1	201000000030	201000000008	2026-04-09 05:29:08	3561	1	EGYVO		0.00	t	4
706	1	201000000031	whatsapp.net	2026-04-21 04:00:08	17125643	2	EGYVO		0.00	t	\N
707	1	201000000015	201090000002	2026-04-18 12:19:08	1	3	EGYVO		0.01	t	\N
708	1	201326784672	whatsapp.net	2026-04-06 12:17:08	48844112	2	EGYVO		0.00	t	\N
709	1	201259012646	google.com	2026-04-21 13:57:08	7378260	6	EGYVO	GER01	0.00	t	\N
710	1	201665180852	201090000001	2026-03-31 08:28:08	3728	5	EGYVO	GER01	0.00	t	4
711	1	201000000001	201090000001	2026-04-19 16:57:08	1	7	EGYVO	GER01	0.00	t	\N
712	1	201393015335	youtube.com	2026-04-17 00:14:08	18309263	2	EGYVO		0.00	t	\N
713	1	201000000032	201090000001	2026-04-25 17:41:08	4952	1	EGYVO		0.00	t	1
714	1	201000000019	201090000001	2026-04-06 22:36:08	1	3	EGYVO		0.00	t	4
715	1	201000000031	201090000003	2026-04-01 08:59:08	566	1	EGYVO		0.00	t	1
716	1	201590834655	201090000003	2026-04-28 14:38:08	1	3	EGYVO		0.01	t	\N
717	1	201807409782	201090000003	2026-04-02 09:55:08	2517	1	EGYVO		8.40	t	\N
718	1	201000000016	201090000002	2026-04-25 08:57:08	1	7	EGYVO	UAE01	0.00	t	\N
719	1	201529549288	201090000001	2026-04-23 04:06:08	5839	1	EGYVO		9.80	t	\N
720	1	201193577939	201223344556	2026-04-10 19:06:08	5081	1	EGYVO		8.50	t	\N
721	1	201000000010	whatsapp.net	2026-04-02 13:33:08	22797287	6	EGYVO	USA01	0.00	t	\N
722	1	201421638665	201223344556	2026-04-23 05:19:08	6326	5	EGYVO	USA01	0.00	t	\N
723	1	201291490356	201090000003	2026-04-11 23:35:08	4111	5	EGYVO	UK01	0.00	t	\N
724	1	201000000002	201000000008	2026-04-24 19:23:08	901	1	EGYVO		1.60	t	\N
725	1	201000000002	201090000003	2026-04-07 02:23:08	1	3	EGYVO		0.02	t	\N
726	1	201000000002	201090000003	2026-04-24 23:46:08	5572	1	EGYVO		9.30	t	\N
727	1	201000000002	201223344556	2026-04-19 11:26:08	1	3	EGYVO		0.02	t	\N
728	1	201000000002	201223344556	2026-04-02 02:43:08	1	3	EGYVO		0.02	t	\N
729	1	201000000002	youtube.com	2026-04-17 14:51:08	844316410	6	EGYVO	USA01	0.00	t	\N
730	1	201000000002	201223344556	2026-04-21 13:58:08	5976	5	EGYVO	UAE01	0.00	t	\N
731	1	201000000002	201090000001	2026-04-25 20:02:08	1	3	EGYVO		0.02	t	\N
732	1	201000000002	201090000003	2026-04-06 12:48:08	1	7	EGYVO	FRA01	0.00	t	\N
733	1	201000000002	201090000003	2026-04-14 21:08:08	2182	5	EGYVO	USA01	0.00	t	\N
734	1	201000000002	201090000002	2026-04-12 08:39:08	1	3	EGYVO		0.02	t	\N
735	1	201000000002	201090000001	2026-04-05 09:01:08	1	3	EGYVO		0.02	t	\N
736	1	201000000002	201090000001	2026-03-30 10:52:08	2713	1	EGYVO		0.00	t	4
841	1	201000000002	201090000001	2026-04-09 07:58:24	1	3	EGYVO		0.02	t	\N
737	1	201000000002	201000000008	2026-04-08 20:11:08	1	3	EGYVO		0.02	t	\N
1123	12	201000000002	201223344556	2026-04-24 12:05:24	1	3	\N	\N	0.02	t	\N
738	1	201000000002	201000000008	2026-04-20 16:04:08	1	3	EGYVO		0.02	t	\N
842	1	201000000002	201090000002	2026-04-03 06:48:24	1	3	EGYVO		0.02	t	\N
739	1	201000000002	201090000002	2026-04-08 03:34:08	1	7	EGYVO	UAE01	0.00	t	\N
1440	16	201000000033	google.com	2026-04-16 22:38:42	1	2	\N	\N	0.00	t	4
740	1	201000000002	201090000002	2026-04-04 08:56:08	1	3	EGYVO		0.02	t	\N
843	1	201000000002	201090000001	2026-04-04 18:44:24	1	7	EGYVO	GER01	0.00	t	\N
741	1	201000000002	201090000003	2026-04-18 00:11:08	7104	1	EGYVO		11.90	t	\N
1124	12	201000000002	201223344556	2026-04-20 16:50:24	5346	1	\N	\N	9.00	t	\N
742	1	201000000002	201090000003	2026-04-26 19:50:08	1	3	EGYVO		0.02	t	\N
844	1	201000000002	201090000002	2026-04-11 11:34:24	3793	1	EGYVO		6.40	t	\N
743	1	201000000002	facebook.com	2026-04-09 04:10:08	2104337681	2	EGYVO		0.10	t	\N
744	1	201000000002	201090000003	2026-04-07 19:14:08	6169	1	EGYVO		10.30	t	\N
845	1	201000000002	201000000008	2026-04-20 07:24:24	4769	1	EGYVO		8.00	t	\N
745	1	201000000002	201090000001	2026-04-27 12:08:08	1	3	EGYVO		0.02	t	\N
1125	12	201000000002	201090000003	2026-04-21 08:34:24	1015	1	\N	\N	1.70	t	\N
746	1	201000000002	201223344556	2026-04-09 02:30:08	1	3	EGYVO		0.02	t	\N
846	1	201000000002	201090000003	2026-04-18 00:45:24	5789	5	EGYVO	UK01	0.00	t	\N
747	1	201000000002	google.com	2026-04-13 13:00:08	1043710425	6	EGYVO	UK01	0.00	t	\N
1441	16	201000000043	201090000003	2026-04-05 12:34:42	2311	1	\N	\N	0.00	t	1
748	1	201000000002	201090000002	2026-04-29 20:45:08	1774	5	EGYVO	UK01	0.00	t	\N
847	1	201000000002	201223344556	2026-04-27 07:36:24	1	3	EGYVO		0.02	t	\N
749	1	201000000002	201223344556	2026-04-05 10:09:08	4052	5	EGYVO	GER01	0.00	t	\N
1126	12	201000000002	whatsapp.net	2026-03-31 16:18:24	1039	6	\N	\N	0.00	t	\N
750	1	201000000002	201090000001	2026-04-20 02:48:08	3066	1	EGYVO		5.20	t	\N
848	1	201000000002	201090000002	2026-04-28 17:18:24	5534	1	EGYVO		9.30	t	\N
751	1	201000000002	201090000002	2026-04-19 15:40:08	1882	1	EGYVO		3.20	t	\N
752	1	201000000002	facebook.com	2026-04-23 03:08:08	1360552308	2	EGYVO		0.06	t	\N
849	1	201000000002	201223344556	2026-04-06 16:45:24	1	3	EGYVO		0.02	t	\N
753	1	201000000002	201090000001	2026-03-30 23:04:08	1	3	EGYVO		0.00	t	4
1127	12	201000000002	201223344556	2026-04-29 01:37:24	393	5	\N	\N	0.70	t	\N
754	1	201000000002	201090000003	2026-04-09 02:01:08	1	3	EGYVO		0.02	t	\N
850	1	201000000002	201090000001	2026-04-28 14:47:24	2804	5	EGYVO	USA01	0.00	t	\N
755	1	201000000002	201223344556	2026-04-14 19:34:08	3441	1	EGYVO		5.80	t	\N
1442	16	201000000029	201090000001	2026-04-07 08:20:42	1766	1	\N	\N	0.00	t	4
756	1	201000000002	201090000001	2026-04-12 10:38:08	2694	1	EGYVO		4.50	t	\N
851	1	201000000002	201223344556	2026-04-24 12:05:24	1	3	EGYVO		0.02	t	\N
757	1	201000000002	201223344556	2026-04-01 21:21:08	2041	1	EGYVO		3.50	t	\N
1128	12	201000000002	whatsapp.net	2026-04-29 07:53:24	3175	2	\N	\N	0.00	t	\N
758	1	201000000002	201090000003	2026-04-09 02:00:08	1	3	EGYVO		0.02	t	\N
852	1	201000000002	201223344556	2026-04-20 16:50:24	5346	1	EGYVO		9.00	t	\N
759	1	201000000002	201090000002	2026-04-07 22:43:08	1	3	EGYVO		0.02	t	\N
760	1	201000000002	201000000008	2026-04-16 06:16:08	1	3	EGYVO		0.02	t	\N
853	1	201000000002	201090000003	2026-04-21 08:34:24	1015	1	EGYVO		1.70	t	\N
761	1	201000000002	201000000008	2026-04-24 10:18:08	1	3	EGYVO		0.02	t	\N
1129	12	201000000002	201090000003	2026-04-24 08:40:24	4538	1	\N	\N	7.60	t	\N
762	1	201000000002	201090000001	2026-04-01 04:42:08	1	3	EGYVO		0.02	t	\N
854	1	201000000002	whatsapp.net	2026-03-31 16:18:24	1089224192	6	EGYVO	USA01	0.00	t	\N
763	1	201000000002	201223344556	2026-04-16 18:13:08	1	7	EGYVO	USA01	0.00	t	\N
1443	16	201000000025	201090000003	2026-04-17 08:42:42	1	3	\N	\N	0.00	t	4
764	1	201000000002	201090000003	2026-04-22 21:56:08	5927	1	EGYVO		9.90	t	\N
855	1	201000000002	201223344556	2026-04-29 01:37:24	393	5	EGYVO	FRA01	0.00	t	\N
765	1	201000000002	201090000003	2026-04-26 21:14:08	1	3	EGYVO		0.02	t	\N
1130	12	201000000002	201090000003	2026-04-25 12:02:24	1	3	\N	\N	0.02	t	\N
766	1	201000000002	youtube.com	2026-04-01 09:16:08	610840388	2	EGYVO		0.03	t	\N
856	1	201000000002	201090000003	2026-04-24 08:40:24	4538	1	EGYVO		7.60	t	\N
767	1	201000000002	201090000003	2026-04-26 09:00:08	1	3	EGYVO		0.02	t	\N
768	1	201000000002	201000000008	2026-04-26 21:02:08	1	3	EGYVO		0.02	t	\N
857	1	201000000002	201090000003	2026-04-25 12:02:24	1	3	EGYVO		0.02	t	\N
769	1	201000000002	201000000008	2026-04-16 00:34:08	3647	1	EGYVO		6.10	t	\N
1131	12	201000000002	youtube.com	2026-04-12 08:11:24	4808	6	\N	\N	0.00	t	\N
770	1	201000000002	201223344556	2026-04-18 14:55:08	1	3	EGYVO		0.02	t	\N
858	1	201000000002	201223344556	2026-04-06 21:13:24	7095	1	EGYVO		11.90	t	\N
771	1	201000000002	201090000001	2026-04-23 13:59:08	1	3	EGYVO		0.02	t	\N
1444	16	201000000033	201000000008	2026-04-04 07:50:42	1039	1	\N	\N	0.00	t	4
772	1	201000000002	201090000002	2026-04-16 15:40:08	1	3	EGYVO		0.02	t	\N
859	1	201000000002	201090000003	2026-04-09 22:56:24	1	3	EGYVO		0.02	t	\N
773	1	201000000002	201090000002	2026-04-13 16:26:08	1	7	EGYVO	FRA01	0.00	t	\N
1132	12	201000000002	201223344556	2026-04-06 21:13:24	7095	1	\N	\N	11.90	t	\N
1133	12	201000000002	201090000003	2026-04-09 22:56:24	1	3	\N	\N	0.02	t	\N
774	1	201000000002	201090000001	2026-04-27 19:07:08	1413	1	EGYVO		2.40	t	\N
860	1	201000000002	201090000001	2026-04-24 21:59:24	1	3	EGYVO		0.02	t	\N
775	1	201000000002	201000000008	2026-04-27 09:19:08	6118	1	EGYVO		10.20	t	\N
1445	16	201000000030	201090000001	2026-04-21 06:55:42	1617	1	\N	\N	0.00	t	4
776	1	201000000002	201223344556	2026-04-05 20:56:08	6439	1	EGYVO		10.80	t	\N
861	1	201000000002	201223344556	2026-04-23 04:51:24	1	3	EGYVO		0.02	t	\N
777	1	201000000002	201223344556	2026-04-23 09:53:08	59	5	EGYVO	USA01	0.00	t	\N
1134	12	201000000002	201090000001	2026-04-24 21:59:24	1	3	\N	\N	0.02	t	\N
778	1	201000000002	201090000003	2026-04-14 21:49:08	1505	1	EGYVO		2.60	t	\N
862	1	201000000002	201223344556	2026-04-06 01:14:24	1	3	EGYVO		0.02	t	\N
779	1	201000000002	201090000001	2026-04-02 05:48:08	6858	1	EGYVO		11.50	t	\N
780	1	201000000002	201090000003	2026-04-17 07:07:08	1	7	EGYVO	GER01	0.00	t	\N
863	1	201000000002	201090000003	2026-04-21 10:22:24	1	3	EGYVO		0.02	t	\N
781	1	201000000002	201090000003	2026-04-14 17:02:08	1	3	EGYVO		0.02	t	\N
1135	12	201000000002	201223344556	2026-04-23 04:51:24	1	3	\N	\N	0.02	t	\N
864	1	201000000002	201223344556	2026-04-17 20:54:24	6119	1	EGYVO		10.20	t	\N
1446	16	201000000026	youtube.com	2026-04-05 04:40:42	1	2	\N	\N	0.00	t	4
865	1	201000000002	201090000002	2026-04-09 01:58:24	1	7	EGYVO	UK01	0.00	t	\N
1136	12	201000000002	201223344556	2026-04-06 01:14:24	1	3	\N	\N	0.02	t	\N
866	1	201000000002	201090000003	2026-04-23 10:24:24	1	3	EGYVO		0.02	t	\N
867	1	201000000002	201090000003	2026-04-28 12:01:24	1036	1	EGYVO		1.80	t	\N
1137	12	201000000002	201090000003	2026-04-21 10:22:24	1	3	\N	\N	0.02	t	\N
868	1	201000000002	facebook.com	2026-04-01 20:10:24	1999202793	2	EGYVO		0.09	t	\N
1447	16	201000000031	201090000003	2026-04-08 02:15:42	1042	1	\N	\N	0.00	t	1
869	1	201000000002	201090000003	2026-04-14 23:01:24	6727	1	EGYVO		11.30	t	\N
1138	12	201000000002	201223344556	2026-04-17 20:54:24	6119	1	\N	\N	10.20	t	\N
870	1	201000000002	201223344556	2026-04-27 13:49:24	1	3	EGYVO		0.02	t	\N
871	1	201000000002	whatsapp.net	2026-04-07 17:39:24	623865925	2	EGYVO		0.03	t	\N
1139	12	201000000002	201090000002	2026-04-09 01:58:24	1	7	\N	\N	0.02	t	\N
872	1	201000000002	201223344556	2026-04-06 05:49:24	3290	5	EGYVO	UAE01	0.00	t	\N
1448	16	201000000038	201090000003	2026-04-18 01:39:42	1	3	\N	\N	0.00	t	4
876	10	201000000043	201090000001	2026-04-16 23:31:42	2266	1	\N	\N	0.00	t	1
1140	12	201000000002	facebook.com	2026-04-22 12:05:24	2801	2	\N	\N	0.00	t	\N
877	10	201000000006	whatsapp.net	2026-04-14 05:07:42	1	2	\N	\N	0.00	t	\N
878	10	201000000042	201090000002	2026-04-05 01:14:42	3089	1	\N	\N	0.00	t	4
1141	12	201000000002	201090000003	2026-04-23 10:24:24	1	3	\N	\N	0.02	t	\N
879	10	201000000029	201090000002	2026-04-15 23:00:42	346	1	\N	\N	0.00	t	4
1449	16	201000000015	201090000003	2026-04-04 23:02:42	1	3	\N	\N	0.01	t	\N
880	10	201000000007	201090000003	2026-04-24 11:41:42	1	3	\N	\N	0.05	t	\N
1142	12	201000000002	201090000003	2026-04-28 12:01:24	1036	1	\N	\N	1.80	t	\N
881	10	201000000032	201090000002	2026-04-02 00:20:42	1729	1	\N	\N	0.00	t	1
882	10	201000000047	201090000002	2026-04-01 18:56:42	2901	1	\N	\N	0.00	t	4
1143	12	201000000002	facebook.com	2026-04-01 20:10:24	1907	2	\N	\N	0.00	t	\N
883	10	201000000047	201090000001	2026-04-13 16:02:42	1	3	\N	\N	0.00	t	4
884	10	201000000008	201090000003	2026-04-13 03:00:42	453	1	\N	\N	0.80	t	\N
1144	12	201000000002	201090000003	2026-04-14 23:01:24	6727	1	\N	\N	11.30	t	\N
885	10	201000000042	201223344556	2026-04-18 17:39:42	1	3	\N	\N	0.00	t	4
886	10	201000000017	201223344556	2026-04-23 21:53:42	1	3	\N	\N	0.02	t	\N
1145	12	201000000002	201223344556	2026-04-27 13:49:24	1	3	\N	\N	0.02	t	\N
887	10	201000000046	fmrz-telecom.net	2026-04-19 18:42:42	1	2	\N	\N	0.00	t	4
888	10	201000000033	google.com	2026-04-16 22:38:42	1	2	\N	\N	0.00	t	4
1146	12	201000000002	whatsapp.net	2026-04-07 17:39:24	595	2	\N	\N	0.00	t	\N
889	10	201000000043	201090000003	2026-04-05 12:34:42	2311	1	\N	\N	0.00	t	1
890	10	201000000029	201090000001	2026-04-07 08:20:42	1766	1	\N	\N	0.00	t	4
1147	12	201000000002	201223344556	2026-04-06 05:49:24	3290	5	\N	\N	5.50	t	\N
891	10	201000000025	201090000003	2026-04-17 08:42:42	1	3	\N	\N	0.00	t	4
892	10	201000000033	201000000008	2026-04-04 07:50:42	1039	1	\N	\N	0.00	t	4
1148	12	201000000002	google.com	2026-04-09 12:16:24	4685	2	\N	\N	0.00	t	\N
893	10	201000000030	201090000001	2026-04-21 06:55:42	1617	1	\N	\N	0.00	t	4
894	10	201000000026	youtube.com	2026-04-05 04:40:42	1	2	\N	\N	0.00	t	4
1234	14	201326784672	whatsapp.net	2026-04-06 12:17:08	47	2	\N	\N	0.00	t	\N
895	10	201000000031	201090000003	2026-04-08 02:15:42	1042	1	\N	\N	0.00	t	1
896	10	201000000038	201090000003	2026-04-18 01:39:42	1	3	\N	\N	0.00	t	4
1235	14	201259012646	google.com	2026-04-21 13:57:08	8	6	\N	\N	0.00	t	\N
897	10	201000000015	201090000003	2026-04-04 23:02:42	1	3	\N	\N	0.01	t	\N
1236	14	201665180852	201090000001	2026-03-31 08:28:08	3728	5	\N	\N	0.00	t	4
1237	14	201000000001	201090000001	2026-04-19 16:57:08	1	7	\N	\N	0.05	t	\N
1238	14	201393015335	youtube.com	2026-04-17 00:14:08	18	2	\N	\N	0.00	t	\N
1239	14	201000000032	201090000001	2026-04-25 17:41:08	4952	1	\N	\N	0.00	t	1
1240	14	201000000019	201090000001	2026-04-06 22:36:08	1	3	\N	\N	0.00	t	4
1241	14	201000000031	201090000003	2026-04-01 08:59:08	566	1	\N	\N	0.00	t	1
1242	14	201590834655	201090000003	2026-04-28 14:38:08	1	3	\N	\N	0.01	t	\N
1243	14	201807409782	201090000003	2026-04-02 09:55:08	2517	1	\N	\N	8.40	t	\N
898	10	201000000035	201090000003	2026-04-21 00:42:42	489	1	\N	\N	0.00	t	1
1450	16	201000000035	201090000003	2026-04-21 00:42:42	489	1	\N	\N	0.00	t	1
899	10	201000000039	201000000008	2026-04-28 13:31:42	1	3	\N	\N	0.00	t	3
1149	13	201000000032	201090000001	2026-04-04 19:32:42	1	3	\N	\N	0.00	t	3
900	10	201000000014	201090000002	2026-04-06 00:58:42	1	3	\N	\N	0.02	t	\N
901	10	201000000002	201223344556	2026-03-31 07:55:42	877	1	\N	\N	1.50	t	\N
1150	13	201000000043	201000000008	2026-04-01 09:55:42	1	3	\N	\N	0.00	t	3
902	10	201000000020	201090000002	2026-04-21 04:26:42	2286	1	\N	\N	0.00	t	4
1451	16	201000000039	201000000008	2026-04-28 13:31:42	1	3	\N	\N	0.00	t	3
903	10	201000000001	201090000002	2026-03-30 22:11:42	1	3	\N	\N	0.05	t	\N
1151	13	201000000014	201090000002	2026-04-28 20:10:42	2838	1	\N	\N	4.80	t	\N
904	10	201000000009	201090000001	2026-04-19 02:03:42	2766	1	\N	\N	9.40	t	\N
905	10	201000000021	fmrz-telecom.net	2026-04-22 08:37:42	1	2	\N	\N	0.00	t	\N
1152	13	201000000043	201090000001	2026-04-16 23:31:42	2266	1	\N	\N	0.00	t	1
906	10	201000000039	google.com	2026-04-15 04:07:42	1	2	\N	\N	0.00	t	\N
1452	16	201000000014	201090000002	2026-04-06 00:58:42	1	3	\N	\N	0.02	t	\N
907	11	201000000046	201000000008	2026-04-27 15:03:08	1	3	\N	\N	0.00	t	4
1153	13	201000000006	whatsapp.net	2026-04-14 05:07:42	1	2	\N	\N	0.00	t	\N
908	11	201421638665	youtube.com	2026-04-18 00:24:08	34	2	\N	\N	0.00	t	\N
909	11	201000000022	youtube.com	2026-04-19 01:37:08	41	6	\N	\N	0.00	t	2
1154	13	201000000042	201090000002	2026-04-05 01:14:42	3089	1	\N	\N	0.00	t	4
910	11	201742482326	201223344556	2026-04-10 05:45:08	1	3	\N	\N	0.01	t	\N
1453	16	201000000002	201223344556	2026-03-31 07:55:42	877	1	\N	\N	1.50	t	\N
911	11	201277676035	whatsapp.net	2026-04-04 13:51:08	33	2	\N	\N	0.00	t	\N
1155	13	201000000029	201090000002	2026-04-15 23:00:42	346	1	\N	\N	0.00	t	4
912	11	201000000035	201223344556	2026-04-12 01:19:08	1	3	\N	\N	0.00	t	3
913	11	201000000023	facebook.com	2026-04-12 06:34:08	39	2	\N	\N	0.00	t	\N
1156	13	201000000007	201090000003	2026-04-24 11:41:42	1	3	\N	\N	0.05	t	\N
914	11	201420731899	201090000003	2026-04-05 15:43:08	2753	1	\N	\N	4.60	t	\N
1454	16	201000000020	201090000002	2026-04-21 04:26:42	2286	1	\N	\N	0.00	t	4
915	11	201590288456	facebook.com	2026-04-04 06:52:08	25	2	\N	\N	0.00	t	\N
1157	13	201000000032	201090000002	2026-04-02 00:20:42	1729	1	\N	\N	0.00	t	1
916	11	201399521241	201223344556	2026-04-12 15:00:08	1	7	\N	\N	0.05	t	\N
917	11	201000000002	google.com	2026-04-29 17:13:08	47	2	\N	\N	0.00	t	\N
1158	13	201000000047	201090000002	2026-04-01 18:56:42	2901	1	\N	\N	0.00	t	4
918	11	201725767736	facebook.com	2026-04-26 14:43:08	26	6	\N	\N	0.00	t	\N
1455	16	201000000001	201090000002	2026-03-30 22:11:42	1	3	\N	\N	0.05	t	\N
919	11	201892594062	201223344556	2026-04-10 12:28:08	6102	5	\N	\N	20.40	t	\N
1159	13	201000000047	201090000001	2026-04-13 16:02:42	1	3	\N	\N	0.00	t	4
920	11	201807409782	fmrz-telecom.net	2026-04-29 08:36:08	31	2	\N	\N	0.00	t	\N
921	11	201480812037	201090000003	2026-04-29 02:20:08	1	7	\N	\N	0.02	t	\N
1160	13	201000000008	201090000003	2026-04-13 03:00:42	453	1	\N	\N	0.80	t	\N
922	11	201731509325	201223344556	2026-04-27 09:22:08	4206	5	\N	\N	14.20	t	\N
1456	16	201000000009	201090000001	2026-04-19 02:03:42	2766	1	\N	\N	9.40	t	\N
923	11	201000000063	201090000003	2026-04-07 22:18:08	1830	5	\N	\N	1.55	t	\N
1161	13	201000000042	201223344556	2026-04-18 17:39:42	1	3	\N	\N	0.00	t	4
924	11	201639909693	facebook.com	2026-04-19 08:29:08	48	2	\N	\N	0.00	t	\N
925	11	201000000033	201090000002	2026-04-24 19:14:08	1	3	\N	\N	0.00	t	4
1162	13	201000000017	201223344556	2026-04-23 21:53:42	1	3	\N	\N	0.02	t	\N
926	11	201000000002	google.com	2026-04-02 03:48:08	44	2	\N	\N	0.00	t	\N
1457	16	201000000021	fmrz-telecom.net	2026-04-22 08:37:42	1	2	\N	\N	0.00	t	\N
927	11	201373685722	201223344556	2026-04-15 16:39:08	1	3	\N	\N	0.02	t	\N
1163	13	201000000046	fmrz-telecom.net	2026-04-19 18:42:42	1	2	\N	\N	0.00	t	4
928	11	201544739530	201090000003	2026-04-07 09:46:08	1	7	\N	\N	0.02	t	\N
929	11	201000000044	201090000002	2026-04-22 05:36:08	4244	1	\N	\N	0.00	t	4
1164	13	201000000033	google.com	2026-04-16 22:38:42	1	2	\N	\N	0.00	t	4
930	11	201884002998	201090000002	2026-04-18 09:15:08	6772	5	\N	\N	22.60	t	\N
1458	16	201000000039	google.com	2026-04-15 04:07:42	1	2	\N	\N	0.00	t	\N
931	11	201590288456	201000000008	2026-04-25 15:44:08	4781	1	\N	\N	8.00	t	\N
1165	13	201000000043	201090000003	2026-04-05 12:34:42	2311	1	\N	\N	0.00	t	1
932	11	201615922194	201000000008	2026-04-12 21:43:08	6691	1	\N	\N	11.20	t	\N
933	11	201699129335	201090000002	2026-04-15 00:35:08	1	3	\N	\N	0.02	t	\N
1166	13	201000000029	201090000001	2026-04-07 08:20:42	1766	1	\N	\N	0.00	t	4
934	11	201573560989	fmrz-telecom.net	2026-04-08 15:31:08	8	2	\N	\N	0.00	t	\N
1459	17	201000000046	201000000008	2026-04-27 15:03:08	1	3	\N	\N	0.00	t	4
935	11	201542776578	201090000003	2026-04-29 14:55:08	1	3	\N	\N	0.05	t	\N
1167	13	201000000025	201090000003	2026-04-17 08:42:42	1	3	\N	\N	0.00	t	4
936	11	201814479848	201090000001	2026-04-11 15:30:08	1	3	\N	\N	0.05	t	\N
937	11	201000000035	whatsapp.net	2026-04-26 14:45:08	35	6	\N	\N	0.00	t	\N
1168	13	201000000033	201000000008	2026-04-04 07:50:42	1039	1	\N	\N	0.00	t	4
938	11	201542776578	201090000003	2026-04-11 13:42:08	7096	1	\N	\N	23.80	t	\N
1460	17	201421638665	youtube.com	2026-04-18 00:24:08	34	2	\N	\N	0.00	t	\N
939	11	201000000021	facebook.com	2026-04-19 05:15:08	12	2	\N	\N	0.00	t	\N
1169	13	201000000030	201090000001	2026-04-21 06:55:42	1617	1	\N	\N	0.00	t	4
940	11	201912929712	201090000002	2026-04-09 10:39:08	1	7	\N	\N	0.02	t	\N
941	11	201000000011	201000000008	2026-04-02 05:53:08	1	7	\N	\N	0.05	t	\N
1170	13	201000000026	youtube.com	2026-04-05 04:40:42	1	2	\N	\N	0.00	t	4
942	11	201000000012	fmrz-telecom.net	2026-04-28 20:52:08	48	2	\N	\N	0.00	t	\N
1461	17	201000000022	youtube.com	2026-04-19 01:37:08	41	6	\N	\N	0.00	t	2
943	11	201649032416	201223344556	2026-04-09 20:04:08	1	3	\N	\N	0.02	t	\N
1171	13	201000000031	201090000003	2026-04-08 02:15:42	1042	1	\N	\N	0.00	t	1
944	11	201000000029	201000000008	2026-04-08 05:38:08	2931	5	\N	\N	0.00	t	4
945	11	201806374057	201090000002	2026-04-02 17:59:08	1	3	\N	\N	0.02	t	\N
1172	13	201000000038	201090000003	2026-04-18 01:39:42	1	3	\N	\N	0.00	t	4
946	11	201000000035	201090000002	2026-04-27 09:13:08	5548	1	\N	\N	0.00	t	1
1462	17	201742482326	201223344556	2026-04-10 05:45:08	1	3	\N	\N	0.01	t	\N
947	11	201000000019	201223344556	2026-04-06 16:29:08	1	3	\N	\N	0.00	t	4
1173	13	201000000015	201090000003	2026-04-04 23:02:42	1	3	\N	\N	0.01	t	\N
948	11	201000000042	201000000008	2026-04-01 03:01:08	1	3	\N	\N	0.00	t	4
949	11	201915057234	google.com	2026-03-30 18:10:08	30	2	\N	\N	0.00	t	\N
1174	13	201000000035	201090000003	2026-04-21 00:42:42	489	1	\N	\N	0.00	t	1
950	11	201884002998	youtube.com	2026-04-16 20:00:08	47	2	\N	\N	0.00	t	\N
1463	17	201277676035	whatsapp.net	2026-04-04 13:51:08	33	2	\N	\N	0.00	t	\N
951	11	201000000045	youtube.com	2026-04-07 04:05:08	11	2	\N	\N	0.00	t	\N
1175	13	201000000039	201000000008	2026-04-28 13:31:42	1	3	\N	\N	0.00	t	3
952	11	201291490356	facebook.com	2026-04-12 03:19:08	28	2	\N	\N	0.00	t	\N
953	11	201000000028	201000000008	2026-04-29 04:06:08	1	3	\N	\N	0.00	t	4
1176	13	201000000014	201090000002	2026-04-06 00:58:42	1	3	\N	\N	0.02	t	\N
954	11	201974222870	youtube.com	2026-03-30 16:51:08	50	2	\N	\N	0.00	t	\N
1464	17	201000000035	201223344556	2026-04-12 01:19:08	1	3	\N	\N	0.00	t	3
955	11	201000000030	201000000008	2026-04-09 05:29:08	3561	1	\N	\N	0.00	t	4
1177	13	201000000002	201223344556	2026-03-31 07:55:42	877	1	\N	\N	1.50	t	\N
956	11	201000000031	whatsapp.net	2026-04-21 04:00:08	17	2	\N	\N	0.00	t	\N
957	11	201000000015	201090000002	2026-04-18 12:19:08	1	3	\N	\N	0.01	t	\N
1178	13	201000000020	201090000002	2026-04-21 04:26:42	2286	1	\N	\N	0.00	t	4
958	11	201326784672	whatsapp.net	2026-04-06 12:17:08	47	2	\N	\N	0.00	t	\N
1465	17	201000000023	facebook.com	2026-04-12 06:34:08	39	2	\N	\N	0.00	t	\N
959	11	201259012646	google.com	2026-04-21 13:57:08	8	6	\N	\N	0.00	t	\N
1179	13	201000000001	201090000002	2026-03-30 22:11:42	1	3	\N	\N	0.05	t	\N
960	11	201665180852	201090000001	2026-03-31 08:28:08	3728	5	\N	\N	0.00	t	4
961	11	201000000001	201090000001	2026-04-19 16:57:08	1	7	\N	\N	0.05	t	\N
1180	13	201000000009	201090000001	2026-04-19 02:03:42	2766	1	\N	\N	9.40	t	\N
962	11	201393015335	youtube.com	2026-04-17 00:14:08	18	2	\N	\N	0.00	t	\N
1466	17	201420731899	201090000003	2026-04-05 15:43:08	2753	1	\N	\N	4.60	t	\N
963	11	201000000032	201090000001	2026-04-25 17:41:08	4952	1	\N	\N	0.00	t	1
1181	13	201000000021	fmrz-telecom.net	2026-04-22 08:37:42	1	2	\N	\N	0.00	t	\N
964	11	201000000019	201090000001	2026-04-06 22:36:08	1	3	\N	\N	0.00	t	4
965	11	201000000031	201090000003	2026-04-01 08:59:08	566	1	\N	\N	0.00	t	1
1182	13	201000000039	google.com	2026-04-15 04:07:42	1	2	\N	\N	0.00	t	\N
966	11	201590834655	201090000003	2026-04-28 14:38:08	1	3	\N	\N	0.01	t	\N
1467	17	201590288456	facebook.com	2026-04-04 06:52:08	25	2	\N	\N	0.00	t	\N
967	11	201807409782	201090000003	2026-04-02 09:55:08	2517	1	\N	\N	8.40	t	\N
1183	14	201000000046	201000000008	2026-04-27 15:03:08	1	3	\N	\N	0.00	t	4
968	11	201000000016	201090000002	2026-04-25 08:57:08	1	7	\N	\N	0.01	t	\N
969	11	201529549288	201090000001	2026-04-23 04:06:08	5839	1	\N	\N	9.80	t	\N
1184	14	201421638665	youtube.com	2026-04-18 00:24:08	34	2	\N	\N	0.00	t	\N
970	11	201193577939	201223344556	2026-04-10 19:06:08	5081	1	\N	\N	8.50	t	\N
1468	17	201399521241	201223344556	2026-04-12 15:00:08	1	7	\N	\N	0.05	t	\N
971	11	201000000010	whatsapp.net	2026-04-02 13:33:08	22	6	\N	\N	0.00	t	\N
1185	14	201000000022	youtube.com	2026-04-19 01:37:08	41	6	\N	\N	0.00	t	2
972	11	201421638665	201223344556	2026-04-23 05:19:08	6326	5	\N	\N	21.20	t	\N
973	11	201291490356	201090000003	2026-04-11 23:35:08	4111	5	\N	\N	3.45	t	\N
1186	14	201742482326	201223344556	2026-04-10 05:45:08	1	3	\N	\N	0.01	t	\N
974	11	201000000002	201000000008	2026-04-24 19:23:08	901	1	\N	\N	1.60	t	\N
1469	17	201000000002	google.com	2026-04-29 17:13:08	47	2	\N	\N	0.00	t	\N
975	11	201000000002	201090000003	2026-04-07 02:23:08	1	3	\N	\N	0.02	t	\N
1187	14	201277676035	whatsapp.net	2026-04-04 13:51:08	33	2	\N	\N	0.00	t	\N
976	11	201000000002	201090000003	2026-04-24 23:46:08	5572	1	\N	\N	9.30	t	\N
977	11	201000000002	youtube.com	2026-04-18 14:31:08	4515	2	\N	\N	0.00	t	\N
1188	14	201000000035	201223344556	2026-04-12 01:19:08	1	3	\N	\N	0.00	t	3
978	11	201000000002	201223344556	2026-04-19 11:26:08	1	3	\N	\N	0.02	t	\N
1470	17	201725767736	facebook.com	2026-04-26 14:43:08	26	6	\N	\N	0.00	t	\N
979	11	201000000002	201223344556	2026-04-02 02:43:08	1	3	\N	\N	0.02	t	\N
1189	14	201000000023	facebook.com	2026-04-12 06:34:08	39	2	\N	\N	0.00	t	\N
980	11	201000000002	youtube.com	2026-04-17 14:51:08	806	6	\N	\N	0.00	t	\N
981	11	201000000002	201223344556	2026-04-21 13:58:08	5976	5	\N	\N	10.00	t	\N
1190	14	201420731899	201090000003	2026-04-05 15:43:08	2753	1	\N	\N	4.60	t	\N
982	11	201000000002	201090000001	2026-04-25 20:02:08	1	3	\N	\N	0.02	t	\N
1471	17	201892594062	201223344556	2026-04-10 12:28:08	6102	5	\N	\N	20.40	t	\N
983	11	201000000002	201090000003	2026-04-06 12:48:08	1	7	\N	\N	0.02	t	\N
1191	14	201590288456	facebook.com	2026-04-04 06:52:08	25	2	\N	\N	0.00	t	\N
984	11	201000000002	201090000003	2026-04-14 21:08:08	2182	5	\N	\N	3.70	t	\N
985	11	201000000002	201090000002	2026-04-12 08:39:08	1	3	\N	\N	0.02	t	\N
1192	14	201399521241	201223344556	2026-04-12 15:00:08	1	7	\N	\N	0.05	t	\N
986	11	201000000002	201090000001	2026-04-05 09:01:08	1	3	\N	\N	0.02	t	\N
1472	17	201807409782	fmrz-telecom.net	2026-04-29 08:36:08	31	2	\N	\N	0.00	t	\N
987	11	201000000002	201090000001	2026-03-30 10:52:08	2713	1	\N	\N	4.60	t	\N
1193	14	201000000002	google.com	2026-04-29 17:13:08	47	2	\N	\N	0.00	t	\N
988	11	201000000002	201000000008	2026-04-08 20:11:08	1	3	\N	\N	0.02	t	\N
989	11	201000000002	201000000008	2026-04-20 16:04:08	1	3	\N	\N	0.02	t	\N
1194	14	201725767736	facebook.com	2026-04-26 14:43:08	26	6	\N	\N	0.00	t	\N
990	11	201000000002	201090000002	2026-04-08 03:34:08	1	7	\N	\N	0.02	t	\N
1473	17	201480812037	201090000003	2026-04-29 02:20:08	1	7	\N	\N	0.02	t	\N
991	11	201000000002	201090000002	2026-04-04 08:56:08	1	3	\N	\N	0.02	t	\N
1195	14	201892594062	201223344556	2026-04-10 12:28:08	6102	5	\N	\N	20.40	t	\N
992	11	201000000002	201090000003	2026-04-18 00:11:08	7104	1	\N	\N	11.90	t	\N
993	11	201000000002	whatsapp.net	2026-03-30 06:24:08	4289	2	\N	\N	0.00	t	\N
1196	14	201807409782	fmrz-telecom.net	2026-04-29 08:36:08	31	2	\N	\N	0.00	t	\N
994	11	201000000002	201090000003	2026-04-26 19:50:08	1	3	\N	\N	0.02	t	\N
1474	17	201731509325	201223344556	2026-04-27 09:22:08	4206	5	\N	\N	14.20	t	\N
995	11	201000000002	facebook.com	2026-04-09 04:10:08	2007	2	\N	\N	0.00	t	\N
1197	14	201480812037	201090000003	2026-04-29 02:20:08	1	7	\N	\N	0.02	t	\N
996	11	201000000002	201090000003	2026-04-07 19:14:08	6169	1	\N	\N	10.30	t	\N
997	11	201000000002	facebook.com	2026-04-21 03:01:08	4726	6	\N	\N	0.00	t	\N
1198	14	201731509325	201223344556	2026-04-27 09:22:08	4206	5	\N	\N	14.20	t	\N
998	11	201000000002	201090000001	2026-04-27 12:08:08	1	3	\N	\N	0.02	t	\N
1475	17	201000000063	201090000003	2026-04-07 22:18:08	1830	5	\N	\N	1.55	t	\N
999	11	201000000002	201223344556	2026-04-09 02:30:08	1	3	\N	\N	0.02	t	\N
1199	14	201000000063	201090000003	2026-04-07 22:18:08	1830	5	\N	\N	1.55	t	\N
1000	11	201000000002	facebook.com	2026-04-25 10:19:08	4179	6	\N	\N	0.00	t	\N
1001	11	201000000002	google.com	2026-04-13 13:00:08	996	6	\N	\N	0.00	t	\N
1200	14	201639909693	facebook.com	2026-04-19 08:29:08	48	2	\N	\N	0.00	t	\N
1002	11	201000000002	201090000002	2026-04-29 20:45:08	1774	5	\N	\N	3.00	t	\N
1476	17	201639909693	facebook.com	2026-04-19 08:29:08	48	2	\N	\N	0.00	t	\N
1003	11	201000000002	201223344556	2026-04-05 10:09:08	4052	5	\N	\N	6.80	t	\N
1201	14	201000000033	201090000002	2026-04-24 19:14:08	1	3	\N	\N	0.00	t	4
1004	11	201000000002	201090000001	2026-04-20 02:48:08	3066	1	\N	\N	5.20	t	\N
1005	11	201000000002	201090000002	2026-04-19 15:40:08	1882	1	\N	\N	3.20	t	\N
1202	14	201000000002	google.com	2026-04-02 03:48:08	44	2	\N	\N	0.00	t	\N
1006	11	201000000002	facebook.com	2026-04-23 03:08:08	1298	2	\N	\N	0.00	t	\N
1477	17	201000000033	201090000002	2026-04-24 19:14:08	1	3	\N	\N	0.00	t	4
1007	11	201000000002	201090000001	2026-03-30 23:04:08	1	3	\N	\N	0.02	t	\N
1203	14	201373685722	201223344556	2026-04-15 16:39:08	1	3	\N	\N	0.02	t	\N
1008	11	201000000002	201090000003	2026-04-09 02:01:08	1	3	\N	\N	0.02	t	\N
1009	11	201000000002	201223344556	2026-04-14 19:34:08	3441	1	\N	\N	5.80	t	\N
1204	14	201544739530	201090000003	2026-04-07 09:46:08	1	7	\N	\N	0.02	t	\N
1010	11	201000000002	201090000001	2026-04-12 10:38:08	2694	1	\N	\N	4.50	t	\N
1478	17	201000000002	google.com	2026-04-02 03:48:08	44	2	\N	\N	0.00	t	\N
1011	11	201000000002	201223344556	2026-04-01 21:21:08	2041	1	\N	\N	3.50	t	\N
1205	14	201000000044	201090000002	2026-04-22 05:36:08	4244	1	\N	\N	0.00	t	4
1012	11	201000000002	201090000003	2026-04-09 02:00:08	1	3	\N	\N	0.02	t	\N
1013	11	201000000002	201090000002	2026-04-07 22:43:08	1	3	\N	\N	0.02	t	\N
1206	14	201884002998	201090000002	2026-04-18 09:15:08	6772	5	\N	\N	22.60	t	\N
1014	11	201000000002	201000000008	2026-04-16 06:16:08	1	3	\N	\N	0.02	t	\N
1479	17	201373685722	201223344556	2026-04-15 16:39:08	1	3	\N	\N	0.02	t	\N
1015	11	201000000002	facebook.com	2026-04-04 14:50:08	2504	2	\N	\N	0.00	t	\N
1207	14	201590288456	201000000008	2026-04-25 15:44:08	4781	1	\N	\N	8.00	t	\N
1016	11	201000000002	201000000008	2026-04-24 10:18:08	1	3	\N	\N	0.02	t	\N
1017	11	201000000002	201090000001	2026-04-01 04:42:08	1	3	\N	\N	0.02	t	\N
1208	14	201615922194	201000000008	2026-04-12 21:43:08	6691	1	\N	\N	11.20	t	\N
1018	11	201000000002	201223344556	2026-04-16 18:13:08	1	7	\N	\N	0.02	t	\N
1480	17	201544739530	201090000003	2026-04-07 09:46:08	1	7	\N	\N	0.02	t	\N
1019	11	201000000002	201090000003	2026-04-22 21:56:08	5927	1	\N	\N	9.90	t	\N
1209	14	201699129335	201090000002	2026-04-15 00:35:08	1	3	\N	\N	0.02	t	\N
1020	11	201000000002	facebook.com	2026-04-10 09:18:08	3372	2	\N	\N	0.00	t	\N
1210	14	201573560989	fmrz-telecom.net	2026-04-08 15:31:08	8	2	\N	\N	0.00	t	\N
1021	11	201000000002	201090000003	2026-04-26 21:14:08	1	3	\N	\N	0.02	t	\N
1481	17	201000000044	201090000002	2026-04-22 05:36:08	4244	1	\N	\N	0.00	t	4
1022	11	201000000002	youtube.com	2026-04-01 09:16:08	583	2	\N	\N	0.00	t	\N
1211	14	201542776578	201090000003	2026-04-29 14:55:08	1	3	\N	\N	0.05	t	\N
1023	11	201000000002	201090000003	2026-04-26 09:00:08	1	3	\N	\N	0.02	t	\N
1024	11	201000000002	201000000008	2026-04-26 21:02:08	1	3	\N	\N	0.02	t	\N
1212	14	201814479848	201090000001	2026-04-11 15:30:08	1	3	\N	\N	0.05	t	\N
1025	11	201000000002	youtube.com	2026-04-03 23:01:08	2572	2	\N	\N	0.00	t	\N
1482	17	201884002998	201090000002	2026-04-18 09:15:08	6772	5	\N	\N	22.60	t	\N
1026	11	201000000002	201000000008	2026-04-16 00:34:08	3647	1	\N	\N	6.10	t	\N
1213	14	201000000035	whatsapp.net	2026-04-26 14:45:08	35	6	\N	\N	0.00	t	\N
1027	11	201000000002	201223344556	2026-04-18 14:55:08	1	3	\N	\N	0.02	t	\N
1028	11	201000000002	201090000001	2026-04-23 13:59:08	1	3	\N	\N	0.02	t	\N
1214	14	201542776578	201090000003	2026-04-11 13:42:08	7096	1	\N	\N	23.80	t	\N
1029	11	201000000002	201090000002	2026-04-16 15:40:08	1	3	\N	\N	0.02	t	\N
1483	17	201590288456	201000000008	2026-04-25 15:44:08	4781	1	\N	\N	8.00	t	\N
1030	11	201000000002	201090000002	2026-04-13 16:26:08	1	7	\N	\N	0.02	t	\N
1215	14	201000000021	facebook.com	2026-04-19 05:15:08	12	2	\N	\N	0.00	t	\N
1031	11	201000000002	201090000001	2026-04-27 19:07:08	1413	1	\N	\N	2.40	t	\N
1032	11	201000000002	201000000008	2026-04-27 09:19:08	6118	1	\N	\N	10.20	t	\N
1216	14	201912929712	201090000002	2026-04-09 10:39:08	1	7	\N	\N	0.02	t	\N
1033	11	201000000002	201223344556	2026-04-05 20:56:08	6439	1	\N	\N	10.80	t	\N
1484	17	201615922194	201000000008	2026-04-12 21:43:08	6691	1	\N	\N	11.20	t	\N
1034	11	201000000002	201223344556	2026-04-23 09:53:08	59	5	\N	\N	0.10	t	\N
1217	14	201000000011	201000000008	2026-04-02 05:53:08	1	7	\N	\N	0.05	t	\N
1035	11	201000000002	201090000003	2026-04-14 21:49:08	1505	1	\N	\N	2.60	t	\N
1036	11	201000000002	201090000001	2026-04-02 05:48:08	6858	1	\N	\N	11.50	t	\N
1218	14	201000000012	fmrz-telecom.net	2026-04-28 20:52:08	48	2	\N	\N	0.00	t	\N
1037	11	201000000002	facebook.com	2026-04-05 00:31:08	2628	2	\N	\N	0.00	t	\N
1485	17	201699129335	201090000002	2026-04-15 00:35:08	1	3	\N	\N	0.02	t	\N
1038	11	201000000002	fmrz-telecom.net	2026-03-30 11:10:08	2702	2	\N	\N	0.00	t	\N
1219	14	201649032416	201223344556	2026-04-09 20:04:08	1	3	\N	\N	0.02	t	\N
1039	11	201000000002	201090000003	2026-04-17 07:07:08	1	7	\N	\N	0.02	t	\N
1040	11	201000000002	201090000003	2026-04-14 17:02:08	1	3	\N	\N	0.02	t	\N
1220	14	201000000029	201000000008	2026-04-08 05:38:08	2931	5	\N	\N	0.00	t	4
1041	11	201000000002	201090000001	2026-04-27 02:27:08	1492	5	\N	\N	2.50	t	\N
1486	17	201573560989	fmrz-telecom.net	2026-04-08 15:31:08	8	2	\N	\N	0.00	t	\N
1042	11	201000000002	201090000002	2026-04-27 06:35:08	2582	1	\N	\N	4.40	t	\N
1221	14	201806374057	201090000002	2026-04-02 17:59:08	1	3	\N	\N	0.02	t	\N
1043	11	201000000002	fmrz-telecom.net	2026-04-06 20:29:08	815	6	\N	\N	0.00	t	\N
1044	11	201000000002	google.com	2026-04-26 12:42:08	1770	2	\N	\N	0.00	t	\N
1222	14	201000000035	201090000002	2026-04-27 09:13:08	5548	1	\N	\N	0.00	t	1
1045	11	201000000002	201000000008	2026-04-14 16:26:08	5463	1	\N	\N	9.20	t	\N
1487	17	201542776578	201090000003	2026-04-29 14:55:08	1	3	\N	\N	0.05	t	\N
1046	11	201000000002	201090000001	2026-04-20 07:13:08	1	7	\N	\N	0.02	t	\N
1223	14	201000000019	201223344556	2026-04-06 16:29:08	1	3	\N	\N	0.00	t	4
1047	11	201000000002	201223344556	2026-04-18 11:29:08	1	3	\N	\N	0.02	t	\N
1048	11	201000000002	201090000001	2026-04-05 08:19:08	1	7	\N	\N	0.02	t	\N
1488	17	201814479848	201090000001	2026-04-11 15:30:08	1	3	\N	\N	0.05	t	\N
1049	12	201000000001	201090000002	2026-04-04 08:01:24	1865	5	\N	\N	6.40	t	\N
1050	12	201000000001	youtube.com	2026-04-29 02:22:24	869	2	\N	\N	0.00	t	\N
1489	17	201000000035	whatsapp.net	2026-04-26 14:45:08	35	6	\N	\N	0.00	t	\N
1051	12	201000000001	201090000001	2026-04-12 16:26:24	1	3	\N	\N	0.05	t	\N
1052	12	201000000001	201090000003	2026-04-24 17:36:24	1	7	\N	\N	0.05	t	\N
1490	17	201542776578	201090000003	2026-04-11 13:42:08	7096	1	\N	\N	23.80	t	\N
1053	12	201000000001	201223344556	2026-04-03 06:50:24	1	3	\N	\N	0.05	t	\N
1054	12	201000000001	google.com	2026-04-02 05:58:24	883	6	\N	\N	0.00	t	\N
1491	17	201000000021	facebook.com	2026-04-19 05:15:08	12	2	\N	\N	0.00	t	\N
1055	12	201000000001	201090000003	2026-04-14 16:47:24	2959	1	\N	\N	10.00	t	\N
1056	12	201000000001	201090000001	2026-04-07 02:51:24	1	7	\N	\N	0.05	t	\N
1492	17	201912929712	201090000002	2026-04-09 10:39:08	1	7	\N	\N	0.02	t	\N
1057	12	201000000001	201223344556	2026-04-04 06:58:24	1	3	\N	\N	0.05	t	\N
1058	12	201000000001	201000000008	2026-03-31 11:15:24	1	3	\N	\N	0.05	t	\N
1493	17	201000000011	201000000008	2026-04-02 05:53:08	1	7	\N	\N	0.05	t	\N
1059	12	201000000001	201090000001	2026-03-31 08:04:24	1	3	\N	\N	0.05	t	\N
1060	12	201000000001	201090000003	2026-04-03 09:32:24	49	1	\N	\N	0.20	t	\N
1061	12	201000000001	youtube.com	2026-04-05 07:51:24	4125	2	\N	\N	0.00	t	\N
1494	17	201000000012	fmrz-telecom.net	2026-04-28 20:52:08	48	2	\N	\N	0.00	t	\N
1062	12	201000000001	fmrz-telecom.net	2026-04-16 05:43:24	3358	6	\N	\N	0.00	t	\N
1063	12	201000000001	201223344556	2026-04-27 17:10:24	4988	5	\N	\N	16.80	t	\N
1495	17	201649032416	201223344556	2026-04-09 20:04:08	1	3	\N	\N	0.02	t	\N
1064	12	201000000001	201090000002	2026-04-23 21:17:24	1	3	\N	\N	0.05	t	\N
1065	12	201000000001	201000000008	2026-04-28 10:13:24	1	3	\N	\N	0.05	t	\N
1496	17	201000000029	201000000008	2026-04-08 05:38:08	2931	5	\N	\N	0.00	t	4
1066	12	201000000001	201090000002	2026-04-01 01:56:24	1	7	\N	\N	0.05	t	\N
1067	12	201000000001	whatsapp.net	2026-04-25 19:39:24	1099	2	\N	\N	0.00	t	\N
1497	17	201806374057	201090000002	2026-04-02 17:59:08	1	3	\N	\N	0.02	t	\N
1068	12	201000000001	google.com	2026-04-24 13:30:24	4294	2	\N	\N	0.00	t	\N
1069	12	201000000001	201000000008	2026-04-28 17:08:24	1	3	\N	\N	0.05	t	\N
1498	17	201000000035	201090000002	2026-04-27 09:13:08	5548	1	\N	\N	0.00	t	1
1070	12	201000000001	201000000008	2026-04-17 02:54:24	1	3	\N	\N	0.05	t	\N
1071	12	201000000001	201223344556	2026-04-09 20:51:24	1	3	\N	\N	0.05	t	\N
1499	17	201000000019	201223344556	2026-04-06 16:29:08	1	3	\N	\N	0.00	t	4
1072	12	201000000001	201090000002	2026-04-15 04:12:24	5369	5	\N	\N	18.00	t	\N
1073	12	201000000001	201090000001	2026-04-28 21:43:24	1	7	\N	\N	0.05	t	\N
1500	17	201000000042	201000000008	2026-04-01 03:01:08	1	3	\N	\N	0.00	t	4
1074	12	201000000001	201090000001	2026-04-03 10:19:24	1	7	\N	\N	0.05	t	\N
1075	12	201000000001	201223344556	2026-04-16 13:28:24	1	3	\N	\N	0.05	t	\N
1501	17	201915057234	google.com	2026-03-30 18:10:08	30	2	\N	\N	0.00	t	\N
1076	12	201000000001	201000000008	2026-04-03 00:41:24	1	3	\N	\N	0.05	t	\N
1077	12	201000000001	201090000001	2026-04-26 18:47:24	1	7	\N	\N	0.05	t	\N
1502	17	201884002998	youtube.com	2026-04-16 20:00:08	47	2	\N	\N	0.00	t	\N
1078	12	201000000001	201090000001	2026-04-25 16:41:24	1	3	\N	\N	0.05	t	\N
1079	12	201000000001	201000000008	2026-04-29 19:20:24	1	3	\N	\N	0.05	t	\N
1503	17	201000000045	youtube.com	2026-04-07 04:05:08	11	2	\N	\N	0.00	t	\N
1080	12	201000000001	201090000002	2026-04-10 00:43:24	2377	1	\N	\N	8.00	t	\N
1081	12	201000000001	whatsapp.net	2026-04-26 08:49:24	2546	2	\N	\N	0.00	t	\N
1504	17	201291490356	facebook.com	2026-04-12 03:19:08	28	2	\N	\N	0.00	t	\N
1082	12	201000000001	whatsapp.net	2026-04-16 09:12:24	3231	2	\N	\N	0.00	t	\N
1083	12	201000000001	201090000003	2026-04-17 14:09:24	1	3	\N	\N	0.05	t	\N
1505	17	201000000028	201000000008	2026-04-29 04:06:08	1	3	\N	\N	0.00	t	4
1084	12	201000000001	201090000003	2026-04-04 01:22:24	6027	5	\N	\N	20.20	t	\N
1085	12	201000000001	201223344556	2026-04-14 11:42:24	1	3	\N	\N	0.05	t	\N
1506	17	201974222870	youtube.com	2026-03-30 16:51:08	50	2	\N	\N	0.00	t	\N
1086	12	201000000001	youtube.com	2026-04-11 00:46:24	1040	2	\N	\N	0.00	t	\N
1087	12	201000000001	google.com	2026-04-23 19:51:24	4533	2	\N	\N	0.00	t	\N
1507	17	201000000030	201000000008	2026-04-09 05:29:08	3561	1	\N	\N	0.00	t	4
1088	12	201000000001	201223344556	2026-04-26 15:48:24	5385	5	\N	\N	18.00	t	\N
1089	12	201000000001	201090000001	2026-04-04 12:49:24	1	3	\N	\N	0.05	t	\N
1508	17	201000000031	whatsapp.net	2026-04-21 04:00:08	17	2	\N	\N	0.00	t	\N
1090	12	201000000001	201000000008	2026-04-22 15:57:24	1	3	\N	\N	0.05	t	\N
1091	12	201000000001	facebook.com	2026-04-23 13:06:24	1751	6	\N	\N	0.00	t	\N
1509	17	201000000015	201090000002	2026-04-18 12:19:08	1	3	\N	\N	0.01	t	\N
1092	12	201000000001	201000000008	2026-04-08 13:15:24	5266	5	\N	\N	17.60	t	\N
1224	14	201000000042	201000000008	2026-04-01 03:01:08	1	3	\N	\N	0.00	t	4
1510	17	201326784672	whatsapp.net	2026-04-06 12:17:08	47	2	\N	\N	0.00	t	\N
1225	14	201915057234	google.com	2026-03-30 18:10:08	30	2	\N	\N	0.00	t	\N
1226	14	201884002998	youtube.com	2026-04-16 20:00:08	47	2	\N	\N	0.00	t	\N
1511	17	201259012646	google.com	2026-04-21 13:57:08	8	6	\N	\N	0.00	t	\N
1227	14	201000000045	youtube.com	2026-04-07 04:05:08	11	2	\N	\N	0.00	t	\N
1228	14	201291490356	facebook.com	2026-04-12 03:19:08	28	2	\N	\N	0.00	t	\N
1512	17	201665180852	201090000001	2026-03-31 08:28:08	3728	5	\N	\N	0.00	t	4
1229	14	201000000028	201000000008	2026-04-29 04:06:08	1	3	\N	\N	0.00	t	4
1230	14	201974222870	youtube.com	2026-03-30 16:51:08	50	2	\N	\N	0.00	t	\N
1513	17	201000000001	201090000001	2026-04-19 16:57:08	1	7	\N	\N	0.05	t	\N
1231	14	201000000030	201000000008	2026-04-09 05:29:08	3561	1	\N	\N	0.00	t	4
1232	14	201000000031	whatsapp.net	2026-04-21 04:00:08	17	2	\N	\N	0.00	t	\N
1514	17	201393015335	youtube.com	2026-04-17 00:14:08	18	2	\N	\N	0.00	t	\N
1233	14	201000000015	201090000002	2026-04-18 12:19:08	1	3	\N	\N	0.01	t	\N
1244	14	201000000016	201090000002	2026-04-25 08:57:08	1	7	\N	\N	0.01	t	\N
1515	17	201000000032	201090000001	2026-04-25 17:41:08	4952	1	\N	\N	0.00	t	1
1245	14	201529549288	201090000001	2026-04-23 04:06:08	5839	1	\N	\N	9.80	t	\N
1246	14	201193577939	201223344556	2026-04-10 19:06:08	5081	1	\N	\N	8.50	t	\N
1516	17	201000000019	201090000001	2026-04-06 22:36:08	1	3	\N	\N	0.00	t	4
1247	14	201000000010	whatsapp.net	2026-04-02 13:33:08	22	6	\N	\N	0.00	t	\N
1248	14	201421638665	201223344556	2026-04-23 05:19:08	6326	5	\N	\N	21.20	t	\N
1517	17	201000000031	201090000003	2026-04-01 08:59:08	566	1	\N	\N	0.00	t	1
1249	14	201291490356	201090000003	2026-04-11 23:35:08	4111	5	\N	\N	3.45	t	\N
1250	14	201000000002	201000000008	2026-04-24 19:23:08	901	1	\N	\N	1.60	t	\N
1518	17	201590834655	201090000003	2026-04-28 14:38:08	1	3	\N	\N	0.01	t	\N
1251	14	201000000002	201090000003	2026-04-07 02:23:08	1	3	\N	\N	0.02	t	\N
1252	14	201000000002	201090000003	2026-04-24 23:46:08	5572	1	\N	\N	9.30	t	\N
1519	17	201807409782	201090000003	2026-04-02 09:55:08	2517	1	\N	\N	8.40	t	\N
1253	14	201000000002	youtube.com	2026-04-18 14:31:08	4515	2	\N	\N	0.00	t	\N
1254	14	201000000002	201223344556	2026-04-19 11:26:08	1	3	\N	\N	0.02	t	\N
1520	17	201000000016	201090000002	2026-04-25 08:57:08	1	7	\N	\N	0.01	t	\N
1255	14	201000000002	201223344556	2026-04-02 02:43:08	1	3	\N	\N	0.02	t	\N
1256	14	201000000002	youtube.com	2026-04-17 14:51:08	806	6	\N	\N	0.00	t	\N
1521	17	201529549288	201090000001	2026-04-23 04:06:08	5839	1	\N	\N	9.80	t	\N
1257	14	201000000002	201223344556	2026-04-21 13:58:08	5976	5	\N	\N	10.00	t	\N
1258	14	201000000002	201090000001	2026-04-25 20:02:08	1	3	\N	\N	0.02	t	\N
1522	17	201193577939	201223344556	2026-04-10 19:06:08	5081	1	\N	\N	8.50	t	\N
1259	14	201000000002	201090000003	2026-04-06 12:48:08	1	7	\N	\N	0.02	t	\N
1260	14	201000000002	201090000003	2026-04-14 21:08:08	2182	5	\N	\N	3.70	t	\N
1523	17	201000000010	whatsapp.net	2026-04-02 13:33:08	22	6	\N	\N	0.00	t	\N
1261	14	201000000002	201090000002	2026-04-12 08:39:08	1	3	\N	\N	0.02	t	\N
1262	14	201000000002	201090000001	2026-04-05 09:01:08	1	3	\N	\N	0.02	t	\N
1524	17	201421638665	201223344556	2026-04-23 05:19:08	6326	5	\N	\N	21.20	t	\N
1263	14	201000000002	201090000001	2026-03-30 10:52:08	2713	1	\N	\N	4.60	t	\N
1264	14	201000000002	201000000008	2026-04-08 20:11:08	1	3	\N	\N	0.02	t	\N
1525	17	201291490356	201090000003	2026-04-11 23:35:08	4111	5	\N	\N	3.45	t	\N
1265	14	201000000002	201000000008	2026-04-20 16:04:08	1	3	\N	\N	0.02	t	\N
1266	14	201000000002	201090000002	2026-04-08 03:34:08	1	7	\N	\N	0.02	t	\N
1526	17	201000000002	201000000008	2026-04-24 19:23:08	901	1	\N	\N	1.60	t	\N
1267	14	201000000002	201090000002	2026-04-04 08:56:08	1	3	\N	\N	0.02	t	\N
1268	14	201000000002	201090000003	2026-04-18 00:11:08	7104	1	\N	\N	11.90	t	\N
1527	17	201000000002	201090000003	2026-04-07 02:23:08	1	3	\N	\N	0.02	t	\N
1269	14	201000000002	whatsapp.net	2026-03-30 06:24:08	4289	2	\N	\N	0.00	t	\N
1270	14	201000000002	201090000003	2026-04-26 19:50:08	1	3	\N	\N	0.02	t	\N
1528	17	201000000002	201090000003	2026-04-24 23:46:08	5572	1	\N	\N	9.30	t	\N
1271	14	201000000002	facebook.com	2026-04-09 04:10:08	2007	2	\N	\N	0.00	t	\N
1272	14	201000000002	201090000003	2026-04-07 19:14:08	6169	1	\N	\N	10.30	t	\N
1529	17	201000000002	youtube.com	2026-04-18 14:31:08	4515	2	\N	\N	0.00	t	\N
1273	14	201000000002	facebook.com	2026-04-21 03:01:08	4726	6	\N	\N	0.00	t	\N
1274	14	201000000002	201090000001	2026-04-27 12:08:08	1	3	\N	\N	0.02	t	\N
1530	17	201000000002	201223344556	2026-04-19 11:26:08	1	3	\N	\N	0.02	t	\N
1275	14	201000000002	201223344556	2026-04-09 02:30:08	1	3	\N	\N	0.02	t	\N
1276	14	201000000002	facebook.com	2026-04-25 10:19:08	4179	6	\N	\N	0.00	t	\N
1531	17	201000000002	201223344556	2026-04-02 02:43:08	1	3	\N	\N	0.02	t	\N
1277	14	201000000002	google.com	2026-04-13 13:00:08	996	6	\N	\N	0.00	t	\N
1278	14	201000000002	201090000002	2026-04-29 20:45:08	1774	5	\N	\N	3.00	t	\N
1532	17	201000000002	youtube.com	2026-04-17 14:51:08	806	6	\N	\N	0.00	t	\N
1279	14	201000000002	201223344556	2026-04-05 10:09:08	4052	5	\N	\N	6.80	t	\N
1280	14	201000000002	201090000001	2026-04-20 02:48:08	3066	1	\N	\N	5.20	t	\N
1533	17	201000000002	201223344556	2026-04-21 13:58:08	5976	5	\N	\N	10.00	t	\N
1281	14	201000000002	201090000002	2026-04-19 15:40:08	1882	1	\N	\N	3.20	t	\N
1282	14	201000000002	facebook.com	2026-04-23 03:08:08	1298	2	\N	\N	0.00	t	\N
1534	17	201000000002	201090000001	2026-04-25 20:02:08	1	3	\N	\N	0.02	t	\N
1283	14	201000000002	201090000001	2026-03-30 23:04:08	1	3	\N	\N	0.02	t	\N
1284	14	201000000002	201090000003	2026-04-09 02:01:08	1	3	\N	\N	0.02	t	\N
1535	17	201000000002	201090000003	2026-04-06 12:48:08	1	7	\N	\N	0.02	t	\N
1285	14	201000000002	201223344556	2026-04-14 19:34:08	3441	1	\N	\N	5.80	t	\N
1286	14	201000000002	201090000001	2026-04-12 10:38:08	2694	1	\N	\N	4.50	t	\N
1536	17	201000000002	201090000003	2026-04-14 21:08:08	2182	5	\N	\N	3.70	t	\N
1287	14	201000000002	201223344556	2026-04-01 21:21:08	2041	1	\N	\N	3.50	t	\N
1288	14	201000000002	201090000003	2026-04-09 02:00:08	1	3	\N	\N	0.02	t	\N
1537	17	201000000002	201090000002	2026-04-12 08:39:08	1	3	\N	\N	0.02	t	\N
1289	14	201000000002	201090000002	2026-04-07 22:43:08	1	3	\N	\N	0.02	t	\N
1290	14	201000000002	201000000008	2026-04-16 06:16:08	1	3	\N	\N	0.02	t	\N
1538	17	201000000002	201090000001	2026-04-05 09:01:08	1	3	\N	\N	0.02	t	\N
1291	14	201000000002	facebook.com	2026-04-04 14:50:08	2504	2	\N	\N	0.00	t	\N
1292	14	201000000002	201000000008	2026-04-24 10:18:08	1	3	\N	\N	0.02	t	\N
1539	17	201000000002	201090000001	2026-03-30 10:52:08	2713	1	\N	\N	4.60	t	\N
1293	14	201000000002	201090000001	2026-04-01 04:42:08	1	3	\N	\N	0.02	t	\N
1294	14	201000000002	201223344556	2026-04-16 18:13:08	1	7	\N	\N	0.02	t	\N
1540	17	201000000002	201000000008	2026-04-08 20:11:08	1	3	\N	\N	0.02	t	\N
1295	14	201000000002	201090000003	2026-04-22 21:56:08	5927	1	\N	\N	9.90	t	\N
1296	14	201000000002	facebook.com	2026-04-10 09:18:08	3372	2	\N	\N	0.00	t	\N
1541	17	201000000002	201000000008	2026-04-20 16:04:08	1	3	\N	\N	0.02	t	\N
1297	14	201000000002	201090000003	2026-04-26 21:14:08	1	3	\N	\N	0.02	t	\N
1298	14	201000000002	youtube.com	2026-04-01 09:16:08	583	2	\N	\N	0.00	t	\N
1542	17	201000000002	201090000002	2026-04-08 03:34:08	1	7	\N	\N	0.02	t	\N
1299	14	201000000002	201090000003	2026-04-26 09:00:08	1	3	\N	\N	0.02	t	\N
1300	14	201000000002	201000000008	2026-04-26 21:02:08	1	3	\N	\N	0.02	t	\N
1543	17	201000000002	201090000002	2026-04-04 08:56:08	1	3	\N	\N	0.02	t	\N
1301	14	201000000002	youtube.com	2026-04-03 23:01:08	2572	2	\N	\N	0.00	t	\N
1302	14	201000000002	201000000008	2026-04-16 00:34:08	3647	1	\N	\N	6.10	t	\N
1544	17	201000000002	201090000003	2026-04-18 00:11:08	7104	1	\N	\N	11.90	t	\N
1303	14	201000000002	201223344556	2026-04-18 14:55:08	1	3	\N	\N	0.02	t	\N
1304	14	201000000002	201090000001	2026-04-23 13:59:08	1	3	\N	\N	0.02	t	\N
1545	17	201000000002	whatsapp.net	2026-03-30 06:24:08	4289	2	\N	\N	0.00	t	\N
1305	14	201000000002	201090000002	2026-04-16 15:40:08	1	3	\N	\N	0.02	t	\N
1306	14	201000000002	201090000002	2026-04-13 16:26:08	1	7	\N	\N	0.02	t	\N
1546	17	201000000002	201090000003	2026-04-26 19:50:08	1	3	\N	\N	0.02	t	\N
1307	14	201000000002	201090000001	2026-04-27 19:07:08	1413	1	\N	\N	2.40	t	\N
1308	14	201000000002	201000000008	2026-04-27 09:19:08	6118	1	\N	\N	10.20	t	\N
1547	17	201000000002	facebook.com	2026-04-09 04:10:08	2007	2	\N	\N	0.00	t	\N
1309	14	201000000002	201223344556	2026-04-05 20:56:08	6439	1	\N	\N	10.80	t	\N
1310	14	201000000002	201223344556	2026-04-23 09:53:08	59	5	\N	\N	0.10	t	\N
1548	17	201000000002	201090000003	2026-04-07 19:14:08	6169	1	\N	\N	10.30	t	\N
1311	14	201000000002	201090000003	2026-04-14 21:49:08	1505	1	\N	\N	2.60	t	\N
1312	14	201000000002	201090000001	2026-04-02 05:48:08	6858	1	\N	\N	11.50	t	\N
1549	17	201000000002	facebook.com	2026-04-21 03:01:08	4726	6	\N	\N	0.00	t	\N
1313	14	201000000002	facebook.com	2026-04-05 00:31:08	2628	2	\N	\N	0.00	t	\N
1314	14	201000000002	fmrz-telecom.net	2026-03-30 11:10:08	2702	2	\N	\N	0.00	t	\N
1550	17	201000000002	201090000001	2026-04-27 12:08:08	1	3	\N	\N	0.02	t	\N
1315	14	201000000002	201090000003	2026-04-17 07:07:08	1	7	\N	\N	0.02	t	\N
1316	14	201000000002	201090000003	2026-04-14 17:02:08	1	3	\N	\N	0.02	t	\N
1551	17	201000000002	201223344556	2026-04-09 02:30:08	1	3	\N	\N	0.02	t	\N
1317	14	201000000002	201090000001	2026-04-27 02:27:08	1492	5	\N	\N	2.50	t	\N
1318	14	201000000002	201090000002	2026-04-27 06:35:08	2582	1	\N	\N	4.40	t	\N
1552	17	201000000002	facebook.com	2026-04-25 10:19:08	4179	6	\N	\N	0.00	t	\N
1319	14	201000000002	fmrz-telecom.net	2026-04-06 20:29:08	815	6	\N	\N	0.00	t	\N
1320	14	201000000002	google.com	2026-04-26 12:42:08	1770	2	\N	\N	0.00	t	\N
1553	17	201000000002	google.com	2026-04-13 13:00:08	996	6	\N	\N	0.00	t	\N
1321	14	201000000002	201000000008	2026-04-14 16:26:08	5463	1	\N	\N	9.20	t	\N
1322	14	201000000002	201090000001	2026-04-20 07:13:08	1	7	\N	\N	0.02	t	\N
1554	17	201000000002	201090000002	2026-04-29 20:45:08	1774	5	\N	\N	3.00	t	\N
1323	14	201000000002	201223344556	2026-04-18 11:29:08	1	3	\N	\N	0.02	t	\N
1324	14	201000000002	201090000001	2026-04-05 08:19:08	1	7	\N	\N	0.02	t	\N
1555	17	201000000002	201223344556	2026-04-05 10:09:08	4052	5	\N	\N	6.80	t	\N
1325	15	201000000001	201090000002	2026-04-04 08:01:24	1865	5	\N	\N	6.40	t	\N
1326	15	201000000001	youtube.com	2026-04-29 02:22:24	869	2	\N	\N	0.00	t	\N
1556	17	201000000002	201090000001	2026-04-20 02:48:08	3066	1	\N	\N	5.20	t	\N
1327	15	201000000001	201090000001	2026-04-12 16:26:24	1	3	\N	\N	0.05	t	\N
1328	15	201000000001	201090000003	2026-04-24 17:36:24	1	7	\N	\N	0.05	t	\N
1557	17	201000000002	201090000002	2026-04-19 15:40:08	1882	1	\N	\N	3.20	t	\N
1329	15	201000000001	201223344556	2026-04-03 06:50:24	1	3	\N	\N	0.05	t	\N
1330	15	201000000001	google.com	2026-04-02 05:58:24	883	6	\N	\N	0.00	t	\N
1558	17	201000000002	facebook.com	2026-04-23 03:08:08	1298	2	\N	\N	0.00	t	\N
1331	15	201000000001	201090000003	2026-04-14 16:47:24	2959	1	\N	\N	10.00	t	\N
1332	15	201000000001	201090000001	2026-04-07 02:51:24	1	7	\N	\N	0.05	t	\N
1559	17	201000000002	201090000001	2026-03-30 23:04:08	1	3	\N	\N	0.02	t	\N
1333	15	201000000001	201223344556	2026-04-04 06:58:24	1	3	\N	\N	0.05	t	\N
1334	15	201000000001	201000000008	2026-03-31 11:15:24	1	3	\N	\N	0.05	t	\N
1560	17	201000000002	201090000003	2026-04-09 02:01:08	1	3	\N	\N	0.02	t	\N
1335	15	201000000001	201090000001	2026-03-31 08:04:24	1	3	\N	\N	0.05	t	\N
1336	15	201000000001	201090000003	2026-04-03 09:32:24	49	1	\N	\N	0.20	t	\N
1561	17	201000000002	201223344556	2026-04-14 19:34:08	3441	1	\N	\N	5.80	t	\N
1337	15	201000000001	youtube.com	2026-04-05 07:51:24	4125	2	\N	\N	0.00	t	\N
1338	15	201000000001	fmrz-telecom.net	2026-04-16 05:43:24	3358	6	\N	\N	0.00	t	\N
1562	17	201000000002	201090000001	2026-04-12 10:38:08	2694	1	\N	\N	4.50	t	\N
1339	15	201000000001	201223344556	2026-04-27 17:10:24	4988	5	\N	\N	16.80	t	\N
1340	15	201000000001	201090000002	2026-04-23 21:17:24	1	3	\N	\N	0.05	t	\N
1563	17	201000000002	201223344556	2026-04-01 21:21:08	2041	1	\N	\N	3.50	t	\N
1341	15	201000000001	201000000008	2026-04-28 10:13:24	1	3	\N	\N	0.05	t	\N
1342	15	201000000001	201090000002	2026-04-01 01:56:24	1	7	\N	\N	0.05	t	\N
1564	17	201000000002	201090000003	2026-04-09 02:00:08	1	3	\N	\N	0.02	t	\N
1343	15	201000000001	whatsapp.net	2026-04-25 19:39:24	1099	2	\N	\N	0.00	t	\N
1344	15	201000000001	google.com	2026-04-24 13:30:24	4294	2	\N	\N	0.00	t	\N
1565	17	201000000002	201090000002	2026-04-07 22:43:08	1	3	\N	\N	0.02	t	\N
1345	15	201000000001	201000000008	2026-04-28 17:08:24	1	3	\N	\N	0.05	t	\N
1346	15	201000000001	201000000008	2026-04-17 02:54:24	1	3	\N	\N	0.05	t	\N
1566	17	201000000002	201000000008	2026-04-16 06:16:08	1	3	\N	\N	0.02	t	\N
1347	15	201000000001	201223344556	2026-04-09 20:51:24	1	3	\N	\N	0.05	t	\N
1348	15	201000000001	201090000002	2026-04-15 04:12:24	5369	5	\N	\N	18.00	t	\N
1567	17	201000000002	facebook.com	2026-04-04 14:50:08	2504	2	\N	\N	0.00	t	\N
1349	15	201000000001	201090000001	2026-04-28 21:43:24	1	7	\N	\N	0.05	t	\N
1350	15	201000000001	201090000001	2026-04-03 10:19:24	1	7	\N	\N	0.05	t	\N
1568	17	201000000002	201000000008	2026-04-24 10:18:08	1	3	\N	\N	0.02	t	\N
1351	15	201000000001	201223344556	2026-04-16 13:28:24	1	3	\N	\N	0.05	t	\N
1352	15	201000000001	201000000008	2026-04-03 00:41:24	1	3	\N	\N	0.05	t	\N
1569	17	201000000002	201090000001	2026-04-01 04:42:08	1	3	\N	\N	0.02	t	\N
1353	15	201000000001	201090000001	2026-04-26 18:47:24	1	7	\N	\N	0.05	t	\N
1354	15	201000000001	201090000001	2026-04-25 16:41:24	1	3	\N	\N	0.05	t	\N
1570	17	201000000002	201223344556	2026-04-16 18:13:08	1	7	\N	\N	0.02	t	\N
1355	15	201000000001	201000000008	2026-04-29 19:20:24	1	3	\N	\N	0.05	t	\N
1356	15	201000000001	201090000002	2026-04-10 00:43:24	2377	1	\N	\N	8.00	t	\N
1571	17	201000000002	201090000003	2026-04-22 21:56:08	5927	1	\N	\N	9.90	t	\N
1357	15	201000000001	whatsapp.net	2026-04-26 08:49:24	2546	2	\N	\N	0.00	t	\N
1358	15	201000000001	whatsapp.net	2026-04-16 09:12:24	3231	2	\N	\N	0.00	t	\N
1572	17	201000000002	facebook.com	2026-04-10 09:18:08	3372	2	\N	\N	0.00	t	\N
1359	15	201000000001	201090000003	2026-04-17 14:09:24	1	3	\N	\N	0.05	t	\N
1360	15	201000000001	201090000003	2026-04-04 01:22:24	6027	5	\N	\N	20.20	t	\N
1573	17	201000000002	201090000003	2026-04-26 21:14:08	1	3	\N	\N	0.02	t	\N
1361	15	201000000001	201223344556	2026-04-14 11:42:24	1	3	\N	\N	0.05	t	\N
1362	15	201000000001	youtube.com	2026-04-11 00:46:24	1040	2	\N	\N	0.00	t	\N
1574	17	201000000002	youtube.com	2026-04-01 09:16:08	583	2	\N	\N	0.00	t	\N
1363	15	201000000001	google.com	2026-04-23 19:51:24	4533	2	\N	\N	0.00	t	\N
1364	15	201000000001	201223344556	2026-04-26 15:48:24	5385	5	\N	\N	18.00	t	\N
1365	15	201000000001	201090000001	2026-04-04 12:49:24	1	3	\N	\N	0.05	t	\N
1575	17	201000000002	201090000003	2026-04-26 09:00:08	1	3	\N	\N	0.02	t	\N
1366	15	201000000001	201000000008	2026-04-22 15:57:24	1	3	\N	\N	0.05	t	\N
1367	15	201000000001	facebook.com	2026-04-23 13:06:24	1751	6	\N	\N	0.00	t	\N
1576	17	201000000002	201000000008	2026-04-26 21:02:08	1	3	\N	\N	0.02	t	\N
1368	15	201000000001	201000000008	2026-04-08 13:15:24	5266	5	\N	\N	17.60	t	\N
1369	15	201000000001	201090000001	2026-04-18 23:48:24	4977	1	\N	\N	16.60	t	\N
1577	17	201000000002	youtube.com	2026-04-03 23:01:08	2572	2	\N	\N	0.00	t	\N
1370	15	201000000001	whatsapp.net	2026-04-14 16:43:24	1868	2	\N	\N	0.00	t	\N
1371	15	201000000001	201000000008	2026-04-03 05:34:24	1	3	\N	\N	0.05	t	\N
1578	17	201000000002	201000000008	2026-04-16 00:34:08	3647	1	\N	\N	6.10	t	\N
1372	15	201000000001	201223344556	2026-04-05 14:59:24	2677	1	\N	\N	9.00	t	\N
1373	15	201000000001	201223344556	2026-04-17 13:42:24	1	3	\N	\N	0.05	t	\N
1579	17	201000000002	201223344556	2026-04-18 14:55:08	1	3	\N	\N	0.02	t	\N
1374	15	201000000001	fmrz-telecom.net	2026-04-08 09:27:24	2082	6	\N	\N	0.00	t	\N
1375	15	201000000002	201000000008	2026-04-06 23:04:24	810	1	\N	\N	1.40	t	\N
1580	17	201000000002	201090000001	2026-04-23 13:59:08	1	3	\N	\N	0.02	t	\N
1376	15	201000000002	201090000001	2026-04-29 10:06:24	5913	1	\N	\N	9.90	t	\N
1377	15	201000000002	facebook.com	2026-04-15 07:54:24	827	2	\N	\N	0.00	t	\N
1581	17	201000000002	201090000002	2026-04-16 15:40:08	1	3	\N	\N	0.02	t	\N
1378	15	201000000002	google.com	2026-04-15 01:40:24	3549	2	\N	\N	0.00	t	\N
1379	15	201000000002	201000000008	2026-04-25 09:50:24	1	7	\N	\N	0.02	t	\N
1582	17	201000000002	201090000002	2026-04-13 16:26:08	1	7	\N	\N	0.02	t	\N
1380	15	201000000002	201223344556	2026-04-07 22:40:24	1	3	\N	\N	0.02	t	\N
1381	15	201000000002	fmrz-telecom.net	2026-04-09 00:44:24	3069	6	\N	\N	0.00	t	\N
1583	17	201000000002	201090000001	2026-04-27 19:07:08	1413	1	\N	\N	2.40	t	\N
1382	15	201000000002	youtube.com	2026-04-28 19:51:24	2239	2	\N	\N	0.00	t	\N
1383	15	201000000002	google.com	2026-04-15 09:42:24	5097	2	\N	\N	0.00	t	\N
1584	17	201000000002	201000000008	2026-04-27 09:19:08	6118	1	\N	\N	10.20	t	\N
1384	15	201000000002	youtube.com	2026-04-28 07:25:24	2865	2	\N	\N	0.00	t	\N
1385	15	201000000002	201090000003	2026-03-31 05:25:24	1	3	\N	\N	0.02	t	\N
1585	17	201000000002	201223344556	2026-04-05 20:56:08	6439	1	\N	\N	10.80	t	\N
1386	15	201000000002	201090000002	2026-04-22 18:34:24	4604	1	\N	\N	7.70	t	\N
1387	15	201000000002	201090000002	2026-04-03 22:44:24	5402	1	\N	\N	9.10	t	\N
1586	17	201000000002	201223344556	2026-04-23 09:53:08	59	5	\N	\N	0.10	t	\N
1388	15	201000000002	201090000001	2026-04-09 07:58:24	1	3	\N	\N	0.02	t	\N
1389	15	201000000002	whatsapp.net	2026-04-21 13:20:24	2335	2	\N	\N	0.00	t	\N
1587	17	201000000002	201090000003	2026-04-14 21:49:08	1505	1	\N	\N	2.60	t	\N
1390	15	201000000002	201090000002	2026-04-03 06:48:24	1	3	\N	\N	0.02	t	\N
1391	15	201000000002	201090000001	2026-04-04 18:44:24	1	7	\N	\N	0.02	t	\N
1588	17	201000000002	201090000001	2026-04-02 05:48:08	6858	1	\N	\N	11.50	t	\N
1392	15	201000000002	201090000002	2026-04-11 11:34:24	3793	1	\N	\N	6.40	t	\N
1393	15	201000000002	201000000008	2026-04-20 07:24:24	4769	1	\N	\N	8.00	t	\N
1589	17	201000000002	facebook.com	2026-04-05 00:31:08	2628	2	\N	\N	0.00	t	\N
1394	15	201000000002	201090000003	2026-04-18 00:45:24	5789	5	\N	\N	9.70	t	\N
1395	15	201000000002	201223344556	2026-04-27 07:36:24	1	3	\N	\N	0.02	t	\N
1590	17	201000000002	fmrz-telecom.net	2026-03-30 11:10:08	2702	2	\N	\N	0.00	t	\N
1396	15	201000000002	201090000002	2026-04-28 17:18:24	5534	1	\N	\N	9.30	t	\N
1397	15	201000000002	201223344556	2026-04-06 16:45:24	1	3	\N	\N	0.02	t	\N
1591	17	201000000002	201090000003	2026-04-17 07:07:08	1	7	\N	\N	0.02	t	\N
1398	15	201000000002	201090000001	2026-04-28 14:47:24	2804	5	\N	\N	4.70	t	\N
1399	15	201000000002	201223344556	2026-04-24 12:05:24	1	3	\N	\N	0.02	t	\N
1592	17	201000000002	201090000003	2026-04-14 17:02:08	1	3	\N	\N	0.02	t	\N
1400	15	201000000002	201223344556	2026-04-20 16:50:24	5346	1	\N	\N	9.00	t	\N
1401	15	201000000002	201090000003	2026-04-21 08:34:24	1015	1	\N	\N	1.70	t	\N
1593	17	201000000002	201090000001	2026-04-27 02:27:08	1492	5	\N	\N	2.50	t	\N
1402	15	201000000002	whatsapp.net	2026-03-31 16:18:24	1039	6	\N	\N	0.00	t	\N
1403	15	201000000002	201223344556	2026-04-29 01:37:24	393	5	\N	\N	0.70	t	\N
1594	17	201000000002	201090000002	2026-04-27 06:35:08	2582	1	\N	\N	4.40	t	\N
1404	15	201000000002	whatsapp.net	2026-04-29 07:53:24	3175	2	\N	\N	0.00	t	\N
1405	15	201000000002	201090000003	2026-04-24 08:40:24	4538	1	\N	\N	7.60	t	\N
1406	15	201000000002	201090000003	2026-04-25 12:02:24	1	3	\N	\N	0.02	t	\N
1595	17	201000000002	fmrz-telecom.net	2026-04-06 20:29:08	815	6	\N	\N	0.00	t	\N
1407	15	201000000002	youtube.com	2026-04-12 08:11:24	4808	6	\N	\N	0.00	t	\N
1408	15	201000000002	201223344556	2026-04-06 21:13:24	7095	1	\N	\N	11.90	t	\N
1596	17	201000000002	google.com	2026-04-26 12:42:08	1770	2	\N	\N	0.00	t	\N
1409	15	201000000002	201090000003	2026-04-09 22:56:24	1	3	\N	\N	0.02	t	\N
1410	15	201000000002	201090000001	2026-04-24 21:59:24	1	3	\N	\N	0.02	t	\N
1597	17	201000000002	201000000008	2026-04-14 16:26:08	5463	1	\N	\N	9.20	t	\N
1411	15	201000000002	201223344556	2026-04-23 04:51:24	1	3	\N	\N	0.02	t	\N
1412	15	201000000002	201223344556	2026-04-06 01:14:24	1	3	\N	\N	0.02	t	\N
1598	17	201000000002	201090000001	2026-04-20 07:13:08	1	7	\N	\N	0.02	t	\N
1413	15	201000000002	201090000003	2026-04-21 10:22:24	1	3	\N	\N	0.02	t	\N
1414	15	201000000002	201223344556	2026-04-17 20:54:24	6119	1	\N	\N	10.20	t	\N
1599	17	201000000002	201223344556	2026-04-18 11:29:08	1	3	\N	\N	0.02	t	\N
1415	15	201000000002	201090000002	2026-04-09 01:58:24	1	7	\N	\N	0.02	t	\N
1416	15	201000000002	facebook.com	2026-04-22 12:05:24	2801	2	\N	\N	0.00	t	\N
1600	17	201000000002	201090000001	2026-04-05 08:19:08	1	7	\N	\N	0.02	t	\N
1417	15	201000000002	201090000003	2026-04-23 10:24:24	1	3	\N	\N	0.02	t	\N
1418	15	201000000002	201090000003	2026-04-28 12:01:24	1036	1	\N	\N	1.80	t	\N
1601	18	201000000001	201090000002	2026-04-04 08:01:24	1865	5	\N	\N	6.40	t	\N
1419	15	201000000002	facebook.com	2026-04-01 20:10:24	1907	2	\N	\N	0.00	t	\N
1420	15	201000000002	201090000003	2026-04-14 23:01:24	6727	1	\N	\N	11.30	t	\N
1602	18	201000000001	youtube.com	2026-04-29 02:22:24	869	2	\N	\N	0.00	t	\N
1421	15	201000000002	201223344556	2026-04-27 13:49:24	1	3	\N	\N	0.02	t	\N
1422	15	201000000002	whatsapp.net	2026-04-07 17:39:24	595	2	\N	\N	0.00	t	\N
1603	18	201000000001	201090000001	2026-04-12 16:26:24	1	3	\N	\N	0.05	t	\N
1423	15	201000000002	201223344556	2026-04-06 05:49:24	3290	5	\N	\N	5.50	t	\N
1424	15	201000000002	google.com	2026-04-09 12:16:24	4685	2	\N	\N	0.00	t	\N
1604	18	201000000001	201090000003	2026-04-24 17:36:24	1	7	\N	\N	0.05	t	\N
1605	18	201000000001	201223344556	2026-04-03 06:50:24	1	3	\N	\N	0.05	t	\N
1606	18	201000000001	google.com	2026-04-02 05:58:24	883	6	\N	\N	0.00	t	\N
1607	18	201000000001	201090000003	2026-04-14 16:47:24	2959	1	\N	\N	10.00	t	\N
1608	18	201000000001	201090000001	2026-04-07 02:51:24	1	7	\N	\N	0.05	t	\N
1609	18	201000000001	201223344556	2026-04-04 06:58:24	1	3	\N	\N	0.05	t	\N
1610	18	201000000001	201000000008	2026-03-31 11:15:24	1	3	\N	\N	0.05	t	\N
1611	18	201000000001	201090000001	2026-03-31 08:04:24	1	3	\N	\N	0.05	t	\N
1612	18	201000000001	201090000003	2026-04-03 09:32:24	49	1	\N	\N	0.20	t	\N
1613	18	201000000001	youtube.com	2026-04-05 07:51:24	4125	2	\N	\N	0.00	t	\N
1614	18	201000000001	fmrz-telecom.net	2026-04-16 05:43:24	3358	6	\N	\N	0.00	t	\N
1615	18	201000000001	201223344556	2026-04-27 17:10:24	4988	5	\N	\N	16.80	t	\N
1616	18	201000000001	201090000002	2026-04-23 21:17:24	1	3	\N	\N	0.05	t	\N
1617	18	201000000001	201000000008	2026-04-28 10:13:24	1	3	\N	\N	0.05	t	\N
1618	18	201000000001	201090000002	2026-04-01 01:56:24	1	7	\N	\N	0.05	t	\N
1619	18	201000000001	whatsapp.net	2026-04-25 19:39:24	1099	2	\N	\N	0.00	t	\N
1620	18	201000000001	google.com	2026-04-24 13:30:24	4294	2	\N	\N	0.00	t	\N
1621	18	201000000001	201000000008	2026-04-28 17:08:24	1	3	\N	\N	0.05	t	\N
1622	18	201000000001	201000000008	2026-04-17 02:54:24	1	3	\N	\N	0.05	t	\N
1623	18	201000000001	201223344556	2026-04-09 20:51:24	1	3	\N	\N	0.05	t	\N
1624	18	201000000001	201090000002	2026-04-15 04:12:24	5369	5	\N	\N	18.00	t	\N
1625	18	201000000001	201090000001	2026-04-28 21:43:24	1	7	\N	\N	0.05	t	\N
1626	18	201000000001	201090000001	2026-04-03 10:19:24	1	7	\N	\N	0.05	t	\N
1627	18	201000000001	201223344556	2026-04-16 13:28:24	1	3	\N	\N	0.05	t	\N
1628	18	201000000001	201000000008	2026-04-03 00:41:24	1	3	\N	\N	0.05	t	\N
1629	18	201000000001	201090000001	2026-04-26 18:47:24	1	7	\N	\N	0.05	t	\N
1630	18	201000000001	201090000001	2026-04-25 16:41:24	1	3	\N	\N	0.05	t	\N
1631	18	201000000001	201000000008	2026-04-29 19:20:24	1	3	\N	\N	0.05	t	\N
1632	18	201000000001	201090000002	2026-04-10 00:43:24	2377	1	\N	\N	8.00	t	\N
1633	18	201000000001	whatsapp.net	2026-04-26 08:49:24	2546	2	\N	\N	0.00	t	\N
1634	18	201000000001	whatsapp.net	2026-04-16 09:12:24	3231	2	\N	\N	0.00	t	\N
1635	18	201000000001	201090000003	2026-04-17 14:09:24	1	3	\N	\N	0.05	t	\N
1636	18	201000000001	201090000003	2026-04-04 01:22:24	6027	5	\N	\N	20.20	t	\N
1637	18	201000000001	201223344556	2026-04-14 11:42:24	1	3	\N	\N	0.05	t	\N
1638	18	201000000001	youtube.com	2026-04-11 00:46:24	1040	2	\N	\N	0.00	t	\N
1639	18	201000000001	google.com	2026-04-23 19:51:24	4533	2	\N	\N	0.00	t	\N
1640	18	201000000001	201223344556	2026-04-26 15:48:24	5385	5	\N	\N	18.00	t	\N
1641	18	201000000001	201090000001	2026-04-04 12:49:24	1	3	\N	\N	0.05	t	\N
1642	18	201000000001	201000000008	2026-04-22 15:57:24	1	3	\N	\N	0.05	t	\N
1643	18	201000000001	facebook.com	2026-04-23 13:06:24	1751	6	\N	\N	0.00	t	\N
1644	18	201000000001	201000000008	2026-04-08 13:15:24	5266	5	\N	\N	17.60	t	\N
1645	18	201000000001	201090000001	2026-04-18 23:48:24	4977	1	\N	\N	16.60	t	\N
1646	18	201000000001	whatsapp.net	2026-04-14 16:43:24	1868	2	\N	\N	0.00	t	\N
1647	18	201000000001	201000000008	2026-04-03 05:34:24	1	3	\N	\N	0.05	t	\N
1648	18	201000000001	201223344556	2026-04-05 14:59:24	2677	1	\N	\N	9.00	t	\N
1649	18	201000000001	201223344556	2026-04-17 13:42:24	1	3	\N	\N	0.05	t	\N
1650	18	201000000001	fmrz-telecom.net	2026-04-08 09:27:24	2082	6	\N	\N	0.00	t	\N
1651	18	201000000002	201000000008	2026-04-06 23:04:24	810	1	\N	\N	1.40	t	\N
1652	18	201000000002	201090000001	2026-04-29 10:06:24	5913	1	\N	\N	9.90	t	\N
1653	18	201000000002	facebook.com	2026-04-15 07:54:24	827	2	\N	\N	0.00	t	\N
1654	18	201000000002	google.com	2026-04-15 01:40:24	3549	2	\N	\N	0.00	t	\N
1655	18	201000000002	201000000008	2026-04-25 09:50:24	1	7	\N	\N	0.02	t	\N
1656	18	201000000002	201223344556	2026-04-07 22:40:24	1	3	\N	\N	0.02	t	\N
1657	18	201000000002	fmrz-telecom.net	2026-04-09 00:44:24	3069	6	\N	\N	0.00	t	\N
1658	18	201000000002	youtube.com	2026-04-28 19:51:24	2239	2	\N	\N	0.00	t	\N
1659	18	201000000002	google.com	2026-04-15 09:42:24	5097	2	\N	\N	0.00	t	\N
1660	18	201000000002	youtube.com	2026-04-28 07:25:24	2865	2	\N	\N	0.00	t	\N
1661	18	201000000002	201090000003	2026-03-31 05:25:24	1	3	\N	\N	0.02	t	\N
1662	18	201000000002	201090000002	2026-04-22 18:34:24	4604	1	\N	\N	7.70	t	\N
1663	18	201000000002	201090000002	2026-04-03 22:44:24	5402	1	\N	\N	9.10	t	\N
1664	18	201000000002	201090000001	2026-04-09 07:58:24	1	3	\N	\N	0.02	t	\N
1665	18	201000000002	whatsapp.net	2026-04-21 13:20:24	2335	2	\N	\N	0.00	t	\N
1666	18	201000000002	201090000002	2026-04-03 06:48:24	1	3	\N	\N	0.02	t	\N
1667	18	201000000002	201090000001	2026-04-04 18:44:24	1	7	\N	\N	0.02	t	\N
1668	18	201000000002	201090000002	2026-04-11 11:34:24	3793	1	\N	\N	6.40	t	\N
1669	18	201000000002	201000000008	2026-04-20 07:24:24	4769	1	\N	\N	8.00	t	\N
1670	18	201000000002	201090000003	2026-04-18 00:45:24	5789	5	\N	\N	9.70	t	\N
1671	18	201000000002	201223344556	2026-04-27 07:36:24	1	3	\N	\N	0.02	t	\N
1672	18	201000000002	201090000002	2026-04-28 17:18:24	5534	1	\N	\N	9.30	t	\N
1673	18	201000000002	201223344556	2026-04-06 16:45:24	1	3	\N	\N	0.02	t	\N
1674	18	201000000002	201090000001	2026-04-28 14:47:24	2804	5	\N	\N	4.70	t	\N
1675	18	201000000002	201223344556	2026-04-24 12:05:24	1	3	\N	\N	0.02	t	\N
1676	18	201000000002	201223344556	2026-04-20 16:50:24	5346	1	\N	\N	9.00	t	\N
1677	18	201000000002	201090000003	2026-04-21 08:34:24	1015	1	\N	\N	1.70	t	\N
1678	18	201000000002	whatsapp.net	2026-03-31 16:18:24	1039	6	\N	\N	0.00	t	\N
1679	18	201000000002	201223344556	2026-04-29 01:37:24	393	5	\N	\N	0.70	t	\N
1680	18	201000000002	whatsapp.net	2026-04-29 07:53:24	3175	2	\N	\N	0.00	t	\N
1681	18	201000000002	201090000003	2026-04-24 08:40:24	4538	1	\N	\N	7.60	t	\N
1682	18	201000000002	201090000003	2026-04-25 12:02:24	1	3	\N	\N	0.02	t	\N
1683	18	201000000002	youtube.com	2026-04-12 08:11:24	4808	6	\N	\N	0.00	t	\N
1684	18	201000000002	201223344556	2026-04-06 21:13:24	7095	1	\N	\N	11.90	t	\N
1685	18	201000000002	201090000003	2026-04-09 22:56:24	1	3	\N	\N	0.02	t	\N
1686	18	201000000002	201090000001	2026-04-24 21:59:24	1	3	\N	\N	0.02	t	\N
1687	18	201000000002	201223344556	2026-04-23 04:51:24	1	3	\N	\N	0.02	t	\N
1688	18	201000000002	201223344556	2026-04-06 01:14:24	1	3	\N	\N	0.02	t	\N
1689	18	201000000002	201090000003	2026-04-21 10:22:24	1	3	\N	\N	0.02	t	\N
1690	18	201000000002	201223344556	2026-04-17 20:54:24	6119	1	\N	\N	10.20	t	\N
1691	18	201000000002	201090000002	2026-04-09 01:58:24	1	7	\N	\N	0.02	t	\N
1692	18	201000000002	facebook.com	2026-04-22 12:05:24	2801	2	\N	\N	0.00	t	\N
1693	18	201000000002	201090000003	2026-04-23 10:24:24	1	3	\N	\N	0.02	t	\N
1694	18	201000000002	201090000003	2026-04-28 12:01:24	1036	1	\N	\N	1.80	t	\N
1695	18	201000000002	facebook.com	2026-04-01 20:10:24	1907	2	\N	\N	0.00	t	\N
1696	18	201000000002	201090000003	2026-04-14 23:01:24	6727	1	\N	\N	11.30	t	\N
1697	18	201000000002	201223344556	2026-04-27 13:49:24	1	3	\N	\N	0.02	t	\N
1698	18	201000000002	whatsapp.net	2026-04-07 17:39:24	595	2	\N	\N	0.00	t	\N
1699	18	201000000002	201223344556	2026-04-06 05:49:24	3290	5	\N	\N	5.50	t	\N
1700	18	201000000002	google.com	2026-04-09 12:16:24	4685	2	\N	\N	0.00	t	\N
1701	19	201633386447	201090000002	2026-04-30 00:23:33	1	3	\N	\N	0.02	t	\N
1702	19	201000000037	201090000003	2026-04-18 15:05:33	583	1	\N	\N	0.00	t	1
1703	19	201573560989	201223344556	2026-04-02 01:28:33	201	1	\N	\N	0.40	t	\N
1704	19	201000000037	201223344556	2026-04-10 07:08:33	2444	1	\N	\N	0.00	t	1
1705	19	201256368244	201000000008	2026-04-05 00:15:33	2524	1	\N	\N	4.30	t	\N
1706	19	201000000047	facebook.com	2026-04-03 14:18:33	1	2	\N	\N	0.00	t	4
1707	19	201470072023	201090000003	2026-04-09 05:09:33	1	3	\N	\N	0.01	t	\N
1708	19	201000000021	201090000003	2026-04-01 07:33:33	1	3	\N	\N	0.00	t	3
1709	19	201000000025	youtube.com	2026-04-27 21:20:33	1	2	\N	\N	0.00	t	4
1710	19	201000000044	201090000003	2026-04-07 00:22:33	1	3	\N	\N	0.00	t	4
1711	19	201000000005	201223344556	2026-04-15 07:11:33	2187	1	\N	\N	7.40	t	\N
1712	19	201399521241	whatsapp.net	2026-04-30 05:16:33	1	2	\N	\N	0.00	t	\N
1713	19	201639748141	201090000003	2026-04-06 10:34:33	1	3	\N	\N	0.02	t	\N
1714	19	201259012646	201090000002	2026-04-17 17:04:33	1	3	\N	\N	0.02	t	\N
1715	19	201884002998	google.com	2026-04-16 19:49:33	1	2	\N	\N	0.00	t	\N
1716	19	201000000019	201223344556	2026-04-18 18:33:33	1	3	\N	\N	0.00	t	4
1717	19	201000000032	201090000002	2026-04-08 18:16:33	1	3	\N	\N	0.00	t	3
1718	19	201000000047	201090000002	2026-04-22 22:54:33	1	3	\N	\N	0.00	t	4
1719	19	201481351069	201000000008	2026-04-21 04:24:33	60	1	\N	\N	0.05	t	\N
1720	19	201000000041	google.com	2026-04-22 19:25:33	1	2	\N	\N	0.00	t	\N
1721	19	201000000042	201090000003	2026-04-10 10:05:33	3514	1	\N	\N	0.00	t	4
1722	19	201405070503	201090000002	2026-04-14 06:35:33	1199	1	\N	\N	1.00	t	\N
1723	19	201905415497	201090000003	2026-04-24 09:31:33	2257	1	\N	\N	3.80	t	\N
1724	19	201529549288	201223344556	2026-04-17 13:11:33	1632	1	\N	\N	2.80	t	\N
1725	19	201000000011	whatsapp.net	2026-04-20 05:57:33	1	2	\N	\N	0.00	t	\N
1726	19	201000000007	201090000002	2026-04-17 23:26:33	650	1	\N	\N	2.20	t	\N
1727	19	201742482326	201090000001	2026-04-20 13:54:33	1	3	\N	\N	0.01	t	\N
1728	19	201313455535	201090000002	2026-04-21 07:42:33	1	3	\N	\N	0.02	t	\N
1729	19	201193975708	fmrz-telecom.net	2026-04-29 06:04:33	1	2	\N	\N	0.00	t	\N
1730	19	201974222870	google.com	2026-04-06 08:13:33	1	2	\N	\N	0.00	t	\N
1731	19	201000000004	201223344556	2026-04-28 22:12:33	2823	1	\N	\N	4.80	t	\N
1732	19	201000000022	201000000008	2026-04-02 21:06:33	1	3	\N	\N	0.00	t	3
1733	19	201837344300	201090000003	2026-04-05 00:36:33	1	3	\N	\N	0.01	t	\N
1734	19	201000000044	201223344556	2026-04-18 00:04:33	708	1	\N	\N	0.00	t	4
1735	19	201000000001	201223344556	2026-04-07 19:06:33	2797	1	\N	\N	9.40	t	\N
1736	19	201000000039	201090000002	2026-04-02 21:59:33	37	1	\N	\N	0.00	t	1
1737	19	201000000035	201090000002	2026-04-22 07:25:33	1	3	\N	\N	0.00	t	3
1738	19	201590288456	youtube.com	2026-04-24 21:05:33	1	2	\N	\N	0.00	t	\N
1739	19	201000000034	201090000003	2026-03-31 13:59:33	2497	1	\N	\N	0.00	t	4
1740	19	201742482326	201090000002	2026-04-18 23:23:33	1	3	\N	\N	0.01	t	\N
1741	19	201699129335	201000000008	2026-04-25 21:32:33	2345	1	\N	\N	4.00	t	\N
1742	19	201229447201	facebook.com	2026-04-13 10:54:33	1	2	\N	\N	0.00	t	\N
1743	19	201649032416	whatsapp.net	2026-04-05 14:26:33	1	2	\N	\N	0.00	t	\N
1744	19	201000000031	201090000003	2026-04-13 22:08:33	685	1	\N	\N	0.00	t	1
1745	19	201456036855	fmrz-telecom.net	2026-04-29 03:08:33	1	2	\N	\N	0.00	t	\N
1746	19	201924767903	google.com	2026-04-24 23:45:33	1	2	\N	\N	0.00	t	\N
1747	19	201336493947	201090000003	2026-04-12 12:28:33	2993	1	\N	\N	5.00	t	\N
1748	19	201481351069	google.com	2026-04-04 16:07:33	1	2	\N	\N	0.00	t	\N
1749	19	201000000001	fmrz-telecom.net	2026-04-25 00:59:33	1	2	\N	\N	0.00	t	\N
1750	19	201367143168	201090000003	2026-04-04 09:41:33	1760	1	\N	\N	1.50	t	\N
1751	19	201393015335	youtube.com	2026-04-07 20:19:33	1	2	\N	\N	0.00	t	\N
1752	19	201000000019	google.com	2026-04-17 17:32:33	1	2	\N	\N	0.00	t	4
1753	19	201972954141	201090000002	2026-04-11 04:07:33	1	3	\N	\N	0.05	t	\N
1754	19	201000000017	201090000002	2026-04-05 05:38:33	1	3	\N	\N	0.02	t	\N
1755	19	201892594062	201000000008	2026-04-26 11:47:33	1	3	\N	\N	0.05	t	\N
1756	19	201000000027	201090000002	2026-04-12 01:27:33	1	3	\N	\N	0.00	t	4
1757	19	201742482326	201000000008	2026-04-14 02:46:33	938	1	\N	\N	0.80	t	\N
1758	19	201000000002	201223344556	2026-04-28 15:43:33	1	3	\N	\N	0.02	t	\N
1759	19	201000000011	201000000008	2026-04-21 04:09:33	1	3	\N	\N	0.05	t	\N
1760	19	201639748141	201090000001	2026-04-16 14:15:33	1	3	\N	\N	0.02	t	\N
1761	19	201699129335	facebook.com	2026-04-03 05:26:33	1	2	\N	\N	0.00	t	\N
1762	19	201690095272	201223344556	2026-04-21 02:09:33	1	3	\N	\N	0.05	t	\N
1763	19	201000000047	fmrz-telecom.net	2026-04-15 03:45:33	1	2	\N	\N	0.00	t	4
1764	19	201837344300	201223344556	2026-04-26 04:20:33	1	3	\N	\N	0.01	t	\N
1765	19	201699129335	201000000008	2026-04-29 05:46:33	505	1	\N	\N	0.90	t	\N
1766	19	201481789330	201223344556	2026-04-14 14:06:33	1017	1	\N	\N	0.85	t	\N
1767	19	201193577939	201000000008	2026-04-01 01:32:33	1	3	\N	\N	0.02	t	\N
1768	19	201892594062	201090000002	2026-04-04 06:08:33	395	1	\N	\N	1.40	t	\N
1769	19	201000000048	201090000003	2026-04-29 10:01:33	1	3	\N	\N	0.00	t	4
1770	19	201229447201	201223344556	2026-04-15 01:21:33	1	3	\N	\N	0.05	t	\N
1771	19	201373685722	201000000008	2026-04-28 09:09:33	3005	1	\N	\N	5.10	t	\N
1772	19	201151750893	google.com	2026-04-04 07:07:33	1	2	\N	\N	0.00	t	\N
1773	19	201699129335	facebook.com	2026-04-25 12:14:33	1	2	\N	\N	0.00	t	\N
1774	19	201000000028	facebook.com	2026-04-06 18:02:33	1	2	\N	\N	0.00	t	4
1775	19	201421638665	201090000003	2026-04-17 21:56:33	1	3	\N	\N	0.05	t	\N
1776	19	201850051553	201223344556	2026-04-15 22:02:33	345	1	\N	\N	0.60	t	\N
1777	19	201742482326	201223344556	2026-04-16 13:16:33	2575	1	\N	\N	2.15	t	\N
1778	19	201193577939	whatsapp.net	2026-04-29 20:49:33	1	2	\N	\N	0.00	t	\N
1779	19	201000000042	201090000001	2026-04-09 07:40:33	1	3	\N	\N	0.00	t	4
1780	19	201000000024	whatsapp.net	2026-04-09 04:28:33	1	2	\N	\N	0.00	t	\N
1781	19	201314768886	201000000008	2026-04-07 04:53:33	1	3	\N	\N	0.01	t	\N
1782	19	201811678129	fmrz-telecom.net	2026-04-30 03:33:33	1	2	\N	\N	0.00	t	\N
1783	19	201000000001	201000000008	2026-04-11 15:46:33	3314	1	\N	\N	11.20	t	\N
1784	19	201393015335	201090000002	2026-04-24 09:16:33	2269	1	\N	\N	3.80	t	\N
1785	19	201892594062	201000000008	2026-04-23 19:29:33	1	3	\N	\N	0.05	t	\N
1786	19	201000000014	201090000003	2026-04-22 20:37:33	1	3	\N	\N	0.02	t	\N
1787	19	201291490356	201090000001	2026-04-08 02:14:33	656	1	\N	\N	0.55	t	\N
1788	19	201590288456	201000000008	2026-04-12 00:02:33	1	3	\N	\N	0.02	t	\N
1789	19	201544739530	google.com	2026-04-04 10:02:33	1	2	\N	\N	0.00	t	\N
1790	19	201000000007	facebook.com	2026-04-26 22:16:33	1	2	\N	\N	0.00	t	\N
1791	19	201946234738	youtube.com	2026-04-27 01:42:33	1	2	\N	\N	0.00	t	\N
1792	19	201000000034	201000000008	2026-04-07 09:45:33	2383	1	\N	\N	0.00	t	4
1793	19	201807409782	201223344556	2026-04-20 13:03:33	1	3	\N	\N	0.05	t	\N
1794	19	201405070503	201000000008	2026-04-26 13:03:33	2815	1	\N	\N	2.35	t	\N
1795	19	201747010017	201090000002	2026-04-05 13:58:33	1	3	\N	\N	0.02	t	\N
1796	19	201650751254	facebook.com	2026-04-18 06:25:33	1	2	\N	\N	0.00	t	\N
1797	19	201000000038	201090000003	2026-04-13 20:21:33	1780	1	\N	\N	0.00	t	4
1798	19	201193577939	201000000008	2026-04-21 14:07:33	1039	1	\N	\N	1.80	t	\N
1799	19	201000000038	201000000008	2026-04-17 23:49:33	3348	1	\N	\N	0.00	t	4
1800	19	201421638665	201090000001	2026-04-03 13:23:33	3075	1	\N	\N	10.40	t	\N
1801	19	201000000005	201090000002	2026-04-09 15:46:33	1367	1	\N	\N	4.60	t	\N
1802	19	201456036855	201090000003	2026-04-26 17:52:33	1	3	\N	\N	0.02	t	\N
1803	19	201000000027	201000000008	2026-04-06 11:08:33	1912	1	\N	\N	0.00	t	4
1804	19	201763359068	youtube.com	2026-04-05 08:10:33	1	2	\N	\N	0.00	t	\N
1805	19	201000000044	google.com	2026-04-20 16:35:33	1	2	\N	\N	0.00	t	4
1806	19	201421638665	201090000003	2026-04-27 12:32:33	1	3	\N	\N	0.05	t	\N
1807	19	201000000033	201090000001	2026-04-12 21:30:33	1	3	\N	\N	0.00	t	4
1808	19	201000000003	201090000002	2026-04-14 03:21:33	1	3	\N	\N	0.05	t	\N
1809	19	201000000016	google.com	2026-04-17 06:07:33	1	2	\N	\N	0.00	t	\N
1810	19	201650751254	fmrz-telecom.net	2026-04-25 15:44:33	1	2	\N	\N	0.00	t	\N
1811	19	201690095272	201223344556	2026-04-21 18:56:33	1	3	\N	\N	0.05	t	\N
1812	19	201529549288	google.com	2026-04-05 04:16:33	1	2	\N	\N	0.00	t	\N
1813	19	201259012646	201000000008	2026-04-26 10:59:33	1	3	\N	\N	0.02	t	\N
1814	19	201486313285	201000000008	2026-04-18 17:48:33	1	3	\N	\N	0.05	t	\N
1815	19	201000000047	201223344556	2026-04-07 15:20:33	1	3	\N	\N	0.00	t	4
1816	19	201615922194	facebook.com	2026-04-29 15:35:33	1	2	\N	\N	0.00	t	\N
1817	19	201837344300	fmrz-telecom.net	2026-04-10 07:53:33	1	2	\N	\N	0.00	t	\N
1818	19	201851881403	whatsapp.net	2026-04-08 04:09:33	1	2	\N	\N	0.00	t	\N
1819	19	201313455535	whatsapp.net	2026-04-08 19:13:33	1	2	\N	\N	0.00	t	\N
1820	19	201000000020	201223344556	2026-04-01 05:59:33	1	3	\N	\N	0.00	t	4
1821	19	201000000033	201090000003	2026-04-29 10:31:33	1387	1	\N	\N	0.00	t	4
1822	19	201542776578	201090000001	2026-04-03 22:35:33	2512	1	\N	\N	8.40	t	\N
1823	19	201277676035	google.com	2026-04-11 09:36:33	1	2	\N	\N	0.00	t	\N
1824	19	201229447201	201000000008	2026-04-29 13:32:33	1814	1	\N	\N	6.20	t	\N
1825	19	201573560989	201000000008	2026-04-13 09:28:33	570	1	\N	\N	1.00	t	\N
1826	19	201742482326	201000000008	2026-04-01 13:43:33	1133	1	\N	\N	0.95	t	\N
1827	19	201000000015	facebook.com	2026-04-27 01:25:33	1	2	\N	\N	0.00	t	\N
1828	19	201405070503	201223344556	2026-04-26 08:56:33	1	3	\N	\N	0.01	t	\N
1829	19	201000000015	201090000002	2026-04-21 13:31:33	1	3	\N	\N	0.01	t	\N
\.


--
-- Data for Name: contract; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.contract (id, user_account_id, rateplan_id, msisdn, status, credit_limit, available_credit) FROM stdin;
201	205	4	201000000050	active	100.00	100.00
2	3	2	201000000002	active	500.00	-573.62
174	175	1	201000000023	active	300.00	300.00
18	19	1	201000000018	terminated	200.00	200.00
200	203	3	201000000063	active	100.00	95.35
91	92	3	201690025215	terminated	1000.00	1000.00
113	114	2	201480470252	suspended_debt	500.00	500.00
168	169	2	201633386447	active	500.00	499.96
146	147	2	201256368244	active	500.00	495.68
138	139	1	201908458100	terminated	200.00	200.00
68	69	1	201884002998	active	200.00	123.30
111	112	2	201905415497	active	500.00	494.48
67	68	2	201173680950	active	500.00	499.10
194	195	1	201000000043	active	300.00	300.00
152	153	2	201122438398	active	500.00	499.98
165	166	2	201974222870	active	500.00	498.38
117	118	3	201679439439	active	1000.00	997.75
188	189	1	201000000037	active	300.00	300.00
110	111	3	201233454802	suspended_debt	1000.00	1000.00
149	150	2	201639748141	active	500.00	492.76
76	77	2	201665180852	active	500.00	499.98
89	90	1	201432260526	active	200.00	195.80
114	115	3	201725767736	active	1000.00	999.99
66	67	2	201772327638	active	500.00	495.88
164	165	1	201814479848	active	200.00	196.75
64	65	2	201912929712	active	500.00	495.62
103	104	1	201880747142	active	200.00	179.20
182	183	1	201000000031	active	300.00	300.00
131	132	2	201699129335	active	500.00	495.00
159	160	3	201590834655	active	1000.00	997.90
104	105	1	201811678129	active	200.00	189.85
162	163	2	201590288456	active	500.00	463.48
151	152	2	201544739530	active	500.00	499.92
71	72	1	201807409782	active	200.00	166.30
112	113	2	201296640008	suspended	500.00	500.00
115	116	1	201743707822	suspended	200.00	200.00
129	130	2	201747010017	active	500.00	499.96
118	119	2	201701152592	suspended	500.00	500.00
120	121	1	201920696979	suspended_debt	200.00	200.00
121	122	2	201694803366	suspended	500.00	500.00
109	110	2	201193577939	active	500.00	464.14
128	129	3	201650751254	active	1000.00	999.09
125	126	2	201787063869	suspended	500.00	500.00
126	127	1	201907682029	suspended	200.00	200.00
95	96	2	201529549288	active	500.00	454.70
137	138	2	201259012646	active	500.00	497.64
96	97	3	201837344300	active	1000.00	999.96
132	133	2	201317072958	suspended	500.00	500.00
133	134	1	201585740806	suspended	200.00	200.00
135	136	3	201681313506	suspended	1000.00	1000.00
116	117	2	201851881403	active	500.00	494.44
140	141	1	201929116979	suspended_debt	200.00	200.00
141	142	2	201804593641	suspended_debt	500.00	500.00
136	137	1	201229447201	active	200.00	183.45
92	93	3	201742482326	active	1000.00	990.93
1	2	1	201000000001	active	200.00	179.40
142	143	1	201149365223	suspended	200.00	200.00
144	145	2	201289319888	suspended_debt	500.00	500.00
145	146	2	201786405082	suspended	500.00	500.00
147	148	3	201672879810	suspended_debt	1000.00	1000.00
148	149	2	201931499262	suspended	500.00	500.00
150	151	1	201576737239	suspended	200.00	200.00
153	154	2	201795118881	suspended_debt	500.00	500.00
154	155	1	201251180810	suspended	200.00	200.00
155	156	2	201443034851	suspended	500.00	500.00
156	157	2	201195845868	suspended	500.00	500.00
157	158	1	201621384437	suspended	200.00	200.00
158	159	2	201640950043	suspended_debt	500.00	500.00
160	161	1	201605591348	suspended_debt	200.00	200.00
163	164	3	201239747722	suspended_debt	1000.00	1000.00
166	167	1	201430418861	suspended_debt	200.00	200.00
167	168	2	201207540095	suspended	500.00	500.00
12	13	2	201000000012	active	500.00	500.00
31	32	3	201915057234	active	1000.00	997.00
10	11	2	201000000010	active	500.00	495.58
19	20	2	201193975708	active	500.00	489.60
4	5	2	201000000004	active	500.00	486.30
53	54	2	201924767903	active	500.00	495.00
33	34	2	201336493947	active	500.00	491.70
41	42	1	201972954141	active	200.00	188.35
17	18	2	201000000017	active	500.00	499.90
11	12	1	201000000011	active	200.00	199.80
28	29	3	201538007758	active	1000.00	999.99
46	47	3	201481789330	active	1000.00	999.14
51	52	1	201151750893	active	200.00	200.00
13	14	1	201000000013	suspended	200.00	200.00
47	48	1	201130026448	active	200.00	189.20
42	43	2	201393015335	active	500.00	496.20
14	15	2	201000000014	active	500.00	470.08
20	21	3	201291490356	active	1000.00	989.10
21	22	2	201646390202	suspended	500.00	500.00
23	24	3	201280350684	suspended_debt	1000.00	1000.00
7	8	1	201000000007	active	200.00	197.55
26	27	1	201568821728	suspended	200.00	200.00
37	38	1	201946234738	active	200.00	199.95
29	30	2	201212953273	suspended_debt	500.00	500.00
30	31	2	201335082038	suspended	500.00	500.00
5	6	1	201000000005	active	200.00	152.35
34	35	1	201763337754	suspended	200.00	200.00
35	36	2	201236672367	suspended	500.00	500.00
38	39	2	201898797034	suspended	500.00	500.00
39	40	1	201916592994	suspended	200.00	200.00
40	41	2	201713840244	suspended	500.00	500.00
3	4	1	201000000003	active	200.00	180.10
43	44	3	201498533478	suspended	1000.00	1000.00
44	45	2	201438107240	suspended	500.00	500.00
45	46	2	201583130923	suspended_debt	500.00	500.00
6	7	2	201000000006	active	500.00	499.98
48	49	1	201671461373	suspended	200.00	200.00
49	50	2	201321500366	suspended_debt	500.00	500.00
50	51	1	201743344137	suspended	200.00	200.00
52	53	3	201167872429	suspended	1000.00	1000.00
54	55	3	201288927515	suspended	1000.00	1000.00
16	17	3	201000000016	active	1000.00	998.67
59	60	2	201737734249	suspended	500.00	500.00
61	62	3	201484340865	suspended	1000.00	1000.00
62	63	3	201238698221	suspended	1000.00	1000.00
25	26	1	201690095272	active	200.00	199.85
8	9	2	201000000008	active	500.00	494.38
27	28	1	201486313285	active	200.00	189.75
56	57	2	201615922194	active	500.00	450.70
32	33	2	201313455535	active	500.00	499.96
60	61	1	201542776578	active	200.00	96.20
36	37	1	201236262234	active	200.00	200.00
57	58	2	201277676035	active	500.00	499.98
22	23	2	201573560989	active	500.00	493.10
9	10	1	201000000009	active	200.00	158.35
15	16	3	201000000015	active	1000.00	996.21
24	25	3	201568820914	active	1000.00	999.95
55	56	1	201818037329	active	200.00	187.05
58	59	2	201845026506	active	500.00	497.46
63	64	1	201309264655	suspended	200.00	200.00
65	66	2	201104263075	suspended	500.00	500.00
173	174	2	201000000022	active	300.00	300.00
186	187	1	201000000035	active	300.00	300.00
172	173	2	201000000021	active	300.00	300.00
69	70	1	201933498428	suspended	200.00	200.00
70	71	3	201486851814	suspended	1000.00	1000.00
73	74	1	201164423903	suspended	200.00	200.00
74	75	2	201222156953	suspended	500.00	500.00
75	76	2	201405902147	suspended	500.00	500.00
81	82	3	201470072023	active	1000.00	998.89
77	78	2	201766366618	suspended	500.00	500.00
79	80	3	201102108531	suspended	1000.00	1000.00
80	81	2	201485924091	suspended	500.00	500.00
82	83	2	201129946977	suspended	500.00	500.00
85	86	2	201403027881	suspended	500.00	500.00
87	88	2	201418928906	suspended	500.00	500.00
119	120	1	201399521241	active	200.00	191.65
93	94	2	201691828182	suspended	500.00	500.00
192	193	1	201000000041	active	300.00	300.00
99	100	2	201169195915	active	500.00	500.00
100	101	1	201245889511	suspended	200.00	200.00
101	102	2	201469461169	suspended_debt	500.00	500.00
102	103	1	201883670030	suspended	200.00	200.00
130	131	2	201806374057	active	500.00	499.92
124	125	2	201649032416	active	500.00	499.92
105	106	1	201821214312	suspended	200.00	200.00
106	107	1	201610578385	suspended_debt	200.00	200.00
107	108	2	201130189015	suspended	500.00	500.00
98	99	3	201481351069	active	1000.00	998.55
196	197	2	201000000045	active	300.00	300.00
123	124	3	201367143168	active	1000.00	998.50
84	85	1	201326784672	active	200.00	200.00
127	128	2	201373685722	active	500.00	494.82
122	123	2	201850051553	active	500.00	496.80
175	176	1	201000000024	active	300.00	300.00
94	95	3	201314768886	active	1000.00	999.99
83	84	1	201892594062	active	200.00	126.30
72	73	2	201456036855	active	500.00	493.08
134	135	1	201763359068	active	200.00	200.00
88	89	1	201421638665	active	200.00	115.30
184	185	2	201000000033	active	300.00	300.00
185	186	2	201000000034	active	300.00	300.00
187	188	3	201000000036	active	300.00	300.00
97	98	3	201405070503	active	1000.00	995.34
189	190	2	201000000038	active	300.00	300.00
191	192	2	201000000040	active	300.00	300.00
193	194	2	201000000042	active	300.00	300.00
195	196	2	201000000044	active	300.00	300.00
197	198	2	201000000046	active	300.00	300.00
198	199	2	201000000047	active	300.00	300.00
199	200	3	201000000048	active	300.00	300.00
170	171	2	201000000019	active	300.00	300.00
171	172	2	201000000020	active	300.00	300.00
176	177	3	201000000025	active	300.00	300.00
177	178	2	201000000026	active	300.00	300.00
178	179	2	201000000027	active	300.00	300.00
179	180	3	201000000028	active	300.00	300.00
180	181	3	201000000029	active	300.00	300.00
181	182	2	201000000030	active	300.00	300.00
190	191	1	201000000039	active	300.00	300.00
78	79	2	201420731899	active	500.00	481.60
139	140	2	201480812037	active	500.00	499.92
86	87	1	201731509325	active	200.00	150.40
108	109	3	201511068195	active	1000.00	1000.00
143	144	1	201639909693	active	200.00	191.20
90	91	3	201637467208	active	1000.00	999.99
161	162	3	201987728795	active	1000.00	1000.00
183	184	1	201000000032	active	300.00	300.00
\.


--
-- Data for Name: contract_addon; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.contract_addon (id, contract_id, service_package_id, purchased_date, expiry_date, is_active, price_paid) FROM stdin;
1	2	4	2026-04-29	2026-04-30	t	0.00
2	7	4	2026-04-29	2026-04-30	t	0.00
3	9	4	2026-04-29	2026-04-30	t	0.00
4	10	4	2026-04-29	2026-04-30	t	0.00
5	12	4	2026-04-29	2026-04-30	t	0.00
6	15	4	2026-04-29	2026-04-30	t	0.00
7	16	4	2026-04-29	2026-04-30	t	0.00
8	17	4	2026-04-29	2026-04-30	t	0.00
9	20	4	2026-04-29	2026-04-30	t	0.00
10	25	4	2026-04-29	2026-04-30	t	0.00
11	28	4	2026-04-29	2026-04-30	t	0.00
12	31	4	2026-04-29	2026-04-30	t	0.00
13	42	4	2026-04-29	2026-04-30	t	0.00
14	46	4	2026-04-29	2026-04-30	t	0.00
15	47	4	2026-04-29	2026-04-30	t	0.00
16	51	4	2026-04-29	2026-04-30	t	0.00
17	55	4	2026-04-29	2026-04-30	t	0.00
18	64	4	2026-04-29	2026-04-30	t	0.00
19	76	4	2026-04-29	2026-04-30	t	0.00
20	78	4	2026-04-29	2026-04-30	t	0.00
21	81	4	2026-04-29	2026-04-30	t	0.00
22	83	4	2026-04-29	2026-04-30	t	0.00
23	89	4	2026-04-29	2026-04-30	t	0.00
24	98	4	2026-04-29	2026-04-30	t	0.00
25	99	4	2026-04-29	2026-04-30	t	0.00
26	114	4	2026-04-29	2026-04-30	t	0.00
27	117	4	2026-04-29	2026-04-30	t	0.00
28	119	4	2026-04-29	2026-04-30	t	0.00
29	127	4	2026-04-29	2026-04-30	t	0.00
30	128	4	2026-04-29	2026-04-30	t	0.00
31	129	4	2026-04-29	2026-04-30	t	0.00
32	130	4	2026-04-29	2026-04-30	t	0.00
33	134	4	2026-04-29	2026-04-30	t	0.00
34	143	4	2026-04-29	2026-04-30	t	0.00
35	146	4	2026-04-29	2026-04-30	t	0.00
36	159	4	2026-04-29	2026-04-30	t	0.00
37	161	4	2026-04-29	2026-04-30	t	0.00
38	168	4	2026-04-29	2026-04-30	t	0.00
39	58	6	2026-04-29	2026-04-30	t	500.00
40	90	6	2026-04-29	2026-04-30	t	500.00
41	10	6	2026-04-29	2026-04-30	t	500.00
42	42	6	2026-04-29	2026-04-30	t	500.00
43	129	6	2026-04-29	2026-04-30	t	500.00
44	146	6	2026-04-29	2026-04-30	t	500.00
\.


--
-- Data for Name: contract_consumption; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.contract_consumption (contract_id, service_package_id, rateplan_id, starting_date, ending_date, consumed, quota_limit, is_billed, bill_id) FROM stdin;
137	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	297
137	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	297
137	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	297
137	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	297
139	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	298
139	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	298
139	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	298
139	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	298
139	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	298
139	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	298
139	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	298
165	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	304
165	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	304
165	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	304
165	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	304
165	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	304
117	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	306
117	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	306
117	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	306
119	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	307
119	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	307
119	4	1	2026-04-01	2026-04-30	0.0000	10000.0000	t	307
127	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	308
127	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	308
127	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	308
127	4	2	2026-04-01	2026-04-30	15.0000	20000.0000	t	308
127	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	308
127	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	308
127	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	308
128	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	309
128	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	309
128	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	309
128	4	3	2026-04-01	2026-04-30	15.0000	20000.0000	t	309
128	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	309
128	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	309
128	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	309
130	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	310
130	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	310
130	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	310
130	4	2	2026-04-01	2026-04-30	15.0000	20000.0000	t	310
130	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	310
130	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	310
130	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	310
134	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	311
134	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	311
134	4	1	2026-04-01	2026-04-30	0.0000	10000.0000	t	311
143	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	312
143	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	312
143	4	1	2026-04-01	2026-04-30	0.0000	10000.0000	t	312
159	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	313
159	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	313
159	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	313
159	4	3	2026-04-01	2026-04-30	15.0000	20000.0000	t	313
159	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	313
159	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	313
159	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	313
161	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	314
161	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	314
161	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	314
161	4	3	2026-04-01	2026-04-30	15.0000	20000.0000	t	314
161	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	314
161	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	314
161	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	314
168	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	315
168	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	315
168	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	315
168	4	2	2026-04-01	2026-04-30	15.0000	20000.0000	t	315
168	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	315
168	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	315
168	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	315
129	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	316
129	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	316
129	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	316
129	4	2	2026-04-01	2026-04-30	15.0000	20000.0000	t	316
129	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	316
129	6	2	2026-04-01	2026-04-30	0.0000	4000.0000	t	316
129	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	316
146	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	317
146	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	317
146	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	317
146	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	317
146	6	2	2026-04-01	2026-04-30	0.0000	4000.0000	t	317
146	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	317
146	4	2	2026-04-01	2026-04-30	15.0000	20000.0000	t	317
92	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
92	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
94	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
94	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
94	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
94	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
94	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
1	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	166
94	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
94	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
95	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
95	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
95	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
95	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
95	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
95	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
95	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
96	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
96	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
96	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
96	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
96	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
96	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
96	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
97	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
97	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
1	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	166
2	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	167
2	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	167
2	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	167
2	4	2	2026-04-01	2026-04-30	0.0000	20000.0000	t	167
2	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	167
2	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	167
2	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	167
3	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	168
184	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
184	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
184	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
33	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	197
184	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
24	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	188
184	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
25	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	189
25	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	189
184	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
27	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	191
27	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	191
185	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
185	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
28	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	192
28	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	192
185	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
185	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
28	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	192
28	4	3	2026-04-01	2026-04-30	15.0000	20000.0000	t	192
185	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
185	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
187	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
187	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
187	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
28	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	192
28	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	192
33	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	197
187	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
187	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
187	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
188	3	1	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
189	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
189	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
189	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
28	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	192
31	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	195
189	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
189	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
189	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
191	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
191	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
191	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
191	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
31	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	195
31	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	195
191	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
191	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
31	4	3	2026-04-01	2026-04-30	0.0000	20000.0000	t	195
31	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	195
193	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
193	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
193	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
193	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
193	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
193	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
195	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
195	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
195	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
195	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
31	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	195
31	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	195
195	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
195	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
196	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
32	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	196
32	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	196
32	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	196
32	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	196
32	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	196
32	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	196
32	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	196
33	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	197
33	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	197
33	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	197
33	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	197
33	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	197
36	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	200
36	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	200
37	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	201
196	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
196	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
196	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
196	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
197	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
197	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
197	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
197	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
197	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
197	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
198	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
198	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
198	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
198	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
198	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
198	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
187	4	3	2026-04-01	2026-04-30	79.0000	10000.0000	f	\N
196	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
196	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
188	1	1	2026-04-01	2026-04-30	122.0000	2000.0000	f	\N
192	3	1	2026-04-01	2026-04-30	1.0000	500.0000	f	\N
183	1	1	2026-04-01	2026-04-30	451.0000	2000.0000	f	\N
183	3	1	2026-04-01	2026-04-30	6.0000	500.0000	f	\N
186	3	1	2026-04-01	2026-04-30	5.0000	500.0000	f	\N
195	4	2	2026-04-01	2026-04-30	324.0000	10000.0000	f	\N
199	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
199	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
199	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
199	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
68	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	232
199	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
199	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
170	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
58	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	222
58	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	222
170	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
58	6	2	2026-04-01	2026-04-30	0.0000	4000.0000	t	222
58	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	222
170	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
60	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	224
60	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	224
170	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
170	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
170	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
171	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
171	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
171	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
171	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
171	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
171	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
172	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
64	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	228
64	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	228
68	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	232
172	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
172	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
172	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
173	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
64	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	228
64	4	2	2026-04-01	2026-04-30	15.0000	20000.0000	t	228
71	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	235
173	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
64	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	228
64	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	228
173	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
64	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	228
66	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	230
174	3	1	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
66	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	230
66	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	230
176	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
176	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
176	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
66	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	230
66	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	230
176	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
176	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
176	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
177	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
177	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
177	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
177	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
177	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
66	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	230
66	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	230
177	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
178	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
178	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
178	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
178	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
67	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	231
67	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	231
67	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	231
67	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	231
67	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	231
67	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	231
67	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	231
71	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	235
72	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	236
72	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	236
72	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	236
72	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	236
72	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	236
72	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	236
72	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	236
76	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	240
178	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
178	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
179	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
179	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
179	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
179	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
179	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
179	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
180	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
180	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
180	3	3	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
180	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
180	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
180	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
181	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
181	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
181	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
173	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
173	6	2	2026-04-01	2026-04-30	2000.0000	2000.0000	f	\N
172	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
172	3	2	2026-04-01	2026-04-30	1.0000	500.0000	f	\N
177	4	2	2026-04-01	2026-04-30	6.0000	10000.0000	f	\N
173	2	2	2026-04-01	2026-04-30	123.0000	10000.0000	f	\N
176	4	3	2026-04-01	2026-04-30	7.0000	10000.0000	f	\N
173	3	2	2026-04-01	2026-04-30	1.0000	500.0000	f	\N
174	1	1	2026-04-01	2026-04-30	52.0000	2000.0000	f	\N
108	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	288
108	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	288
108	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	288
181	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
108	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	288
181	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
92	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	255
108	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	288
92	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	255
92	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	255
108	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	288
108	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	288
109	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	289
109	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	289
109	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	289
109	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	289
109	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	289
109	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	289
94	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	257
94	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	257
96	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	259
109	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	289
111	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	290
111	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	290
111	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	290
111	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	290
111	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	290
111	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	290
111	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	290
116	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	291
94	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	257
94	4	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	257
116	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	291
116	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	291
116	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	291
94	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	257
94	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	257
181	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
94	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	257
95	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	258
95	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	258
95	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	258
182	3	1	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
95	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	258
95	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	258
96	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	259
95	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	258
95	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	258
96	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	259
96	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	259
96	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	259
96	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	259
96	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	259
97	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	260
97	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	260
97	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	260
97	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	260
97	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	260
97	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	260
97	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	260
116	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	291
116	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	291
116	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	291
114	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	305
114	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	305
114	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	305
114	4	3	2026-04-01	2026-04-30	15.0000	20000.0000	t	305
114	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	305
114	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	305
114	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	305
117	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	306
117	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	306
117	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	306
117	4	3	2026-04-01	2026-04-30	0.0000	20000.0000	t	306
182	1	1	2026-04-01	2026-04-30	124.0000	2000.0000	f	\N
174	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
174	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
11	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
11	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
15	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
15	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
15	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
15	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
15	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
15	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
14	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
14	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
14	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
14	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
14	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
14	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
14	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
12	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
12	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
12	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
12	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
12	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
12	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
12	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
9	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
9	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
15	4	3	2026-03-01	2026-03-31	1.0000	10000.0000	f	\N
2	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	t	364
5	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
5	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
16	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
16	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
16	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
16	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
16	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
122	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	292
122	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	292
16	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
122	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	292
122	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	292
122	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	292
122	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	292
122	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	292
123	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	293
123	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	293
123	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	293
123	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	293
123	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	293
123	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	293
123	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	293
124	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	294
124	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	294
16	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
124	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	294
124	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	294
4	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
124	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	294
124	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	294
4	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
124	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	294
131	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	295
131	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	295
131	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	295
131	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	295
131	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	295
131	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	295
131	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	295
136	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	296
136	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	296
137	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	297
137	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	297
137	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	297
4	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
4	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
4	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
4	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
4	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
3	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
3	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
6	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
6	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
6	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
6	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
6	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
6	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
6	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
7	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
7	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
8	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
8	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
8	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
8	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
8	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
8	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
8	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
10	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
10	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
10	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
10	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
10	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
10	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
10	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
17	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
17	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
17	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
17	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
17	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
17	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
19	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
19	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
19	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
19	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
19	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
19	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
19	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
20	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
20	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
20	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
20	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
20	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
20	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
20	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
22	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
22	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
22	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
22	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
22	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
22	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
22	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
24	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
24	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
24	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
24	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
24	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
24	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
24	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
25	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
25	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
27	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
27	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
17	4	2	2026-03-01	2026-03-31	4.0000	10000.0000	f	\N
7	4	1	2026-04-01	2026-04-30	0.0000	10000.0000	t	172
9	4	1	2026-04-01	2026-04-30	0.0000	10000.0000	t	174
25	4	1	2026-04-01	2026-04-30	0.0000	10000.0000	t	189
47	4	1	2026-04-01	2026-04-30	0.0000	10000.0000	t	211
28	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
51	4	1	2026-04-01	2026-04-30	0.0000	10000.0000	t	215
55	4	1	2026-04-01	2026-04-30	0.0000	10000.0000	t	219
28	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
83	4	1	2026-04-01	2026-04-30	0.0000	10000.0000	t	247
89	4	1	2026-04-01	2026-04-30	0.0000	10000.0000	t	253
28	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
149	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	299
149	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	299
149	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	299
149	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	299
149	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	299
149	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	299
149	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	299
151	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	300
151	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	300
151	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	300
28	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
151	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	300
151	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	300
28	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
151	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	300
151	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	300
152	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	301
28	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
31	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
31	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
3	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	168
4	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	169
4	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	169
4	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	169
4	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	169
4	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	169
4	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	169
4	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	169
5	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	170
5	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	170
6	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	171
6	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	171
6	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	171
6	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	171
6	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	171
6	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	171
152	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	301
152	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	301
152	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	301
152	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	301
152	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	301
152	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	301
162	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	302
162	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	302
162	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	302
162	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	302
162	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	302
162	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	302
162	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	302
164	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	303
164	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	303
165	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	304
165	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	304
31	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
31	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
31	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
32	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
32	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
32	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
32	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
32	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
32	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
32	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
33	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
33	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
33	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
33	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
33	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
33	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
33	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
36	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
36	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
37	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
37	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
41	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
42	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
42	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
42	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
42	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
42	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
42	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
42	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
46	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
46	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
46	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
46	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
46	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
46	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
46	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
47	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
47	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
51	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
51	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
53	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
53	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
53	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
53	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
53	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
53	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
53	4	2	2026-03-01	2026-03-31	48.0000	10000.0000	f	\N
31	4	3	2026-03-01	2026-03-31	10000.0000	10000.0000	f	\N
31	2	3	2026-03-01	2026-03-31	10000.0000	10000.0000	f	\N
6	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	171
7	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	172
7	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	172
8	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	173
8	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	173
8	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	173
8	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	173
8	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	173
8	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	173
8	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	173
9	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	174
9	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	174
10	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	175
10	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	175
10	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	175
10	4	2	2026-04-01	2026-04-30	0.0000	20000.0000	t	175
10	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	175
10	6	2	2026-04-01	2026-04-30	0.0000	4000.0000	t	175
10	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	175
11	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	176
11	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	176
12	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	177
12	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	177
12	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	177
12	4	2	2026-04-01	2026-04-30	0.0000	20000.0000	t	177
12	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	177
12	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	177
12	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	177
14	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	179
14	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	179
14	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	179
14	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	179
14	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	179
14	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	179
14	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	179
15	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	180
15	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	180
15	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	180
15	4	3	2026-04-01	2026-04-30	0.0000	20000.0000	t	180
15	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	180
15	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	180
15	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	180
16	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	181
16	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	181
16	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	181
16	4	3	2026-04-01	2026-04-30	0.0000	20000.0000	t	181
16	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	181
16	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	181
16	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	181
17	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	182
17	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	182
17	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	182
17	4	2	2026-04-01	2026-04-30	0.0000	20000.0000	t	182
17	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	182
17	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	182
17	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	182
19	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	183
19	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	183
19	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	183
19	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	183
19	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	183
19	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	183
19	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	183
20	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	184
20	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	184
20	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	184
20	4	3	2026-04-01	2026-04-30	15.0000	20000.0000	t	184
20	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	184
20	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	184
20	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	184
22	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	186
22	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	186
22	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	186
22	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	186
22	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	186
22	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	186
22	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	186
24	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	188
24	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	188
24	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	188
24	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	188
24	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	188
24	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	188
37	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	201
41	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	205
41	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	205
42	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	206
42	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	206
42	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	206
42	4	2	2026-04-01	2026-04-30	15.0000	20000.0000	t	206
42	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	206
42	6	2	2026-04-01	2026-04-30	0.0000	4000.0000	t	206
42	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	206
46	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	210
46	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	210
46	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	210
46	4	3	2026-04-01	2026-04-30	0.0000	20000.0000	t	210
46	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	210
46	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	210
46	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	210
47	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	211
47	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	211
51	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	215
51	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	215
53	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	217
53	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	217
53	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	217
53	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	217
53	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	217
53	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	217
53	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	217
55	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	219
55	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	219
56	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	220
56	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	220
56	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	220
56	4	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	220
56	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	220
56	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	220
56	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	220
57	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	221
57	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	221
57	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	221
57	4	2	2026-04-01	2026-04-30	15.0000	10000.0000	t	221
57	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	221
57	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	221
57	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	221
58	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	222
58	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	222
58	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	222
76	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	240
76	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	240
76	4	2	2026-04-01	2026-04-30	0.0000	20000.0000	t	240
76	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	240
76	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	240
76	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	240
78	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	242
78	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	242
78	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	242
78	4	2	2026-04-01	2026-04-30	15.0000	20000.0000	t	242
78	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	242
78	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	242
78	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	242
81	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	245
81	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	245
81	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	245
81	4	3	2026-04-01	2026-04-30	15.0000	20000.0000	t	245
81	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	245
81	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	245
81	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	245
83	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	247
83	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	247
84	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	248
84	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	248
86	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	250
86	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	250
88	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	252
88	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	252
89	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	253
89	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	253
90	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	254
90	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	254
90	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	254
90	4	3	2026-04-01	2026-04-30	15.0000	10000.0000	t	254
90	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	254
90	6	3	2026-04-01	2026-04-30	0.0000	4000.0000	t	254
90	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	254
92	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	255
92	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	255
92	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	255
92	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	255
98	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	261
98	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	261
98	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	261
98	4	3	2026-04-01	2026-04-30	15.0000	20000.0000	t	261
98	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	261
98	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	261
98	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	261
99	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	262
99	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	262
99	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	262
99	4	2	2026-04-01	2026-04-30	0.0000	20000.0000	t	262
99	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	262
99	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	262
99	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	262
103	1	1	2026-04-01	2026-04-30	15.0000	2000.0000	t	266
103	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	266
104	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	267
104	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	267
55	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
19	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
19	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
19	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
19	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
19	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
19	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
19	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
22	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
22	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
22	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
22	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
22	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
22	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
22	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
24	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
24	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
24	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
24	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
24	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
24	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
24	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
27	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
27	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
32	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
32	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
32	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
32	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
32	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
32	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
32	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
33	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
33	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
33	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
33	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
33	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
33	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
33	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
36	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
36	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
37	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
37	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
41	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
41	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
53	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
53	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
53	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
53	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
53	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
53	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
53	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
56	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
56	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
56	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
56	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
56	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
56	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
56	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
57	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
57	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
57	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
57	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
57	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
57	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
57	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
60	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
60	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
66	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
66	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
66	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
66	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
66	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
66	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
66	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
67	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
67	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
67	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
67	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
67	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
67	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
67	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
68	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
68	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
71	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
71	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
72	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
72	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
72	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
72	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
72	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
72	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
72	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
84	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
84	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
86	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
86	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
88	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
88	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
92	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
92	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
92	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
92	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
92	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
92	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
92	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
94	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
94	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
94	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
94	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
94	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
94	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
94	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
95	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
95	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
95	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
95	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
95	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
95	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
95	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
96	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
96	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
96	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
96	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
96	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
96	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
96	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
97	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
97	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
97	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
97	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
97	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
97	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
97	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
103	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
103	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
104	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
104	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
1	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
1	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
3	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
3	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
108	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
108	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
108	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
108	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
108	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
108	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
108	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
109	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
109	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
109	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
109	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
109	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
109	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
109	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
111	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
111	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
111	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
111	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
111	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
111	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
111	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
116	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
116	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
116	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
116	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
116	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
116	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
116	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
122	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
122	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
122	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
122	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
122	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
122	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
122	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
123	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
123	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
123	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
123	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
123	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
123	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
123	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
124	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
124	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
124	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
124	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
124	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
124	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
124	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
131	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
131	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
131	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
131	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
131	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
131	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
131	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
136	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
136	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
137	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
137	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
137	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
137	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
137	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
137	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
137	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
139	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
139	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
139	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
139	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
139	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
139	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
139	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
149	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
149	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
149	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
149	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
149	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
149	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
149	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
151	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
151	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
151	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
151	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
151	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
151	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
151	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
152	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
152	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
152	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
152	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
152	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
152	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
152	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
162	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
162	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
162	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
162	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
162	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
162	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
162	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
164	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
164	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
165	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
165	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
165	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
165	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
165	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
165	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
165	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
20	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
20	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
20	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
20	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
20	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
20	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
20	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
25	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
25	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
28	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
28	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
28	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
28	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
28	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
28	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
28	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
31	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
31	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
31	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
31	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
31	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
31	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
31	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
46	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
46	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
46	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
46	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
46	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
46	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
46	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
47	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
47	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
51	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
51	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
55	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
55	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
64	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
64	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
64	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
64	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
64	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
64	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
64	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
76	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
76	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
76	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
76	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
76	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
76	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
76	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
78	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
78	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
78	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
78	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
78	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
78	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
78	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
81	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
81	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
81	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
81	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
81	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
81	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
81	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
83	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
83	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
89	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
89	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
98	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
98	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
98	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
98	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
98	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
98	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
98	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
99	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
99	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
99	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
99	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
99	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
99	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
99	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
114	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
114	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
114	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
114	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
114	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
114	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
114	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
117	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
117	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
117	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
117	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
117	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
117	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
117	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
119	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
119	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
127	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
127	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
127	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
127	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
127	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
127	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
127	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
128	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
128	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
128	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
128	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
128	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
128	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
128	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
130	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
130	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
130	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
130	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
130	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
130	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
130	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
134	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
134	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
143	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
143	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
159	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
159	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
159	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
159	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
159	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
159	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
159	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
161	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
161	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
161	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
161	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
161	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
161	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
161	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
168	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
168	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
168	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
168	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
168	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
168	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
168	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
58	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
58	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
58	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
58	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
58	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
58	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
58	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
90	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
90	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
90	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
90	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
90	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
90	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
90	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
42	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
42	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
42	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
42	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
42	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
42	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
42	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
129	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
129	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
129	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
129	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
129	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
129	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
129	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
146	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
146	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
146	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
146	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
146	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
146	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
146	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
2	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
2	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
2	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
2	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
2	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
2	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
2	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
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
170	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
170	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
170	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
170	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
170	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
170	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
170	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
171	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
171	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
171	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
171	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
171	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
171	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
171	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
172	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
172	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
172	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
172	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
172	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
172	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
172	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
173	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
173	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
173	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
173	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
173	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
173	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
173	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
174	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
174	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
175	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
175	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
176	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
176	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
176	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
176	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
176	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
176	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
176	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
177	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
177	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
177	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
177	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
177	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
177	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
177	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
178	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
178	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
178	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
178	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
178	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
178	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
178	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
179	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
179	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
179	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
179	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
179	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
179	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
179	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
180	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
180	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
180	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
180	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
180	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
180	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
180	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
181	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
181	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
181	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
181	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
181	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
181	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
181	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
182	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
182	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
183	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
183	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
184	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
184	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
184	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
184	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
184	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
184	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
184	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
185	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
185	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
185	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
185	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
185	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
185	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
185	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
186	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
186	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
187	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
187	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
187	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
187	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
187	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
187	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
187	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
188	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
188	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
189	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
189	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
189	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
189	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
189	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
189	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
189	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
190	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
190	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
191	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
191	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
191	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
191	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
191	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
191	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
191	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
192	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
192	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
193	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
193	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
193	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
193	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
193	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
193	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
193	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
194	1	1	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
194	3	1	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
195	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
195	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
195	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
195	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
195	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
195	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
195	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
196	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
196	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
196	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
196	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
196	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
196	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
196	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
197	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
197	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
197	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
197	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
197	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
197	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
197	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
198	1	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
198	2	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
198	3	2	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
198	4	2	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
198	5	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
198	6	2	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
198	7	2	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
199	1	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
199	2	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
199	3	3	2026-04-29	2026-04-30	0.0000	500.0000	f	\N
199	4	3	2026-04-29	2026-04-30	0.0000	10000.0000	f	\N
199	5	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
199	6	3	2026-04-29	2026-04-30	0.0000	2000.0000	f	\N
199	7	3	2026-04-29	2026-04-30	0.0000	100.0000	f	\N
55	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
56	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
56	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
56	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
56	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
56	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
56	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
56	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
57	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
57	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
57	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
57	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
57	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
57	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
57	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
58	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
58	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
58	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
58	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
58	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
58	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
58	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
60	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
60	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
64	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
64	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
64	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
64	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
64	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
64	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
64	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
66	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
66	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
66	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
66	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
66	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
66	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
66	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
67	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
67	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
67	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
67	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
67	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
67	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
68	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
71	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
71	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
72	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
72	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
72	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
72	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
72	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
72	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
72	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
76	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
76	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
76	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
76	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
76	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
76	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
78	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
78	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
78	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
78	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
78	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
78	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
78	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
81	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
81	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
81	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
81	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
81	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
81	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
81	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
83	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
83	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
84	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
84	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
86	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
88	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
88	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
89	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
89	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
90	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
90	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
90	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
90	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
90	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
90	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
90	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
92	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
92	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
92	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
92	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
92	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
68	1	1	2026-03-01	2026-03-31	44.0000	2000.0000	f	\N
97	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
97	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
97	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
97	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
97	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
98	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
98	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
98	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
98	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
98	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
98	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
98	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
99	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
99	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
99	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
99	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
99	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
99	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
99	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
103	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
103	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
104	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
104	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
108	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
108	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
108	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
108	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
108	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
108	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
109	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
109	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
109	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
109	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
109	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
109	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
109	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
111	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
111	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
111	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
111	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
111	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
111	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
111	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
116	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
116	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
116	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
116	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
116	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
116	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
116	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
122	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
122	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
122	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
122	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
122	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
122	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
122	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
123	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
123	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
123	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
123	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
123	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
123	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
123	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
124	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
124	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
124	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
124	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
124	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
124	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
124	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
131	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
131	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
131	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
131	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
131	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
131	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
131	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
136	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
136	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
137	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
137	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
137	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
137	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
137	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
137	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
137	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
139	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
139	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
139	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
139	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
139	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
139	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
139	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
149	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
149	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
149	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
149	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
149	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
149	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
149	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
151	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
151	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
151	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
151	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
151	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
151	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
151	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
152	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
152	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
152	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
152	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
152	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
152	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
152	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
162	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
162	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
162	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
162	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
162	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
162	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
162	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
164	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
164	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
165	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
165	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
165	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
165	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
165	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
114	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
114	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
114	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
114	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
114	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
114	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
114	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
117	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
117	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
117	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
117	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
117	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
117	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
117	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
119	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
119	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
127	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
127	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
127	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
127	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
127	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
127	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
127	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
128	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
128	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
128	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
128	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
128	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
128	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
128	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
130	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
130	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
130	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
130	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
130	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
130	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
130	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
134	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
134	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
143	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
143	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
159	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
159	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
159	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
159	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
159	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
159	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
159	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
161	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
161	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
161	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
161	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
161	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
161	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
161	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
168	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
168	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
168	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
168	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
168	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
168	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
168	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
129	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
129	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
129	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
129	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
129	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
129	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
129	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
146	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
146	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
146	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
146	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
146	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
146	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
146	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
183	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
183	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
184	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
184	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
184	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
184	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
184	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
184	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
184	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
185	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
185	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
185	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
185	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
185	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
185	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
186	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
186	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
187	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
187	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
187	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
187	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
187	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
187	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
187	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
188	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
188	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
189	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
189	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
189	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
189	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
165	4	2	2026-03-01	2026-03-31	10000.0000	10000.0000	f	\N
185	4	2	2026-03-01	2026-03-31	42.0000	10000.0000	f	\N
189	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
189	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
191	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
191	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
191	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
191	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
191	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
191	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
191	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
193	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
193	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
193	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
193	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
193	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
193	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
193	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
194	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
194	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
195	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
195	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
195	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
195	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
195	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
195	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
195	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
196	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
196	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
196	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
196	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
196	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
196	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
196	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
197	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
197	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
197	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
197	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
197	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
197	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
197	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
198	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
198	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
198	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
198	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
198	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
198	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
198	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
199	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
199	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
199	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
199	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
199	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
199	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
199	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
170	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
170	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
170	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
170	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
170	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
170	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
171	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
171	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
171	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
171	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
171	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
171	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
171	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
172	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
172	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
172	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
172	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
172	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
172	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
172	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
173	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
173	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
173	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
173	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
173	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
173	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
173	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
175	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
175	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
176	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
176	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
176	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
176	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
176	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
176	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
176	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
177	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
177	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
177	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
177	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
177	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
177	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
177	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
178	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
178	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
178	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
178	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
178	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
178	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
178	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
179	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
179	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
179	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
179	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
179	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
179	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
180	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
180	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
180	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
180	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
180	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
180	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
180	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
181	1	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
181	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
179	4	3	2026-03-01	2026-03-31	1.0000	10000.0000	f	\N
181	3	2	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
181	4	2	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
181	5	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
181	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
181	7	2	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
182	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
182	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
192	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
192	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
190	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
190	3	1	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
191	4	2	2026-04-01	2026-04-30	64.0000	10000.0000	f	\N
193	4	2	2026-04-01	2026-04-30	306.0000	10000.0000	f	\N
170	4	2	2026-03-01	2026-03-31	112.0000	10000.0000	f	\N
165	2	2	2026-03-01	2026-03-31	10000.0000	10000.0000	f	\N
185	4	2	2026-04-01	2026-04-30	51.0000	10000.0000	f	\N
189	4	2	2026-04-01	2026-04-30	92.0000	10000.0000	f	\N
178	4	2	2026-04-01	2026-04-30	52.0000	10000.0000	f	\N
28	4	3	2026-03-01	2026-03-31	1.0000	10000.0000	f	\N
198	4	2	2026-04-01	2026-04-30	205.0000	10000.0000	f	\N
190	3	1	2026-04-01	2026-04-30	4.0000	500.0000	f	\N
171	4	2	2026-04-01	2026-04-30	182.0000	10000.0000	f	\N
184	4	2	2026-04-01	2026-04-30	106.0000	10000.0000	f	\N
67	4	2	2026-03-01	2026-03-31	49.0000	10000.0000	f	\N
197	4	2	2026-04-01	2026-04-30	8.0000	10000.0000	f	\N
194	3	1	2026-04-01	2026-04-30	6.0000	500.0000	f	\N
180	4	3	2026-04-01	2026-04-30	395.0000	10000.0000	f	\N
186	1	1	2026-04-01	2026-04-30	408.0000	2000.0000	f	\N
86	3	1	2026-03-01	2026-03-31	1.0000	500.0000	f	\N
175	3	1	2026-04-01	2026-04-30	1.0000	500.0000	f	\N
175	1	1	2026-04-01	2026-04-30	21.0000	2000.0000	f	\N
181	4	2	2026-04-01	2026-04-30	349.0000	10000.0000	f	\N
189	4	2	2026-03-01	2026-03-31	50.0000	10000.0000	f	\N
192	1	1	2026-04-01	2026-04-30	161.0000	2000.0000	f	\N
76	4	2	2026-03-01	2026-03-31	253.0000	10000.0000	f	\N
41	1	1	2026-03-01	2026-03-31	57.0000	2000.0000	f	\N
108	4	3	2026-03-01	2026-03-31	1.0000	10000.0000	f	\N
201	4	4	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
201	5	4	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
172	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
200	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	349
200	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	349
200	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	349
200	4	3	2026-04-01	2026-04-30	31.0000	10000.0000	t	349
200	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	349
200	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	349
200	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	349
194	1	1	2026-04-01	2026-04-30	308.0000	2000.0000	f	\N
200	1	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
200	2	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
200	3	3	2026-03-01	2026-03-31	0.0000	500.0000	f	\N
200	4	3	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
200	5	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
200	6	3	2026-03-01	2026-03-31	0.0000	2000.0000	f	\N
200	7	3	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
190	1	1	2026-04-01	2026-04-30	85.0000	2000.0000	f	\N
1	3	1	2026-03-01	2026-03-31	3.0000	500.0000	t	363
1	1	1	2026-03-01	2026-03-31	0.0000	2000.0000	t	363
201	4	4	2026-03-01	2026-03-31	0.0000	10000.0000	f	\N
201	5	4	2026-03-01	2026-03-31	0.0000	100.0000	f	\N
170	4	2	2026-04-01	2026-04-30	105.0000	10000.0000	f	\N
199	4	3	2026-04-01	2026-04-30	83.0000	10000.0000	f	\N
2	7	2	2026-03-01	2026-03-31	0.0000	100.0000	t	364
2	2	2	2026-03-01	2026-03-31	0.0000	10000.0000	t	364
2	3	2	2026-03-01	2026-03-31	0.0000	500.0000	t	364
2	4	2	2026-03-01	2026-03-31	62.0000	10000.0000	t	364
2	5	2	2026-03-01	2026-03-31	0.0000	100.0000	t	364
2	6	2	2026-03-01	2026-03-31	0.0000	2000.0000	t	364
179	4	3	2026-04-01	2026-04-30	61.0000	10000.0000	f	\N
\.


--
-- Data for Name: file; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.file (id, parsed_flag, file_path) FROM stdin;
1	t	/tmp/cdr_april_batch1.csv
2	t	/tmp/cdr_april_batch2.csv
3	t	master_test.cdr
4	t	CDR20260429202415_659.csv
6	t	CDR20260429202415_659.csv
7	t	CDR20260430003342_167.csv
8	t	CDR20260429214252_564.csv
9	t	CDR20260429214646_38.csv
10	t	CDR20260430003342_167.csv
11	t	CDR20260430041708_926.csv
12	t	CDR20260430042124_612.csv
13	t	CDR20260430003342_167.csv
14	t	CDR20260430041708_926.csv
15	t	CDR20260430042124_612.csv
16	t	CDR20260430003342_167.csv
17	t	CDR20260430041708_926.csv
18	t	CDR20260430042124_612.csv
19	t	CDR20260430113033_447.csv
\.


--
-- Data for Name: invoice; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.invoice (id, bill_id, pdf_path, generation_date) FROM stdin;
2	2	/invoices/feb26_contract2.pdf	2026-04-29 17:43:26.536298
3	3	/invoices/feb26_contract3.pdf	2026-04-29 17:43:26.536298
4	4	/invoices/feb26_contract4.pdf	2026-04-29 17:43:26.536298
5	5	/invoices/feb26_contract5.pdf	2026-04-29 17:43:26.536298
6	6	/invoices/feb26_contract6.pdf	2026-04-29 17:43:26.536298
7	7	/invoices/feb26_contract7.pdf	2026-04-29 17:43:26.536298
8	8	/invoices/feb26_contract8.pdf	2026-04-29 17:43:26.536298
9	9	/invoices/feb26_contract9.pdf	2026-04-29 17:43:26.536298
10	10	/invoices/feb26_contract10.pdf	2026-04-29 17:43:26.536298
11	11	/invoices/feb26_contract11.pdf	2026-04-29 17:43:26.536298
12	12	/invoices/feb26_contract12.pdf	2026-04-29 17:43:26.536298
13	13	/invoices/feb26_contract14.pdf	2026-04-29 17:43:26.536298
14	14	/invoices/feb26_contract15.pdf	2026-04-29 17:43:26.536298
15	15	/invoices/feb26_contract16.pdf	2026-04-29 17:43:26.536298
16	16	/invoices/feb26_contract17.pdf	2026-04-29 17:43:26.536298
17	17	/invoices/mar26_contract1.pdf	2026-04-29 17:43:26.536298
18	18	/invoices/mar26_contract2.pdf	2026-04-29 17:43:26.536298
\.


--
-- Data for Name: msisdn_pool; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.msisdn_pool (id, msisdn, is_available) FROM stdin;
63	201000000063	f
50	201000000050	f
49	201000000049	t
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
100	201193975708	f
101	201291490356	f
102	201646390202	f
103	201573560989	f
104	201280350684	f
105	201568820914	f
106	201690095272	f
107	201568821728	f
108	201486313285	f
109	201538007758	f
110	201212953273	f
111	201335082038	f
112	201915057234	f
113	201313455535	f
114	201336493947	f
115	201763337754	f
116	201236672367	f
117	201236262234	f
118	201946234738	f
119	201898797034	f
120	201916592994	f
121	201713840244	f
122	201972954141	f
123	201393015335	f
124	201498533478	f
125	201438107240	f
126	201583130923	f
127	201481789330	f
128	201130026448	f
129	201671461373	f
130	201321500366	f
131	201743344137	f
132	201151750893	f
133	201167872429	f
134	201924767903	f
135	201288927515	f
136	201818037329	f
137	201615922194	f
138	201277676035	f
139	201845026506	f
140	201737734249	f
141	201542776578	f
142	201484340865	f
143	201238698221	f
144	201309264655	f
145	201912929712	f
146	201104263075	f
147	201772327638	f
148	201173680950	f
149	201884002998	f
150	201933498428	f
151	201486851814	f
152	201807409782	f
153	201456036855	f
154	201164423903	f
155	201222156953	f
156	201405902147	f
157	201665180852	f
158	201766366618	f
159	201420731899	f
160	201102108531	f
161	201485924091	f
162	201470072023	f
163	201129946977	f
164	201892594062	f
165	201326784672	f
166	201403027881	f
167	201731509325	f
168	201418928906	f
169	201421638665	f
170	201432260526	f
171	201637467208	f
172	201690025215	f
173	201742482326	f
174	201691828182	f
175	201314768886	f
176	201529549288	f
177	201837344300	f
178	201405070503	f
179	201481351069	f
180	201169195915	f
181	201245889511	f
182	201469461169	f
183	201883670030	f
184	201880747142	f
185	201811678129	f
186	201821214312	f
187	201610578385	f
188	201130189015	f
189	201511068195	f
190	201193577939	f
191	201233454802	f
192	201905415497	f
193	201296640008	f
194	201480470252	f
195	201725767736	f
196	201743707822	f
197	201851881403	f
198	201679439439	f
199	201701152592	f
200	201399521241	f
201	201920696979	f
202	201694803366	f
203	201850051553	f
204	201367143168	f
205	201649032416	f
206	201787063869	f
207	201907682029	f
208	201373685722	f
209	201650751254	f
210	201747010017	f
211	201806374057	f
212	201699129335	f
213	201317072958	f
214	201585740806	f
215	201763359068	f
216	201681313506	f
217	201229447201	f
218	201259012646	f
219	201908458100	f
220	201480812037	f
221	201929116979	f
222	201804593641	f
223	201149365223	f
224	201639909693	f
225	201289319888	f
226	201786405082	f
227	201256368244	f
228	201672879810	f
229	201931499262	f
230	201639748141	f
231	201576737239	f
232	201544739530	f
233	201122438398	f
234	201795118881	f
235	201251180810	f
236	201443034851	f
237	201195845868	f
238	201621384437	f
239	201640950043	f
240	201590834655	f
241	201605591348	f
242	201987728795	f
243	201590288456	f
244	201239747722	f
245	201814479848	f
246	201974222870	f
247	201430418861	f
248	201207540095	f
249	201633386447	f
\.


--
-- Data for Name: onetime_fee; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.onetime_fee (id, contract_id, fee_type, amount, description, applied_date, bill_id) FROM stdin;
1	1	SIM_REPLACEMENT	150.00	SIM card replacement due to loss	2026-04-30	363
\.


--
-- Data for Name: payment; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.payment (id, bill_id, amount, payment_method, payment_date, transaction_id) FROM stdin;
\.


--
-- Data for Name: rateplan; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.rateplan (id, name, ror_data, ror_voice, ror_sms, ror_roaming_data, ror_roaming_voice, ror_roaming_sms, price) FROM stdin;
3	Elite Enterprise	0.02	0.05	0.01	\N	\N	\N	950.00
4	FouadEl2r4	0.01	0.01	0.01	\N	\N	\N	1.00
1	Basic	0.10	0.20	0.05	80.00	15.00	2.50	75.00
2	Premium Gold	0.05	0.10	0.02	65.00	12.00	1.50	370.00
\.


--
-- Data for Name: rateplan_service_package; Type: TABLE DATA; Schema: public; Owner: neondb_owner
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
4	5
4	4
\.


--
-- Data for Name: rejected_cdr; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.rejected_cdr (id, file_id, dial_a, dial_b, start_time, duration, service_id, rejection_reason, rejected_at) FROM stdin;
254	26	201560098469	201090000001	2026-04-11 09:54:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
255	26	201868108276	whatsapp.net	2026-04-25 12:39:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
256	26	201311169287	201090000002	2026-04-22 05:12:43	2092	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
257	26	201971294191	fmrz-telecom.net	2026-04-25 17:21:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
258	26	201253193055	whatsapp.net	2026-04-14 19:35:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
259	26	201973065083	201223344556	2026-04-12 13:57:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
260	26	201462099679	google.com	2026-04-20 17:05:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
261	26	201977901803	google.com	2026-04-14 21:13:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
262	26	201293346699	201000000008	2026-03-30 06:33:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
263	26	201358767975	201223344556	2026-04-01 08:01:43	1310	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
264	26	201264979417	201223344556	2026-04-03 14:02:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
265	26	201453406328	201090000003	2026-04-25 08:28:43	1864	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
266	26	201758547932	201090000002	2026-04-17 18:13:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
267	26	201745792041	201090000001	2026-04-17 03:35:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
268	26	201443434524	201223344556	2026-04-11 16:41:43	2665	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
269	26	201382757644	fmrz-telecom.net	2026-04-01 09:04:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
270	26	201765178273	fmrz-telecom.net	2026-04-12 09:04:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
271	26	201563988655	whatsapp.net	2026-04-19 22:59:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
272	26	201936541669	201223344556	2026-04-16 19:08:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
273	26	201577029209	201000000008	2026-04-23 15:41:43	1092	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
274	26	201934948509	201090000001	2026-04-14 02:30:43	2791	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
275	26	201664555584	fmrz-telecom.net	2026-04-25 04:21:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
276	26	201929443681	201000000008	2026-04-28 00:04:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
277	26	201926549412	facebook.com	2026-04-16 08:01:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
278	26	201576869694	201090000001	2026-04-12 10:45:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
279	26	201840246205	201000000008	2026-04-07 14:22:43	2824	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
280	26	201836494481	whatsapp.net	2026-04-20 20:16:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
281	26	201903689006	fmrz-telecom.net	2026-04-01 16:32:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
282	26	201141678272	fmrz-telecom.net	2026-04-07 13:58:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
283	26	201311169287	facebook.com	2026-04-25 15:06:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
284	26	201250407138	youtube.com	2026-04-22 07:14:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
285	26	201777712118	201090000002	2026-04-03 16:46:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
286	26	201523335558	201223344556	2026-04-14 16:39:43	2362	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
287	26	201773592311	201090000003	2026-04-01 23:32:43	3344	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
288	26	201243897854	201223344556	2026-04-20 15:12:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
289	26	201691258957	facebook.com	2026-04-26 05:15:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
290	26	201836494481	201090000001	2026-04-12 08:29:43	2550	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
291	26	201922219519	201090000002	2026-04-28 15:17:43	434	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
292	26	201453406328	201000000008	2026-04-18 06:28:43	494	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
293	26	201233888603	fmrz-telecom.net	2026-04-24 08:07:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
294	26	201651964318	youtube.com	2026-04-03 17:15:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
295	26	201773592311	201090000002	2026-04-26 21:10:43	1507	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
296	26	201975919900	201090000002	2026-04-17 03:03:43	699	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
297	26	201558289515	youtube.com	2026-03-30 03:32:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
298	26	201958871119	201090000003	2026-04-23 03:04:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
299	26	201763896489	201090000001	2026-04-07 14:27:43	3042	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
300	26	201212911963	whatsapp.net	2026-04-25 14:03:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
301	26	201776684616	201223344556	2026-03-31 02:00:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
302	26	201411625546	201223344556	2026-03-29 22:27:43	808	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
303	26	201966464792	youtube.com	2026-04-15 14:32:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
304	26	201988487838	201090000003	2026-04-19 07:50:43	140	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
305	26	201836494481	201090000002	2026-04-06 16:20:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
306	26	201402249115	201090000001	2026-04-14 22:18:43	1662	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
307	26	201947919413	201090000001	2026-04-25 12:03:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
308	26	201402249115	google.com	2026-04-12 21:13:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
309	26	201563988655	whatsapp.net	2026-04-16 13:44:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
310	26	201828797537	201090000002	2026-04-15 06:01:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
311	26	201252951019	201223344556	2026-04-06 13:05:43	526	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
312	26	201880722237	facebook.com	2026-04-20 08:09:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
313	26	201503209696	201000000008	2026-04-11 16:33:43	2324	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
314	26	201277202859	201000000008	2026-04-09 05:18:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
315	26	201922219519	201223344556	2026-04-01 14:50:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
316	26	201911268488	201000000008	2026-04-08 18:25:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
317	26	201362708743	google.com	2026-04-22 18:12:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
318	26	201252951019	201090000002	2026-04-03 06:32:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
319	26	201971560057	201090000001	2026-04-20 03:23:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
320	26	201200072017	youtube.com	2026-04-17 08:15:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
321	26	201894655743	201090000001	2026-04-02 23:14:43	159	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
322	26	201462099679	201000000008	2026-04-14 14:39:43	304	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
323	26	201198754346	201000000008	2026-04-18 23:59:43	514	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
324	26	201288445442	201000000008	2026-04-16 12:17:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
325	26	201691093859	201090000001	2026-04-18 08:55:43	600	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
326	26	201782140786	201090000002	2026-04-20 02:15:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
327	26	201949566929	fmrz-telecom.net	2026-04-02 01:08:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
328	26	201732245339	fmrz-telecom.net	2026-04-19 07:41:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
329	26	201955098229	fmrz-telecom.net	2026-04-09 08:31:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
330	26	201133087012	201090000002	2026-04-01 00:24:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
331	26	201189986095	fmrz-telecom.net	2026-04-08 15:47:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
332	26	201239535883	201090000002	2026-04-14 04:26:43	2347	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
333	26	201944566056	fmrz-telecom.net	2026-04-11 14:42:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
334	26	201376247512	201090000002	2026-04-05 23:25:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
335	26	201311702940	201000000008	2026-03-31 02:45:43	2620	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
336	26	201503209696	201090000001	2026-04-01 13:16:43	1321	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
337	26	201923881590	201223344556	2026-04-22 14:47:43	528	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
338	26	201623681391	201090000001	2026-04-15 20:52:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
339	26	201127385614	201090000003	2026-04-27 19:24:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
340	26	201240998376	facebook.com	2026-04-02 15:06:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
341	26	201462099679	201090000001	2026-04-14 01:28:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
342	26	201857808992	whatsapp.net	2026-04-20 02:36:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
343	26	201294741054	201090000001	2026-04-08 03:13:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
344	26	201398740844	fmrz-telecom.net	2026-04-03 08:03:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
345	26	201948481257	google.com	2026-04-08 22:15:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
346	26	201729037750	whatsapp.net	2026-04-28 09:43:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
347	26	201993721590	201090000002	2026-04-13 16:42:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
348	26	201155296993	201090000002	2026-04-17 07:44:43	2068	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
349	26	201440372741	facebook.com	2026-04-23 00:07:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
350	26	201133087012	201000000008	2026-04-26 11:40:43	1004	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
351	26	201568891063	201090000003	2026-04-23 03:54:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
352	26	201590865366	201090000002	2026-04-11 20:30:43	1923	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
353	26	201629559387	201090000001	2026-04-20 04:27:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
354	26	201342567152	201000000008	2026-04-09 06:55:43	2087	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
355	26	201960638663	201000000008	2026-04-17 14:41:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
356	26	201934948509	201000000008	2026-04-15 19:39:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
357	26	201954285513	facebook.com	2026-04-08 09:35:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
358	26	201952235801	201090000002	2026-04-17 12:05:43	1355	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
359	26	201810520048	201000000008	2026-04-29 19:58:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
360	26	201749088746	201090000002	2026-04-12 01:36:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
361	26	201369118737	201090000003	2026-04-23 01:21:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
362	26	201197452045	201090000002	2026-04-03 01:07:43	319	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
363	26	201301312298	201223344556	2026-04-24 15:33:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
364	26	201994216976	fmrz-telecom.net	2026-04-26 15:12:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
365	26	201198754346	facebook.com	2026-04-01 21:32:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
366	26	201958741292	youtube.com	2026-03-31 09:48:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
367	26	201198229833	201090000003	2026-03-30 15:19:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
368	26	201624427143	201000000008	2026-04-15 11:46:43	141	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
369	26	201817510118	201223344556	2026-04-22 00:43:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
370	26	201369118737	google.com	2026-03-31 15:29:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
371	26	201955816352	201090000003	2026-04-01 04:38:43	776	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
372	26	201994281608	201090000001	2026-04-21 22:48:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
373	26	201966464792	201090000001	2026-03-30 11:18:43	1676	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
374	26	201255851063	google.com	2026-04-14 11:16:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
375	26	201264979417	201090000001	2026-04-25 11:13:43	799	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
376	26	201688266834	201000000008	2026-04-06 19:21:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
377	26	201746369648	201090000001	2026-04-18 22:39:43	627	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
378	26	201233888603	201090000001	2026-04-16 17:06:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
379	26	201688266834	201090000002	2026-04-21 07:24:43	3583	1	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
380	26	201148309599	google.com	2026-04-02 00:51:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
381	26	201402249115	201000000008	2026-04-12 12:15:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
382	26	201947919413	google.com	2026-04-18 13:57:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
383	26	201840246205	201090000003	2026-04-16 13:45:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
384	26	201462099679	201090000002	2026-04-07 23:04:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
385	26	201676533855	google.com	2026-04-28 19:41:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
386	26	201671270881	201000000008	2026-04-16 04:33:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
387	26	201781708648	201090000002	2026-04-11 11:46:43	1	3	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
388	26	201453534222	youtube.com	2026-03-30 01:44:43	1	2	NO_CONTRACT_FOUND	2026-04-29 17:16:43.970573
389	27	201747728661	201090000002	2026-03-31 01:18:10	936	1	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
390	27	201976337336	201090000003	2026-04-10 20:27:10	707	1	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
391	27	201873089796	whatsapp.net	2026-04-02 04:19:10	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
392	27	201987284894	fmrz-telecom.net	2026-04-10 10:58:10	1	2	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
393	27	201812151012	201090000001	2026-04-12 18:28:10	1	3	CONTRACT_DEBT_HOLD	2026-04-29 17:17:10.57621
394	27	201000000018	201090000001	2026-04-25 02:20:10	1	3	CONTRACT_TERMINATED	2026-04-29 17:17:10.57621
395	27	201571491852	google.com	2026-04-18 03:52:10	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
396	27	201536117987	201090000002	2026-04-17 17:57:10	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
397	27	201483356980	201090000001	2026-04-20 10:57:10	1	3	CONTRACT_DEBT_HOLD	2026-04-29 17:17:10.57621
398	27	201927321736	youtube.com	2026-04-16 22:01:10	1	2	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
399	27	201697146405	201090000003	2026-04-12 02:53:10	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
400	27	201972882426	facebook.com	2026-04-17 12:32:10	1	2	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
401	27	201536117987	201090000003	2026-04-14 04:08:10	648	1	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
402	27	201788349956	201090000003	2026-04-07 16:31:10	3350	1	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
403	27	201385193015	google.com	2026-04-19 20:15:10	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
404	27	201385193015	facebook.com	2026-03-30 15:20:10	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
405	27	201483850292	fmrz-telecom.net	2026-04-26 20:26:10	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
406	27	201139449782	201000000008	2026-04-06 08:14:10	2396	1	CONTRACT_DEBT_HOLD	2026-04-29 17:17:10.57621
407	27	201309264924	201090000001	2026-04-04 02:58:10	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
408	27	201207365610	whatsapp.net	2026-04-23 02:26:10	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
409	27	201988381018	google.com	2026-04-17 03:35:10	1	2	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
410	27	201400634335	201000000008	2026-04-17 13:30:10	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
411	27	201597950279	201090000003	2026-03-31 02:01:10	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
412	27	201981231815	201000000008	2026-04-24 02:30:10	1	3	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
413	27	201964750846	youtube.com	2026-04-15 14:30:10	1	2	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
414	27	201958687287	fmrz-telecom.net	2026-04-15 05:33:10	1	2	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
415	27	201940132536	google.com	2026-04-23 00:33:10	1	2	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
416	27	201956566033	facebook.com	2026-04-15 05:44:10	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
417	27	201655520407	whatsapp.net	2026-04-29 15:05:10	1	2	CONTRACT_DEBT_HOLD	2026-04-29 17:17:10.57621
418	27	201997644052	201223344556	2026-03-31 05:00:10	3262	1	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
419	27	201995004376	youtube.com	2026-04-29 04:11:10	1	2	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
420	27	201588843428	201090000003	2026-04-26 00:16:10	1894	1	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
421	27	201400634335	201000000008	2026-04-13 10:06:10	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
422	27	201984329640	201090000003	2026-04-14 18:18:10	3070	1	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
423	27	201983056461	201223344556	2026-04-11 08:59:10	1	3	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
424	27	201953541738	201090000003	2026-04-05 19:34:10	1	3	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
425	27	201947522638	201223344556	2026-04-01 06:02:10	1	3	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
426	27	201599843015	201090000002	2026-04-06 03:18:10	1232	1	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
427	27	201272518692	201090000003	2026-04-23 17:27:10	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
428	27	201919920289	201090000001	2026-04-09 13:14:10	1	3	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
429	27	201000000013	fmrz-telecom.net	2026-04-20 01:35:10	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
430	27	201597950279	201000000008	2026-04-07 11:56:10	2140	1	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
431	27	201582580004	201223344556	2026-04-18 11:42:10	1992	1	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
432	27	201485461340	whatsapp.net	2026-04-08 02:07:10	1	2	CONTRACT_DEBT_HOLD	2026-04-29 17:17:10.57621
433	27	201922767161	201000000008	2026-04-18 08:53:10	1	3	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
434	27	201898189763	facebook.com	2026-04-14 11:52:10	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
435	27	201948176180	201090000002	2026-04-04 17:12:10	1	3	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
436	27	201536117987	201090000002	2026-04-09 19:10:10	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
437	27	201914700901	fmrz-telecom.net	2026-04-10 04:42:10	1	2	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
438	27	201927363900	201000000008	2026-04-16 12:31:10	453	1	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
439	27	201989326331	201090000001	2026-04-17 05:29:10	1493	1	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
440	27	201385193015	201223344556	2026-04-21 12:00:10	1350	1	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
441	27	201503292458	201223344556	2026-04-11 03:38:10	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
442	27	201542700474	201090000002	2026-04-27 02:23:10	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
443	27	201930595687	201090000001	2026-04-08 12:58:10	1	3	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
444	27	201483850292	youtube.com	2026-04-02 13:15:10	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
445	27	201655520407	google.com	2026-04-07 03:26:10	1	2	CONTRACT_DEBT_HOLD	2026-04-29 17:17:10.57621
446	27	201936243697	201090000001	2026-04-21 05:09:10	1256	1	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
447	27	201597950279	youtube.com	2026-04-19 11:51:10	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
448	27	201697146405	facebook.com	2026-04-13 23:35:10	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
449	27	201655520407	201223344556	2026-03-31 14:48:10	1	3	CONTRACT_DEBT_HOLD	2026-04-29 17:17:10.57621
450	27	201984120775	facebook.com	2026-04-05 12:20:10	1	2	NO_CONTRACT_FOUND	2026-04-29 17:17:10.57621
451	27	201988830569	201090000002	2026-04-09 10:58:10	800	1	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
452	27	201000000013	youtube.com	2026-04-03 22:29:10	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
453	27	201385305556	fmrz-telecom.net	2026-04-09 19:52:10	1	2	CONTRACT_DEBT_HOLD	2026-04-29 17:17:10.57621
454	27	201582580004	201090000002	2026-04-27 03:02:10	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
455	27	201297694951	youtube.com	2026-04-14 11:13:10	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
456	27	201788349956	201090000001	2026-04-20 01:53:10	3185	1	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
457	27	201483356980	201000000008	2026-04-05 03:49:10	1	3	CONTRACT_DEBT_HOLD	2026-04-29 17:17:10.57621
458	27	201793137497	201000000008	2026-04-12 05:16:10	1787	1	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
459	27	201756553646	201223344556	2026-04-26 02:33:10	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 17:17:10.57621
460	4	201836162878	201223344556	2026-04-13 06:50:15	799	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
461	4	201582165582	201223344556	2026-04-21 09:10:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
462	4	201656715920	201090000003	2026-04-13 00:23:15	2298	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
463	4	201526237308	201090000002	2026-04-07 10:10:15	2578	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
464	4	201776684616	201090000001	2026-04-19 04:29:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
465	4	201123905982	201223344556	2026-04-17 13:28:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
466	4	201934948509	201000000008	2026-04-18 01:19:15	1108	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
467	4	201256506041	201223344556	2026-04-20 12:47:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
468	4	201779264035	201090000003	2026-04-22 01:24:15	3534	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
469	4	201197452045	201000000008	2026-04-20 17:45:15	2442	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
470	4	201189986095	whatsapp.net	2026-04-10 19:33:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
471	4	201656715920	facebook.com	2026-04-03 16:21:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
472	4	201777712118	201223344556	2026-04-06 07:08:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
473	4	201293346699	google.com	2026-04-13 10:32:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
474	4	201653069004	201000000008	2026-04-15 07:48:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
475	4	201420871936	201000000008	2026-04-05 12:45:15	2730	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
476	4	201938325149	201223344556	2026-04-16 17:32:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
477	4	201127385614	fmrz-telecom.net	2026-04-07 16:49:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
478	4	201758547932	201090000003	2026-04-13 20:38:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
479	4	201167088186	201090000001	2026-04-25 17:30:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
480	4	201718702362	201090000001	2026-04-17 21:56:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
481	4	201807282720	201090000002	2026-04-27 11:42:15	1110	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
482	4	201857808992	201090000003	2026-04-15 02:27:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
483	4	201411625546	201090000001	2026-04-08 16:38:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
484	4	201653069004	youtube.com	2026-04-19 05:34:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
485	4	201133087012	fmrz-telecom.net	2026-04-04 11:54:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
486	4	201767489862	201090000003	2026-04-21 05:15:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
487	4	201804307139	201090000001	2026-04-08 05:24:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
488	4	201186352421	fmrz-telecom.net	2026-04-21 06:43:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
489	4	201807868584	youtube.com	2026-04-01 21:55:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
490	4	201676533855	youtube.com	2026-04-21 21:48:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
491	4	201807868584	youtube.com	2026-04-08 10:43:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
492	4	201211097847	201090000001	2026-04-03 13:25:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
493	4	201802917632	201090000001	2026-04-18 11:13:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
494	4	201288445442	facebook.com	2026-04-18 17:43:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
495	4	201936218593	201090000003	2026-04-02 01:05:15	2928	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
496	4	201782140786	201223344556	2026-04-21 09:57:15	3000	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
497	4	201717769502	fmrz-telecom.net	2026-04-03 23:41:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
498	4	201419739858	201090000001	2026-04-23 10:58:15	3089	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
499	4	201335272827	google.com	2026-04-02 14:00:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
500	4	201233997401	201223344556	2026-04-21 22:15:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
501	4	201982089526	fmrz-telecom.net	2026-04-12 13:59:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
502	4	201255851063	201090000002	2026-04-16 19:49:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
503	4	201495133161	201000000008	2026-04-13 22:21:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
504	4	201711745398	youtube.com	2026-04-24 17:18:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
505	4	201670213654	youtube.com	2026-04-01 12:48:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
506	4	201385628459	201090000001	2026-04-09 07:58:15	3390	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
507	4	201694166136	201090000001	2026-04-05 03:38:15	2745	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
508	4	201382757644	google.com	2026-03-31 13:51:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
509	4	201804307139	201223344556	2026-04-14 15:47:15	1853	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
510	4	201398740844	201090000001	2026-03-30 20:25:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
511	4	201267326529	201000000008	2026-04-05 01:38:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
512	4	201803964873	201090000002	2026-03-30 10:32:15	83	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
513	4	201944158137	201000000008	2026-04-21 01:52:15	2800	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
514	4	201382757644	google.com	2026-04-05 05:14:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
515	4	201141678272	201090000002	2026-04-17 00:09:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
516	4	201718702362	201223344556	2026-04-08 16:44:15	1509	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
517	4	201753036489	201090000002	2026-04-08 15:46:15	911	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
518	4	201407381378	201000000008	2026-04-20 21:48:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
519	4	201806271599	whatsapp.net	2026-04-22 08:59:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
520	4	201987939852	201090000001	2026-04-11 11:21:15	2890	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
521	4	201608773241	facebook.com	2026-04-02 15:36:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
522	4	201753036489	201090000002	2026-04-11 05:39:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
523	4	201753036489	201090000003	2026-04-21 13:48:15	476	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
524	4	201367791331	facebook.com	2026-04-29 18:18:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
525	4	201444773169	201090000003	2026-04-27 22:09:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
526	4	201972231258	201090000003	2026-04-20 21:26:15	3132	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
527	4	201998010690	facebook.com	2026-04-24 19:05:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
528	4	201489016716	201090000002	2026-04-11 16:00:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
529	4	201807868584	201090000002	2026-04-08 04:38:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
530	4	201453534222	201223344556	2026-04-23 08:11:15	2977	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
531	4	201971560057	facebook.com	2026-04-23 23:18:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
532	4	201133087012	youtube.com	2026-04-16 08:10:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
533	4	201330199728	201090000002	2026-04-20 18:04:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
534	4	201649117498	201000000008	2026-04-22 12:41:15	3079	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
535	4	201563988655	google.com	2026-04-11 08:55:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
536	4	201773592311	201223344556	2026-04-28 16:02:15	1302	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
537	4	201547174916	201000000008	2026-04-12 23:29:15	1413	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
538	4	201192472707	201223344556	2026-04-29 19:32:15	790	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
539	4	201974879326	201000000008	2026-04-02 10:11:15	3096	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
540	4	201810520048	201090000002	2026-04-07 17:01:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
541	4	201255851063	whatsapp.net	2026-04-29 17:23:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
542	4	201420871936	youtube.com	2026-04-02 15:34:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
543	4	201175597165	201223344556	2026-04-12 18:48:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
544	4	201915226015	youtube.com	2026-04-18 09:39:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
545	4	201758547932	201090000001	2026-04-28 10:02:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
546	4	201824794284	youtube.com	2026-04-28 13:54:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
547	4	201187441626	fmrz-telecom.net	2026-04-20 18:43:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
548	4	201773592311	201090000002	2026-04-24 23:35:15	2554	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
549	4	201619259144	201223344556	2026-04-07 03:31:15	921	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
550	4	201987939852	201090000001	2026-04-28 08:15:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
551	4	201473293348	whatsapp.net	2026-04-12 04:03:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
552	4	201121918717	201090000002	2026-04-06 17:19:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
553	4	201659706181	google.com	2026-04-18 00:57:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
554	4	201659605961	201090000001	2026-04-01 14:08:15	3018	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
555	4	201781708648	201000000008	2026-04-06 04:52:15	3136	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
556	4	201367791331	201223344556	2026-04-28 14:45:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
557	4	201121918717	201000000008	2026-04-12 20:56:15	116	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
558	4	201571953826	whatsapp.net	2026-04-08 19:27:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
559	4	201670213654	facebook.com	2026-04-29 13:31:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
560	4	201733342762	youtube.com	2026-04-13 03:14:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
561	4	201987939852	201090000001	2026-04-25 09:26:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
562	4	201198229833	youtube.com	2026-04-13 16:48:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
563	4	201906393104	201090000003	2026-04-05 22:26:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
564	4	201358767975	201000000008	2026-04-07 10:41:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
565	4	201471555986	201223344556	2026-04-12 13:34:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
566	4	201711745398	201000000008	2026-04-28 23:45:15	3580	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
567	4	201256506041	201090000001	2026-03-30 03:26:15	757	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
568	4	201906393104	201223344556	2026-04-21 16:56:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
569	4	201955666023	201223344556	2026-04-09 10:09:15	662	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
570	4	201835042990	youtube.com	2026-04-05 14:43:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
571	4	201977256247	google.com	2026-04-10 20:45:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
572	4	201311169287	201090000003	2026-04-06 13:00:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
573	4	201984327233	201090000002	2026-04-14 21:33:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
574	4	201225632920	201000000008	2026-04-26 11:29:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
575	4	201984327233	201090000001	2026-04-22 05:38:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
576	4	201254131544	201000000008	2026-04-05 16:19:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
577	4	201694166136	201090000002	2026-04-11 21:40:15	935	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
578	4	201998039083	fmrz-telecom.net	2026-04-28 13:55:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
579	4	201711745398	fmrz-telecom.net	2026-04-08 15:47:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
580	4	201554543248	whatsapp.net	2026-04-29 03:52:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
581	4	201591504256	201000000008	2026-04-15 12:04:15	3395	1	NO_CONTRACT_FOUND	2026-04-29 21:15:01.05864
582	6	201836162878	201223344556	2026-04-13 06:50:15	799	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
583	6	201582165582	201223344556	2026-04-21 09:10:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
584	6	201656715920	201090000003	2026-04-13 00:23:15	2298	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
585	6	201526237308	201090000002	2026-04-07 10:10:15	2578	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
586	6	201776684616	201090000001	2026-04-19 04:29:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
587	6	201123905982	201223344556	2026-04-17 13:28:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
588	6	201934948509	201000000008	2026-04-18 01:19:15	1108	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
589	6	201256506041	201223344556	2026-04-20 12:47:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
590	6	201779264035	201090000003	2026-04-22 01:24:15	3534	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
591	6	201197452045	201000000008	2026-04-20 17:45:15	2442	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
592	6	201189986095	whatsapp.net	2026-04-10 19:33:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
593	6	201656715920	facebook.com	2026-04-03 16:21:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
594	6	201777712118	201223344556	2026-04-06 07:08:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
595	6	201293346699	google.com	2026-04-13 10:32:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
596	6	201653069004	201000000008	2026-04-15 07:48:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
597	6	201420871936	201000000008	2026-04-05 12:45:15	2730	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
598	6	201938325149	201223344556	2026-04-16 17:32:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
599	6	201127385614	fmrz-telecom.net	2026-04-07 16:49:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
600	6	201758547932	201090000003	2026-04-13 20:38:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
601	6	201167088186	201090000001	2026-04-25 17:30:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
602	6	201718702362	201090000001	2026-04-17 21:56:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
603	6	201807282720	201090000002	2026-04-27 11:42:15	1110	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
604	6	201857808992	201090000003	2026-04-15 02:27:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
605	6	201411625546	201090000001	2026-04-08 16:38:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
606	6	201653069004	youtube.com	2026-04-19 05:34:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
607	6	201133087012	fmrz-telecom.net	2026-04-04 11:54:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
608	6	201767489862	201090000003	2026-04-21 05:15:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
609	6	201804307139	201090000001	2026-04-08 05:24:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
610	6	201186352421	fmrz-telecom.net	2026-04-21 06:43:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
611	6	201807868584	youtube.com	2026-04-01 21:55:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
612	6	201676533855	youtube.com	2026-04-21 21:48:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
613	6	201807868584	youtube.com	2026-04-08 10:43:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
614	6	201211097847	201090000001	2026-04-03 13:25:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
615	6	201802917632	201090000001	2026-04-18 11:13:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
616	6	201288445442	facebook.com	2026-04-18 17:43:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
617	6	201936218593	201090000003	2026-04-02 01:05:15	2928	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
618	6	201782140786	201223344556	2026-04-21 09:57:15	3000	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
619	6	201717769502	fmrz-telecom.net	2026-04-03 23:41:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
620	6	201419739858	201090000001	2026-04-23 10:58:15	3089	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
621	6	201335272827	google.com	2026-04-02 14:00:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
622	6	201233997401	201223344556	2026-04-21 22:15:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
623	6	201982089526	fmrz-telecom.net	2026-04-12 13:59:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
624	6	201255851063	201090000002	2026-04-16 19:49:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
625	6	201495133161	201000000008	2026-04-13 22:21:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
626	6	201711745398	youtube.com	2026-04-24 17:18:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
627	6	201670213654	youtube.com	2026-04-01 12:48:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
628	6	201385628459	201090000001	2026-04-09 07:58:15	3390	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
629	6	201694166136	201090000001	2026-04-05 03:38:15	2745	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
630	6	201382757644	google.com	2026-03-31 13:51:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
631	6	201804307139	201223344556	2026-04-14 15:47:15	1853	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
632	6	201398740844	201090000001	2026-03-30 20:25:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
633	6	201267326529	201000000008	2026-04-05 01:38:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
634	6	201803964873	201090000002	2026-03-30 10:32:15	83	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
635	6	201944158137	201000000008	2026-04-21 01:52:15	2800	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
636	6	201382757644	google.com	2026-04-05 05:14:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
637	6	201141678272	201090000002	2026-04-17 00:09:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
638	6	201718702362	201223344556	2026-04-08 16:44:15	1509	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
639	6	201753036489	201090000002	2026-04-08 15:46:15	911	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
640	6	201407381378	201000000008	2026-04-20 21:48:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
641	6	201806271599	whatsapp.net	2026-04-22 08:59:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
642	6	201987939852	201090000001	2026-04-11 11:21:15	2890	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
643	6	201608773241	facebook.com	2026-04-02 15:36:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
644	6	201753036489	201090000002	2026-04-11 05:39:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
645	6	201753036489	201090000003	2026-04-21 13:48:15	476	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
646	6	201367791331	facebook.com	2026-04-29 18:18:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
647	6	201444773169	201090000003	2026-04-27 22:09:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
648	6	201972231258	201090000003	2026-04-20 21:26:15	3132	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
649	6	201998010690	facebook.com	2026-04-24 19:05:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
650	6	201489016716	201090000002	2026-04-11 16:00:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
651	6	201807868584	201090000002	2026-04-08 04:38:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
652	6	201453534222	201223344556	2026-04-23 08:11:15	2977	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
653	6	201971560057	facebook.com	2026-04-23 23:18:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
654	6	201133087012	youtube.com	2026-04-16 08:10:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
655	6	201330199728	201090000002	2026-04-20 18:04:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
656	6	201649117498	201000000008	2026-04-22 12:41:15	3079	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
657	6	201563988655	google.com	2026-04-11 08:55:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
658	6	201773592311	201223344556	2026-04-28 16:02:15	1302	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
659	6	201547174916	201000000008	2026-04-12 23:29:15	1413	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
660	6	201192472707	201223344556	2026-04-29 19:32:15	790	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
661	6	201974879326	201000000008	2026-04-02 10:11:15	3096	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
662	6	201810520048	201090000002	2026-04-07 17:01:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
663	6	201255851063	whatsapp.net	2026-04-29 17:23:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
664	6	201420871936	youtube.com	2026-04-02 15:34:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
665	6	201175597165	201223344556	2026-04-12 18:48:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
666	6	201915226015	youtube.com	2026-04-18 09:39:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
667	6	201758547932	201090000001	2026-04-28 10:02:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
668	6	201824794284	youtube.com	2026-04-28 13:54:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
669	6	201187441626	fmrz-telecom.net	2026-04-20 18:43:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
670	6	201773592311	201090000002	2026-04-24 23:35:15	2554	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
671	6	201619259144	201223344556	2026-04-07 03:31:15	921	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
672	6	201987939852	201090000001	2026-04-28 08:15:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
673	6	201473293348	whatsapp.net	2026-04-12 04:03:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
674	6	201121918717	201090000002	2026-04-06 17:19:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
675	6	201659706181	google.com	2026-04-18 00:57:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
676	6	201659605961	201090000001	2026-04-01 14:08:15	3018	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
677	6	201781708648	201000000008	2026-04-06 04:52:15	3136	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
678	6	201367791331	201223344556	2026-04-28 14:45:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
679	6	201121918717	201000000008	2026-04-12 20:56:15	116	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
680	6	201571953826	whatsapp.net	2026-04-08 19:27:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
681	6	201670213654	facebook.com	2026-04-29 13:31:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
682	6	201733342762	youtube.com	2026-04-13 03:14:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
683	6	201987939852	201090000001	2026-04-25 09:26:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
684	6	201198229833	youtube.com	2026-04-13 16:48:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
685	6	201906393104	201090000003	2026-04-05 22:26:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
686	6	201358767975	201000000008	2026-04-07 10:41:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
687	6	201471555986	201223344556	2026-04-12 13:34:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
688	6	201711745398	201000000008	2026-04-28 23:45:15	3580	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
689	6	201256506041	201090000001	2026-03-30 03:26:15	757	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
690	6	201906393104	201223344556	2026-04-21 16:56:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
691	6	201955666023	201223344556	2026-04-09 10:09:15	662	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
692	6	201835042990	youtube.com	2026-04-05 14:43:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
693	6	201977256247	google.com	2026-04-10 20:45:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
694	6	201311169287	201090000003	2026-04-06 13:00:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
695	6	201984327233	201090000002	2026-04-14 21:33:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
696	6	201225632920	201000000008	2026-04-26 11:29:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
697	6	201984327233	201090000001	2026-04-22 05:38:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
698	6	201254131544	201000000008	2026-04-05 16:19:15	1	3	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
699	6	201694166136	201090000002	2026-04-11 21:40:15	935	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
700	6	201998039083	fmrz-telecom.net	2026-04-28 13:55:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
701	6	201711745398	fmrz-telecom.net	2026-04-08 15:47:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
702	6	201554543248	whatsapp.net	2026-04-29 03:52:15	1	2	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
703	6	201591504256	201000000008	2026-04-15 12:04:15	3395	1	NO_CONTRACT_FOUND	2026-04-29 21:29:59.552718
704	7	201187441626	201090000002	2026-04-21 14:29:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
705	7	201554543248	201090000001	2026-04-11 06:35:42	3226	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
706	7	201294741054	201000000008	2026-04-24 23:16:42	1682	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
707	7	201929443681	201090000002	2026-04-16 04:51:42	1126	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
708	7	201960970378	facebook.com	2026-04-16 23:50:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
709	7	201254131544	whatsapp.net	2026-03-30 09:07:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
710	7	201989105436	201090000002	2026-03-30 17:24:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
711	7	201653069004	201090000003	2026-04-01 17:38:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
712	7	201949415036	facebook.com	2026-04-17 15:25:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
713	7	201255851063	201000000008	2026-03-31 19:14:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
714	7	201987939852	201090000003	2026-04-18 12:50:42	2544	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
715	7	201255516201	201090000002	2026-04-22 02:08:42	214	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
716	7	201192472707	google.com	2026-04-09 02:19:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
717	7	201935743165	youtube.com	2026-04-01 04:12:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
718	7	201243897854	201223344556	2026-04-22 10:32:42	714	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
719	7	201358767975	201000000008	2026-04-05 08:51:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
720	7	201582165582	201223344556	2026-04-02 05:24:42	3295	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
721	7	201804307139	youtube.com	2026-04-07 05:33:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
722	7	201804307139	201000000008	2026-04-16 13:10:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
723	7	201462924192	201090000002	2026-04-24 16:58:42	2748	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
724	7	201419739858	201090000002	2026-04-01 03:00:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
725	7	201200072017	facebook.com	2026-04-17 22:14:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
726	7	201971560057	201090000001	2026-04-14 11:26:42	978	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
727	7	201929443681	whatsapp.net	2026-04-19 21:58:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
728	7	201473293348	201223344556	2026-04-05 10:57:42	993	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
729	7	201766068173	201090000003	2026-04-28 02:48:42	1356	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
730	7	201113312729	201223344556	2026-04-24 01:53:42	1702	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
731	7	201135432749	201000000008	2026-04-05 01:46:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
732	7	201100488135	201000000008	2026-04-08 16:38:42	386	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
733	7	201779264035	201223344556	2026-04-19 08:58:42	3546	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
734	7	201402249115	google.com	2026-04-15 05:59:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
735	7	201623681391	201090000001	2026-04-20 17:59:42	300	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
736	7	201720066465	201223344556	2026-04-17 07:41:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
737	7	201671270881	201090000001	2026-04-29 05:52:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
738	7	201489016716	google.com	2026-04-10 10:58:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
739	7	201449404580	fmrz-telecom.net	2026-04-21 16:55:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
740	7	201949566929	google.com	2026-03-30 07:56:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
741	7	201198229833	201090000003	2026-04-07 03:18:42	1958	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
742	7	201599166808	201090000001	2026-04-20 07:35:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
743	7	201284293396	fmrz-telecom.net	2026-04-23 21:21:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
744	7	201186352421	fmrz-telecom.net	2026-04-07 14:37:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
745	7	201921537400	fmrz-telecom.net	2026-04-28 09:45:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
746	7	201659605961	201223344556	2026-04-09 10:13:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
747	7	201511060475	201223344556	2026-04-26 20:58:42	411	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
748	7	201455334792	whatsapp.net	2026-04-13 20:17:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
749	7	201473293348	fmrz-telecom.net	2026-04-19 11:10:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
750	7	201777712118	201090000002	2026-04-03 20:33:42	1548	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
751	7	201274207034	201223344556	2026-04-08 05:53:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
752	7	201758547932	201223344556	2026-04-09 03:38:42	429	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
753	7	201684075608	201223344556	2026-04-23 01:40:42	2685	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
754	7	201453534222	facebook.com	2026-04-05 16:12:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
755	7	201988892685	201090000001	2026-03-30 00:34:42	2185	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
756	7	201766068173	201223344556	2026-04-14 12:16:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
757	7	201942725017	201090000001	2026-04-08 22:07:42	2393	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
758	7	201509717260	whatsapp.net	2026-04-02 23:56:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
759	7	201570066932	201000000008	2026-04-12 08:56:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
760	7	201115133298	fmrz-telecom.net	2026-04-12 00:58:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
761	7	201211097847	youtube.com	2026-04-18 21:41:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
762	7	201470237935	201223344556	2026-04-26 17:07:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
763	7	201926931465	201090000002	2026-04-11 00:49:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
764	7	201329180329	201090000003	2026-04-12 18:39:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
765	7	201141678272	201090000003	2026-03-30 17:28:42	1274	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
766	7	201804307139	fmrz-telecom.net	2026-04-27 12:45:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
767	7	201502613870	youtube.com	2026-04-19 13:49:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
768	7	201148309599	201000000008	2026-04-11 04:13:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
769	7	201959327703	facebook.com	2026-04-24 20:23:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
770	7	201767489862	201223344556	2026-04-16 18:13:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
771	7	201449404580	201090000003	2026-04-28 10:37:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
772	7	201998039083	201223344556	2026-04-10 09:14:42	3461	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
773	7	201671270881	201000000008	2026-04-09 19:59:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
774	7	201284293396	201090000003	2026-04-10 11:11:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
775	7	201921537400	201090000002	2026-04-11 14:32:42	1899	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
776	7	201691281998	201090000002	2026-04-25 23:06:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
777	7	201198229833	201000000008	2026-04-22 00:09:42	2520	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
778	7	201309518429	201090000002	2026-04-27 12:02:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
779	7	201284293396	201090000001	2026-04-26 13:08:42	2336	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
780	7	201624427143	google.com	2026-04-15 18:58:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
781	7	201309518429	facebook.com	2026-04-02 07:04:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
782	7	201599166808	201090000002	2026-04-18 05:47:42	1709	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
783	7	201766068173	fmrz-telecom.net	2026-04-17 00:31:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
784	7	201758547932	201000000008	2026-04-24 01:54:42	3568	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
785	7	201367791331	201090000001	2026-04-27 13:49:42	2148	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
786	7	201243897854	201223344556	2026-04-18 09:27:42	274	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
787	7	201652299436	201090000001	2026-04-07 03:21:42	3342	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
788	7	201489051711	google.com	2026-04-04 22:40:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
789	7	201985690407	facebook.com	2026-04-04 20:04:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
790	7	201828688191	201090000001	2026-04-24 00:24:42	1159	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
791	7	201286932142	201000000008	2026-04-23 12:21:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
792	7	201570066932	whatsapp.net	2026-04-13 05:56:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
793	7	201189986095	youtube.com	2026-04-24 01:30:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
794	7	201582165582	201223344556	2026-04-17 10:38:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
795	7	201570066932	youtube.com	2026-04-14 14:48:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
796	7	201398740844	fmrz-telecom.net	2026-04-29 07:39:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
797	7	201720066465	201223344556	2026-04-03 06:24:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
798	7	201274207034	201223344556	2026-04-29 06:26:42	84	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
799	7	201123905982	201090000002	2026-04-22 19:21:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
800	7	201903689006	youtube.com	2026-04-06 02:03:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
801	7	201599166808	201090000001	2026-04-14 21:22:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
802	7	201868108276	201090000001	2026-04-20 11:48:42	1266	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
803	7	201471555986	201223344556	2026-04-24 07:16:42	491	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
804	7	201284293396	201090000003	2026-04-24 15:02:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
805	7	201929443681	facebook.com	2026-04-09 06:27:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
806	7	201254131544	201090000003	2026-04-10 17:00:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
807	7	201926548886	201223344556	2026-04-06 20:56:42	3123	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
808	7	201924975793	201090000003	2026-04-29 17:49:42	3175	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
809	7	201443434524	fmrz-telecom.net	2026-04-06 12:41:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
810	7	201385628459	201090000003	2026-04-23 06:23:42	2542	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
811	7	201189986095	201090000001	2026-04-25 11:28:42	955	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
812	7	201437218906	whatsapp.net	2026-04-28 05:42:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
813	7	201563988655	fmrz-telecom.net	2026-04-13 07:50:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
814	7	201420871936	youtube.com	2026-04-08 01:14:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
815	7	201133087012	201223344556	2026-04-25 09:12:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
816	7	201563988655	google.com	2026-04-29 12:41:42	1	2	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
817	7	201544098306	201090000001	2026-04-06 21:34:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
818	7	201733342762	201223344556	2026-04-18 02:18:42	1	3	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
819	7	201828688191	201090000003	2026-04-29 00:17:42	836	1	NO_CONTRACT_FOUND	2026-04-29 21:41:33.304592
820	8	201737734249	fmrz-telecom.net	2026-04-28 16:06:52	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 21:43:00.718836
821	8	201994095574	201090000002	2026-04-10 15:14:52	2721	1	NO_CONTRACT_FOUND	2026-04-29 21:43:00.718836
822	8	201605591348	201223344556	2026-04-24 12:32:52	370	1	CONTRACT_DEBT_HOLD	2026-04-29 21:43:00.718836
823	8	201207540095	201090000001	2026-04-29 18:55:52	1573	1	CONTRACT_ADMIN_HOLD	2026-04-29 21:43:00.718836
824	8	201989442768	youtube.com	2026-04-17 22:37:52	1	2	NO_CONTRACT_FOUND	2026-04-29 21:43:00.718836
825	8	201443034851	201000000008	2026-04-18 07:56:52	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 21:43:00.718836
826	8	201999508283	facebook.com	2026-04-24 18:58:52	1	2	NO_CONTRACT_FOUND	2026-04-29 21:43:00.718836
827	8	201222156953	201090000002	2026-04-25 10:48:52	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 21:43:00.718836
828	8	201963671788	201090000001	2026-04-03 13:50:52	1	3	NO_CONTRACT_FOUND	2026-04-29 21:43:00.718836
829	8	201691828182	facebook.com	2026-04-06 09:09:52	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 21:43:00.718836
830	8	201212953273	201090000001	2026-04-03 06:41:52	1	3	CONTRACT_DEBT_HOLD	2026-04-29 21:43:00.718836
831	8	201430418861	201090000001	2026-04-11 15:11:52	1	3	CONTRACT_DEBT_HOLD	2026-04-29 21:43:00.718836
832	8	201821214312	201090000002	2026-04-05 14:20:52	676	1	CONTRACT_ADMIN_HOLD	2026-04-29 21:43:00.718836
833	8	201485924091	facebook.com	2026-03-31 20:59:52	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 21:43:00.718836
834	8	201480470252	201000000008	2026-04-05 22:00:52	1	3	CONTRACT_DEBT_HOLD	2026-04-29 21:43:00.718836
835	8	201931499262	201090000001	2026-04-29 11:26:52	2435	1	CONTRACT_ADMIN_HOLD	2026-04-29 21:43:00.718836
836	8	201309264655	youtube.com	2026-04-19 08:48:52	1	2	CONTRACT_ADMIN_HOLD	2026-04-29 21:43:00.718836
837	8	201681313506	201223344556	2026-04-24 04:29:52	1030	1	CONTRACT_ADMIN_HOLD	2026-04-29 21:43:00.718836
838	8	201985698095	201223344556	2026-04-07 09:24:52	451	1	NO_CONTRACT_FOUND	2026-04-29 21:43:00.718836
839	8	201480470252	201090000001	2026-04-01 07:55:52	1	3	CONTRACT_DEBT_HOLD	2026-04-29 21:43:00.718836
840	8	201280350684	201000000008	2026-04-10 22:58:52	3543	1	CONTRACT_DEBT_HOLD	2026-04-29 21:43:00.718836
841	8	201568821728	201223344556	2026-04-17 17:44:52	526	1	CONTRACT_ADMIN_HOLD	2026-04-29 21:43:00.718836
842	8	201335082038	201223344556	2026-04-20 09:12:52	623	1	CONTRACT_ADMIN_HOLD	2026-04-29 21:43:00.718836
843	8	201943119660	201090000002	2026-04-07 07:59:52	394	1	NO_CONTRACT_FOUND	2026-04-29 21:43:00.718836
844	8	201920376723	youtube.com	2026-04-20 21:32:52	1	2	NO_CONTRACT_FOUND	2026-04-29 21:43:00.718836
845	9	201980562893	201000000008	2026-04-10 05:14:46	1	3	NO_CONTRACT_FOUND	2026-04-29 21:46:52.946685
846	9	201935514910	201090000001	2026-04-03 23:08:46	1	3	NO_CONTRACT_FOUND	2026-04-29 21:46:52.946685
847	9	201925617435	google.com	2026-04-12 04:20:46	1	2	NO_CONTRACT_FOUND	2026-04-29 21:46:52.946685
848	9	201568821728	201223344556	2026-04-17 13:06:46	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 21:46:52.946685
849	9	201480470252	201223344556	2026-04-18 18:47:46	3166	1	CONTRACT_DEBT_HOLD	2026-04-29 21:46:52.946685
850	9	201933498428	201090000002	2026-04-26 15:14:46	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 21:46:52.946685
851	9	201289319888	201223344556	2026-04-01 22:20:46	894	1	CONTRACT_DEBT_HOLD	2026-04-29 21:46:52.946685
852	9	201964410438	201090000003	2026-04-18 04:58:46	923	1	NO_CONTRACT_FOUND	2026-04-29 21:46:52.946685
853	9	201640950043	201090000002	2026-04-08 10:22:46	1	3	CONTRACT_DEBT_HOLD	2026-04-29 21:46:52.946685
854	9	201795118881	201090000002	2026-04-02 04:25:46	1	3	CONTRACT_DEBT_HOLD	2026-04-29 21:46:52.946685
855	9	201430418861	whatsapp.net	2026-04-13 16:24:46	1	2	CONTRACT_DEBT_HOLD	2026-04-29 21:46:52.946685
856	9	201913664205	201090000002	2026-04-29 15:43:46	1892	1	NO_CONTRACT_FOUND	2026-04-29 21:46:52.946685
857	9	201933498428	201090000002	2026-04-26 04:21:46	3453	1	CONTRACT_ADMIN_HOLD	2026-04-29 21:46:52.946685
858	9	201933498428	201090000002	2026-04-20 21:27:46	2307	1	CONTRACT_ADMIN_HOLD	2026-04-29 21:46:52.946685
859	9	201936480554	201090000002	2026-04-11 14:19:46	1118	1	NO_CONTRACT_FOUND	2026-04-29 21:46:52.946685
860	9	201931499262	201000000008	2026-04-23 06:53:46	3457	1	CONTRACT_ADMIN_HOLD	2026-04-29 21:46:52.946685
861	9	201418928906	201090000002	2026-04-23 14:18:46	1	3	CONTRACT_ADMIN_HOLD	2026-04-29 21:46:52.946685
862	9	201908458100	201090000001	2026-04-13 04:22:46	2540	1	CONTRACT_TERMINATED	2026-04-29 21:46:52.946685
863	9	201935340135	201000000008	2026-04-04 01:17:46	1	3	NO_CONTRACT_FOUND	2026-04-29 21:46:52.946685
864	9	201979462605	201090000001	2026-04-18 17:39:46	1	3	NO_CONTRACT_FOUND	2026-04-29 21:46:52.946685
865	9	201948565403	201090000001	2026-04-06 10:36:46	3514	1	NO_CONTRACT_FOUND	2026-04-29 21:46:52.946685
866	1	201222156953	201223344556	2026-04-16 07:48:08	1	7	CONTRACT_ADMIN_HOLD	2026-04-30 01:17:26.868332
867	1	201795118881	201000000008	2026-04-06 06:52:08	1	3	CONTRACT_DEBT_HOLD	2026-04-30 01:17:28.993663
868	1	201280350684	201000000008	2026-04-12 17:37:08	3365	1	CONTRACT_DEBT_HOLD	2026-04-30 01:17:33.339803
869	1	201207540095	201090000002	2026-03-31 08:47:08	1	7	CONTRACT_ADMIN_HOLD	2026-04-30 01:17:37.231542
870	1	201672879810	youtube.com	2026-04-02 22:07:08	24697827	2	CONTRACT_DEBT_HOLD	2026-04-30 01:17:43.248064
871	1	201960106287	201223344556	2026-04-07 00:13:08	1	3	NO_CONTRACT_FOUND	2026-04-30 01:17:44.115008
872	1	201443034851	201090000003	2026-03-31 07:32:08	1	3	CONTRACT_ADMIN_HOLD	2026-04-30 01:17:48.468954
873	1	201938650036	201090000001	2026-04-10 19:43:08	4444	1	NO_CONTRACT_FOUND	2026-04-30 01:17:51.895463
874	10	201187441626	201090000002	2026-04-21 14:29:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
875	10	201554543248	201090000001	2026-04-11 06:35:42	3226	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
876	10	201294741054	201000000008	2026-04-24 23:16:42	1682	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
877	10	201929443681	201090000002	2026-04-16 04:51:42	1126	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
878	10	201960970378	facebook.com	2026-04-16 23:50:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
879	10	201254131544	whatsapp.net	2026-03-30 09:07:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
880	10	201989105436	201090000002	2026-03-30 17:24:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
881	10	201653069004	201090000003	2026-04-01 17:38:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
882	10	201949415036	facebook.com	2026-04-17 15:25:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
883	10	201255851063	201000000008	2026-03-31 19:14:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
884	10	201987939852	201090000003	2026-04-18 12:50:42	2544	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
885	10	201255516201	201090000002	2026-04-22 02:08:42	214	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
886	10	201192472707	google.com	2026-04-09 02:19:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
887	10	201935743165	youtube.com	2026-04-01 04:12:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
888	10	201243897854	201223344556	2026-04-22 10:32:42	714	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
889	10	201358767975	201000000008	2026-04-05 08:51:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
890	10	201582165582	201223344556	2026-04-02 05:24:42	3295	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
891	10	201804307139	youtube.com	2026-04-07 05:33:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
892	10	201804307139	201000000008	2026-04-16 13:10:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
893	10	201462924192	201090000002	2026-04-24 16:58:42	2748	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
894	10	201419739858	201090000002	2026-04-01 03:00:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
895	10	201200072017	facebook.com	2026-04-17 22:14:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
896	10	201971560057	201090000001	2026-04-14 11:26:42	978	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
897	10	201929443681	whatsapp.net	2026-04-19 21:58:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
898	10	201473293348	201223344556	2026-04-05 10:57:42	993	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
899	10	201766068173	201090000003	2026-04-28 02:48:42	1356	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
900	10	201113312729	201223344556	2026-04-24 01:53:42	1702	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
901	10	201135432749	201000000008	2026-04-05 01:46:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
902	10	201100488135	201000000008	2026-04-08 16:38:42	386	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
903	10	201779264035	201223344556	2026-04-19 08:58:42	3546	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
904	10	201402249115	google.com	2026-04-15 05:59:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
905	10	201623681391	201090000001	2026-04-20 17:59:42	300	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
906	10	201720066465	201223344556	2026-04-17 07:41:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
907	10	201671270881	201090000001	2026-04-29 05:52:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
908	10	201489016716	google.com	2026-04-10 10:58:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
909	10	201449404580	fmrz-telecom.net	2026-04-21 16:55:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
910	10	201949566929	google.com	2026-03-30 07:56:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
911	10	201198229833	201090000003	2026-04-07 03:18:42	1958	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
912	10	201599166808	201090000001	2026-04-20 07:35:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
913	10	201284293396	fmrz-telecom.net	2026-04-23 21:21:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
914	10	201186352421	fmrz-telecom.net	2026-04-07 14:37:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
915	10	201921537400	fmrz-telecom.net	2026-04-28 09:45:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
916	10	201659605961	201223344556	2026-04-09 10:13:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
917	10	201511060475	201223344556	2026-04-26 20:58:42	411	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
918	10	201455334792	whatsapp.net	2026-04-13 20:17:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
919	10	201473293348	fmrz-telecom.net	2026-04-19 11:10:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
920	10	201777712118	201090000002	2026-04-03 20:33:42	1548	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
921	10	201274207034	201223344556	2026-04-08 05:53:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
922	10	201758547932	201223344556	2026-04-09 03:38:42	429	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
923	10	201684075608	201223344556	2026-04-23 01:40:42	2685	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
924	10	201453534222	facebook.com	2026-04-05 16:12:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
925	10	201988892685	201090000001	2026-03-30 00:34:42	2185	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
926	10	201766068173	201223344556	2026-04-14 12:16:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
927	10	201942725017	201090000001	2026-04-08 22:07:42	2393	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
928	10	201509717260	whatsapp.net	2026-04-02 23:56:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
929	10	201570066932	201000000008	2026-04-12 08:56:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
930	10	201115133298	fmrz-telecom.net	2026-04-12 00:58:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
931	10	201211097847	youtube.com	2026-04-18 21:41:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
932	10	201470237935	201223344556	2026-04-26 17:07:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
933	10	201926931465	201090000002	2026-04-11 00:49:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
934	10	201329180329	201090000003	2026-04-12 18:39:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
935	10	201141678272	201090000003	2026-03-30 17:28:42	1274	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
936	10	201804307139	fmrz-telecom.net	2026-04-27 12:45:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
937	10	201502613870	youtube.com	2026-04-19 13:49:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
938	10	201148309599	201000000008	2026-04-11 04:13:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
939	10	201959327703	facebook.com	2026-04-24 20:23:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
940	10	201767489862	201223344556	2026-04-16 18:13:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
941	10	201449404580	201090000003	2026-04-28 10:37:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
942	10	201998039083	201223344556	2026-04-10 09:14:42	3461	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
943	10	201671270881	201000000008	2026-04-09 19:59:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
944	10	201284293396	201090000003	2026-04-10 11:11:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
945	10	201921537400	201090000002	2026-04-11 14:32:42	1899	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
946	10	201691281998	201090000002	2026-04-25 23:06:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
947	10	201198229833	201000000008	2026-04-22 00:09:42	2520	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
948	10	201309518429	201090000002	2026-04-27 12:02:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
949	10	201284293396	201090000001	2026-04-26 13:08:42	2336	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
950	10	201624427143	google.com	2026-04-15 18:58:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
951	10	201309518429	facebook.com	2026-04-02 07:04:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
952	10	201599166808	201090000002	2026-04-18 05:47:42	1709	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
953	10	201766068173	fmrz-telecom.net	2026-04-17 00:31:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
954	10	201758547932	201000000008	2026-04-24 01:54:42	3568	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
955	10	201367791331	201090000001	2026-04-27 13:49:42	2148	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
956	10	201243897854	201223344556	2026-04-18 09:27:42	274	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
957	10	201652299436	201090000001	2026-04-07 03:21:42	3342	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
958	10	201489051711	google.com	2026-04-04 22:40:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
959	10	201985690407	facebook.com	2026-04-04 20:04:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
960	10	201828688191	201090000001	2026-04-24 00:24:42	1159	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
961	10	201286932142	201000000008	2026-04-23 12:21:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
962	10	201570066932	whatsapp.net	2026-04-13 05:56:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
963	10	201189986095	youtube.com	2026-04-24 01:30:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
964	10	201582165582	201223344556	2026-04-17 10:38:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
965	10	201570066932	youtube.com	2026-04-14 14:48:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
966	10	201398740844	fmrz-telecom.net	2026-04-29 07:39:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
967	10	201720066465	201223344556	2026-04-03 06:24:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
968	10	201274207034	201223344556	2026-04-29 06:26:42	84	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
969	10	201123905982	201090000002	2026-04-22 19:21:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
970	10	201903689006	youtube.com	2026-04-06 02:03:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
971	10	201599166808	201090000001	2026-04-14 21:22:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
972	10	201868108276	201090000001	2026-04-20 11:48:42	1266	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
973	10	201471555986	201223344556	2026-04-24 07:16:42	491	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
974	10	201284293396	201090000003	2026-04-24 15:02:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
975	10	201929443681	facebook.com	2026-04-09 06:27:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
976	10	201254131544	201090000003	2026-04-10 17:00:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
977	10	201926548886	201223344556	2026-04-06 20:56:42	3123	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
978	10	201924975793	201090000003	2026-04-29 17:49:42	3175	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
979	10	201443434524	fmrz-telecom.net	2026-04-06 12:41:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
980	10	201385628459	201090000003	2026-04-23 06:23:42	2542	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
981	10	201189986095	201090000001	2026-04-25 11:28:42	955	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
982	10	201437218906	whatsapp.net	2026-04-28 05:42:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
983	10	201563988655	fmrz-telecom.net	2026-04-13 07:50:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
984	10	201420871936	youtube.com	2026-04-08 01:14:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
985	10	201133087012	201223344556	2026-04-25 09:12:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
986	10	201563988655	google.com	2026-04-29 12:41:42	1	2	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
987	10	201544098306	201090000001	2026-04-06 21:34:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
988	10	201733342762	201223344556	2026-04-18 02:18:42	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
989	10	201828688191	201090000003	2026-04-29 00:17:42	836	1	NO_CONTRACT_FOUND	2026-04-30 01:58:03.213038
990	11	201222156953	201223344556	2026-04-16 07:48:08	1	7	CONTRACT_ADMIN_HOLD	2026-04-30 01:58:12.41828
991	11	201795118881	201000000008	2026-04-06 06:52:08	1	3	CONTRACT_DEBT_HOLD	2026-04-30 01:58:12.41828
992	11	201280350684	201000000008	2026-04-12 17:37:08	3365	1	CONTRACT_DEBT_HOLD	2026-04-30 01:58:12.41828
993	11	201207540095	201090000002	2026-03-31 08:47:08	1	7	CONTRACT_ADMIN_HOLD	2026-04-30 01:58:12.41828
994	11	201672879810	youtube.com	2026-04-02 22:07:08	24	2	CONTRACT_DEBT_HOLD	2026-04-30 01:58:12.41828
995	11	201960106287	201223344556	2026-04-07 00:13:08	1	3	NO_CONTRACT_FOUND	2026-04-30 01:58:12.41828
996	11	201443034851	201090000003	2026-03-31 07:32:08	1	3	CONTRACT_ADMIN_HOLD	2026-04-30 01:58:12.41828
997	11	201938650036	201090000001	2026-04-10 19:43:08	4444	1	NO_CONTRACT_FOUND	2026-04-30 01:58:12.41828
998	13	201187441626	201090000002	2026-04-21 14:29:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
999	13	201554543248	201090000001	2026-04-11 06:35:42	3226	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1000	13	201294741054	201000000008	2026-04-24 23:16:42	1682	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1001	13	201929443681	201090000002	2026-04-16 04:51:42	1126	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1002	13	201960970378	facebook.com	2026-04-16 23:50:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1003	13	201254131544	whatsapp.net	2026-03-30 09:07:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1004	13	201989105436	201090000002	2026-03-30 17:24:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1005	13	201653069004	201090000003	2026-04-01 17:38:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1006	13	201949415036	facebook.com	2026-04-17 15:25:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1007	13	201255851063	201000000008	2026-03-31 19:14:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1008	13	201987939852	201090000003	2026-04-18 12:50:42	2544	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1009	13	201255516201	201090000002	2026-04-22 02:08:42	214	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1010	13	201192472707	google.com	2026-04-09 02:19:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1011	13	201935743165	youtube.com	2026-04-01 04:12:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1012	13	201243897854	201223344556	2026-04-22 10:32:42	714	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1013	13	201358767975	201000000008	2026-04-05 08:51:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1014	13	201582165582	201223344556	2026-04-02 05:24:42	3295	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1015	13	201804307139	youtube.com	2026-04-07 05:33:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1016	13	201804307139	201000000008	2026-04-16 13:10:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1017	13	201462924192	201090000002	2026-04-24 16:58:42	2748	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1018	13	201419739858	201090000002	2026-04-01 03:00:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1019	13	201200072017	facebook.com	2026-04-17 22:14:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1020	13	201971560057	201090000001	2026-04-14 11:26:42	978	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1021	13	201929443681	whatsapp.net	2026-04-19 21:58:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1022	13	201473293348	201223344556	2026-04-05 10:57:42	993	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1023	13	201766068173	201090000003	2026-04-28 02:48:42	1356	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1024	13	201113312729	201223344556	2026-04-24 01:53:42	1702	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1025	13	201135432749	201000000008	2026-04-05 01:46:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1026	13	201100488135	201000000008	2026-04-08 16:38:42	386	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1027	13	201779264035	201223344556	2026-04-19 08:58:42	3546	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1028	13	201402249115	google.com	2026-04-15 05:59:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1029	13	201623681391	201090000001	2026-04-20 17:59:42	300	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1030	13	201720066465	201223344556	2026-04-17 07:41:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1031	13	201671270881	201090000001	2026-04-29 05:52:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1032	13	201489016716	google.com	2026-04-10 10:58:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1033	13	201449404580	fmrz-telecom.net	2026-04-21 16:55:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1034	13	201949566929	google.com	2026-03-30 07:56:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1035	13	201198229833	201090000003	2026-04-07 03:18:42	1958	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1036	13	201599166808	201090000001	2026-04-20 07:35:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1037	13	201284293396	fmrz-telecom.net	2026-04-23 21:21:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1038	13	201186352421	fmrz-telecom.net	2026-04-07 14:37:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1039	13	201921537400	fmrz-telecom.net	2026-04-28 09:45:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1040	13	201659605961	201223344556	2026-04-09 10:13:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1041	13	201511060475	201223344556	2026-04-26 20:58:42	411	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1042	13	201455334792	whatsapp.net	2026-04-13 20:17:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1043	13	201473293348	fmrz-telecom.net	2026-04-19 11:10:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1044	13	201777712118	201090000002	2026-04-03 20:33:42	1548	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1045	13	201274207034	201223344556	2026-04-08 05:53:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1046	13	201758547932	201223344556	2026-04-09 03:38:42	429	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1047	13	201684075608	201223344556	2026-04-23 01:40:42	2685	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1048	13	201453534222	facebook.com	2026-04-05 16:12:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1049	13	201988892685	201090000001	2026-03-30 00:34:42	2185	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1050	13	201766068173	201223344556	2026-04-14 12:16:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1051	13	201942725017	201090000001	2026-04-08 22:07:42	2393	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1052	13	201509717260	whatsapp.net	2026-04-02 23:56:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1053	13	201570066932	201000000008	2026-04-12 08:56:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1054	13	201115133298	fmrz-telecom.net	2026-04-12 00:58:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1055	13	201211097847	youtube.com	2026-04-18 21:41:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1056	13	201470237935	201223344556	2026-04-26 17:07:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1057	13	201926931465	201090000002	2026-04-11 00:49:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1058	13	201329180329	201090000003	2026-04-12 18:39:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1059	13	201141678272	201090000003	2026-03-30 17:28:42	1274	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1060	13	201804307139	fmrz-telecom.net	2026-04-27 12:45:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1061	13	201502613870	youtube.com	2026-04-19 13:49:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1062	13	201148309599	201000000008	2026-04-11 04:13:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1063	13	201959327703	facebook.com	2026-04-24 20:23:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1064	13	201767489862	201223344556	2026-04-16 18:13:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1065	13	201449404580	201090000003	2026-04-28 10:37:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1066	13	201998039083	201223344556	2026-04-10 09:14:42	3461	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1067	13	201671270881	201000000008	2026-04-09 19:59:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1068	13	201284293396	201090000003	2026-04-10 11:11:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1069	13	201921537400	201090000002	2026-04-11 14:32:42	1899	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1070	13	201691281998	201090000002	2026-04-25 23:06:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1071	13	201198229833	201000000008	2026-04-22 00:09:42	2520	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1072	13	201309518429	201090000002	2026-04-27 12:02:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1073	13	201284293396	201090000001	2026-04-26 13:08:42	2336	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1074	13	201624427143	google.com	2026-04-15 18:58:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1075	13	201309518429	facebook.com	2026-04-02 07:04:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1076	13	201599166808	201090000002	2026-04-18 05:47:42	1709	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1077	13	201766068173	fmrz-telecom.net	2026-04-17 00:31:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1078	13	201758547932	201000000008	2026-04-24 01:54:42	3568	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1079	13	201367791331	201090000001	2026-04-27 13:49:42	2148	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1080	13	201243897854	201223344556	2026-04-18 09:27:42	274	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1081	13	201652299436	201090000001	2026-04-07 03:21:42	3342	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1082	13	201489051711	google.com	2026-04-04 22:40:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1083	13	201985690407	facebook.com	2026-04-04 20:04:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1084	13	201828688191	201090000001	2026-04-24 00:24:42	1159	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1085	13	201286932142	201000000008	2026-04-23 12:21:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1086	13	201570066932	whatsapp.net	2026-04-13 05:56:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1087	13	201189986095	youtube.com	2026-04-24 01:30:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1088	13	201582165582	201223344556	2026-04-17 10:38:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1089	13	201570066932	youtube.com	2026-04-14 14:48:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1090	13	201398740844	fmrz-telecom.net	2026-04-29 07:39:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1091	13	201720066465	201223344556	2026-04-03 06:24:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1092	13	201274207034	201223344556	2026-04-29 06:26:42	84	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1093	13	201123905982	201090000002	2026-04-22 19:21:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1094	13	201903689006	youtube.com	2026-04-06 02:03:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1095	13	201599166808	201090000001	2026-04-14 21:22:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1096	13	201868108276	201090000001	2026-04-20 11:48:42	1266	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1097	13	201471555986	201223344556	2026-04-24 07:16:42	491	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1098	13	201284293396	201090000003	2026-04-24 15:02:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1099	13	201929443681	facebook.com	2026-04-09 06:27:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1100	13	201254131544	201090000003	2026-04-10 17:00:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1101	13	201926548886	201223344556	2026-04-06 20:56:42	3123	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1102	13	201924975793	201090000003	2026-04-29 17:49:42	3175	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1103	13	201443434524	fmrz-telecom.net	2026-04-06 12:41:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1104	13	201385628459	201090000003	2026-04-23 06:23:42	2542	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1105	13	201189986095	201090000001	2026-04-25 11:28:42	955	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1106	13	201437218906	whatsapp.net	2026-04-28 05:42:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1107	13	201563988655	fmrz-telecom.net	2026-04-13 07:50:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1108	13	201420871936	youtube.com	2026-04-08 01:14:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1109	13	201133087012	201223344556	2026-04-25 09:12:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1110	13	201563988655	google.com	2026-04-29 12:41:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1111	13	201544098306	201090000001	2026-04-06 21:34:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1112	13	201733342762	201223344556	2026-04-18 02:18:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1113	13	201828688191	201090000003	2026-04-29 00:17:42	836	1	NO_CONTRACT_FOUND	2026-04-30 02:17:23.087012
1114	14	201222156953	201223344556	2026-04-16 07:48:08	1	7	CONTRACT_ADMIN_HOLD	2026-04-30 02:17:32.225279
1115	14	201795118881	201000000008	2026-04-06 06:52:08	1	3	CONTRACT_DEBT_HOLD	2026-04-30 02:17:32.225279
1116	14	201280350684	201000000008	2026-04-12 17:37:08	3365	1	CONTRACT_DEBT_HOLD	2026-04-30 02:17:32.225279
1117	14	201207540095	201090000002	2026-03-31 08:47:08	1	7	CONTRACT_ADMIN_HOLD	2026-04-30 02:17:32.225279
1118	14	201672879810	youtube.com	2026-04-02 22:07:08	24	2	CONTRACT_DEBT_HOLD	2026-04-30 02:17:32.225279
1119	14	201960106287	201223344556	2026-04-07 00:13:08	1	3	NO_CONTRACT_FOUND	2026-04-30 02:17:32.225279
1120	14	201443034851	201090000003	2026-03-31 07:32:08	1	3	CONTRACT_ADMIN_HOLD	2026-04-30 02:17:32.225279
1121	14	201938650036	201090000001	2026-04-10 19:43:08	4444	1	NO_CONTRACT_FOUND	2026-04-30 02:17:32.225279
1122	16	201187441626	201090000002	2026-04-21 14:29:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1123	16	201554543248	201090000001	2026-04-11 06:35:42	3226	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1124	16	201294741054	201000000008	2026-04-24 23:16:42	1682	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1125	16	201929443681	201090000002	2026-04-16 04:51:42	1126	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1126	16	201960970378	facebook.com	2026-04-16 23:50:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1127	16	201254131544	whatsapp.net	2026-03-30 09:07:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1128	16	201989105436	201090000002	2026-03-30 17:24:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1129	16	201653069004	201090000003	2026-04-01 17:38:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1130	16	201949415036	facebook.com	2026-04-17 15:25:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1131	16	201255851063	201000000008	2026-03-31 19:14:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1132	16	201987939852	201090000003	2026-04-18 12:50:42	2544	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1133	16	201255516201	201090000002	2026-04-22 02:08:42	214	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1134	16	201192472707	google.com	2026-04-09 02:19:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1135	16	201935743165	youtube.com	2026-04-01 04:12:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1136	16	201243897854	201223344556	2026-04-22 10:32:42	714	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1137	16	201358767975	201000000008	2026-04-05 08:51:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1138	16	201582165582	201223344556	2026-04-02 05:24:42	3295	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1139	16	201804307139	youtube.com	2026-04-07 05:33:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1140	16	201804307139	201000000008	2026-04-16 13:10:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1141	16	201462924192	201090000002	2026-04-24 16:58:42	2748	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1142	16	201419739858	201090000002	2026-04-01 03:00:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1143	16	201200072017	facebook.com	2026-04-17 22:14:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1144	16	201971560057	201090000001	2026-04-14 11:26:42	978	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1145	16	201929443681	whatsapp.net	2026-04-19 21:58:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1146	16	201473293348	201223344556	2026-04-05 10:57:42	993	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1147	16	201766068173	201090000003	2026-04-28 02:48:42	1356	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1148	16	201113312729	201223344556	2026-04-24 01:53:42	1702	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1149	16	201135432749	201000000008	2026-04-05 01:46:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1150	16	201100488135	201000000008	2026-04-08 16:38:42	386	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1151	16	201779264035	201223344556	2026-04-19 08:58:42	3546	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1152	16	201402249115	google.com	2026-04-15 05:59:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1153	16	201623681391	201090000001	2026-04-20 17:59:42	300	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1154	16	201720066465	201223344556	2026-04-17 07:41:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1155	16	201671270881	201090000001	2026-04-29 05:52:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1156	16	201489016716	google.com	2026-04-10 10:58:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1157	16	201449404580	fmrz-telecom.net	2026-04-21 16:55:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1158	16	201949566929	google.com	2026-03-30 07:56:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1159	16	201198229833	201090000003	2026-04-07 03:18:42	1958	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1160	16	201599166808	201090000001	2026-04-20 07:35:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1161	16	201284293396	fmrz-telecom.net	2026-04-23 21:21:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1162	16	201186352421	fmrz-telecom.net	2026-04-07 14:37:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1163	16	201921537400	fmrz-telecom.net	2026-04-28 09:45:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1164	16	201659605961	201223344556	2026-04-09 10:13:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1165	16	201511060475	201223344556	2026-04-26 20:58:42	411	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1166	16	201455334792	whatsapp.net	2026-04-13 20:17:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1167	16	201473293348	fmrz-telecom.net	2026-04-19 11:10:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1168	16	201777712118	201090000002	2026-04-03 20:33:42	1548	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1169	16	201274207034	201223344556	2026-04-08 05:53:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1170	16	201758547932	201223344556	2026-04-09 03:38:42	429	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1171	16	201684075608	201223344556	2026-04-23 01:40:42	2685	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1172	16	201453534222	facebook.com	2026-04-05 16:12:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1173	16	201988892685	201090000001	2026-03-30 00:34:42	2185	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1174	16	201766068173	201223344556	2026-04-14 12:16:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1175	16	201942725017	201090000001	2026-04-08 22:07:42	2393	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1176	16	201509717260	whatsapp.net	2026-04-02 23:56:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1177	16	201570066932	201000000008	2026-04-12 08:56:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1178	16	201115133298	fmrz-telecom.net	2026-04-12 00:58:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1179	16	201211097847	youtube.com	2026-04-18 21:41:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1180	16	201470237935	201223344556	2026-04-26 17:07:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1181	16	201926931465	201090000002	2026-04-11 00:49:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1182	16	201329180329	201090000003	2026-04-12 18:39:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1183	16	201141678272	201090000003	2026-03-30 17:28:42	1274	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1184	16	201804307139	fmrz-telecom.net	2026-04-27 12:45:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1185	16	201502613870	youtube.com	2026-04-19 13:49:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1186	16	201148309599	201000000008	2026-04-11 04:13:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1187	16	201959327703	facebook.com	2026-04-24 20:23:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1188	16	201767489862	201223344556	2026-04-16 18:13:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1189	16	201449404580	201090000003	2026-04-28 10:37:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1190	16	201998039083	201223344556	2026-04-10 09:14:42	3461	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1191	16	201671270881	201000000008	2026-04-09 19:59:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1192	16	201284293396	201090000003	2026-04-10 11:11:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1193	16	201921537400	201090000002	2026-04-11 14:32:42	1899	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1194	16	201691281998	201090000002	2026-04-25 23:06:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1195	16	201198229833	201000000008	2026-04-22 00:09:42	2520	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1196	16	201309518429	201090000002	2026-04-27 12:02:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1197	16	201284293396	201090000001	2026-04-26 13:08:42	2336	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1198	16	201624427143	google.com	2026-04-15 18:58:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1199	16	201309518429	facebook.com	2026-04-02 07:04:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1200	16	201599166808	201090000002	2026-04-18 05:47:42	1709	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1201	16	201766068173	fmrz-telecom.net	2026-04-17 00:31:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1202	16	201758547932	201000000008	2026-04-24 01:54:42	3568	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1203	16	201367791331	201090000001	2026-04-27 13:49:42	2148	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1204	16	201243897854	201223344556	2026-04-18 09:27:42	274	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1205	16	201652299436	201090000001	2026-04-07 03:21:42	3342	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1206	16	201489051711	google.com	2026-04-04 22:40:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1207	16	201985690407	facebook.com	2026-04-04 20:04:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1208	16	201828688191	201090000001	2026-04-24 00:24:42	1159	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1209	16	201286932142	201000000008	2026-04-23 12:21:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1210	16	201570066932	whatsapp.net	2026-04-13 05:56:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1211	16	201189986095	youtube.com	2026-04-24 01:30:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1212	16	201582165582	201223344556	2026-04-17 10:38:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1213	16	201570066932	youtube.com	2026-04-14 14:48:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1214	16	201398740844	fmrz-telecom.net	2026-04-29 07:39:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1215	16	201720066465	201223344556	2026-04-03 06:24:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1216	16	201274207034	201223344556	2026-04-29 06:26:42	84	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1217	16	201123905982	201090000002	2026-04-22 19:21:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1218	16	201903689006	youtube.com	2026-04-06 02:03:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1219	16	201599166808	201090000001	2026-04-14 21:22:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1220	16	201868108276	201090000001	2026-04-20 11:48:42	1266	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1221	16	201471555986	201223344556	2026-04-24 07:16:42	491	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1222	16	201284293396	201090000003	2026-04-24 15:02:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1223	16	201929443681	facebook.com	2026-04-09 06:27:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1224	16	201254131544	201090000003	2026-04-10 17:00:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1225	16	201926548886	201223344556	2026-04-06 20:56:42	3123	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1226	16	201924975793	201090000003	2026-04-29 17:49:42	3175	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1227	16	201443434524	fmrz-telecom.net	2026-04-06 12:41:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1228	16	201385628459	201090000003	2026-04-23 06:23:42	2542	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1229	16	201189986095	201090000001	2026-04-25 11:28:42	955	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1230	16	201437218906	whatsapp.net	2026-04-28 05:42:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1231	16	201563988655	fmrz-telecom.net	2026-04-13 07:50:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1232	16	201420871936	youtube.com	2026-04-08 01:14:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1233	16	201133087012	201223344556	2026-04-25 09:12:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1234	16	201563988655	google.com	2026-04-29 12:41:42	1	2	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1235	16	201544098306	201090000001	2026-04-06 21:34:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1236	16	201733342762	201223344556	2026-04-18 02:18:42	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1237	16	201828688191	201090000003	2026-04-29 00:17:42	836	1	NO_CONTRACT_FOUND	2026-04-30 02:22:41.739446
1238	17	201222156953	201223344556	2026-04-16 07:48:08	1	7	CONTRACT_ADMIN_HOLD	2026-04-30 02:22:42.274027
1239	17	201795118881	201000000008	2026-04-06 06:52:08	1	3	CONTRACT_DEBT_HOLD	2026-04-30 02:22:42.274027
1240	17	201280350684	201000000008	2026-04-12 17:37:08	3365	1	CONTRACT_DEBT_HOLD	2026-04-30 02:22:42.274027
1241	17	201207540095	201090000002	2026-03-31 08:47:08	1	7	CONTRACT_ADMIN_HOLD	2026-04-30 02:22:42.274027
1242	17	201672879810	youtube.com	2026-04-02 22:07:08	24	2	CONTRACT_DEBT_HOLD	2026-04-30 02:22:42.274027
1243	17	201960106287	201223344556	2026-04-07 00:13:08	1	3	NO_CONTRACT_FOUND	2026-04-30 02:22:42.274027
1244	17	201443034851	201090000003	2026-03-31 07:32:08	1	3	CONTRACT_ADMIN_HOLD	2026-04-30 02:22:42.274027
1245	17	201938650036	201090000001	2026-04-10 19:43:08	4444	1	NO_CONTRACT_FOUND	2026-04-30 02:22:42.274027
1246	19	201923993369	201090000003	2026-04-10 00:18:33	543	1	NO_CONTRACT_FOUND	2026-04-30 11:30:40.489661
1247	19	201942415512	201000000008	2026-04-11 11:41:33	1	3	NO_CONTRACT_FOUND	2026-04-30 11:30:40.489661
1248	19	201995588849	facebook.com	2026-04-14 07:32:33	1	2	NO_CONTRACT_FOUND	2026-04-30 11:30:40.489661
1249	19	201924841825	201090000002	2026-04-19 08:12:33	3130	1	NO_CONTRACT_FOUND	2026-04-30 11:30:40.489661
1250	19	201931499262	201090000002	2026-04-06 07:50:33	1	3	CONTRACT_ADMIN_HOLD	2026-04-30 11:30:40.489661
1251	19	201961861086	youtube.com	2026-04-08 20:44:33	1	2	NO_CONTRACT_FOUND	2026-04-30 11:30:40.489661
1252	19	201640950043	201090000001	2026-04-28 07:47:33	1	3	CONTRACT_DEBT_HOLD	2026-04-30 11:30:40.489661
1253	19	201821214312	201223344556	2026-04-28 23:43:33	643	1	CONTRACT_ADMIN_HOLD	2026-04-30 11:30:40.489661
1254	19	201907682029	whatsapp.net	2026-04-04 13:31:33	1	2	CONTRACT_ADMIN_HOLD	2026-04-30 11:30:40.489661
1255	19	201883670030	facebook.com	2026-04-29 16:43:33	1	2	CONTRACT_ADMIN_HOLD	2026-04-30 11:30:40.489661
1256	19	201403027881	201090000002	2026-04-29 17:22:33	1	3	CONTRACT_ADMIN_HOLD	2026-04-30 11:30:40.489661
1257	19	201913798760	201090000002	2026-04-29 03:01:33	2206	1	NO_CONTRACT_FOUND	2026-04-30 11:30:40.489661
1258	19	201309264655	201000000008	2026-04-26 00:52:33	2846	1	CONTRACT_ADMIN_HOLD	2026-04-30 11:30:40.489661
1259	19	201000000013	201090000002	2026-04-15 02:20:33	1	3	CONTRACT_ADMIN_HOLD	2026-04-30 11:30:40.489661
1260	19	201212953273	whatsapp.net	2026-04-22 17:36:33	1	2	CONTRACT_DEBT_HOLD	2026-04-30 11:30:40.489661
1261	19	201923464159	fmrz-telecom.net	2026-04-25 10:07:33	1	2	NO_CONTRACT_FOUND	2026-04-30 11:30:40.489661
1262	19	201766366618	201090000001	2026-04-03 18:08:33	561	1	CONTRACT_ADMIN_HOLD	2026-04-30 11:30:40.489661
1263	19	201486851814	201223344556	2026-04-26 00:08:33	1	3	CONTRACT_ADMIN_HOLD	2026-04-30 11:30:40.489661
1264	19	201991371559	201000000008	2026-04-29 00:37:33	1	3	NO_CONTRACT_FOUND	2026-04-30 11:30:40.489661
1265	19	201932147399	201223344556	2026-04-23 15:06:33	1	3	NO_CONTRACT_FOUND	2026-04-30 11:30:40.489661
1266	19	201640950043	201223344556	2026-04-22 16:04:33	2285	1	CONTRACT_DEBT_HOLD	2026-04-30 11:30:40.489661
\.


--
-- Data for Name: ror_contract; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.ror_contract (contract_id, rateplan_id, starting_date, data, voice, sms, roaming_voice, roaming_data, roaming_sms, bill_id) FROM stdin;
6	2	2026-04-01	2855	40.00	4	0.00	0	0	\N
13	1	2026-04-01	0	0.00	0	0.00	0	0	\N
8	2	2026-04-01	1400	75.00	3	0.00	0	0	\N
18	1	2026-04-01	0	0.00	0	0.00	0	0	\N
201	4	2026-04-01	0	0.00	0	0.00	0	0	\N
81	3	2026-04-01	0	22.00	1	0.00	0	0	\N
89	1	2026-04-01	0	21.00	0	0.00	0	0	\N
190	1	2026-04-01	8	0.00	0	0.00	0	0	\N
119	1	2026-04-01	1	41.00	3	0.00	0	1	\N
108	3	2026-04-01	1	0.00	0	0.00	0	0	\N
68	1	2026-04-01	48392599	383.00	2	113.00	0	0	\N
194	1	2026-04-01	2	0.00	0	0.00	0	0	\N
152	2	2026-04-01	1	0.00	1	0.00	0	0	\N
24	3	2026-04-01	0	1.00	0	0.00	0	0	\N
192	1	2026-04-01	3	0.00	0	0.00	0	0	\N
117	3	2026-04-01	0	45.00	0	0.00	0	0	\N
188	1	2026-04-01	1	0.00	0	0.00	0	0	\N
1	1	2026-03-01	16106127360	7200.00	59	2700.00	2684354560	10	363
111	2	2026-04-01	0	55.00	1	0.00	0	0	\N
90	3	2026-04-01	1	0.00	1	0.00	0	0	\N
28	3	2026-04-01	0	0.00	1	0.00	0	0	\N
165	2	2026-04-01	1	16.00	1	0.00	0	0	\N
161	3	2026-04-01	1	0.00	0	0.00	0	0	\N
4	2	2026-04-01	2102	159.00	2	0.00	0	0	\N
174	1	2026-04-01	40393193	0.00	0	0.00	0	0	\N
98	3	2026-04-01	1	29.00	0	0.00	0	0	\N
174	1	2026-03-01	1	0.00	0	0.00	0	0	\N
31	3	2026-04-01	1	60.00	0	0.00	0	0	\N
114	3	2026-04-01	79	0.00	1	0.00	26442596	0	\N
183	1	2026-04-01	1	0.00	0	0.00	0	0	\N
58	2	2026-04-01	1	25.00	2	0.00	0	0	\N
139	2	2026-04-01	0	0.00	4	0.00	0	1	\N
86	1	2026-04-01	0	248.00	0	71.00	0	0	\N
200	3	2026-04-01	0	93.00	0	0.00	0	0	349
143	1	2026-04-01	49309675	44.00	0	0.00	0	0	\N
186	1	2026-04-01	105	0.00	0	0.00	36563003	0	\N
172	2	2026-04-01	12378914	0.00	0	0.00	0	0	\N
131	2	2026-04-01	2	49.00	5	0.00	0	0	\N
122	2	2026-04-01	0	32.00	0	0.00	0	0	\N
42	2	2026-04-01	18309319	38.00	0	0.00	0	0	\N
83	1	2026-04-01	0	368.00	2	102.00	0	0	\N
162	2	2026-04-01	26102722	365.00	1	0.00	0	0	\N
37	1	2026-04-01	2	0.00	1	0.00	0	0	\N
173	2	2026-04-01	0	0.00	0	0.00	42056315	0	\N
168	2	2026-04-01	0	0.00	2	0.00	0	0	\N
182	1	2026-04-01	17125695	0.00	0	0.00	0	0	\N
84	1	2026-04-01	48844253	0.00	0	0.00	0	0	\N
159	3	2026-04-01	0	41.00	5	0.00	0	0	\N
146	2	2026-04-01	0	43.00	1	0.00	0	0	\N
76	2	2026-04-01	1	0.00	1	0.00	0	0	\N
9	1	2026-04-01	0	214.00	3	0.00	0	0	\N
78	2	2026-04-01	0	184.00	0	0.00	0	0	\N
66	2	2026-04-01	1	41.00	1	0.00	0	0	\N
67	2	2026-04-01	0	9.00	0	0.00	0	0	\N
47	1	2026-04-01	1	54.00	0	0.00	0	0	\N
164	1	2026-04-01	0	15.00	5	0.00	0	0	\N
103	1	2026-04-01	2	104.00	0	0.00	0	0	\N
19	2	2026-04-01	1	104.00	0	0.00	0	0	\N
36	1	2026-04-01	1	0.00	0	0.00	0	0	\N
124	2	2026-04-01	1	0.00	4	0.00	0	0	\N
53	2	2026-04-01	1	50.00	0	0.00	0	0	\N
33	2	2026-04-01	0	83.00	0	0.00	0	0	\N
64	2	2026-04-01	0	43.00	4	0.00	0	1	\N
123	3	2026-04-01	0	30.00	0	0.00	0	0	\N
55	1	2026-04-01	0	64.00	3	0.00	0	0	\N
41	1	2026-04-01	1	58.00	1	0.00	0	0	\N
12	2	2026-04-01	49881140	11.00	1	0.00	0	0	\N
17	2	2026-04-01	1350	12.00	7	0.00	0	0	\N
130	2	2026-04-01	0	0.00	4	0.00	0	0	\N
31	3	2026-03-01	30415138	0.00	0	0.00	0	0	\N
196	2	2026-04-01	10540381	0.00	0	0.00	0	0	\N
165	2	2026-03-01	51820009	0.00	0	0.00	0	0	\N
11	1	2026-04-01	3	34.00	8	0.00	0	1	\N
149	2	2026-04-01	1	72.00	2	0.00	0	0	\N
46	3	2026-04-01	1	17.00	1	0.00	0	0	\N
127	2	2026-04-01	0	51.00	4	0.00	0	0	\N
51	1	2026-04-01	1	0.00	0	0.00	0	0	\N
175	1	2026-04-01	1	0.00	0	0.00	0	0	\N
94	3	2026-04-01	0	0.00	1	0.00	0	0	\N
10	2	2026-04-01	2467	67.00	3	0.00	22797287	0	\N
104	1	2026-04-01	1	50.00	3	0.00	0	0	\N
1	1	2026-04-01	5110062046	2576.00	99	485.00	2761487155	7	\N
14	2	2026-04-01	1351	313.00	8	0.00	0	0	\N
20	3	2026-04-01	28527861	218.00	0	69.00	0	0	\N
151	2	2026-04-01	3	0.00	4	0.00	0	1	\N
7	1	2026-04-01	1	21.00	7	0.00	0	0	\N
71	1	2026-04-01	32236010	168.00	2	0.00	0	0	\N
129	2	2026-04-01	0	0.00	2	0.00	0	0	\N
109	2	2026-04-01	4	358.00	3	0.00	0	0	\N
5	1	2026-04-01	1	245.00	3	0.00	0	0	\N
72	2	2026-04-01	1	69.00	1	0.00	0	0	\N
134	1	2026-04-01	2	0.00	0	0.00	0	0	\N
88	1	2026-04-01	35136219	423.00	2	106.00	0	0	\N
3	1	2026-04-01	1	110.00	4	0.00	0	0	\N
16	3	2026-04-01	4824	62.00	10	0.00	0	1	\N
128	3	2026-04-01	3	18.00	1	0.00	0	0	\N
25	1	2026-04-01	3	0.00	3	0.00	0	0	\N
95	2	2026-04-01	4	453.00	0	0.00	0	0	\N
137	2	2026-04-01	25	23.00	3	0.00	7378260	0	\N
27	1	2026-04-01	1	51.00	1	0.00	0	0	\N
56	2	2026-04-01	1	493.00	0	0.00	0	0	\N
96	3	2026-04-01	1	0.00	4	0.00	0	0	\N
116	2	2026-04-01	1	55.00	3	0.00	0	0	\N
32	2	2026-04-01	1	0.00	2	0.00	0	0	\N
60	1	2026-04-01	1	518.00	4	0.00	0	0	\N
57	2	2026-04-01	33586317	0.00	1	0.00	0	0	\N
136	1	2026-04-01	2	82.00	3	0.00	0	0	\N
22	2	2026-04-01	7744308	69.00	0	0.00	0	0	\N
92	3	2026-04-01	2	180.00	7	0.00	0	0	\N
97	3	2026-04-01	0	93.00	1	0.00	0	0	\N
15	3	2026-04-01	4505	104.00	11	4.00	400	1	\N
2	2	2026-03-01	53687115290	683.00	107	1000.00	22564060672	50	364
2	2	2026-04-01	9515140983	10540.00	196	472.00	2742418347	11	\N
\.


--
-- Data for Name: service_package; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.service_package (id, name, type, amount, priority, price, is_roaming, description) FROM stdin;
1	Voice Pack	voice	2000.0000	2	75.00	f	2000 local minutes per month
2	Data Pack	data	10000.0000	2	150.00	f	10GB data per month
3	SMS Pack	sms	500.0000	2	25.00	f	500 SMS per month
4	🎁 Welcome Gift	free_units	10000.0000	1	0.00	f	10GB free data for new customers
5	Roaming Voice Pack	voice	100.0000	2	250.00	t	100 roaming minutes
6	Roaming Data Pack	data	2000.0000	2	500.00	t	2GB roaming data
7	Roaming SMS Pack	sms	100.0000	2	100.00	t	100 roaming SMS
8	FouadSpecial	voice	100.0000	2	1.00	t	elm3lm fo2ad byda7yyyyyyyyyyyyyyyyy
\.


--
-- Data for Name: user_account; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.user_account (id, username, password, role, name, email, address, birthdate) FROM stdin;
203	abdulnaby	123456	customer	mohamed	mohamed@gmail.com	beni-suef	2002-07-23
205	yasser123	123456	customer	yasser fouad	fouadyasser20@gmail.com	Ismailia, Egypt, Cairo, 11511, Egypt	1555-02-02
1	admin	!Admin123!	admin	System Admin	admin@fmrz.com	HQ Cairo	1985-01-01
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
20	khaled_1_4164	123456	customer	Khaled Moussa	khaled_1_4164@fmrz-telecom.com	17 El-Nasr St, Alexandria	2006-02-18
21	mariam_2_8767	123456	customer	Mariam Gaber	mariam_2_8767@fmrz-telecom.com	14 Maadi St, Luxor	2011-01-22
22	ahmed_3_5251	123456	customer	Ahmed Ezzat	ahmed_3_5251@fmrz-telecom.com	35 Gameat El Dowal, Cairo	2007-12-16
23	salma_4_9250	123456	customer	Salma Fouad	salma_4_9250@fmrz-telecom.com	17 Zamalek Dr, Cairo	1970-02-04
24	fatma_5_9454	123456	customer	Fatma Moussa	fatma_5_9454@fmrz-telecom.com	85 Makram Ebeid, Luxor	1972-09-04
25	amir_6_4324	123456	customer	Amir Moussa	amir_6_4324@fmrz-telecom.com	34 Abbas El Akkad, Hurghada	1985-07-29
26	layla_7_4423	123456	customer	Layla Hamad	layla_7_4423@fmrz-telecom.com	85 Zamalek Dr, Mansoura	1978-04-16
27	omar_8_3486	123456	customer	Omar Ezzat	omar_8_3486@fmrz-telecom.com	73 El-Nasr St, Alexandria	2004-07-28
28	sara_9_5864	123456	customer	Sara Mansour	sara_9_5864@fmrz-telecom.com	23 Makram Ebeid, Mansoura	2002-07-05
29	hala_10_8972	123456	customer	Hala Soliman	hala_10_8972@fmrz-telecom.com	10 Gameat El Dowal, Aswan	1971-12-31
30	dina_11_6431	123456	customer	Dina Ezzat	dina_11_6431@fmrz-telecom.com	96 Maadi St, Mansoura	1999-11-28
31	nour_12_3631	123456	customer	Nour Ezzat	nour_12_3631@fmrz-telecom.com	70 Gameat El Dowal, Hurghada	2003-04-17
32	sara_13_2609	123456	customer	Sara Hamad	sara_13_2609@fmrz-telecom.com	75 Makram Ebeid, Hurghada	2005-03-19
33	mona_14_8731	123456	customer	Mona Gaber	mona_14_8731@fmrz-telecom.com	26 Cornish Rd, Cairo	1995-08-13
34	ziad_15_1123	123456	customer	Ziad Mansour	ziad_15_1123@fmrz-telecom.com	99 El-Nasr St, Mansoura	1995-12-24
35	hala_16_3171	123456	customer	Hala Soliman	hala_16_3171@fmrz-telecom.com	28 Makram Ebeid, Cairo	1976-10-25
36	hala_17_6684	123456	customer	Hala Said	hala_17_6684@fmrz-telecom.com	68 Gameat El Dowal, Giza	1982-08-17
37	amir_18_9675	123456	customer	Amir Wahba	amir_18_9675@fmrz-telecom.com	40 Maadi St, Aswan	1995-05-10
38	tarek_19_9441	123456	customer	Tarek Wahba	tarek_19_9441@fmrz-telecom.com	30 Makram Ebeid, Cairo	1990-04-19
39	hassan_20_3488	123456	customer	Hassan Ezzat	hassan_20_3488@fmrz-telecom.com	27 Cornish Rd, Giza	1975-08-03
40	mohamed_21_2388	123456	customer	Mohamed Wahba	mohamed_21_2388@fmrz-telecom.com	63 Gameat El Dowal, Hurghada	1997-06-24
41	hassan_22_2847	123456	customer	Hassan Gaber	hassan_22_2847@fmrz-telecom.com	83 Makram Ebeid, Cairo	1987-03-29
42	mona_23_2754	123456	customer	Mona Zaki	mona_23_2754@fmrz-telecom.com	48 Makram Ebeid, Giza	1999-08-21
43	salma_24_9737	123456	customer	Salma Hamad	salma_24_9737@fmrz-telecom.com	44 Gameat El Dowal, Cairo	2006-01-15
44	ibrahim_25_6895	123456	customer	Ibrahim Gaber	ibrahim_25_6895@fmrz-telecom.com	78 9th Street, Giza	2006-07-26
45	ahmed_26_2476	123456	customer	Ahmed Nasr	ahmed_26_2476@fmrz-telecom.com	43 Cornish Rd, Cairo	2008-06-08
46	ziad_27_2663	123456	customer	Ziad Moussa	ziad_27_2663@fmrz-telecom.com	15 Zamalek Dr, Hurghada	1975-07-08
47	mona_28_8932	123456	customer	Mona Nasr	mona_28_8932@fmrz-telecom.com	35 Tahrir Sq, Cairo	2007-05-12
48	layla_29_1562	123456	customer	Layla Zaki	layla_29_1562@fmrz-telecom.com	16 Maadi St, Suez	2010-10-18
49	youssef_30_6677	123456	customer	Youssef Nasr	youssef_30_6677@fmrz-telecom.com	79 Maadi St, Luxor	1995-03-25
50	omar_31_9254	123456	customer	Omar Moussa	omar_31_9254@fmrz-telecom.com	10 Maadi St, Giza	1982-01-29
51	nour_32_9418	123456	customer	Nour Hassan	nour_32_9418@fmrz-telecom.com	95 Abbas El Akkad, Luxor	1993-10-20
52	khaled_33_6223	123456	customer	Khaled Nasr	khaled_33_6223@fmrz-telecom.com	41 Makram Ebeid, Aswan	2008-10-17
53	layla_34_8069	123456	customer	Layla Mansour	layla_34_8069@fmrz-telecom.com	59 Zamalek Dr, Aswan	2002-07-13
54	mohamed_35_6924	123456	customer	Mohamed Khattab	mohamed_35_6924@fmrz-telecom.com	15 Gameat El Dowal, Giza	2000-05-10
55	omar_36_6011	123456	customer	Omar Said	omar_36_6011@fmrz-telecom.com	19 Maadi St, Luxor	1983-08-31
56	omar_37_2941	123456	customer	Omar Hamad	omar_37_2941@fmrz-telecom.com	28 El-Nasr St, Suez	2004-12-02
57	hala_38_8087	123456	customer	Hala Fouad	hala_38_8087@fmrz-telecom.com	37 9th Street, Alexandria	1984-05-08
58	ibrahim_39_3713	123456	customer	Ibrahim Hassan	ibrahim_39_3713@fmrz-telecom.com	88 9th Street, Cairo	1997-03-31
59	layla_40_3030	123456	customer	Layla Salem	layla_40_3030@fmrz-telecom.com	10 Cornish Rd, Mansoura	2002-08-24
60	khaled_41_2705	123456	customer	Khaled Soliman	khaled_41_2705@fmrz-telecom.com	27 Tahrir Sq, Suez	1970-12-09
61	nour_42_9895	123456	customer	Nour Said	nour_42_9895@fmrz-telecom.com	34 Zamalek Dr, Luxor	1999-11-09
62	layla_43_1499	123456	customer	Layla Gaber	layla_43_1499@fmrz-telecom.com	45 9th Street, Luxor	1975-09-10
63	omar_44_7432	123456	customer	Omar Fouad	omar_44_7432@fmrz-telecom.com	60 Makram Ebeid, Suez	1976-02-15
64	khaled_45_2930	123456	customer	Khaled Gaber	khaled_45_2930@fmrz-telecom.com	75 Abbas El Akkad, Hurghada	1971-08-31
65	ahmed_46_7561	123456	customer	Ahmed Moussa	ahmed_46_7561@fmrz-telecom.com	32 Gameat El Dowal, Alexandria	1978-06-03
66	omar_47_1494	123456	customer	Omar Badawi	omar_47_1494@fmrz-telecom.com	79 Maadi St, Giza	2010-09-16
67	mohamed_48_8853	123456	customer	Mohamed Gaber	mohamed_48_8853@fmrz-telecom.com	34 9th Street, Aswan	1995-01-05
68	fatma_49_1564	123456	customer	Fatma Gaber	fatma_49_1564@fmrz-telecom.com	36 El-Nasr St, Aswan	2001-10-22
69	nour_50_7443	123456	customer	Nour Salem	nour_50_7443@fmrz-telecom.com	19 9th Street, Aswan	2005-11-19
70	nour_51_1973	123456	customer	Nour Salem	nour_51_1973@fmrz-telecom.com	31 Cornish Rd, Hurghada	1996-06-26
71	mariam_52_5114	123456	customer	Mariam Zaki	mariam_52_5114@fmrz-telecom.com	11 Abbas El Akkad, Alexandria	1990-06-08
72	sara_53_6784	123456	customer	Sara Badawi	sara_53_6784@fmrz-telecom.com	76 Abbas El Akkad, Cairo	1999-09-04
73	hassan_54_3051	123456	customer	Hassan Moussa	hassan_54_3051@fmrz-telecom.com	80 Cornish Rd, Aswan	1991-10-14
74	fatma_55_4000	123456	customer	Fatma Said	fatma_55_4000@fmrz-telecom.com	30 Makram Ebeid, Hurghada	1997-06-06
75	sara_56_4124	123456	customer	Sara Gaber	sara_56_4124@fmrz-telecom.com	22 Zamalek Dr, Cairo	1996-08-22
76	mona_57_4934	123456	customer	Mona Nasr	mona_57_4934@fmrz-telecom.com	57 9th Street, Cairo	2001-10-23
77	fatma_58_7548	123456	customer	Fatma Mansour	fatma_58_7548@fmrz-telecom.com	66 Maadi St, Alexandria	1985-03-26
78	hassan_59_4171	123456	customer	Hassan Badawi	hassan_59_4171@fmrz-telecom.com	85 Abbas El Akkad, Aswan	1975-04-02
79	fatma_60_7700	123456	customer	Fatma Salem	fatma_60_7700@fmrz-telecom.com	48 El-Nasr St, Aswan	1980-02-10
80	ahmed_61_4602	123456	customer	Ahmed Zaki	ahmed_61_4602@fmrz-telecom.com	20 Maadi St, Giza	1994-02-09
81	dina_62_3589	123456	customer	Dina Moussa	dina_62_3589@fmrz-telecom.com	46 Makram Ebeid, Alexandria	2001-12-22
82	dina_63_9132	123456	customer	Dina Fouad	dina_63_9132@fmrz-telecom.com	69 Maadi St, Aswan	1972-09-28
83	nour_64_2472	123456	customer	Nour Ezzat	nour_64_2472@fmrz-telecom.com	10 Zamalek Dr, Suez	1974-02-24
84	khaled_65_9560	123456	customer	Khaled Nasr	khaled_65_9560@fmrz-telecom.com	80 Gameat El Dowal, Alexandria	1999-03-26
85	nour_66_5005	123456	customer	Nour Said	nour_66_5005@fmrz-telecom.com	45 9th Street, Giza	2007-09-23
86	layla_67_6155	123456	customer	Layla Khattab	layla_67_6155@fmrz-telecom.com	93 El-Nasr St, Mansoura	1985-05-18
87	sameh_68_6397	123456	customer	Sameh Hamad	sameh_68_6397@fmrz-telecom.com	86 Zamalek Dr, Hurghada	2008-10-05
88	tarek_69_1607	123456	customer	Tarek Gaber	tarek_69_1607@fmrz-telecom.com	25 El-Nasr St, Suez	1992-03-22
89	hassan_70_8402	123456	customer	Hassan Khattab	hassan_70_8402@fmrz-telecom.com	49 9th Street, Giza	1991-05-05
90	ziad_71_4212	123456	customer	Ziad Hamad	ziad_71_4212@fmrz-telecom.com	28 9th Street, Aswan	2000-09-06
91	ibrahim_72_4316	123456	customer	Ibrahim Ezzat	ibrahim_72_4316@fmrz-telecom.com	88 Abbas El Akkad, Suez	2007-06-26
92	nour_73_9168	123456	customer	Nour Wahba	nour_73_9168@fmrz-telecom.com	47 El-Nasr St, Giza	1999-12-23
93	omar_74_1263	123456	customer	Omar Salem	omar_74_1263@fmrz-telecom.com	68 Gameat El Dowal, Mansoura	1988-12-20
94	mona_75_9313	123456	customer	Mona Wahba	mona_75_9313@fmrz-telecom.com	32 Tahrir Sq, Hurghada	1993-06-18
95	sara_76_6238	123456	customer	Sara Zaki	sara_76_6238@fmrz-telecom.com	81 9th Street, Alexandria	2004-04-28
96	tarek_77_2285	123456	customer	Tarek Said	tarek_77_2285@fmrz-telecom.com	87 Zamalek Dr, Mansoura	1987-02-14
97	mohamed_78_6563	123456	customer	Mohamed Nasr	mohamed_78_6563@fmrz-telecom.com	23 Zamalek Dr, Cairo	1995-04-01
98	ziad_79_5054	123456	customer	Ziad Hassan	ziad_79_5054@fmrz-telecom.com	84 Tahrir Sq, Aswan	1987-05-21
99	dina_80_1446	123456	customer	Dina Wahba	dina_80_1446@fmrz-telecom.com	73 Tahrir Sq, Mansoura	2006-08-08
100	mariam_81_6971	123456	customer	Mariam Zaki	mariam_81_6971@fmrz-telecom.com	97 Abbas El Akkad, Suez	1992-07-10
101	hassan_82_9858	123456	customer	Hassan Hassan	hassan_82_9858@fmrz-telecom.com	28 9th Street, Mansoura	1981-08-02
102	ziad_83_4060	123456	customer	Ziad Said	ziad_83_4060@fmrz-telecom.com	52 El-Nasr St, Mansoura	1987-07-24
103	layla_84_8207	123456	customer	Layla Ezzat	layla_84_8207@fmrz-telecom.com	80 Cornish Rd, Luxor	1976-06-02
104	ahmed_85_4236	123456	customer	Ahmed Soliman	ahmed_85_4236@fmrz-telecom.com	73 Zamalek Dr, Hurghada	1992-02-09
105	sameh_86_8892	123456	customer	Sameh Soliman	sameh_86_8892@fmrz-telecom.com	83 Makram Ebeid, Hurghada	1982-06-10
106	sameh_87_8248	123456	customer	Sameh Nasr	sameh_87_8248@fmrz-telecom.com	98 Cornish Rd, Hurghada	2008-07-06
107	sara_88_1613	123456	customer	Sara Hassan	sara_88_1613@fmrz-telecom.com	34 Tahrir Sq, Cairo	1975-06-01
108	sara_89_7168	123456	customer	Sara Salem	sara_89_7168@fmrz-telecom.com	79 Zamalek Dr, Alexandria	1987-12-29
109	ibrahim_90_2589	123456	customer	Ibrahim Zaki	ibrahim_90_2589@fmrz-telecom.com	51 Maadi St, Cairo	1973-01-06
110	tarek_91_6101	123456	customer	Tarek Badawi	tarek_91_6101@fmrz-telecom.com	37 Cornish Rd, Suez	1980-09-01
111	fatma_92_2441	123456	customer	Fatma Ezzat	fatma_92_2441@fmrz-telecom.com	36 Tahrir Sq, Cairo	2008-01-13
112	hala_93_3779	123456	customer	Hala Hamad	hala_93_3779@fmrz-telecom.com	60 Makram Ebeid, Aswan	2003-11-18
113	fatma_94_1730	123456	customer	Fatma Salem	fatma_94_1730@fmrz-telecom.com	34 El-Nasr St, Alexandria	1992-08-19
114	sameh_95_8227	123456	customer	Sameh Khattab	sameh_95_8227@fmrz-telecom.com	63 El-Nasr St, Alexandria	1977-11-16
115	nour_96_1034	123456	customer	Nour Hamad	nour_96_1034@fmrz-telecom.com	90 Maadi St, Aswan	1996-09-20
116	fatma_97_7669	123456	customer	Fatma Hassan	fatma_97_7669@fmrz-telecom.com	67 Tahrir Sq, Giza	1987-01-09
117	mohamed_98_2829	123456	customer	Mohamed Hamad	mohamed_98_2829@fmrz-telecom.com	18 Abbas El Akkad, Aswan	1978-05-26
118	fatma_99_6843	123456	customer	Fatma Khattab	fatma_99_6843@fmrz-telecom.com	74 Abbas El Akkad, Luxor	1988-11-05
119	youssef_100_9174	123456	customer	Youssef Said	youssef_100_9174@fmrz-telecom.com	33 9th Street, Aswan	2005-02-08
120	hassan_101_9448	123456	customer	Hassan Hamad	hassan_101_9448@fmrz-telecom.com	71 Makram Ebeid, Giza	1997-01-20
121	fatma_102_5114	123456	customer	Fatma Nasr	fatma_102_5114@fmrz-telecom.com	99 El-Nasr St, Cairo	2008-05-21
122	sameh_103_1371	123456	customer	Sameh Soliman	sameh_103_1371@fmrz-telecom.com	11 Abbas El Akkad, Aswan	1971-03-15
123	tarek_104_6274	123456	customer	Tarek Ezzat	tarek_104_6274@fmrz-telecom.com	49 Gameat El Dowal, Mansoura	1981-02-03
124	layla_105_6125	123456	customer	Layla Fouad	layla_105_6125@fmrz-telecom.com	70 El-Nasr St, Aswan	1994-03-07
125	nour_106_1257	123456	customer	Nour Said	nour_106_1257@fmrz-telecom.com	99 El-Nasr St, Suez	1977-12-06
126	salma_107_5311	123456	customer	Salma Hamad	salma_107_5311@fmrz-telecom.com	75 Makram Ebeid, Alexandria	1982-10-30
127	salma_108_4601	123456	customer	Salma Mansour	salma_108_4601@fmrz-telecom.com	33 9th Street, Aswan	2001-01-27
128	ibrahim_109_8646	123456	customer	Ibrahim Badawi	ibrahim_109_8646@fmrz-telecom.com	44 Abbas El Akkad, Giza	1978-09-12
129	mariam_110_2949	123456	customer	Mariam Hassan	mariam_110_2949@fmrz-telecom.com	96 Abbas El Akkad, Mansoura	1973-10-16
130	mohamed_111_8203	123456	customer	Mohamed Mansour	mohamed_111_8203@fmrz-telecom.com	75 Zamalek Dr, Alexandria	1971-06-14
131	mariam_112_1231	123456	customer	Mariam Badawi	mariam_112_1231@fmrz-telecom.com	54 Makram Ebeid, Aswan	2009-04-27
132	nour_113_9335	123456	customer	Nour Badawi	nour_113_9335@fmrz-telecom.com	43 Zamalek Dr, Cairo	2006-02-10
133	sameh_114_4617	123456	customer	Sameh Nasr	sameh_114_4617@fmrz-telecom.com	36 9th Street, Cairo	1976-09-05
134	tarek_115_6380	123456	customer	Tarek Said	tarek_115_6380@fmrz-telecom.com	11 Maadi St, Mansoura	1990-12-05
135	ziad_116_3180	123456	customer	Ziad Zaki	ziad_116_3180@fmrz-telecom.com	72 El-Nasr St, Cairo	1997-06-04
136	salma_117_7424	123456	customer	Salma Mansour	salma_117_7424@fmrz-telecom.com	26 Zamalek Dr, Alexandria	1979-09-02
137	layla_118_4793	123456	customer	Layla Hassan	layla_118_4793@fmrz-telecom.com	69 El-Nasr St, Luxor	1985-10-04
138	amir_119_8979	123456	customer	Amir Moussa	amir_119_8979@fmrz-telecom.com	57 Makram Ebeid, Cairo	1994-06-30
139	mariam_120_7740	123456	customer	Mariam Hassan	mariam_120_7740@fmrz-telecom.com	21 Cornish Rd, Giza	1970-01-20
140	khaled_121_8675	123456	customer	Khaled Khattab	khaled_121_8675@fmrz-telecom.com	85 El-Nasr St, Giza	1979-04-25
141	khaled_122_9874	123456	customer	Khaled Wahba	khaled_122_9874@fmrz-telecom.com	26 Tahrir Sq, Suez	1972-02-26
142	mona_123_7384	123456	customer	Mona Said	mona_123_7384@fmrz-telecom.com	34 Tahrir Sq, Giza	2007-03-27
143	mariam_124_3557	123456	customer	Mariam Nasr	mariam_124_3557@fmrz-telecom.com	80 Abbas El Akkad, Hurghada	1977-07-08
144	hala_125_4792	123456	customer	Hala Badawi	hala_125_4792@fmrz-telecom.com	89 Tahrir Sq, Giza	2004-01-20
145	youssef_126_5828	123456	customer	Youssef Fouad	youssef_126_5828@fmrz-telecom.com	78 Zamalek Dr, Giza	2005-01-23
146	layla_127_8241	123456	customer	Layla Nasr	layla_127_8241@fmrz-telecom.com	43 Cornish Rd, Mansoura	2005-05-20
147	youssef_128_7118	123456	customer	Youssef Ezzat	youssef_128_7118@fmrz-telecom.com	74 9th Street, Mansoura	1990-01-09
148	layla_129_8641	123456	customer	Layla Khattab	layla_129_8641@fmrz-telecom.com	63 Gameat El Dowal, Suez	1973-01-03
149	sara_130_1865	123456	customer	Sara Gaber	sara_130_1865@fmrz-telecom.com	19 Gameat El Dowal, Hurghada	1980-02-11
150	mohamed_131_1072	123456	customer	Mohamed Soliman	mohamed_131_1072@fmrz-telecom.com	75 9th Street, Cairo	1973-06-15
151	mohamed_132_6602	123456	customer	Mohamed Nasr	mohamed_132_6602@fmrz-telecom.com	18 Tahrir Sq, Suez	1974-02-20
152	ziad_133_3499	123456	customer	Ziad Hassan	ziad_133_3499@fmrz-telecom.com	26 El-Nasr St, Giza	1997-12-19
153	nour_134_9886	123456	customer	Nour Ezzat	nour_134_9886@fmrz-telecom.com	57 Cornish Rd, Giza	1981-02-17
154	layla_135_1932	123456	customer	Layla Ezzat	layla_135_1932@fmrz-telecom.com	86 Zamalek Dr, Giza	1988-09-09
155	omar_136_9512	123456	customer	Omar Khattab	omar_136_9512@fmrz-telecom.com	24 El-Nasr St, Aswan	1994-10-21
156	sara_137_4583	123456	customer	Sara Soliman	sara_137_4583@fmrz-telecom.com	35 Gameat El Dowal, Hurghada	2007-07-07
157	hassan_138_8663	123456	customer	Hassan Hamad	hassan_138_8663@fmrz-telecom.com	95 Cornish Rd, Cairo	1993-10-06
158	youssef_139_2984	123456	customer	Youssef Moussa	youssef_139_2984@fmrz-telecom.com	43 El-Nasr St, Aswan	1977-08-10
159	fatma_140_8155	123456	customer	Fatma Khattab	fatma_140_8155@fmrz-telecom.com	21 Zamalek Dr, Suez	1995-02-03
160	ziad_141_3897	123456	customer	Ziad Wahba	ziad_141_3897@fmrz-telecom.com	44 Makram Ebeid, Luxor	2006-06-30
161	salma_142_2573	123456	customer	Salma Hassan	salma_142_2573@fmrz-telecom.com	49 El-Nasr St, Aswan	1989-06-07
162	salma_143_8314	123456	customer	Salma Fouad	salma_143_8314@fmrz-telecom.com	18 El-Nasr St, Suez	1971-07-17
163	amir_144_8621	123456	customer	Amir Khattab	amir_144_8621@fmrz-telecom.com	12 Tahrir Sq, Aswan	1984-10-31
164	omar_145_7550	123456	customer	Omar Zaki	omar_145_7550@fmrz-telecom.com	96 Tahrir Sq, Mansoura	1978-06-15
165	sameh_146_2852	123456	customer	Sameh Fouad	sameh_146_2852@fmrz-telecom.com	98 Cornish Rd, Giza	2002-08-12
166	hala_147_9697	123456	customer	Hala Badawi	hala_147_9697@fmrz-telecom.com	68 El-Nasr St, Suez	2008-04-25
167	ibrahim_148_7698	123456	customer	Ibrahim Zaki	ibrahim_148_7698@fmrz-telecom.com	74 Tahrir Sq, Giza	1993-02-26
168	omar_149_1735	123456	customer	Omar Zaki	omar_149_1735@fmrz-telecom.com	89 Zamalek Dr, Luxor	1979-12-19
169	mona_150_1921	123456	customer	Mona Ezzat	mona_150_1921@fmrz-telecom.com	26 Zamalek Dr, Suez	2001-06-06
171	hassan_101	123456	customer	Hassan Said	hassan.said11@fmrz-telecom.com	18 Makram Ebeid, Cairo	1988-11-11
172	youssef_102	123456	customer	Youssef Ezzat	youssef.ezzat12@fmrz-telecom.com	61 Cornish Rd, Alexandria	1986-08-19
173	ziad_103	123456	customer	Ziad Salem	ziad.salem13@fmrz-telecom.com	28 El-Nasr St, Cairo	1999-09-22
174	mona_104	123456	customer	Mona Gaber	mona.gaber14@fmrz-telecom.com	46 Makram Ebeid, Suez	1998-07-25
175	ahmed_105	123456	customer	Ahmed Mansour	ahmed.mansour15@fmrz-telecom.com	67 Abbas El Akkad, Luxor	1985-12-22
176	layla_106	123456	customer	Layla Gaber	layla.gaber16@fmrz-telecom.com	14 Tahrir Sq, Suez	2010-10-13
177	mohamed_107	123456	customer	Mohamed Nasr	mohamed.nasr17@fmrz-telecom.com	85 Makram Ebeid, Suez	2003-04-02
178	mohamed_108	123456	customer	Mohamed Said	mohamed.said18@fmrz-telecom.com	40 Abbas El Akkad, Cairo	1990-05-31
179	youssef_109	123456	customer	Youssef Zaki	youssef.zaki19@fmrz-telecom.com	54 El-Nasr St, Mansoura	2005-03-14
180	omar_110	123456	customer	Omar Nasr	omar.nasr20@fmrz-telecom.com	70 Tahrir Sq, Luxor	1996-07-29
181	youssef_111	123456	customer	Youssef Salem	youssef.salem21@fmrz-telecom.com	14 Tahrir Sq, Suez	1987-11-15
182	ziad_112	123456	customer	Ziad Salem	ziad.salem22@fmrz-telecom.com	75 Gameat El Dowal, Alexandria	1995-02-07
183	ahmed_113	123456	customer	Ahmed Zaki	ahmed.zaki23@fmrz-telecom.com	10 9th Street, Suez	1992-12-09
184	sara_114	123456	customer	Sara Salem	sara.salem24@fmrz-telecom.com	61 Abbas El Akkad, Suez	2009-11-30
185	nour_115	123456	customer	Nour Gaber	nour.gaber25@fmrz-telecom.com	10 Makram Ebeid, Alexandria	1995-06-03
186	salma_116	123456	customer	Salma Ezzat	salma.ezzat26@fmrz-telecom.com	12 Abbas El Akkad, Luxor	1987-09-24
187	ahmed_117	123456	customer	Ahmed Khattab	ahmed.khattab27@fmrz-telecom.com	87 Cornish Rd, Suez	2000-03-31
188	fatma_118	123456	customer	Fatma Nasr	fatma.nasr28@fmrz-telecom.com	97 Cornish Rd, Cairo	2003-05-02
189	mona_119	123456	customer	Mona Said	mona.said29@fmrz-telecom.com	63 Gameat El Dowal, Mansoura	1996-05-03
190	youssef_120	123456	customer	Youssef Nasr	youssef.nasr30@fmrz-telecom.com	52 Makram Ebeid, Suez	2002-04-19
191	salma_121	123456	customer	Salma Said	salma.said31@fmrz-telecom.com	49 El-Nasr St, Mansoura	2012-02-22
192	sara_122	123456	customer	Sara Hassan	sara.hassan32@fmrz-telecom.com	23 Abbas El Akkad, Cairo	2006-10-28
193	mohamed_123	123456	customer	Mohamed Wahba	mohamed.wahba33@fmrz-telecom.com	39 Tahrir Sq, Alexandria	2011-05-01
194	hassan_124	123456	customer	Hassan Zaki	hassan.zaki34@fmrz-telecom.com	35 El-Nasr St, Giza	1985-04-02
195	hassan_125	123456	customer	Hassan Zaki	hassan.zaki35@fmrz-telecom.com	21 El-Nasr St, Suez	2001-04-06
196	ahmed_126	123456	customer	Ahmed Ezzat	ahmed.ezzat36@fmrz-telecom.com	48 Cornish Rd, Alexandria	2011-10-12
197	mona_127	123456	customer	Mona Said	mona.said37@fmrz-telecom.com	15 Tahrir Sq, Suez	1985-07-31
198	mona_128	123456	customer	Mona Khattab	mona.khattab38@fmrz-telecom.com	36 9th Street, Mansoura	2011-09-21
199	mona_129	123456	customer	Mona Gaber	mona.gaber39@fmrz-telecom.com	52 Cornish Rd, Mansoura	1985-07-29
200	fatma_130	123456	customer	Fatma Wahba	fatma.wahba40@fmrz-telecom.com	21 Gameat El Dowal, Cairo	2005-11-14
\.


--
-- Name: audit_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.audit_log_id_seq', 3, true);


--
-- Name: bill_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.bill_id_seq', 366, true);


--
-- Name: cdr_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.cdr_id_seq', 1829, true);


--
-- Name: contract_addon_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.contract_addon_id_seq', 44, true);


--
-- Name: contract_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.contract_id_seq', 201, true);


--
-- Name: file_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.file_id_seq', 19, true);


--
-- Name: invoice_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.invoice_id_seq', 18, true);


--
-- Name: msisdn_pool_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.msisdn_pool_id_seq', 249, true);


--
-- Name: onetime_fee_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.onetime_fee_id_seq', 1, true);


--
-- Name: payment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.payment_id_seq', 1, false);


--
-- Name: rateplan_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.rateplan_id_seq', 5, true);


--
-- Name: rejected_cdr_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.rejected_cdr_id_seq', 1266, true);


--
-- Name: service_package_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.service_package_id_seq', 8, true);


--
-- Name: user_account_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.user_account_id_seq', 205, true);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: bill bill_contract_id_billing_period_start_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.bill
    ADD CONSTRAINT bill_contract_id_billing_period_start_key UNIQUE (contract_id, billing_period_start);


--
-- Name: bill bill_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.bill
    ADD CONSTRAINT bill_pkey PRIMARY KEY (id);


--
-- Name: cdr cdr_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.cdr
    ADD CONSTRAINT cdr_pkey PRIMARY KEY (id);


--
-- Name: contract_addon contract_addon_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.contract_addon
    ADD CONSTRAINT contract_addon_pkey PRIMARY KEY (id);


--
-- Name: contract_consumption contract_consumption_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.contract_consumption
    ADD CONSTRAINT contract_consumption_pkey PRIMARY KEY (contract_id, service_package_id, rateplan_id, starting_date, ending_date);


--
-- Name: contract contract_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.contract
    ADD CONSTRAINT contract_pkey PRIMARY KEY (id);


--
-- Name: file file_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.file
    ADD CONSTRAINT file_pkey PRIMARY KEY (id);


--
-- Name: invoice invoice_bill_id_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_bill_id_key UNIQUE (bill_id);


--
-- Name: invoice invoice_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_pkey PRIMARY KEY (id);


--
-- Name: msisdn_pool msisdn_pool_msisdn_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.msisdn_pool
    ADD CONSTRAINT msisdn_pool_msisdn_key UNIQUE (msisdn);


--
-- Name: msisdn_pool msisdn_pool_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.msisdn_pool
    ADD CONSTRAINT msisdn_pool_pkey PRIMARY KEY (id);


--
-- Name: onetime_fee onetime_fee_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.onetime_fee
    ADD CONSTRAINT onetime_fee_pkey PRIMARY KEY (id);


--
-- Name: payment payment_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_pkey PRIMARY KEY (id);


--
-- Name: payment payment_transaction_id_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_transaction_id_key UNIQUE (transaction_id);


--
-- Name: rateplan rateplan_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.rateplan
    ADD CONSTRAINT rateplan_pkey PRIMARY KEY (id);


--
-- Name: rateplan_service_package rateplan_service_package_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.rateplan_service_package
    ADD CONSTRAINT rateplan_service_package_pkey PRIMARY KEY (rateplan_id, service_package_id);


--
-- Name: rejected_cdr rejected_cdr_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.rejected_cdr
    ADD CONSTRAINT rejected_cdr_pkey PRIMARY KEY (id);


--
-- Name: ror_contract ror_contract_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.ror_contract
    ADD CONSTRAINT ror_contract_pkey PRIMARY KEY (contract_id, rateplan_id, starting_date);


--
-- Name: service_package service_package_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.service_package
    ADD CONSTRAINT service_package_pkey PRIMARY KEY (id);


--
-- Name: user_account user_account_email_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.user_account
    ADD CONSTRAINT user_account_email_key UNIQUE (email);


--
-- Name: user_account user_account_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.user_account
    ADD CONSTRAINT user_account_pkey PRIMARY KEY (id);


--
-- Name: user_account user_account_username_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.user_account
    ADD CONSTRAINT user_account_username_key UNIQUE (username);


--
-- Name: contract_msisdn_active_idx; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE UNIQUE INDEX contract_msisdn_active_idx ON public.contract USING btree (msisdn) WHERE (status <> 'terminated'::public.contract_status);


--
-- Name: idx_addon_active; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_addon_active ON public.contract_addon USING btree (contract_id, is_active);


--
-- Name: idx_addon_contract; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_addon_contract ON public.contract_addon USING btree (contract_id);


--
-- Name: idx_bill_billing_date; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_bill_billing_date ON public.bill USING btree (billing_date);


--
-- Name: idx_bill_contract; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_bill_contract ON public.bill USING btree (contract_id);


--
-- Name: idx_cdr_dial_a; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_cdr_dial_a ON public.cdr USING btree (dial_a);


--
-- Name: idx_cdr_file_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_cdr_file_id ON public.cdr USING btree (file_id);


--
-- Name: idx_cdr_rated_flag; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_cdr_rated_flag ON public.cdr USING btree (rated_flag);


--
-- Name: idx_contract_user_account; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_contract_user_account ON public.contract USING btree (user_account_id);


--
-- Name: idx_invoice_bill; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX idx_invoice_bill ON public.invoice USING btree (bill_id);


--
-- Name: idx_rateplan_name; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE UNIQUE INDEX idx_rateplan_name ON public.rateplan USING btree (name);


--
-- Name: cdr trg_auto_initialize_consumption; Type: TRIGGER; Schema: public; Owner: neondb_owner
--

CREATE TRIGGER trg_auto_initialize_consumption BEFORE INSERT ON public.cdr FOR EACH ROW EXECUTE FUNCTION public.auto_initialize_consumption();


--
-- Name: cdr trg_auto_rate_cdr; Type: TRIGGER; Schema: public; Owner: neondb_owner
--

CREATE TRIGGER trg_auto_rate_cdr AFTER INSERT ON public.cdr FOR EACH ROW EXECUTE FUNCTION public.auto_rate_cdr();


--
-- Name: bill trg_bill_inserted; Type: TRIGGER; Schema: public; Owner: neondb_owner
--

CREATE TRIGGER trg_bill_inserted AFTER INSERT ON public.bill FOR EACH ROW EXECUTE FUNCTION public.notify_bill_generation();


--
-- Name: bill trg_bill_payment; Type: TRIGGER; Schema: public; Owner: neondb_owner
--

CREATE TRIGGER trg_bill_payment AFTER UPDATE ON public.bill FOR EACH ROW EXECUTE FUNCTION public.trg_restore_credit_on_payment();


--
-- Name: bill bill_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.bill
    ADD CONSTRAINT bill_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contract(id);


--
-- Name: cdr cdr_file_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.cdr
    ADD CONSTRAINT cdr_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.file(id);


--
-- Name: cdr cdr_service_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.cdr
    ADD CONSTRAINT cdr_service_id_fkey FOREIGN KEY (service_id) REFERENCES public.service_package(id);


--
-- Name: contract_addon contract_addon_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.contract_addon
    ADD CONSTRAINT contract_addon_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contract(id);


--
-- Name: contract_addon contract_addon_service_package_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.contract_addon
    ADD CONSTRAINT contract_addon_service_package_id_fkey FOREIGN KEY (service_package_id) REFERENCES public.service_package(id);


--
-- Name: contract_consumption contract_consumption_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.contract_consumption
    ADD CONSTRAINT contract_consumption_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bill(id);


--
-- Name: contract_consumption contract_consumption_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.contract_consumption
    ADD CONSTRAINT contract_consumption_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contract(id);


--
-- Name: contract_consumption contract_consumption_rateplan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.contract_consumption
    ADD CONSTRAINT contract_consumption_rateplan_id_fkey FOREIGN KEY (rateplan_id) REFERENCES public.rateplan(id);


--
-- Name: contract_consumption contract_consumption_service_package_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.contract_consumption
    ADD CONSTRAINT contract_consumption_service_package_id_fkey FOREIGN KEY (service_package_id) REFERENCES public.service_package(id);


--
-- Name: contract contract_rateplan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.contract
    ADD CONSTRAINT contract_rateplan_id_fkey FOREIGN KEY (rateplan_id) REFERENCES public.rateplan(id);


--
-- Name: contract contract_user_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.contract
    ADD CONSTRAINT contract_user_account_id_fkey FOREIGN KEY (user_account_id) REFERENCES public.user_account(id);


--
-- Name: invoice invoice_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.invoice
    ADD CONSTRAINT invoice_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bill(id);


--
-- Name: onetime_fee onetime_fee_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.onetime_fee
    ADD CONSTRAINT onetime_fee_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bill(id);


--
-- Name: onetime_fee onetime_fee_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.onetime_fee
    ADD CONSTRAINT onetime_fee_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contract(id);


--
-- Name: payment payment_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bill(id);


--
-- Name: rateplan_service_package rateplan_service_package_rateplan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.rateplan_service_package
    ADD CONSTRAINT rateplan_service_package_rateplan_id_fkey FOREIGN KEY (rateplan_id) REFERENCES public.rateplan(id);


--
-- Name: rateplan_service_package rateplan_service_package_service_package_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.rateplan_service_package
    ADD CONSTRAINT rateplan_service_package_service_package_id_fkey FOREIGN KEY (service_package_id) REFERENCES public.service_package(id);


--
-- Name: ror_contract ror_contract_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.ror_contract
    ADD CONSTRAINT ror_contract_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bill(id);


--
-- Name: ror_contract ror_contract_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.ror_contract
    ADD CONSTRAINT ror_contract_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contract(id);


--
-- Name: ror_contract ror_contract_rateplan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.ror_contract
    ADD CONSTRAINT ror_contract_rateplan_id_fkey FOREIGN KEY (rateplan_id) REFERENCES public.rateplan(id);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: neondb_owner
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;


--
-- PostgreSQL database dump complete
--

\unrestrict QAhNCqjh3AGJ9KcbuZQe0xSAD8cDvjtzYAttFGnM6hKGtZ2zQCxWX96gZzcgopG

