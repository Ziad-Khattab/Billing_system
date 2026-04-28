--
-- PostgreSQL database dump
--

\restrict RwFaKbTXk7nYR5bL27HUW2WoLPEKeB2FMh47bNOgy8dDkNtB0Sdofnsrg61hotk

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
    'suspended_debt',
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


--
-- Name: generate_bill(integer, date); Type: FUNCTION; Schema: public; Owner: -
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

        SELECT 
            COALESCE(SUM(CASE WHEN sp.type::TEXT = 'voice' THEN c.duration ELSE 0 END), 0)::INT,
            COALESCE(SUM(CASE WHEN sp.type::TEXT = 'data' THEN c.duration ELSE 0 END), 0)::INT,
            COALESCE(SUM(CASE WHEN sp.type::TEXT = 'sms' THEN 1 ELSE 0 END), 0)::INT
        INTO v_voice_usage, v_data_usage, v_sms_usage
        FROM cdr c JOIN service_package sp ON c.service_id = sp.id
        WHERE c.dial_a = v_msisdn AND c.start_time >= p_billing_period_start AND c.start_time <= v_billing_period_end;

        v_overage_charge := 0;
        v_roaming_charge := 0;
        SELECT 
            COALESCE(voice + data + sms, 0),
            COALESCE(roaming_voice + roaming_data + roaming_sms, 0)
        INTO v_overage_charge, v_roaming_charge
        FROM ror_contract WHERE contract_id = p_contract_id AND bill_id IS NULL;
        
        v_overage_charge := COALESCE(v_overage_charge, 0);
        v_roaming_charge := COALESCE(v_roaming_charge, 0);

        -- Calculate Promotional Savings (Regex for better matching)
        SELECT 
            COALESCE(SUM(
              CASE 
                WHEN sp.type::TEXT = 'voice' THEN cc.consumed * v_ror_rate_v
                WHEN sp.type::TEXT = 'data'  THEN cc.consumed * v_ror_rate_d
                WHEN sp.type::TEXT = 'sms'   THEN cc.consumed * v_ror_rate_s
                ELSE 0 
              END), 0)
        INTO v_promo_discount
        FROM contract_consumption cc
        JOIN service_package sp ON cc.service_package_id = sp.id
        WHERE cc.contract_id = p_contract_id AND cc.starting_date = p_billing_period_start
            AND (sp.name ~* 'Welcome|Gift|Bonus');

        -- Math Precision: Savings already reflected in overage (Overage is 0 if covered).
        -- We don't double-subtract. We show it for transparency.
        v_subtotal := (v_recurring_fees + COALESCE(v_overage_charge,0) + COALESCE(v_roaming_charge,0));
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

        UPDATE ror_contract SET bill_id = v_bill_id WHERE contract_id = p_contract_id AND bill_id IS NULL;
        UPDATE contract_consumption SET bill_id = v_bill_id, is_billed = TRUE WHERE contract_id = p_contract_id AND starting_date = p_billing_period_start;
        
        RETURN v_bill_id;
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
            ua.id,
            ua.username,
            ua.name,
            ua.email,
            ua.role,
            ua.address,
            ua.birthdate,
            c.msisdn
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


--
-- Name: rate_cdr(integer); Type: FUNCTION; Schema: public; Owner: -
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
     v_overage_charge NUMERIC := 0;
     v_rated_service_id INTEGER;
     v_is_roaming BOOLEAN;
 BEGIN
     SELECT * INTO v_cdr FROM cdr WHERE id = p_cdr_id;
     
     -- Only rate for ACTIVE contracts
     SELECT * INTO v_contract FROM contract WHERE msisdn = v_cdr.dial_a AND status = 'active';
     
     IF NOT FOUND THEN
         UPDATE cdr SET rated_flag = TRUE, external_charges = 0, rated_service_id = NULL WHERE id = p_cdr_id;
         RETURN;
     END IF;

     SELECT type::TEXT INTO v_service_type FROM service_package WHERE id = v_cdr.service_id;
     v_remaining := v_cdr.duration;
     v_is_roaming := (v_cdr.vplmn IS NOT NULL);

     FOR v_bundle IN 
         SELECT cc.*, sp.name, sp.is_roaming as pkg_roaming
         FROM contract_consumption cc
         JOIN service_package sp ON cc.service_package_id = sp.id
         WHERE cc.contract_id = v_contract.id AND cc.is_billed = FALSE
           AND (sp.type::TEXT = v_service_type OR sp.type::TEXT = 'free_units')
           AND sp.is_roaming = v_is_roaming
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
           AND starting_date = v_bundle.starting_date 
           AND ending_date = v_bundle.ending_date;
         v_rated_service_id := v_bundle.service_package_id;
     END LOOP;

     IF v_remaining > 0 THEN
         SELECT CASE v_service_type 
            WHEN 'voice' THEN ror_voice WHEN 'data' THEN ror_data WHEN 'sms' THEN ror_sms 
            END INTO v_ror_rate FROM rateplan WHERE id = v_contract.rateplan_id;
         
         v_overage_charge := v_remaining * COALESCE(v_ror_rate, 0);

         IF v_is_roaming THEN
             INSERT INTO ror_contract (contract_id, rateplan_id, roaming_voice, roaming_data, roaming_sms)
             VALUES (v_contract.id, v_contract.rateplan_id, 
                    CASE WHEN v_service_type='voice' THEN v_overage_charge ELSE 0 END,
                    CASE WHEN v_service_type='data'  THEN v_overage_charge ELSE 0 END,
                    CASE WHEN v_service_type='sms'   THEN v_overage_charge ELSE 0 END)
             ON CONFLICT (contract_id, rateplan_id) DO UPDATE SET
                roaming_voice = ror_contract.roaming_voice + EXCLUDED.roaming_voice,
                roaming_data = ror_contract.roaming_data + EXCLUDED.roaming_data,
                roaming_sms = ror_contract.roaming_sms + EXCLUDED.roaming_sms;
         ELSE
             INSERT INTO ror_contract (contract_id, rateplan_id, voice, data, sms)
             VALUES (v_contract.id, v_contract.rateplan_id, 
                    CASE WHEN v_service_type='voice' THEN v_overage_charge ELSE 0 END,
                    CASE WHEN v_service_type='data'  THEN v_overage_charge ELSE 0 END,
                    CASE WHEN v_service_type='sms'   THEN v_overage_charge ELSE 0 END)
             ON CONFLICT (contract_id, rateplan_id) DO UPDATE SET
                voice = ror_contract.voice + EXCLUDED.voice,
                data = ror_contract.data + EXCLUDED.data,
                sms = ror_contract.sms + EXCLUDED.sms;
         END IF;
     END IF;

     UPDATE cdr SET rated_flag = TRUE, external_charges = v_overage_charge, rated_service_id = v_rated_service_id WHERE id = p_cdr_id;
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
    overage_charge numeric(12,2) DEFAULT 0 NOT NULL,
    roaming_charge numeric(12,2) DEFAULT 0 NOT NULL,
    promotional_discount numeric(12,2) DEFAULT 0 NOT NULL,
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
    rated_flag boolean DEFAULT false NOT NULL,
    rated_service_id integer
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
    consumed numeric(12,4) DEFAULT 0 NOT NULL,
    quota_limit numeric(12,4) DEFAULT 0 NOT NULL,
    is_billed boolean DEFAULT false NOT NULL,
    bill_id integer
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
    roaming_voice numeric(12,2) DEFAULT 0.00,
    roaming_data numeric(12,2) DEFAULT 0.00,
    roaming_sms numeric(12,2) DEFAULT 0.00,
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
19	3	2026-03-01	2026-03-31	2026-04-01	75.00	0.69	170	0	20	0.00	0.00	0.00	0.00	10.50	86.19	issued	f
20	4	2026-03-01	2026-03-31	2026-04-01	370.00	0.69	450	1600	58	0.00	0.00	0.00	0.00	51.80	422.49	issued	f
21	5	2026-03-01	2026-03-31	2026-04-01	75.00	0.69	90	0	11	0.00	0.00	0.00	0.00	10.50	86.19	issued	f
22	6	2026-03-01	2026-03-31	2026-04-01	370.00	0.69	720	3100	105	0.00	0.00	0.00	0.00	51.80	422.49	issued	f
23	7	2026-03-01	2026-03-31	2026-04-01	75.00	0.69	200	0	28	0.00	0.00	0.00	0.00	10.50	86.19	issued	f
24	8	2026-03-01	2026-03-31	2026-04-01	370.00	0.69	380	1350	50	0.00	0.00	0.00	0.00	51.80	422.49	issued	f
25	9	2026-03-01	2026-03-31	2026-04-01	75.00	0.69	130	0	16	0.00	0.00	0.00	0.00	10.50	86.19	issued	f
26	10	2026-03-01	2026-03-31	2026-04-01	370.00	0.69	500	1900	68	0.00	0.00	0.00	0.00	51.80	422.49	issued	f
27	11	2026-03-01	2026-03-31	2026-04-01	75.00	0.69	900	0	195	14.50	0.00	0.00	0.00	6.52	71.71	issued	f
28	12	2026-03-01	2026-03-31	2026-04-01	370.00	0.69	280	850	35	0.00	0.00	0.00	0.00	51.80	422.49	issued	f
29	14	2026-03-01	2026-03-31	2026-04-01	370.00	0.69	420	1100	55	0.00	0.00	0.00	0.00	51.80	422.49	issued	f
30	15	2026-03-01	2026-03-31	2026-04-01	950.00	0.69	800	3700	140	0.00	0.00	0.00	0.00	133.00	1083.69	issued	f
31	16	2026-03-01	2026-03-31	2026-04-01	950.00	0.69	920	4800	170	8.00	0.00	0.00	0.00	35.77	393.46	issued	f
32	17	2026-03-01	2026-03-31	2026-04-01	370.00	0.69	330	980	45	0.00	0.00	0.00	0.00	51.80	422.49	issued	f
33	1	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	2460	0	6	0.00	492.00	0.00	0.00	79.38	646.38	issued	f
34	2	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	2130	3550	5	0.00	336.00	55.02	0.00	106.54	867.56	issued	f
35	3	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	630	0	2	0.00	126.00	0.00	0.00	28.14	229.14	issued	f
36	4	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	1320	2100	2	0.00	237.00	0.00	0.00	84.98	691.98	issued	f
37	5	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	360	0	2	0.00	72.00	0.00	0.00	20.58	167.58	issued	f
38	6	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	2400	2850	3	0.00	383.00	0.00	0.00	105.42	858.42	issued	f
39	7	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	600	0	2	0.00	120.00	0.00	0.00	27.30	222.30	issued	f
40	8	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	1110	1400	2	0.00	182.00	0.00	0.00	77.28	629.28	issued	f
41	9	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	330	0	2	0.00	66.00	0.00	0.00	19.74	160.74	issued	f
42	10	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	1380	2400	2	0.00	258.00	0.00	0.00	87.92	715.92	issued	f
43	11	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	2040	0	4	0.00	408.00	0.00	0.00	67.62	550.62	issued	f
44	12	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	600	550	1	0.00	88.00	0.00	0.00	64.12	522.12	issued	f
45	14	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	840	1350	2	0.00	152.00	0.00	0.00	73.08	595.08	issued	f
61	31	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
62	32	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
63	33	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
64	34	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
65	35	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
67	37	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
68	38	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
69	39	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
70	40	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
71	41	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
72	42	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
73	43	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
74	44	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
75	45	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t
47	16	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	2220	4800	2	0.00	227.00	0.00	0.00	164.78	1341.78	paid	t
66	36	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t
49	19	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t
46	15	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	2040	4900	3	0.00	180.00	20.01	0.00	161.00	1311.01	paid	t
78	48	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	0	0	0	0.00	0.00	0.00	0.00	51.80	421.80	paid	t
77	47	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	0	0	0	0.00	0.00	0.00	0.00	133.00	1083.00	paid	t
76	46	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	paid	t
48	17	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	720	1350	2	0.00	140.00	0.00	0.00	71.40	581.40	paid	t
80	22	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	253	37888	2	0.00	0.00	5.30	0.00	52.54	427.84	issued	f
81	23	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	107	78848	2	0.00	0.00	7884.80	0.00	1114.37	9074.17	issued	f
82	24	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	108	26624	2	0.00	0.00	0.00	0.00	133.00	1083.00	issued	f
83	25	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	306	128000	1	0.00	1760.00	0.00	0.00	379.40	3089.40	issued	f
86	28	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	222	47104	1	0.00	355.00	0.00	0.00	101.50	826.50	issued	f
87	29	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	326	82944	2	0.00	865.00	0.00	0.00	254.10	2069.10	issued	f
88	30	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	252	81920	2	0.00	0.00	50.40	0.00	17.56	142.96	issued	f
89	20	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	517	41984	1	0.00	0.00	4198.40	0.00	598.28	4871.68	issued	f
90	53	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	79	15360	2	0.00	544.00	0.05	0.00	86.67	705.72	issued	f
91	54	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	49	140288	1	0.00	0.00	5222.40	0.00	741.64	6039.04	issued	f
93	56	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	235	83968	2	0.00	7420.00	0.00	0.00	1049.30	8544.30	issued	f
94	58	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	264	72704	1	0.00	2635.00	0.00	0.00	420.70	3425.70	issued	f
95	59	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	488	86016	1	0.00	7633.00	35.80	0.00	1084.13	8827.93	issued	f
96	60	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	34	18432	2	0.00	0.00	328.64	0.00	179.01	1457.65	issued	f
97	63	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	71	143360	1	0.00	14336.00	0.00	0.00	2017.54	16428.54	issued	f
98	66	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	143	14336	1	0.00	1434.00	0.00	0.00	211.26	1720.26	issued	f
99	68	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	215	65536	2	0.00	2288.00	0.00	0.00	372.12	3030.12	issued	f
100	69	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	301	54272	1	0.00	5428.00	0.00	0.00	770.42	6273.42	issued	f
101	70	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	562	92160	1	0.00	0.00	22.80	0.00	54.99	447.79	issued	f
102	71	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	125	45056	2	0.00	3518.00	0.05	0.00	503.03	4096.08	issued	f
103	72	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	182	79872	1	0.00	7270.00	716.80	0.00	1128.65	9190.45	issued	f
104	73	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	245	72704	1	0.00	2138.00	0.00	0.00	351.12	2859.12	issued	f
105	76	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	255	8192	2	0.00	0.00	7.75	0.00	134.09	1091.84	issued	f
106	77	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	41	29696	1	0.00	0.00	1026.40	0.00	195.50	1591.90	issued	f
107	79	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	219	34816	1	0.00	0.00	3481.60	0.00	497.92	4054.52	issued	f
108	80	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	291	44032	2	0.00	1216.00	0.00	0.00	222.04	1808.04	issued	f
109	81	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	153	99328	1	0.00	0.00	156.00	0.00	73.64	599.64	issued	f
110	82	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	413	53248	1	0.00	0.00	2562.40	0.00	410.54	3342.94	issued	f
111	83	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	282	29696	2	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
112	84	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	209	151552	1	0.00	2431.00	0.00	0.00	473.34	3854.34	issued	f
113	85	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	437	10240	1	0.00	53.00	0.00	0.00	17.92	145.92	issued	f
114	87	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	93	24576	2	0.00	1467.00	0.00	0.00	215.88	1757.88	issued	f
115	88	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	49	177152	1	0.00	7857.00	0.00	0.00	1151.78	9378.78	issued	f
116	90	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	432	83968	1	0.00	2704.00	0.00	0.00	430.36	3504.36	issued	f
117	91	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	52	48128	2	0.00	564.00	0.00	0.00	211.96	1725.96	issued	f
118	92	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	104	52224	1	0.00	638.00	872.80	0.00	263.31	2144.11	issued	f
119	93	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	568	72704	1	0.00	7270.00	0.00	0.00	1028.30	8373.30	issued	f
120	94	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	95	63488	2	0.00	1679.00	0.00	0.00	286.86	2335.86	issued	f
121	95	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	177	103424	1	0.00	9342.00	0.00	0.00	1318.38	10735.38	issued	f
122	99	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	301	78848	1	0.00	7885.00	0.00	0.00	1114.40	9074.40	issued	f
123	101	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	200	51200	2	0.00	1070.00	0.00	0.00	201.60	1641.60	issued	f
124	102	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	229	97280	1	0.00	0.00	130.29	0.00	151.24	1231.53	issued	f
125	103	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	101	87040	1	0.00	1341.00	0.00	0.00	320.74	2611.74	issued	f
126	104	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	328	90112	2	0.00	0.00	4405.60	0.00	668.58	5444.18	issued	f
127	105	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	45	121856	1	0.00	11185.00	0.00	0.00	1576.40	12836.40	issued	f
128	106	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	341	84992	1	0.00	2755.00	0.00	0.00	437.50	3562.50	issued	f
129	107	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	64	67584	2	0.00	0.00	3279.20	0.00	510.89	4160.09	issued	f
130	109	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	256	183296	1	0.00	0.00	9625.60	0.00	1358.08	11058.68	issued	f
131	111	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	551	24576	1	0.00	0.00	2513.80	0.00	362.43	2951.23	issued	f
132	112	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	132	66560	2	0.00	0.00	6656.00	0.00	942.34	7673.34	issued	f
133	113	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	70	176128	1	0.00	16613.00	0.00	0.00	2336.32	19024.32	issued	f
134	114	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	432	55296	1	0.00	5530.00	0.00	0.00	784.70	6389.70	issued	f
135	115	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	177	98304	2	0.00	3424.00	0.00	0.00	531.16	4325.16	issued	f
136	118	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	183	109568	1	0.00	4479.00	0.00	0.00	678.86	5527.86	issued	f
137	119	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	218	60416	1	0.00	2027.00	0.00	0.00	335.58	2732.58	issued	f
138	121	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	326	16384	2	0.00	0.00	0.00	0.00	51.80	421.80	issued	f
139	122	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	182	86016	1	0.00	8601.00	0.00	0.00	1214.64	9890.64	issued	f
140	125	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	428	29696	1	0.00	0.00	32.80	0.00	56.39	459.19	issued	f
141	126	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	246	36864	2	0.00	856.00	0.00	0.00	171.64	1397.64	issued	f
142	127	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	71	120832	1	0.00	11083.00	0.00	0.00	1562.12	12720.12	issued	f
143	129	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	340	62464	1	0.00	2137.00	0.00	0.00	350.98	2857.98	issued	f
144	130	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	85	88064	2	0.00	2908.00	0.00	0.00	458.92	3736.92	issued	f
145	134	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	242	161792	1	0.00	15179.00	48.40	0.00	2142.34	17444.74	issued	f
146	135	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	534	59392	1	0.00	5939.00	0.00	0.00	841.96	6855.96	issued	f
147	136	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	195	73728	2	0.00	878.00	0.00	0.00	255.92	2083.92	issued	f
148	137	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	152	112640	1	0.00	4632.00	0.00	0.00	700.28	5702.28	issued	f
149	140	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	271	50176	1	0.00	1016.00	0.00	0.00	194.04	1580.04	issued	f
92	55	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	429	95232	1	0.00	3274.00	0.00	0.00	510.16	4154.16	paid	t
85	27	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	251	121856	1	0.00	1638.00	0.00	0.00	362.32	2950.32	paid	t
79	21	2026-04-01	2026-04-30	2026-04-28	950.00	0.00	319	103424	1	0.00	1268.00	0.00	0.00	310.52	2528.52	paid	t
150	142	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	293	70656	2	0.00	2547.00	0.00	0.00	408.38	3325.38	issued	f
151	145	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	97	126976	1	0.00	5349.00	0.00	0.00	800.66	6519.66	issued	f
152	146	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	352	83968	1	0.00	0.00	8.30	0.00	52.96	431.26	issued	f
153	149	2026-04-01	2026-04-30	2026-04-28	370.00	0.00	316	71680	2	0.00	2600.00	0.00	0.00	415.80	3385.80	issued	f
154	150	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	314	121856	1	0.00	11186.00	62.80	0.00	1585.33	12909.13	issued	f
84	26	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	97	68608	2	0.00	0.00	0.05	0.00	10.51	85.56	paid	t
156	151	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
158	152	2026-04-01	2026-04-30	2026-04-28	75.00	0.00	0	0	0	0.00	0.00	0.00	0.00	10.50	85.50	issued	f
\.


--
-- Data for Name: cdr; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cdr (id, file_id, dial_a, dial_b, start_time, duration, service_id, hplmn, vplmn, external_charges, rated_flag, rated_service_id) FROM stdin;
130	1	201000000044	201090000000	2026-04-01 10:30:00	77824	2	EGYVO	\N	756.48	t	2
131	1	201000000044	201090000000	2026-04-01 11:00:00	1	3	EGYVO	\N	0.00	t	3
132	1	201000000044	201090000000	2026-04-01 11:30:00	66	1	EGYVO	\N	0.00	t	1
133	1	201000000044	201090000000	2026-04-01 12:00:00	37888	2	EGYVO	\N	757.76	t	\N
134	1	201000000047	201090000000	2026-04-01 12:30:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
135	1	201000000047	201090000000	2026-04-01 13:00:00	301	1	EGYVO	\N	0.00	t	4
136	1	201000000047	201090000000	2026-04-01 13:30:00	73728	2	EGYVO	\N	680.58	t	2
137	1	201000000047	201090000000	2026-04-01 14:00:00	1	3	EGYVO	\N	0.00	t	3
138	1	201000000041	201090000000	2026-04-01 14:30:00	70	1	EGYVO	\N	0.00	t	4
139	1	201000000041	201090000000	2026-04-01 15:00:00	8192	2	EGYVO	\N	0.00	t	4
140	1	201000000041	201090000000	2026-04-01 15:30:00	1	3	EGYVO	\N	0.00	t	4
141	1	201000000041	201090000000	2026-04-01 16:00:00	216	1	EGYVO	\N	0.00	t	4
142	1	201000000027	201090000000	2026-04-01 16:30:00	50176	2	EGYVO	\N	203.52	t	2
143	1	201000000027	201090000000	2026-04-01 17:00:00	1	3	EGYVO	\N	0.00	t	3
144	1	201000000027	201090000000	2026-04-01 17:30:00	251	1	EGYVO	\N	0.00	t	1
145	1	201000000027	201090000000	2026-04-01 18:00:00	71680	2	EGYVO	\N	1433.60	t	\N
146	1	201000000001	201090000000	2026-04-01 18:30:00	1	3	EGYVO	VODAFONE_UK	0.05	t	\N
147	1	201000000001	201090000000	2026-04-01 19:00:00	233	1	EGYVO	\N	0.00	t	1
148	1	201000000001	201090000000	2026-04-01 19:30:00	46080	2	EGYVO	\N	4608.00	t	\N
149	1	201000000001	201090000000	2026-04-01 20:00:00	1	3	EGYVO	VODAFONE_UK	0.05	t	\N
150	1	201000000042	201090000000	2026-04-01 20:30:00	142	1	EGYVO	\N	0.00	t	1
151	1	201000000042	201090000000	2026-04-01 21:00:00	71680	2	EGYVO	\N	7168.00	t	\N
152	1	201000000042	201090000000	2026-04-01 21:30:00	1	3	EGYVO	VODAFONE_UK	0.05	t	\N
153	1	201000000042	201090000000	2026-04-01 22:00:00	185	1	EGYVO	VODAFONE_UK	37.00	t	\N
154	1	201000000011	201090000000	2026-04-01 22:30:00	39936	2	EGYVO	\N	3993.60	t	\N
155	1	201000000011	201090000000	2026-04-01 23:00:00	1	3	EGYVO	\N	0.00	t	3
156	1	201000000011	201090000000	2026-04-01 23:30:00	315	1	EGYVO	VODAFONE_UK	63.00	t	\N
157	1	201000000011	201090000000	2026-04-02 00:00:00	30720	2	EGYVO	\N	3072.00	t	\N
158	1	201000000026	201090000000	2026-04-02 00:30:00	1	3	EGYVO	VODAFONE_UK	0.05	t	\N
159	1	201000000026	201090000000	2026-04-02 01:00:00	97	1	EGYVO	\N	0.00	t	1
160	1	201000000026	201090000000	2026-04-02 01:30:00	68608	2	EGYVO	\N	6860.80	t	\N
161	1	201000000026	201090000000	2026-04-02 02:00:00	1	3	EGYVO	\N	0.00	t	3
162	1	201000000034	201090000000	2026-04-02 02:30:00	203	1	EGYVO	\N	0.00	t	1
163	1	201000000034	201090000000	2026-04-02 03:00:00	49152	2	EGYVO	\N	4915.20	t	\N
164	1	201000000034	201090000000	2026-04-02 03:30:00	1	3	EGYVO	\N	0.00	t	3
165	1	201000000034	201090000000	2026-04-02 04:00:00	258	1	EGYVO	\N	0.00	t	1
166	1	201000000019	201090000000	2026-04-02 04:30:00	40960	2	EGYVO	VODAFONE_UK	1848.00	t	6
167	1	201000000019	201090000000	2026-04-02 05:00:00	1	3	EGYVO	\N	0.00	t	4
168	1	201000000019	201090000000	2026-04-02 05:30:00	162	1	EGYVO	\N	0.00	t	4
169	1	201000000019	201090000000	2026-04-02 06:00:00	54272	2	EGYVO	VODAFONE_UK	2713.60	t	\N
170	1	201000000014	201090000000	2026-04-02 06:30:00	1	3	EGYVO	\N	0.00	t	4
171	1	201000000014	201090000000	2026-04-02 07:00:00	32	1	EGYVO	\N	0.00	t	4
172	1	201000000014	201090000000	2026-04-02 07:30:00	8192	2	EGYVO	\N	0.00	t	4
173	1	201000000014	201090000000	2026-04-02 08:00:00	1	3	EGYVO	\N	0.00	t	4
174	1	201000000005	201090000000	2026-04-02 08:30:00	88	1	EGYVO	\N	0.00	t	1
175	1	201000000005	201090000000	2026-04-02 09:00:00	25600	2	EGYVO	\N	2560.00	t	\N
176	1	201000000005	201090000000	2026-04-02 09:30:00	1	3	EGYVO	\N	0.00	t	3
177	1	201000000005	201090000000	2026-04-02 10:00:00	97	1	EGYVO	VODAFONE_UK	19.40	t	\N
178	1	201000000004	201090000000	2026-04-02 10:30:00	64512	2	EGYVO	\N	2225.60	t	2
179	1	201000000004	201090000000	2026-04-02 11:00:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
180	1	201000000004	201090000000	2026-04-02 11:30:00	212	1	EGYVO	\N	0.00	t	1
181	1	201000000004	201090000000	2026-04-02 12:00:00	53248	2	EGYVO	\N	2662.40	t	\N
182	1	201000000023	201090000000	2026-04-02 12:30:00	1	3	EGYVO	\N	0.00	t	3
183	1	201000000023	201090000000	2026-04-02 13:00:00	107	1	EGYVO	\N	0.00	t	1
184	1	201000000023	201090000000	2026-04-02 13:30:00	78848	2	EGYVO	VODAFONE_UK	7884.80	t	\N
185	1	201000000023	201090000000	2026-04-02 14:00:00	1	3	EGYVO	\N	0.00	t	3
186	1	201000000002	201090000000	2026-04-02 14:30:00	238	1	EGYVO	\N	0.00	t	4
187	1	201000000002	201090000000	2026-04-02 15:00:00	73728	2	EGYVO	\N	2698.30	t	2
188	1	201000000002	201090000000	2026-04-02 15:30:00	1	3	EGYVO	\N	0.00	t	3
189	1	201000000002	201090000000	2026-04-02 16:00:00	252	1	EGYVO	\N	0.00	t	1
190	1	201000000036	201090000000	2026-04-02 16:30:00	72704	2	EGYVO	\N	7270.40	t	\N
191	1	201000000036	201090000000	2026-04-02 17:00:00	1	3	EGYVO	\N	0.00	t	3
192	1	201000000036	201090000000	2026-04-02 17:30:00	169	1	EGYVO	\N	0.00	t	1
1	1	201000000001	201000000002	2026-04-01 09:15:00	180	1	EGYVO	\N	36.00	t	\N
2	1	201000000001	201000000003	2026-04-01 14:30:00	1	3	EGYVO	\N	0.05	t	\N
3	1	201000000001	201000000005	2026-04-02 08:00:00	300	1	EGYVO	\N	60.00	t	\N
4	1	201000000001	201000000007	2026-04-03 11:20:00	1	3	EGYVO	\N	0.05	t	\N
5	1	201000000001	201000000009	2026-04-04 10:05:00	240	1	EGYVO	\N	48.00	t	\N
6	1	201000000001	201000000002	2026-04-05 16:45:00	1	3	EGYVO	\N	0.05	t	\N
7	1	201000000001	201000000011	2026-04-07 09:30:00	420	1	EGYVO	\N	84.00	t	\N
8	1	201000000001	201000000013	2026-04-08 13:00:00	1	3	EGYVO	\N	0.05	t	\N
9	1	201000000001	201000000015	2026-04-09 17:20:00	150	1	EGYVO	\N	30.00	t	\N
10	1	201000000001	201000000002	2026-04-10 08:45:00	360	1	EGYVO	\N	72.00	t	\N
11	1	201000000001	201000000003	2026-04-12 12:10:00	1	3	EGYVO	\N	0.05	t	\N
12	1	201000000001	201000000017	2026-04-14 15:30:00	210	1	EGYVO	\N	42.00	t	\N
13	1	201000000001	201000000004	2026-04-16 09:00:00	270	1	EGYVO	\N	54.00	t	\N
14	1	201000000001	201000000006	2026-04-18 14:00:00	1	3	EGYVO	\N	0.05	t	\N
15	1	201000000001	201000000008	2026-04-20 10:30:00	330	1	EGYVO	\N	66.00	t	\N
16	1	201000000002	201000000001	2026-04-01 08:30:00	300	1	EGYVO	\N	30.00	t	\N
17	1	201000000002	201000000004	2026-04-01 10:00:00	500	2	EGYVO	\N	25.00	t	\N
18	1	201000000002	201000000006	2026-04-01 12:00:00	1	3	EGYVO	\N	0.02	t	\N
19	1	201000000002	201000000008	2026-04-02 09:15:00	450	1	EGYVO	\N	45.00	t	\N
20	1	201000000002	201000000010	2026-04-02 14:30:00	750	2	EGYVO	\N	37.50	t	\N
21	1	201000000002	201000000012	2026-04-03 08:00:00	1	3	EGYVO	\N	0.02	t	\N
22	1	201000000002	201000000001	2026-04-04 11:45:00	600	1	EGYVO	\N	60.00	t	\N
23	1	201000000002	201000000014	2026-04-05 15:00:00	1000	2	EGYVO	\N	50.00	t	\N
24	1	201000000002	201000000016	2026-04-06 09:30:00	1	3	EGYVO	\N	0.02	t	\N
25	1	201000000002	201000000018	2026-04-07 13:20:00	480	1	EGYVO	\N	48.00	t	\N
26	1	201000000002	201000000001	2026-04-08 17:00:00	800	2	EGYVO	\N	40.00	t	\N
27	1	201000000002	201000000003	2026-04-09 10:15:00	1	3	EGYVO	\N	0.02	t	\N
28	2	201000000002	201000000001	2026-04-15 10:00:00	180	5	EGYVO	DEUTS	18.00	t	\N
29	2	201000000002	201000000004	2026-04-15 14:30:00	200	6	EGYVO	DEUTS	10.00	t	\N
30	2	201000000002	201000000006	2026-04-16 09:00:00	1	7	EGYVO	DEUTS	0.02	t	\N
31	2	201000000002	201000000008	2026-04-16 15:45:00	120	5	EGYVO	DEUTS	12.00	t	\N
32	2	201000000002	201000000001	2026-04-17 11:00:00	300	6	EGYVO	DEUTS	15.00	t	\N
33	1	201000000003	201000000001	2026-04-01 09:00:00	120	1	EGYVO	\N	24.00	t	\N
34	1	201000000003	201000000005	2026-04-02 11:30:00	1	3	EGYVO	\N	0.05	t	\N
35	1	201000000003	201000000007	2026-04-04 14:00:00	240	1	EGYVO	\N	48.00	t	\N
36	1	201000000003	201000000009	2026-04-06 16:30:00	1	3	EGYVO	\N	0.05	t	\N
37	1	201000000003	201000000001	2026-04-08 10:15:00	180	1	EGYVO	\N	36.00	t	\N
38	1	201000000003	201000000011	2026-04-10 13:45:00	90	1	EGYVO	\N	18.00	t	\N
39	1	201000000004	201000000002	2026-04-01 08:00:00	360	1	EGYVO	\N	36.00	t	\N
40	1	201000000004	201000000006	2026-04-01 13:00:00	600	2	EGYVO	\N	30.00	t	\N
41	1	201000000004	201000000008	2026-04-02 10:30:00	1	3	EGYVO	\N	0.02	t	\N
42	1	201000000004	201000000010	2026-04-03 15:00:00	420	1	EGYVO	\N	42.00	t	\N
43	1	201000000004	201000000012	2026-04-05 09:45:00	800	2	EGYVO	\N	40.00	t	\N
44	1	201000000004	201000000002	2026-04-07 14:00:00	1	3	EGYVO	\N	0.02	t	\N
45	1	201000000004	201000000014	2026-04-09 11:30:00	540	1	EGYVO	\N	54.00	t	\N
46	1	201000000004	201000000016	2026-04-11 16:00:00	700	2	EGYVO	\N	35.00	t	\N
47	1	201000000005	201000000001	2026-04-01 10:00:00	90	1	EGYVO	\N	18.00	t	\N
48	1	201000000005	201000000003	2026-04-03 12:30:00	1	3	EGYVO	\N	0.05	t	\N
49	1	201000000005	201000000007	2026-04-05 15:45:00	150	1	EGYVO	\N	30.00	t	\N
50	1	201000000005	201000000009	2026-04-08 09:00:00	1	3	EGYVO	\N	0.05	t	\N
51	1	201000000005	201000000001	2026-04-11 11:15:00	120	1	EGYVO	\N	24.00	t	\N
52	2	201000000006	201000000002	2026-04-01 09:30:00	540	1	EGYVO	\N	54.00	t	\N
53	2	201000000006	201000000008	2026-04-01 13:00:00	900	2	EGYVO	\N	45.00	t	\N
54	2	201000000006	201000000010	2026-04-02 08:15:00	1	3	EGYVO	\N	0.02	t	\N
55	2	201000000006	201000000012	2026-04-02 14:00:00	480	1	EGYVO	\N	48.00	t	\N
56	2	201000000006	201000000014	2026-04-03 10:30:00	1100	2	EGYVO	\N	55.00	t	\N
57	2	201000000006	201000000002	2026-04-04 15:45:00	1	3	EGYVO	\N	0.02	t	\N
58	2	201000000006	201000000016	2026-04-05 09:00:00	660	1	EGYVO	\N	66.00	t	\N
59	2	201000000006	201000000018	2026-04-06 12:30:00	850	2	EGYVO	\N	42.50	t	\N
60	2	201000000006	201000000002	2026-04-07 16:00:00	1	3	EGYVO	\N	0.02	t	\N
61	2	201000000006	201000000004	2026-04-08 10:15:00	720	1	EGYVO	\N	72.00	t	\N
62	2	201000000007	201000000001	2026-04-01 08:45:00	60	1	EGYVO	\N	12.00	t	\N
63	2	201000000007	201000000009	2026-04-03 13:30:00	1	3	EGYVO	\N	0.05	t	\N
64	2	201000000007	201000000011	2026-04-05 16:00:00	120	1	EGYVO	\N	24.00	t	\N
65	2	201000000007	201000000001	2026-04-08 10:00:00	180	1	EGYVO	\N	36.00	t	\N
66	2	201000000007	201000000003	2026-04-11 14:15:00	1	3	EGYVO	\N	0.05	t	\N
67	2	201000000007	201000000005	2026-04-14 09:30:00	240	1	EGYVO	\N	48.00	t	\N
68	2	201000000008	201000000002	2026-04-01 10:15:00	300	1	EGYVO	\N	30.00	t	\N
69	2	201000000008	201000000004	2026-04-02 12:00:00	650	2	EGYVO	\N	32.50	t	\N
70	2	201000000008	201000000006	2026-04-03 15:30:00	1	3	EGYVO	\N	0.02	t	\N
71	2	201000000008	201000000010	2026-04-04 09:00:00	420	1	EGYVO	\N	42.00	t	\N
72	2	201000000008	201000000012	2026-04-05 13:45:00	750	2	EGYVO	\N	37.50	t	\N
73	2	201000000008	201000000002	2026-04-07 11:00:00	1	3	EGYVO	\N	0.02	t	\N
74	2	201000000008	201000000014	2026-04-09 16:30:00	390	1	EGYVO	\N	39.00	t	\N
75	2	201000000009	201000000001	2026-04-01 11:00:00	180	1	EGYVO	\N	36.00	t	\N
76	2	201000000009	201000000003	2026-04-03 14:00:00	1	3	EGYVO	\N	0.05	t	\N
77	2	201000000009	201000000005	2026-04-06 09:30:00	150	1	EGYVO	\N	30.00	t	\N
78	2	201000000009	201000000007	2026-04-09 12:45:00	1	3	EGYVO	\N	0.05	t	\N
79	2	201000000010	201000000002	2026-04-01 09:45:00	360	1	EGYVO	\N	36.00	t	\N
80	2	201000000010	201000000004	2026-04-02 13:15:00	700	2	EGYVO	\N	35.00	t	\N
81	2	201000000010	201000000006	2026-04-03 16:00:00	1	3	EGYVO	\N	0.02	t	\N
82	2	201000000010	201000000008	2026-04-04 10:30:00	480	1	EGYVO	\N	48.00	t	\N
83	2	201000000010	201000000012	2026-04-05 14:00:00	900	2	EGYVO	\N	45.00	t	\N
84	2	201000000010	201000000002	2026-04-07 09:15:00	1	3	EGYVO	\N	0.02	t	\N
85	2	201000000010	201000000014	2026-04-09 15:45:00	540	1	EGYVO	\N	54.00	t	\N
86	2	201000000010	201000000016	2026-04-11 11:00:00	800	2	EGYVO	\N	40.00	t	\N
87	1	201000000011	201000000001	2026-04-01 08:00:00	600	1	EGYVO	\N	120.00	t	\N
88	1	201000000011	201000000003	2026-04-02 10:30:00	1	3	EGYVO	\N	0.05	t	\N
89	1	201000000011	201000000005	2026-04-03 14:15:00	480	1	EGYVO	\N	96.00	t	\N
90	1	201000000011	201000000007	2026-04-04 16:45:00	1	3	EGYVO	\N	0.05	t	\N
91	1	201000000011	201000000009	2026-04-05 09:30:00	540	1	EGYVO	\N	108.00	t	\N
92	1	201000000011	201000000001	2026-04-07 13:00:00	1	3	EGYVO	\N	0.05	t	\N
93	1	201000000011	201000000003	2026-04-09 10:15:00	420	1	EGYVO	\N	84.00	t	\N
94	1	201000000011	201000000005	2026-04-11 15:30:00	1	3	EGYVO	\N	0.05	t	\N
95	1	201000000012	201000000002	2026-04-01 11:30:00	270	1	EGYVO	\N	27.00	t	\N
96	1	201000000012	201000000004	2026-04-03 09:00:00	550	2	EGYVO	\N	27.50	t	\N
97	1	201000000012	201000000006	2026-04-05 13:45:00	1	3	EGYVO	\N	0.02	t	\N
98	1	201000000012	201000000008	2026-04-07 16:00:00	330	1	EGYVO	\N	33.00	t	\N
99	1	201000000014	201000000002	2026-04-01 09:00:00	390	1	EGYVO	\N	39.00	t	\N
100	1	201000000014	201000000004	2026-04-02 11:30:00	650	2	EGYVO	\N	32.50	t	\N
101	1	201000000014	201000000006	2026-04-03 14:00:00	1	3	EGYVO	\N	0.02	t	\N
102	1	201000000014	201000000008	2026-04-05 16:30:00	450	1	EGYVO	\N	45.00	t	\N
103	1	201000000014	201000000010	2026-04-07 10:15:00	700	2	EGYVO	\N	35.00	t	\N
104	1	201000000014	201000000002	2026-04-09 13:45:00	1	3	EGYVO	\N	0.02	t	\N
105	2	201000000015	201000000002	2026-04-01 08:00:00	480	1	EGYVO	\N	24.00	t	\N
106	2	201000000015	201000000004	2026-04-01 10:30:00	1200	2	EGYVO	\N	24.00	t	\N
107	2	201000000015	201000000006	2026-04-01 13:00:00	1	3	EGYVO	\N	0.01	t	\N
108	2	201000000015	201000000008	2026-04-02 09:00:00	600	1	EGYVO	\N	30.00	t	\N
109	2	201000000015	201000000010	2026-04-02 14:00:00	1500	2	EGYVO	\N	30.00	t	\N
110	2	201000000015	201000000012	2026-04-03 10:15:00	1	3	EGYVO	\N	0.01	t	\N
111	2	201000000015	201000000002	2026-04-04 15:30:00	720	1	EGYVO	\N	36.00	t	\N
112	2	201000000015	201000000016	2026-04-05 09:45:00	1800	2	EGYVO	\N	36.00	t	\N
113	2	201000000015	201000000002	2026-04-20 10:00:00	240	5	EGYVO	FRANC	12.00	t	\N
114	2	201000000015	201000000004	2026-04-20 14:30:00	400	6	EGYVO	FRANC	8.00	t	\N
115	2	201000000015	201000000006	2026-04-21 09:00:00	1	7	EGYVO	FRANC	0.01	t	\N
116	2	201000000016	201000000002	2026-04-01 09:30:00	600	1	EGYVO	\N	30.00	t	\N
117	2	201000000016	201000000004	2026-04-01 12:00:00	1400	2	EGYVO	\N	28.00	t	\N
118	2	201000000016	201000000006	2026-04-01 15:30:00	1	3	EGYVO	\N	0.01	t	\N
119	2	201000000016	201000000008	2026-04-02 08:30:00	780	1	EGYVO	\N	39.00	t	\N
120	2	201000000016	201000000010	2026-04-02 13:00:00	1600	2	EGYVO	\N	32.00	t	\N
121	2	201000000016	201000000012	2026-04-03 10:00:00	1	3	EGYVO	\N	0.01	t	\N
122	2	201000000016	201000000014	2026-04-03 16:00:00	840	1	EGYVO	\N	42.00	t	\N
123	2	201000000016	201000000002	2026-04-04 11:30:00	1800	2	EGYVO	\N	36.00	t	\N
124	2	201000000017	201000000002	2026-04-01 10:00:00	300	1	EGYVO	\N	30.00	t	\N
125	2	201000000017	201000000004	2026-04-02 12:30:00	600	2	EGYVO	\N	30.00	t	\N
126	2	201000000017	201000000006	2026-04-03 15:00:00	1	3	EGYVO	\N	0.02	t	\N
127	2	201000000017	201000000008	2026-04-05 09:30:00	420	1	EGYVO	\N	42.00	t	\N
128	2	201000000017	201000000010	2026-04-07 14:00:00	750	2	EGYVO	\N	37.50	t	\N
129	2	201000000017	201000000002	2026-04-09 11:15:00	1	3	EGYVO	\N	0.02	t	\N
193	1	201000000036	201090000000	2026-04-02 18:00:00	32768	2	EGYVO	\N	3276.80	t	\N
194	1	201000000022	201090000000	2026-04-02 18:30:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
195	1	201000000022	201090000000	2026-04-02 19:00:00	253	1	EGYVO	VODAFONE_UK	5.30	t	5
196	1	201000000022	201090000000	2026-04-02 19:30:00	37888	2	EGYVO	\N	0.00	t	2
197	1	201000000022	201090000000	2026-04-02 20:00:00	1	3	EGYVO	\N	0.00	t	3
198	1	201000000007	201090000000	2026-04-02 20:30:00	135	1	EGYVO	\N	0.00	t	1
199	1	201000000007	201090000000	2026-04-02 21:00:00	82944	2	EGYVO	\N	8294.40	t	\N
200	1	201000000007	201090000000	2026-04-02 21:30:00	1	3	EGYVO	\N	0.00	t	3
201	1	201000000007	201090000000	2026-04-02 22:00:00	42	1	EGYVO	\N	0.00	t	1
202	1	201000000009	201090000000	2026-04-02 22:30:00	38912	2	EGYVO	\N	3891.20	t	\N
203	1	201000000009	201090000000	2026-04-02 23:00:00	1	3	EGYVO	\N	0.00	t	3
204	1	201000000009	201090000000	2026-04-02 23:30:00	160	1	EGYVO	VODAFONE_UK	32.00	t	\N
205	1	201000000009	201090000000	2026-04-03 00:00:00	6144	2	EGYVO	\N	614.40	t	\N
206	1	201000000033	201090000000	2026-04-03 00:30:00	1	3	EGYVO	\N	0.00	t	3
207	1	201000000033	201090000000	2026-04-03 01:00:00	259	1	EGYVO	\N	0.00	t	1
208	1	201000000033	201090000000	2026-04-03 01:30:00	92160	2	EGYVO	\N	9216.00	t	\N
209	1	201000000033	201090000000	2026-04-03 02:00:00	1	3	EGYVO	\N	0.00	t	3
210	1	201000000040	201090000000	2026-04-03 02:30:00	198	1	EGYVO	\N	0.00	t	1
211	1	201000000040	201090000000	2026-04-03 03:00:00	92160	2	EGYVO	\N	9216.00	t	\N
212	1	201000000040	201090000000	2026-04-03 03:30:00	1	3	EGYVO	\N	0.00	t	3
213	1	201000000040	201090000000	2026-04-03 04:00:00	151	1	EGYVO	\N	0.00	t	1
314	1	2010105100	201090000000	2026-04-01 10:20:00	75776	2	EGYVO	\N	6577.60	t	4
315	1	2010105100	201090000000	2026-04-01 10:40:00	1	3	EGYVO	\N	0.00	t	3
316	1	2010105100	201090000000	2026-04-01 11:00:00	314	1	EGYVO	VODAFONE_UK	62.80	t	\N
317	1	2010105100	201090000000	2026-04-01 11:20:00	46080	2	EGYVO	\N	4608.00	t	\N
318	1	2010105099	201090000000	2026-04-01 11:40:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
319	1	2010105099	201090000000	2026-04-01 12:00:00	316	1	EGYVO	\N	0.00	t	4
320	1	2010105099	201090000000	2026-04-01 12:20:00	71680	2	EGYVO	\N	2599.80	t	2
321	1	2010105099	201090000000	2026-04-01 12:40:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
322	1	2010105096	201090000000	2026-04-01 13:00:00	183	1	EGYVO	VODAFONE_UK	8.30	t	5
323	1	2010105096	201090000000	2026-04-01 13:20:00	83968	2	EGYVO	\N	3198.40	t	2
214	1	201000000037	201090000000	2026-04-03 04:30:00	72704	2	EGYVO	\N	7270.40	t	\N
215	1	201000000037	201090000000	2026-04-03 05:00:00	1	3	EGYVO	\N	0.00	t	3
216	1	201000000037	201090000000	2026-04-03 05:30:00	38	1	EGYVO	\N	0.00	t	1
217	1	201000000037	201090000000	2026-04-03 06:00:00	78848	2	EGYVO	\N	7884.80	t	\N
218	1	201000000030	201090000000	2026-04-03 06:30:00	1	3	EGYVO	\N	0.00	t	3
219	1	201000000030	201090000000	2026-04-03 07:00:00	252	1	EGYVO	VODAFONE_UK	50.40	t	\N
220	1	201000000030	201090000000	2026-04-03 07:30:00	81920	2	EGYVO	\N	8192.00	t	\N
221	1	201000000030	201090000000	2026-04-03 08:00:00	1	3	EGYVO	\N	0.00	t	3
222	1	201000000028	201090000000	2026-04-03 08:30:00	130	1	EGYVO	VODAFONE_UK	0.00	t	5
223	1	201000000028	201090000000	2026-04-03 09:00:00	47104	2	EGYVO	\N	355.20	t	2
224	1	201000000028	201090000000	2026-04-03 09:30:00	1	3	EGYVO	\N	0.00	t	3
225	1	201000000028	201090000000	2026-04-03 10:00:00	92	1	EGYVO	\N	0.00	t	1
226	1	201000000048	201090000000	2026-04-03 10:30:00	47104	2	EGYVO	\N	355.20	t	2
227	1	201000000048	201090000000	2026-04-03 11:00:00	1	3	EGYVO	\N	0.00	t	3
228	1	201000000048	201090000000	2026-04-03 11:30:00	102	1	EGYVO	\N	0.00	t	1
229	1	201000000048	201090000000	2026-04-03 12:00:00	55296	2	EGYVO	VODAFONE_UK	2564.80	t	6
230	1	201000000032	201090000000	2026-04-03 12:30:00	1	3	EGYVO	\N	0.00	t	3
231	1	201000000032	201090000000	2026-04-03 13:00:00	323	1	EGYVO	\N	0.00	t	1
232	1	201000000032	201090000000	2026-04-03 13:30:00	100352	2	EGYVO	\N	10035.20	t	\N
233	1	201000000032	201090000000	2026-04-03 14:00:00	1	3	EGYVO	\N	0.00	t	3
234	1	201000000020	201090000000	2026-04-03 14:30:00	327	1	EGYVO	\N	0.00	t	1
235	1	201000000020	201090000000	2026-04-03 15:00:00	41984	2	EGYVO	VODAFONE_UK	4198.40	t	\N
236	1	201000000020	201090000000	2026-04-03 15:30:00	1	3	EGYVO	\N	0.00	t	3
237	1	201000000020	201090000000	2026-04-03 16:00:00	190	1	EGYVO	\N	0.00	t	1
238	1	201000000015	201090000000	2026-04-03 16:30:00	23552	2	EGYVO	\N	71.04	t	2
239	1	201000000015	201090000000	2026-04-03 17:00:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
240	1	201000000015	201090000000	2026-04-03 17:30:00	224	1	EGYVO	\N	0.00	t	1
241	1	201000000015	201090000000	2026-04-03 18:00:00	101376	2	EGYVO	\N	2027.52	t	\N
242	1	201000000006	201090000000	2026-04-03 18:30:00	1	3	EGYVO	\N	0.00	t	4
243	1	201000000006	201090000000	2026-04-03 19:00:00	187	1	EGYVO	\N	0.00	t	4
244	1	201000000006	201090000000	2026-04-03 19:30:00	96256	2	EGYVO	\N	3822.20	t	2
245	1	201000000006	201090000000	2026-04-03 20:00:00	1	3	EGYVO	\N	0.00	t	3
246	1	201000000038	201090000000	2026-04-03 20:30:00	235	1	EGYVO	VODAFONE_UK	47.00	t	\N
247	1	201000000038	201090000000	2026-04-03 21:00:00	83968	2	EGYVO	\N	8396.80	t	\N
248	1	201000000038	201090000000	2026-04-03 21:30:00	1	3	EGYVO	\N	0.00	t	3
249	1	201000000038	201090000000	2026-04-03 22:00:00	242	1	EGYVO	\N	0.00	t	1
250	1	201000000003	201090000000	2026-04-03 22:30:00	35840	2	EGYVO	\N	3584.00	t	\N
251	1	201000000003	201090000000	2026-04-03 23:00:00	1	3	EGYVO	\N	0.00	t	3
252	1	201000000003	201090000000	2026-04-03 23:30:00	174	1	EGYVO	VODAFONE_UK	34.80	t	\N
253	1	201000000003	201090000000	2026-04-04 00:00:00	15360	2	EGYVO	\N	1536.00	t	\N
254	1	201000000024	201090000000	2026-04-04 00:30:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
255	1	201000000024	201090000000	2026-04-04 01:00:00	108	1	EGYVO	VODAFONE_UK	0.00	t	5
256	1	201000000024	201090000000	2026-04-04 01:30:00	26624	2	EGYVO	\N	0.00	t	2
257	1	201000000024	201090000000	2026-04-04 02:00:00	1	3	EGYVO	\N	0.00	t	3
258	1	201000000035	201090000000	2026-04-04 02:30:00	197	1	EGYVO	VODAFONE_UK	0.00	t	5
259	1	201000000035	201090000000	2026-04-04 03:00:00	41984	2	EGYVO	\N	99.20	t	2
260	1	201000000035	201090000000	2026-04-04 03:30:00	1	3	EGYVO	\N	0.00	t	3
261	1	201000000035	201090000000	2026-04-04 04:00:00	52	1	EGYVO	\N	0.00	t	1
262	1	201000000016	201090000000	2026-04-04 04:30:00	77824	2	EGYVO	\N	1156.48	t	2
263	1	201000000016	201090000000	2026-04-04 05:00:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
264	1	201000000016	201090000000	2026-04-04 05:30:00	264	1	EGYVO	\N	0.00	t	1
265	1	201000000016	201090000000	2026-04-04 06:00:00	43008	2	EGYVO	\N	860.16	t	\N
266	1	201000000046	201090000000	2026-04-04 06:30:00	1	3	EGYVO	\N	0.00	t	3
267	1	201000000046	201090000000	2026-04-04 07:00:00	251	1	EGYVO	\N	0.00	t	1
268	1	201000000046	201090000000	2026-04-04 07:30:00	73728	2	EGYVO	\N	7372.80	t	\N
269	1	201000000046	201090000000	2026-04-04 08:00:00	1	3	EGYVO	\N	0.00	t	3
270	1	201000000010	201090000000	2026-04-04 08:30:00	32	1	EGYVO	\N	0.00	t	4
271	1	201000000010	201090000000	2026-04-04 09:00:00	41984	2	EGYVO	\N	1100.80	t	2
272	1	201000000010	201090000000	2026-04-04 09:30:00	1	3	EGYVO	\N	0.00	t	3
273	1	201000000010	201090000000	2026-04-04 10:00:00	227	1	EGYVO	VODAFONE_UK	12.70	t	5
274	1	201000000031	201090000000	2026-04-04 10:30:00	29696	2	EGYVO	\N	0.00	t	2
275	1	201000000031	201090000000	2026-04-04 11:00:00	1	3	EGYVO	\N	0.00	t	3
276	1	201000000031	201090000000	2026-04-04 11:30:00	144	1	EGYVO	\N	0.00	t	1
277	1	201000000031	201090000000	2026-04-04 12:00:00	51200	2	EGYVO	\N	2044.80	t	2
278	1	201000000008	201090000000	2026-04-04 12:30:00	1	3	EGYVO	\N	0.00	t	4
279	1	201000000008	201090000000	2026-04-04 13:00:00	131	1	EGYVO	\N	0.00	t	4
280	1	201000000008	201090000000	2026-04-04 13:30:00	63488	2	EGYVO	\N	2181.00	t	2
281	1	201000000008	201090000000	2026-04-04 14:00:00	1	3	EGYVO	\N	0.00	t	3
282	1	201000000012	201090000000	2026-04-04 14:30:00	110	1	EGYVO	\N	0.00	t	4
283	1	201000000012	201090000000	2026-04-04 15:00:00	47104	2	EGYVO	VODAFONE_UK	2255.20	t	6
284	1	201000000012	201090000000	2026-04-04 15:30:00	1	3	EGYVO	\N	0.00	t	4
285	1	201000000012	201090000000	2026-04-04 16:00:00	238	1	EGYVO	\N	0.00	t	4
286	1	201000000025	201090000000	2026-04-04 16:30:00	25600	2	EGYVO	\N	0.00	t	2
287	1	201000000025	201090000000	2026-04-04 17:00:00	1	3	EGYVO	\N	0.00	t	3
288	1	201000000025	201090000000	2026-04-04 17:30:00	306	1	EGYVO	\N	0.00	t	1
289	1	201000000025	201090000000	2026-04-04 18:00:00	102400	2	EGYVO	\N	1760.00	t	2
290	1	201000000017	201090000000	2026-04-04 18:30:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
291	1	201000000017	201090000000	2026-04-04 19:00:00	234	1	EGYVO	\N	0.00	t	4
292	1	201000000017	201090000000	2026-04-04 19:30:00	62464	2	EGYVO	\N	2134.90	t	2
293	1	201000000017	201090000000	2026-04-04 20:00:00	1	3	EGYVO	\N	0.00	t	3
294	1	201000000039	201090000000	2026-04-04 20:30:00	307	1	EGYVO	VODAFONE_UK	61.40	t	\N
295	1	201000000039	201090000000	2026-04-04 21:00:00	62464	2	EGYVO	\N	6246.40	t	\N
296	1	201000000039	201090000000	2026-04-04 21:30:00	1	3	EGYVO	\N	0.00	t	3
297	1	201000000039	201090000000	2026-04-04 22:00:00	282	1	EGYVO	VODAFONE_UK	56.40	t	\N
298	1	201000000043	201090000000	2026-04-04 22:30:00	23552	2	EGYVO	\N	0.00	t	2
299	1	201000000043	201090000000	2026-04-04 23:00:00	1	3	EGYVO	\N	0.00	t	3
300	1	201000000043	201090000000	2026-04-04 23:30:00	58	1	EGYVO	VODAFONE_UK	0.00	t	5
301	1	201000000043	201090000000	2026-04-05 00:00:00	59392	2	EGYVO	\N	858.88	t	2
302	1	201000000029	201090000000	2026-04-05 00:30:00	1	3	EGYVO	\N	0.00	t	4
303	1	201000000029	201090000000	2026-04-05 01:00:00	326	1	EGYVO	\N	0.00	t	4
304	1	201000000029	201090000000	2026-04-05 01:30:00	82944	2	EGYVO	\N	865.42	t	2
305	1	201000000029	201090000000	2026-04-05 02:00:00	1	3	EGYVO	\N	0.00	t	3
306	1	201000000045	201090000000	2026-04-05 02:30:00	59	1	EGYVO	\N	0.00	t	4
307	1	201000000045	201090000000	2026-04-05 03:00:00	24576	2	EGYVO	\N	0.00	t	2
308	1	201000000045	201090000000	2026-04-05 03:30:00	1	3	EGYVO	\N	0.00	t	3
309	1	201000000045	201090000000	2026-04-05 04:00:00	140	1	EGYVO	\N	0.00	t	1
310	1	201000000021	201090000000	2026-04-05 04:30:00	96256	2	EGYVO	\N	1125.12	t	2
311	1	201000000021	201090000000	2026-04-05 05:00:00	1	3	EGYVO	\N	0.00	t	3
312	1	201000000021	201090000000	2026-04-05 05:30:00	319	1	EGYVO	\N	0.00	t	1
313	1	201000000021	201090000000	2026-04-05 06:00:00	7168	2	EGYVO	\N	143.36	t	\N
324	1	2010105096	201090000000	2026-04-01 13:40:00	1	3	EGYVO	\N	0.00	t	3
325	1	2010105096	201090000000	2026-04-01 14:00:00	169	1	EGYVO	\N	0.00	t	1
326	1	2010105095	201090000000	2026-04-01 14:20:00	87040	2	EGYVO	\N	3352.00	t	2
327	1	2010105095	201090000000	2026-04-01 14:40:00	1	3	EGYVO	\N	0.00	t	3
328	1	2010105095	201090000000	2026-04-01 15:00:00	97	1	EGYVO	\N	0.00	t	1
329	1	2010105095	201090000000	2026-04-01 15:20:00	39936	2	EGYVO	\N	1996.80	t	\N
330	1	2010105092	201090000000	2026-04-01 15:40:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
331	1	2010105092	201090000000	2026-04-01 16:00:00	293	1	EGYVO	\N	0.00	t	4
332	1	2010105092	201090000000	2026-04-01 16:20:00	70656	2	EGYVO	\N	2547.45	t	2
333	1	2010105092	201090000000	2026-04-01 16:40:00	1	3	EGYVO	\N	0.00	t	3
334	1	2010105090	201090000000	2026-04-01 17:00:00	152	1	EGYVO	\N	0.00	t	4
335	1	2010105090	201090000000	2026-04-01 17:20:00	50176	2	EGYVO	\N	1016.40	t	2
336	1	2010105090	201090000000	2026-04-01 17:40:00	1	3	EGYVO	\N	0.00	t	3
337	1	2010105090	201090000000	2026-04-01 18:00:00	119	1	EGYVO	\N	0.00	t	1
338	1	2010105087	201090000000	2026-04-01 18:20:00	83968	2	EGYVO	\N	3198.40	t	2
339	1	2010105087	201090000000	2026-04-01 18:40:00	1	3	EGYVO	\N	0.00	t	3
340	1	2010105087	201090000000	2026-04-01 19:00:00	152	1	EGYVO	\N	0.00	t	1
341	1	2010105087	201090000000	2026-04-01 19:20:00	28672	2	EGYVO	\N	1433.60	t	\N
342	1	2010105086	201090000000	2026-04-01 19:40:00	1	3	EGYVO	\N	0.00	t	4
343	1	2010105086	201090000000	2026-04-01 20:00:00	195	1	EGYVO	\N	0.00	t	4
344	1	2010105086	201090000000	2026-04-01 20:20:00	73728	2	EGYVO	\N	878.48	t	2
345	1	2010105086	201090000000	2026-04-01 20:40:00	1	3	EGYVO	\N	0.00	t	3
346	1	2010105085	201090000000	2026-04-01 21:00:00	245	1	EGYVO	\N	0.00	t	1
347	1	2010105085	201090000000	2026-04-01 21:20:00	59392	2	EGYVO	\N	5939.20	t	\N
348	1	2010105085	201090000000	2026-04-01 21:40:00	1	3	EGYVO	\N	0.00	t	3
349	1	2010105085	201090000000	2026-04-01 22:00:00	289	1	EGYVO	\N	0.00	t	1
350	1	2010105084	201090000000	2026-04-01 22:20:00	87040	2	EGYVO	\N	7704.00	t	4
351	1	2010105084	201090000000	2026-04-01 22:40:00	1	3	EGYVO	\N	0.00	t	3
352	1	2010105084	201090000000	2026-04-01 23:00:00	242	1	EGYVO	VODAFONE_UK	48.40	t	\N
353	1	2010105084	201090000000	2026-04-01 23:20:00	74752	2	EGYVO	\N	7475.20	t	\N
354	1	2010105080	201090000000	2026-04-01 23:40:00	1	3	EGYVO	\N	0.00	t	4
355	1	2010105080	201090000000	2026-04-02 00:00:00	85	1	EGYVO	\N	0.00	t	4
356	1	2010105080	201090000000	2026-04-02 00:20:00	88064	2	EGYVO	\N	2907.50	t	2
357	1	2010105080	201090000000	2026-04-02 00:40:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
358	1	2010105079	201090000000	2026-04-02 01:00:00	276	1	EGYVO	\N	0.00	t	4
359	1	2010105079	201090000000	2026-04-02 01:20:00	62464	2	EGYVO	\N	2137.00	t	2
360	1	2010105079	201090000000	2026-04-02 01:40:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
361	1	2010105079	201090000000	2026-04-02 02:00:00	64	1	EGYVO	\N	0.00	t	1
362	1	2010105077	201090000000	2026-04-02 02:20:00	90112	2	EGYVO	\N	8011.20	t	4
363	1	2010105077	201090000000	2026-04-02 02:40:00	1	3	EGYVO	\N	0.00	t	3
364	1	2010105077	201090000000	2026-04-02 03:00:00	71	1	EGYVO	\N	0.00	t	1
365	1	2010105077	201090000000	2026-04-02 03:20:00	30720	2	EGYVO	\N	3072.00	t	\N
366	1	2010105076	201090000000	2026-04-02 03:40:00	1	3	EGYVO	\N	0.00	t	4
367	1	2010105076	201090000000	2026-04-02 04:00:00	246	1	EGYVO	\N	0.00	t	4
368	1	2010105076	201090000000	2026-04-02 04:20:00	36864	2	EGYVO	\N	855.55	t	2
369	1	2010105076	201090000000	2026-04-02 04:40:00	1	3	EGYVO	\N	0.00	t	3
370	1	2010105075	201090000000	2026-04-02 05:00:00	178	1	EGYVO	VODAFONE_UK	7.80	t	5
371	1	2010105075	201090000000	2026-04-02 05:20:00	29696	2	EGYVO	\N	0.00	t	2
372	1	2010105075	201090000000	2026-04-02 05:40:00	1	3	EGYVO	\N	0.00	t	3
373	1	2010105075	201090000000	2026-04-02 06:00:00	250	1	EGYVO	VODAFONE_UK	25.00	t	\N
374	1	2010105072	201090000000	2026-04-02 06:20:00	67584	2	EGYVO	\N	6758.40	t	\N
375	1	2010105072	201090000000	2026-04-02 06:40:00	1	3	EGYVO	\N	0.00	t	3
376	1	2010105072	201090000000	2026-04-02 07:00:00	182	1	EGYVO	\N	0.00	t	1
377	1	2010105072	201090000000	2026-04-02 07:20:00	18432	2	EGYVO	\N	1843.20	t	\N
378	1	2010105071	201090000000	2026-04-02 07:40:00	1	3	EGYVO	\N	0.00	t	4
379	1	2010105071	201090000000	2026-04-02 08:00:00	326	1	EGYVO	\N	0.00	t	4
380	1	2010105071	201090000000	2026-04-02 08:20:00	16384	2	EGYVO	\N	0.00	t	4
381	1	2010105071	201090000000	2026-04-02 08:40:00	1	3	EGYVO	\N	0.00	t	4
382	1	2010105069	201090000000	2026-04-02 09:00:00	122	1	EGYVO	\N	0.00	t	4
383	1	2010105069	201090000000	2026-04-02 09:20:00	60416	2	EGYVO	\N	2026.90	t	2
384	1	2010105069	201090000000	2026-04-02 09:40:00	1	3	EGYVO	\N	0.00	t	3
385	1	2010105069	201090000000	2026-04-02 10:00:00	96	1	EGYVO	\N	0.00	t	1
386	1	2010105068	201090000000	2026-04-02 10:20:00	65536	2	EGYVO	\N	2276.80	t	2
387	1	2010105068	201090000000	2026-04-02 10:40:00	1	3	EGYVO	\N	0.00	t	3
388	1	2010105068	201090000000	2026-04-02 11:00:00	183	1	EGYVO	\N	0.00	t	1
389	1	2010105068	201090000000	2026-04-02 11:20:00	44032	2	EGYVO	\N	2201.60	t	\N
390	1	2010105065	201090000000	2026-04-02 11:40:00	1	3	EGYVO	\N	0.00	t	4
391	1	2010105065	201090000000	2026-04-02 12:00:00	177	1	EGYVO	\N	0.00	t	4
392	1	2010105065	201090000000	2026-04-02 12:20:00	98304	2	EGYVO	\N	3424.10	t	2
393	1	2010105065	201090000000	2026-04-02 12:40:00	1	3	EGYVO	\N	0.00	t	3
394	1	2010105064	201090000000	2026-04-02 13:00:00	135	1	EGYVO	\N	0.00	t	1
395	1	2010105064	201090000000	2026-04-02 13:20:00	55296	2	EGYVO	\N	5529.60	t	\N
396	1	2010105064	201090000000	2026-04-02 13:40:00	1	3	EGYVO	\N	0.00	t	3
397	1	2010105064	201090000000	2026-04-02 14:00:00	297	1	EGYVO	\N	0.00	t	1
398	1	2010105063	201090000000	2026-04-02 14:20:00	81920	2	EGYVO	\N	7192.00	t	4
399	1	2010105063	201090000000	2026-04-02 14:40:00	1	3	EGYVO	\N	0.00	t	3
400	1	2010105063	201090000000	2026-04-02 15:00:00	70	1	EGYVO	\N	0.00	t	1
401	1	2010105063	201090000000	2026-04-02 15:20:00	94208	2	EGYVO	\N	9420.80	t	\N
402	1	2010105062	201090000000	2026-04-02 15:40:00	1	3	EGYVO	\N	0.00	t	3
403	1	2010105062	201090000000	2026-04-02 16:00:00	132	1	EGYVO	\N	0.00	t	1
404	1	2010105062	201090000000	2026-04-02 16:20:00	66560	2	EGYVO	VODAFONE_UK	6656.00	t	\N
405	1	2010105062	201090000000	2026-04-02 16:40:00	1	3	EGYVO	\N	0.00	t	3
406	1	2010105061	201090000000	2026-04-02 17:00:00	270	1	EGYVO	\N	0.00	t	4
407	1	2010105061	201090000000	2026-04-02 17:20:00	24576	2	EGYVO	VODAFONE_UK	2457.60	t	\N
408	1	2010105061	201090000000	2026-04-02 17:40:00	1	3	EGYVO	\N	0.00	t	4
409	1	2010105061	201090000000	2026-04-02 18:00:00	281	1	EGYVO	VODAFONE_UK	56.20	t	\N
410	1	2010105059	201090000000	2026-04-02 18:20:00	96256	2	EGYVO	VODAFONE_UK	9625.60	t	\N
411	1	2010105059	201090000000	2026-04-02 18:40:00	1	3	EGYVO	\N	0.00	t	4
412	1	2010105059	201090000000	2026-04-02 19:00:00	256	1	EGYVO	\N	0.00	t	4
413	1	2010105059	201090000000	2026-04-02 19:20:00	87040	2	EGYVO	\N	7729.70	t	4
414	1	2010105057	201090000000	2026-04-02 19:40:00	1	3	EGYVO	\N	0.00	t	4
415	1	2010105057	201090000000	2026-04-02 20:00:00	64	1	EGYVO	\N	0.00	t	4
416	1	2010105057	201090000000	2026-04-02 20:20:00	67584	2	EGYVO	VODAFONE_UK	3279.20	t	6
417	1	2010105057	201090000000	2026-04-02 20:40:00	1	3	EGYVO	\N	0.00	t	4
418	1	2010105056	201090000000	2026-04-02 21:00:00	107	1	EGYVO	\N	0.00	t	4
419	1	2010105056	201090000000	2026-04-02 21:20:00	84992	2	EGYVO	\N	2754.95	t	2
420	1	2010105056	201090000000	2026-04-02 21:40:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
421	1	2010105056	201090000000	2026-04-02 22:00:00	234	1	EGYVO	\N	0.00	t	1
422	1	2010105055	201090000000	2026-04-02 22:20:00	82944	2	EGYVO	\N	7294.40	t	4
423	1	2010105055	201090000000	2026-04-02 22:40:00	1	3	EGYVO	\N	0.00	t	3
424	1	2010105055	201090000000	2026-04-02 23:00:00	45	1	EGYVO	\N	0.00	t	1
425	1	2010105055	201090000000	2026-04-02 23:20:00	38912	2	EGYVO	\N	3891.20	t	\N
426	1	2010105054	201090000000	2026-04-02 23:40:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
427	1	2010105054	201090000000	2026-04-03 00:00:00	328	1	EGYVO	\N	0.00	t	4
428	1	2010105054	201090000000	2026-04-03 00:20:00	90112	2	EGYVO	VODAFONE_UK	4405.60	t	6
429	1	2010105054	201090000000	2026-04-03 00:40:00	1	3	EGYVO	\N	0.00	t	4
430	1	2010105053	201090000000	2026-04-03 01:00:00	68	1	EGYVO	VODAFONE_UK	0.00	t	5
431	1	2010105053	201090000000	2026-04-03 01:20:00	87040	2	EGYVO	\N	1340.80	t	2
432	1	2010105053	201090000000	2026-04-03 01:40:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
433	1	2010105053	201090000000	2026-04-03 02:00:00	33	1	EGYVO	\N	0.00	t	1
434	1	2010105052	201090000000	2026-04-03 02:20:00	8192	2	EGYVO	VODAFONE_UK	123.84	t	6
435	1	2010105052	201090000000	2026-04-03 02:40:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
436	1	2010105052	201090000000	2026-04-03 03:00:00	229	1	EGYVO	VODAFONE_UK	6.45	t	5
437	1	2010105052	201090000000	2026-04-03 03:20:00	89088	2	EGYVO	\N	1381.76	t	2
438	1	2010105051	201090000000	2026-04-03 03:40:00	1	3	EGYVO	\N	0.00	t	4
439	1	2010105051	201090000000	2026-04-03 04:00:00	200	1	EGYVO	\N	0.00	t	4
440	1	2010105051	201090000000	2026-04-03 04:20:00	51200	2	EGYVO	\N	1070.05	t	2
441	1	2010105051	201090000000	2026-04-03 04:40:00	1	3	EGYVO	\N	0.00	t	3
442	1	2010105049	201090000000	2026-04-03 05:00:00	149	1	EGYVO	\N	0.00	t	1
443	1	2010105049	201090000000	2026-04-03 05:20:00	78848	2	EGYVO	\N	7884.80	t	\N
444	1	2010105049	201090000000	2026-04-03 05:40:00	1	3	EGYVO	\N	0.00	t	3
445	1	2010105049	201090000000	2026-04-03 06:00:00	152	1	EGYVO	\N	0.00	t	1
446	1	2010105045	201090000000	2026-04-03 06:20:00	44032	2	EGYVO	\N	3403.20	t	4
447	1	2010105045	201090000000	2026-04-03 06:40:00	1	3	EGYVO	\N	0.00	t	3
448	1	2010105045	201090000000	2026-04-03 07:00:00	177	1	EGYVO	\N	0.00	t	1
449	1	2010105045	201090000000	2026-04-03 07:20:00	59392	2	EGYVO	\N	5939.20	t	\N
450	1	2010105044	201090000000	2026-04-03 07:40:00	1	3	EGYVO	\N	0.00	t	4
451	1	2010105044	201090000000	2026-04-03 08:00:00	95	1	EGYVO	\N	0.00	t	4
452	1	2010105044	201090000000	2026-04-03 08:20:00	63488	2	EGYVO	\N	1679.20	t	2
453	1	2010105044	201090000000	2026-04-03 08:40:00	1	3	EGYVO	\N	0.00	t	3
454	1	2010105043	201090000000	2026-04-03 09:00:00	291	1	EGYVO	\N	0.00	t	1
455	1	2010105043	201090000000	2026-04-03 09:20:00	72704	2	EGYVO	\N	7270.40	t	\N
456	1	2010105043	201090000000	2026-04-03 09:40:00	1	3	EGYVO	\N	0.00	t	3
457	1	2010105043	201090000000	2026-04-03 10:00:00	277	1	EGYVO	\N	0.00	t	1
458	1	2010105042	201090000000	2026-04-03 10:20:00	32768	2	EGYVO	\N	638.40	t	2
459	1	2010105042	201090000000	2026-04-03 10:40:00	1	3	EGYVO	\N	0.00	t	3
460	1	2010105042	201090000000	2026-04-03 11:00:00	104	1	EGYVO	\N	0.00	t	1
461	1	2010105042	201090000000	2026-04-03 11:20:00	19456	2	EGYVO	VODAFONE_UK	872.80	t	6
462	1	2010105041	201090000000	2026-04-03 11:40:00	1	3	EGYVO	\N	0.00	t	4
463	1	2010105041	201090000000	2026-04-03 12:00:00	52	1	EGYVO	\N	0.00	t	4
464	1	2010105041	201090000000	2026-04-03 12:20:00	48128	2	EGYVO	\N	563.62	t	2
465	1	2010105041	201090000000	2026-04-03 12:40:00	1	3	EGYVO	\N	0.00	t	3
466	1	2010105040	201090000000	2026-04-03 13:00:00	105	1	EGYVO	\N	0.00	t	4
467	1	2010105040	201090000000	2026-04-03 13:20:00	83968	2	EGYVO	\N	2703.65	t	2
468	1	2010105040	201090000000	2026-04-03 13:40:00	1	3	EGYVO	\N	0.00	t	3
469	1	2010105040	201090000000	2026-04-03 14:00:00	327	1	EGYVO	\N	0.00	t	1
470	1	2010105038	201090000000	2026-04-03 14:20:00	93184	2	EGYVO	\N	3659.20	t	2
471	1	2010105038	201090000000	2026-04-03 14:40:00	1	3	EGYVO	\N	0.00	t	3
472	1	2010105038	201090000000	2026-04-03 15:00:00	49	1	EGYVO	\N	0.00	t	1
473	1	2010105038	201090000000	2026-04-03 15:20:00	83968	2	EGYVO	\N	4198.40	t	\N
474	1	2010105037	201090000000	2026-04-03 15:40:00	1	3	EGYVO	\N	0.00	t	4
475	1	2010105037	201090000000	2026-04-03 16:00:00	93	1	EGYVO	\N	0.00	t	4
476	1	2010105037	201090000000	2026-04-03 16:20:00	24576	2	EGYVO	\N	1467.00	t	4
477	1	2010105037	201090000000	2026-04-03 16:40:00	1	3	EGYVO	\N	0.00	t	3
478	1	2010105035	201090000000	2026-04-03 17:00:00	292	1	EGYVO	\N	0.00	t	4
479	1	2010105035	201090000000	2026-04-03 17:20:00	10240	2	EGYVO	\N	53.20	t	4
480	1	2010105035	201090000000	2026-04-03 17:40:00	1	3	EGYVO	\N	0.00	t	3
481	1	2010105035	201090000000	2026-04-03 18:00:00	145	1	EGYVO	\N	0.00	t	1
482	1	2010105034	201090000000	2026-04-03 18:20:00	97280	2	EGYVO	\N	1345.60	t	2
483	1	2010105034	201090000000	2026-04-03 18:40:00	1	3	EGYVO	\N	0.00	t	3
484	1	2010105034	201090000000	2026-04-03 19:00:00	209	1	EGYVO	\N	0.00	t	1
485	1	2010105034	201090000000	2026-04-03 19:20:00	54272	2	EGYVO	\N	1085.44	t	\N
486	1	2010105033	201090000000	2026-04-03 19:40:00	1	3	EGYVO	\N	0.00	t	4
487	1	2010105033	201090000000	2026-04-03 20:00:00	282	1	EGYVO	\N	0.00	t	4
488	1	2010105033	201090000000	2026-04-03 20:20:00	29696	2	EGYVO	\N	0.00	t	2
489	1	2010105033	201090000000	2026-04-03 20:40:00	1	3	EGYVO	\N	0.00	t	3
490	1	2010105032	201090000000	2026-04-03 21:00:00	223	1	EGYVO	\N	0.00	t	4
491	1	2010105032	201090000000	2026-04-03 21:20:00	53248	2	EGYVO	VODAFONE_UK	2562.40	t	6
492	1	2010105032	201090000000	2026-04-03 21:40:00	1	3	EGYVO	\N	0.00	t	4
493	1	2010105032	201090000000	2026-04-03 22:00:00	190	1	EGYVO	\N	0.00	t	4
494	1	2010105031	201090000000	2026-04-03 22:20:00	5120	2	EGYVO	VODAFONE_UK	156.00	t	6
495	1	2010105031	201090000000	2026-04-03 22:40:00	1	3	EGYVO	\N	0.00	t	4
496	1	2010105031	201090000000	2026-04-03 23:00:00	153	1	EGYVO	\N	0.00	t	4
497	1	2010105031	201090000000	2026-04-03 23:20:00	94208	2	EGYVO	\N	3218.10	t	2
498	1	2010105030	201090000000	2026-04-03 23:40:00	1	3	EGYVO	\N	0.00	t	4
499	1	2010105030	201090000000	2026-04-04 00:00:00	291	1	EGYVO	\N	0.00	t	4
500	1	2010105030	201090000000	2026-04-04 00:20:00	44032	2	EGYVO	\N	1216.20	t	2
501	1	2010105030	201090000000	2026-04-04 00:40:00	1	3	EGYVO	\N	0.00	t	3
502	1	2010105029	201090000000	2026-04-04 01:00:00	163	1	EGYVO	\N	0.00	t	4
503	1	2010105029	201090000000	2026-04-04 01:20:00	34816	2	EGYVO	VODAFONE_UK	3481.60	t	\N
504	1	2010105029	201090000000	2026-04-04 01:40:00	1	3	EGYVO	\N	0.00	t	4
505	1	2010105029	201090000000	2026-04-04 02:00:00	56	1	EGYVO	\N	0.00	t	4
506	1	2010105027	201090000000	2026-04-04 02:20:00	22528	2	EGYVO	VODAFONE_UK	1026.40	t	6
507	1	2010105027	201090000000	2026-04-04 02:40:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
508	1	2010105027	201090000000	2026-04-04 03:00:00	41	1	EGYVO	\N	0.00	t	4
509	1	2010105027	201090000000	2026-04-04 03:20:00	7168	2	EGYVO	\N	0.00	t	4
510	1	2010105026	201090000000	2026-04-04 03:40:00	1	3	EGYVO	\N	0.00	t	4
511	1	2010105026	201090000000	2026-04-04 04:00:00	255	1	EGYVO	VODAFONE_UK	7.75	t	5
512	1	2010105026	201090000000	2026-04-04 04:20:00	8192	2	EGYVO	\N	0.00	t	4
513	1	2010105026	201090000000	2026-04-04 04:40:00	1	3	EGYVO	\N	0.00	t	4
514	1	2010105023	201090000000	2026-04-04 05:00:00	58	1	EGYVO	\N	0.00	t	4
515	1	2010105023	201090000000	2026-04-04 05:20:00	72704	2	EGYVO	\N	2138.10	t	2
516	1	2010105023	201090000000	2026-04-04 05:40:00	1	3	EGYVO	\N	0.00	t	3
517	1	2010105023	201090000000	2026-04-04 06:00:00	187	1	EGYVO	\N	0.00	t	1
518	1	2010105022	201090000000	2026-04-04 06:20:00	72704	2	EGYVO	\N	7270.40	t	\N
519	1	2010105022	201090000000	2026-04-04 06:40:00	1	3	EGYVO	\N	0.00	t	3
520	1	2010105022	201090000000	2026-04-04 07:00:00	182	1	EGYVO	\N	0.00	t	1
521	1	2010105022	201090000000	2026-04-04 07:20:00	7168	2	EGYVO	VODAFONE_UK	716.80	t	\N
522	1	2010105021	201090000000	2026-04-04 07:40:00	1	3	EGYVO	\N	0.00	t	4
523	1	2010105021	201090000000	2026-04-04 08:00:00	125	1	EGYVO	\N	0.00	t	4
524	1	2010105021	201090000000	2026-04-04 08:20:00	45056	2	EGYVO	\N	3518.20	t	4
525	1	2010105021	201090000000	2026-04-04 08:40:00	1	3	EGYVO	VODAFONE_UK	0.05	t	\N
526	1	2010105020	201090000000	2026-04-04 09:00:00	328	1	EGYVO	VODAFONE_UK	22.80	t	5
527	1	2010105020	201090000000	2026-04-04 09:20:00	92160	2	EGYVO	\N	3608.00	t	2
528	1	2010105020	201090000000	2026-04-04 09:40:00	1	3	EGYVO	\N	0.00	t	3
529	1	2010105020	201090000000	2026-04-04 10:00:00	234	1	EGYVO	\N	0.00	t	1
530	1	2010105019	201090000000	2026-04-04 10:20:00	45056	2	EGYVO	\N	4505.60	t	\N
531	1	2010105019	201090000000	2026-04-04 10:40:00	1	3	EGYVO	\N	0.00	t	3
532	1	2010105019	201090000000	2026-04-04 11:00:00	301	1	EGYVO	\N	0.00	t	1
533	1	2010105019	201090000000	2026-04-04 11:20:00	9216	2	EGYVO	\N	921.60	t	\N
534	1	2010105018	201090000000	2026-04-04 11:40:00	1	3	EGYVO	\N	0.00	t	4
535	1	2010105018	201090000000	2026-04-04 12:00:00	215	1	EGYVO	\N	0.00	t	4
536	1	2010105018	201090000000	2026-04-04 12:20:00	65536	2	EGYVO	\N	2287.60	t	2
537	1	2010105018	201090000000	2026-04-04 12:40:00	1	3	EGYVO	\N	0.00	t	3
538	1	2010105016	201090000000	2026-04-04 13:00:00	37	1	EGYVO	\N	0.00	t	1
539	1	2010105016	201090000000	2026-04-04 13:20:00	14336	2	EGYVO	\N	1433.60	t	\N
540	1	2010105016	201090000000	2026-04-04 13:40:00	1	3	EGYVO	\N	0.00	t	3
541	1	2010105016	201090000000	2026-04-04 14:00:00	106	1	EGYVO	\N	0.00	t	1
542	1	2010105013	201090000000	2026-04-04 14:20:00	101376	2	EGYVO	\N	10137.60	t	\N
543	1	2010105013	201090000000	2026-04-04 14:40:00	1	3	EGYVO	\N	0.00	t	3
544	1	2010105013	201090000000	2026-04-04 15:00:00	71	1	EGYVO	\N	0.00	t	1
545	1	2010105013	201090000000	2026-04-04 15:20:00	41984	2	EGYVO	\N	4198.40	t	\N
546	1	2010105010	201090000000	2026-04-04 15:40:00	1	3	EGYVO	\N	0.00	t	4
547	1	2010105010	201090000000	2026-04-04 16:00:00	34	1	EGYVO	\N	0.00	t	4
548	1	2010105010	201090000000	2026-04-04 16:20:00	18432	2	EGYVO	VODAFONE_UK	328.64	t	6
549	1	2010105010	201090000000	2026-04-04 16:40:00	1	3	EGYVO	\N	0.00	t	4
550	1	2010105009	201090000000	2026-04-04 17:00:00	309	1	EGYVO	\N	0.00	t	4
551	1	2010105009	201090000000	2026-04-04 17:20:00	86016	2	EGYVO	\N	7632.50	t	4
552	1	2010105009	201090000000	2026-04-04 17:40:00	1	3	EGYVO	\N	0.00	t	3
553	1	2010105009	201090000000	2026-04-04 18:00:00	179	1	EGYVO	VODAFONE_UK	35.80	t	\N
554	1	2010105008	201090000000	2026-04-04 18:20:00	62464	2	EGYVO	\N	2123.20	t	2
555	1	2010105008	201090000000	2026-04-04 18:40:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
556	1	2010105008	201090000000	2026-04-04 19:00:00	264	1	EGYVO	\N	0.00	t	1
557	1	2010105008	201090000000	2026-04-04 19:20:00	10240	2	EGYVO	\N	512.00	t	\N
558	1	2010105006	201090000000	2026-04-04 19:40:00	1	3	EGYVO	\N	0.00	t	4
559	1	2010105006	201090000000	2026-04-04 20:00:00	235	1	EGYVO	\N	0.00	t	4
560	1	2010105006	201090000000	2026-04-04 20:20:00	83968	2	EGYVO	\N	7420.40	t	4
561	1	2010105006	201090000000	2026-04-04 20:40:00	1	3	EGYVO	\N	0.00	t	3
562	1	2010105005	201090000000	2026-04-04 21:00:00	243	1	EGYVO	\N	0.00	t	4
563	1	2010105005	201090000000	2026-04-04 21:20:00	95232	2	EGYVO	\N	3273.75	t	2
564	1	2010105005	201090000000	2026-04-04 21:40:00	1	3	EGYVO	\N	0.00	t	3
565	1	2010105005	201090000000	2026-04-04 22:00:00	186	1	EGYVO	\N	0.00	t	1
566	1	2010105004	201090000000	2026-04-04 22:20:00	52224	2	EGYVO	VODAFONE_UK	5222.40	t	\N
567	1	2010105004	201090000000	2026-04-04 22:40:00	1	3	EGYVO	\N	0.00	t	4
568	1	2010105004	201090000000	2026-04-04 23:00:00	49	1	EGYVO	\N	0.00	t	4
569	1	2010105004	201090000000	2026-04-04 23:20:00	88064	2	EGYVO	\N	7811.40	t	4
570	1	2010105003	201090000000	2026-04-04 23:40:00	1	3	EGYVO	\N	0.00	t	4
571	1	2010105003	201090000000	2026-04-05 00:00:00	79	1	EGYVO	\N	0.00	t	4
572	1	2010105003	201090000000	2026-04-05 00:20:00	15360	2	EGYVO	\N	544.00	t	4
573	1	2010105003	201090000000	2026-04-05 00:40:00	1	3	EGYVO	VODAFONE_UK	0.05	t	\N
574	1	201000000048	201090000000	2026-04-05 01:00:00	308	1	EGYVO	\N	0.00	t	1
575	1	201000000048	201090000000	2026-04-05 01:20:00	44032	2	EGYVO	\N	2201.60	t	\N
576	1	201000000048	201090000000	2026-04-05 01:40:00	1	3	EGYVO	\N	0.00	t	3
577	1	201000000048	201090000000	2026-04-05 02:00:00	234	1	EGYVO	\N	0.00	t	1
578	1	201000000047	201090000000	2026-04-05 02:20:00	10240	2	EGYVO	\N	204.80	t	\N
579	1	201000000047	201090000000	2026-04-05 02:40:00	1	3	EGYVO	\N	0.00	t	3
580	1	201000000047	201090000000	2026-04-05 03:00:00	131	1	EGYVO	VODAFONE_UK	0.00	t	5
581	1	201000000047	201090000000	2026-04-05 03:20:00	46080	2	EGYVO	\N	921.60	t	\N
582	1	201000000046	201090000000	2026-04-05 03:40:00	1	3	EGYVO	\N	0.00	t	3
583	1	201000000046	201090000000	2026-04-05 04:00:00	195	1	EGYVO	\N	0.00	t	1
584	1	201000000046	201090000000	2026-04-05 04:20:00	10240	2	EGYVO	\N	1024.00	t	\N
585	1	201000000046	201090000000	2026-04-05 04:40:00	1	3	EGYVO	\N	0.00	t	3
586	1	201000000045	201090000000	2026-04-05 05:00:00	73	1	EGYVO	\N	0.00	t	1
587	1	201000000045	201090000000	2026-04-05 05:20:00	57344	2	EGYVO	\N	2098.95	t	2
588	1	201000000045	201090000000	2026-04-05 05:40:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
589	1	201000000045	201090000000	2026-04-05 06:00:00	110	1	EGYVO	VODAFONE_UK	0.00	t	5
590	1	201000000044	201090000000	2026-04-05 06:20:00	78848	2	EGYVO	VODAFONE_UK	1496.96	t	6
591	1	201000000044	201090000000	2026-04-05 06:40:00	1	3	EGYVO	\N	0.00	t	3
592	1	201000000044	201090000000	2026-04-05 07:00:00	105	1	EGYVO	\N	0.00	t	1
593	1	201000000044	201090000000	2026-04-05 07:20:00	36864	2	EGYVO	\N	737.28	t	\N
594	1	201000000043	201090000000	2026-04-05 07:40:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
595	1	201000000043	201090000000	2026-04-05 08:00:00	221	1	EGYVO	\N	0.00	t	1
596	1	201000000043	201090000000	2026-04-05 08:20:00	30720	2	EGYVO	\N	614.40	t	\N
597	1	201000000043	201090000000	2026-04-05 08:40:00	1	3	EGYVO	\N	0.00	t	3
598	1	201000000042	201090000000	2026-04-05 09:00:00	265	1	EGYVO	\N	0.00	t	1
599	1	201000000042	201090000000	2026-04-05 09:20:00	104448	2	EGYVO	\N	10444.80	t	\N
600	1	201000000042	201090000000	2026-04-05 09:40:00	1	3	EGYVO	\N	0.00	t	3
601	1	201000000042	201090000000	2026-04-05 10:00:00	110	1	EGYVO	\N	0.00	t	1
602	1	201000000041	201090000000	2026-04-05 10:20:00	75776	2	EGYVO	\N	2212.75	t	2
603	1	201000000041	201090000000	2026-04-05 10:40:00	1	3	EGYVO	\N	0.00	t	3
604	1	201000000041	201090000000	2026-04-05 11:00:00	73	1	EGYVO	VODAFONE_UK	0.00	t	5
605	1	201000000041	201090000000	2026-04-05 11:20:00	53248	2	EGYVO	\N	2662.40	t	\N
606	1	201000000040	201090000000	2026-04-05 11:40:00	1	3	EGYVO	\N	0.00	t	3
607	1	201000000040	201090000000	2026-04-05 12:00:00	326	1	EGYVO	\N	0.00	t	1
608	1	201000000040	201090000000	2026-04-05 12:20:00	36864	2	EGYVO	\N	3686.40	t	\N
609	1	201000000040	201090000000	2026-04-05 12:40:00	1	3	EGYVO	\N	0.00	t	3
610	1	201000000039	201090000000	2026-04-05 13:00:00	185	1	EGYVO	\N	0.00	t	1
611	1	201000000039	201090000000	2026-04-05 13:20:00	27648	2	EGYVO	\N	2764.80	t	\N
612	1	201000000039	201090000000	2026-04-05 13:40:00	1	3	EGYVO	\N	0.00	t	3
613	1	201000000039	201090000000	2026-04-05 14:00:00	186	1	EGYVO	\N	0.00	t	1
614	1	201000000038	201090000000	2026-04-05 14:20:00	11264	2	EGYVO	\N	1126.40	t	\N
615	1	201000000038	201090000000	2026-04-05 14:40:00	1	3	EGYVO	VODAFONE_UK	0.05	t	\N
616	1	201000000038	201090000000	2026-04-05 15:00:00	310	1	EGYVO	\N	0.00	t	1
617	1	201000000038	201090000000	2026-04-05 15:20:00	10240	2	EGYVO	\N	1024.00	t	\N
618	1	201000000037	201090000000	2026-04-05 15:40:00	1	3	EGYVO	\N	0.00	t	3
619	1	201000000037	201090000000	2026-04-05 16:00:00	75	1	EGYVO	\N	0.00	t	1
620	1	201000000037	201090000000	2026-04-05 16:20:00	87040	2	EGYVO	\N	8704.00	t	\N
621	1	201000000037	201090000000	2026-04-05 16:40:00	1	3	EGYVO	\N	0.00	t	3
622	1	201000000036	201090000000	2026-04-05 17:00:00	44	1	EGYVO	\N	0.00	t	1
623	1	201000000036	201090000000	2026-04-05 17:20:00	94208	2	EGYVO	\N	9420.80	t	\N
624	1	201000000036	201090000000	2026-04-05 17:40:00	1	3	EGYVO	\N	0.00	t	3
625	1	201000000036	201090000000	2026-04-05 18:00:00	59	1	EGYVO	\N	0.00	t	1
626	1	201000000035	201090000000	2026-04-05 18:20:00	49152	2	EGYVO	\N	2457.60	t	\N
627	1	201000000035	201090000000	2026-04-05 18:40:00	1	3	EGYVO	\N	0.00	t	3
628	1	201000000035	201090000000	2026-04-05 19:00:00	287	1	EGYVO	VODAFONE_UK	28.40	t	5
629	1	201000000035	201090000000	2026-04-05 19:20:00	97280	2	EGYVO	\N	4864.00	t	\N
630	1	201000000034	201090000000	2026-04-05 19:40:00	1	3	EGYVO	\N	0.00	t	3
631	1	201000000034	201090000000	2026-04-05 20:00:00	92	1	EGYVO	VODAFONE_UK	18.40	t	\N
632	1	201000000034	201090000000	2026-04-05 20:20:00	32768	2	EGYVO	\N	3276.80	t	\N
633	1	201000000034	201090000000	2026-04-05 20:40:00	1	3	EGYVO	\N	0.00	t	3
634	1	201000000033	201090000000	2026-04-05 21:00:00	251	1	EGYVO	\N	0.00	t	1
635	1	201000000033	201090000000	2026-04-05 21:20:00	105472	2	EGYVO	\N	10547.20	t	\N
636	1	201000000033	201090000000	2026-04-05 21:40:00	1	3	EGYVO	\N	0.00	t	3
637	1	201000000033	201090000000	2026-04-05 22:00:00	253	1	EGYVO	\N	0.00	t	1
638	1	201000000032	201090000000	2026-04-05 22:20:00	52224	2	EGYVO	\N	5222.40	t	\N
639	1	201000000032	201090000000	2026-04-05 22:40:00	1	3	EGYVO	VODAFONE_UK	0.05	t	\N
640	1	201000000032	201090000000	2026-04-05 23:00:00	194	1	EGYVO	\N	0.00	t	1
641	1	201000000032	201090000000	2026-04-05 23:20:00	78848	2	EGYVO	\N	7884.80	t	\N
642	1	201000000031	201090000000	2026-04-05 23:40:00	1	3	EGYVO	\N	0.00	t	3
643	1	201000000031	201090000000	2026-04-06 00:00:00	312	1	EGYVO	\N	0.00	t	1
644	1	201000000031	201090000000	2026-04-06 00:20:00	99328	2	EGYVO	\N	4966.40	t	\N
645	1	201000000031	201090000000	2026-04-06 00:40:00	1	3	EGYVO	\N	0.00	t	3
646	1	201000000030	201090000000	2026-04-06 01:00:00	186	1	EGYVO	VODAFONE_UK	37.20	t	\N
647	1	201000000030	201090000000	2026-04-06 01:20:00	54272	2	EGYVO	VODAFONE_UK	5427.20	t	\N
648	1	201000000030	201090000000	2026-04-06 01:40:00	1	3	EGYVO	\N	0.00	t	3
649	1	201000000030	201090000000	2026-04-06 02:00:00	31	1	EGYVO	VODAFONE_UK	6.20	t	\N
650	1	201000000029	201090000000	2026-04-06 02:20:00	91136	2	EGYVO	\N	1822.72	t	\N
651	1	201000000029	201090000000	2026-04-06 02:40:00	1	3	EGYVO	\N	0.00	t	3
652	1	201000000029	201090000000	2026-04-06 03:00:00	230	1	EGYVO	\N	0.00	t	1
653	1	201000000029	201090000000	2026-04-06 03:20:00	95232	2	EGYVO	\N	1904.64	t	\N
654	1	201000000028	201090000000	2026-04-06 03:40:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
655	1	201000000028	201090000000	2026-04-06 04:00:00	152	1	EGYVO	\N	0.00	t	1
656	1	201000000028	201090000000	2026-04-06 04:20:00	106496	2	EGYVO	\N	5324.80	t	\N
657	1	201000000028	201090000000	2026-04-06 04:40:00	1	3	EGYVO	\N	0.00	t	3
658	1	201000000027	201090000000	2026-04-06 05:00:00	316	1	EGYVO	\N	0.00	t	1
659	1	201000000027	201090000000	2026-04-06 05:20:00	9216	2	EGYVO	\N	184.32	t	\N
660	1	201000000027	201090000000	2026-04-06 05:40:00	1	3	EGYVO	\N	0.00	t	3
661	1	201000000027	201090000000	2026-04-06 06:00:00	231	1	EGYVO	\N	0.00	t	1
662	1	201000000026	201090000000	2026-04-06 06:20:00	55296	2	EGYVO	\N	5529.60	t	\N
663	1	201000000026	201090000000	2026-04-06 06:40:00	1	3	EGYVO	\N	0.00	t	3
664	1	201000000026	201090000000	2026-04-06 07:00:00	108	1	EGYVO	\N	0.00	t	1
665	1	201000000026	201090000000	2026-04-06 07:20:00	38912	2	EGYVO	\N	3891.20	t	\N
666	1	201000000025	201090000000	2026-04-06 07:40:00	1	3	EGYVO	\N	0.00	t	3
667	1	201000000025	201090000000	2026-04-06 08:00:00	225	1	EGYVO	\N	0.00	t	1
668	1	201000000025	201090000000	2026-04-06 08:20:00	39936	2	EGYVO	VODAFONE_UK	758.72	t	6
669	1	201000000025	201090000000	2026-04-06 08:40:00	1	3	EGYVO	\N	0.00	t	3
670	1	201000000024	201090000000	2026-04-06 09:00:00	85	1	EGYVO	VODAFONE_UK	0.00	t	5
671	1	201000000024	201090000000	2026-04-06 09:20:00	43008	2	EGYVO	\N	660.16	t	2
672	1	201000000024	201090000000	2026-04-06 09:40:00	1	3	EGYVO	\N	0.00	t	3
673	1	201000000024	201090000000	2026-04-06 10:00:00	323	1	EGYVO	\N	0.00	t	1
674	1	201000000023	201090000000	2026-04-06 10:20:00	38912	2	EGYVO	\N	3891.20	t	\N
675	1	201000000023	201090000000	2026-04-06 10:40:00	1	3	EGYVO	\N	0.00	t	3
676	1	201000000023	201090000000	2026-04-06 11:00:00	273	1	EGYVO	\N	0.00	t	1
677	1	201000000023	201090000000	2026-04-06 11:20:00	79872	2	EGYVO	\N	7987.20	t	\N
678	1	201000000022	201090000000	2026-04-06 11:40:00	1	3	EGYVO	\N	0.00	t	3
679	1	201000000022	201090000000	2026-04-06 12:00:00	201	1	EGYVO	\N	0.00	t	1
680	1	201000000022	201090000000	2026-04-06 12:20:00	8192	2	EGYVO	\N	304.00	t	2
681	1	201000000022	201090000000	2026-04-06 12:40:00	1	3	EGYVO	\N	0.00	t	3
682	1	201000000021	201090000000	2026-04-06 13:00:00	54	1	EGYVO	\N	0.00	t	1
683	1	201000000021	201090000000	2026-04-06 13:20:00	53248	2	EGYVO	VODAFONE_UK	1024.96	t	6
684	1	201000000021	201090000000	2026-04-06 13:40:00	1	3	EGYVO	\N	0.00	t	3
685	1	201000000021	201090000000	2026-04-06 14:00:00	190	1	EGYVO	\N	0.00	t	1
686	1	201000000020	201090000000	2026-04-06 14:20:00	21504	2	EGYVO	\N	2150.40	t	\N
687	1	201000000020	201090000000	2026-04-06 14:40:00	1	3	EGYVO	VODAFONE_UK	0.05	t	\N
688	1	201000000020	201090000000	2026-04-06 15:00:00	279	1	EGYVO	VODAFONE_UK	55.80	t	\N
689	1	201000000020	201090000000	2026-04-06 15:20:00	48128	2	EGYVO	\N	4812.80	t	\N
690	1	201000000019	201090000000	2026-04-06 15:40:00	1	3	EGYVO	\N	0.00	t	4
691	1	201000000019	201090000000	2026-04-06 16:00:00	41	1	EGYVO	VODAFONE_UK	0.00	t	5
692	1	201000000019	201090000000	2026-04-06 16:20:00	6144	2	EGYVO	\N	0.00	t	4
693	1	201000000019	201090000000	2026-04-06 16:40:00	1	3	EGYVO	\N	0.00	t	4
694	1	201000000017	201090000000	2026-04-06 17:00:00	252	1	EGYVO	\N	0.00	t	1
695	1	201000000017	201090000000	2026-04-06 17:20:00	103424	2	EGYVO	VODAFONE_UK	5071.20	t	6
696	1	201000000017	201090000000	2026-04-06 17:40:00	1	3	EGYVO	\N	0.00	t	3
697	1	201000000017	201090000000	2026-04-06 18:00:00	133	1	EGYVO	VODAFONE_UK	3.30	t	5
698	1	201000000016	201090000000	2026-04-06 18:20:00	87040	2	EGYVO	\N	1740.80	t	\N
699	1	201000000016	201090000000	2026-04-06 18:40:00	1	3	EGYVO	\N	0.00	t	3
700	1	201000000016	201090000000	2026-04-06 19:00:00	48	1	EGYVO	\N	0.00	t	1
701	1	201000000016	201090000000	2026-04-06 19:20:00	39936	2	EGYVO	\N	798.72	t	\N
702	1	201000000015	201090000000	2026-04-06 19:40:00	1	3	EGYVO	\N	0.00	t	3
703	1	201000000015	201090000000	2026-04-06 20:00:00	214	1	EGYVO	\N	0.00	t	1
704	1	201000000015	201090000000	2026-04-06 20:20:00	86016	2	EGYVO	\N	1720.32	t	\N
705	1	201000000015	201090000000	2026-04-06 20:40:00	1	3	EGYVO	\N	0.00	t	3
706	1	201000000014	201090000000	2026-04-06 21:00:00	106	1	EGYVO	\N	0.00	t	4
707	1	201000000014	201090000000	2026-04-06 21:20:00	20480	2	EGYVO	\N	440.60	t	2
708	1	201000000014	201090000000	2026-04-06 21:40:00	1	3	EGYVO	\N	0.00	t	3
709	1	201000000014	201090000000	2026-04-06 22:00:00	280	1	EGYVO	\N	0.00	t	1
710	1	201000000012	201090000000	2026-04-06 22:20:00	20480	2	EGYVO	\N	41.45	t	2
711	1	201000000012	201090000000	2026-04-06 22:40:00	1	3	EGYVO	VODAFONE_UK	0.00	t	7
712	1	201000000012	201090000000	2026-04-06 23:00:00	219	1	EGYVO	\N	0.00	t	1
713	1	201000000012	201090000000	2026-04-06 23:20:00	103424	2	EGYVO	\N	5171.20	t	\N
\.


--
-- Data for Name: contract; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.contract (id, user_account_id, rateplan_id, msisdn, status, credit_limit, available_credit) FROM stdin;
1	2	1	201000000001	active	200.00	200.00
2	3	2	201000000002	active	500.00	500.00
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
14	15	2	201000000014	active	500.00	500.00
18	19	1	201000000018	terminated	200.00	200.00
22	23	2	201000000022	active	300.00	300.00
23	24	1	201000000023	active	300.00	300.00
24	25	3	201000000024	active	300.00	300.00
25	26	3	201000000025	active	300.00	300.00
28	29	2	201000000028	active	300.00	300.00
29	30	3	201000000029	active	300.00	300.00
30	31	1	201000000030	active	300.00	300.00
31	32	2	201000000031	active	300.00	300.00
32	33	1	201000000032	active	300.00	300.00
33	34	1	201000000033	active	300.00	300.00
34	35	1	201000000034	active	300.00	300.00
35	36	2	201000000035	active	300.00	300.00
37	38	1	201000000037	active	300.00	300.00
38	39	1	201000000038	active	300.00	300.00
39	40	1	201000000039	active	300.00	300.00
40	41	1	201000000040	active	300.00	300.00
41	42	2	201000000041	active	300.00	300.00
42	43	1	201000000042	active	300.00	300.00
43	44	3	201000000043	active	300.00	300.00
44	45	3	201000000044	active	300.00	300.00
48	49	2	201000000048	active	300.00	300.00
47	48	3	201000000047	active	300.00	300.00
46	47	1	201000000046	active	300.00	300.00
45	46	2	201000000045	active	300.00	300.00
16	17	3	201000000016	active	1000.00	1000.00
17	18	2	201000000017	active	500.00	500.00
36	37	1	201000000036	active	300.00	300.00
19	20	2	201000000019	active	300.00	300.00
15	16	3	201000000015	active	1000.00	1000.00
20	21	1	201000000020	active	300.00	300.00
51	52	1	2010105001	suspended_debt	200.00	200.00
52	53	1	2010105002	suspended	200.00	200.00
53	54	1	2010105003	active	200.00	200.00
54	55	1	2010105004	active	200.00	200.00
56	57	1	2010105006	active	200.00	200.00
57	58	2	2010105007	suspended	500.00	500.00
58	59	2	2010105008	active	500.00	500.00
59	60	1	2010105009	active	200.00	200.00
60	61	3	2010105010	active	1000.00	1000.00
61	62	1	2010105011	suspended	200.00	200.00
62	63	3	2010105012	suspended	1000.00	1000.00
63	64	1	2010105013	active	200.00	200.00
64	65	1	2010105014	suspended	200.00	200.00
65	66	2	2010105015	suspended	500.00	500.00
66	67	1	2010105016	active	200.00	200.00
67	68	1	2010105017	terminated	200.00	200.00
68	69	2	2010105018	active	500.00	500.00
69	70	1	2010105019	active	200.00	200.00
70	71	2	2010105020	active	500.00	500.00
71	72	1	2010105021	active	200.00	200.00
72	73	1	2010105022	active	200.00	200.00
73	74	2	2010105023	active	500.00	500.00
74	75	2	2010105024	suspended	500.00	500.00
75	76	2	2010105025	suspended	500.00	500.00
76	77	3	2010105026	active	1000.00	1000.00
77	78	2	2010105027	active	500.00	500.00
78	79	1	2010105028	suspended_debt	200.00	200.00
79	80	1	2010105029	active	200.00	200.00
80	81	2	2010105030	active	500.00	500.00
81	82	2	2010105031	active	500.00	500.00
82	83	2	2010105032	active	500.00	500.00
83	84	2	2010105033	active	500.00	500.00
84	85	3	2010105034	active	1000.00	1000.00
85	86	1	2010105035	active	200.00	200.00
86	87	2	2010105036	suspended	500.00	500.00
87	88	1	2010105037	active	200.00	200.00
88	89	2	2010105038	active	500.00	500.00
89	90	3	2010105039	suspended	1000.00	1000.00
90	91	2	2010105040	active	500.00	500.00
91	92	3	2010105041	active	1000.00	1000.00
92	93	2	2010105042	active	500.00	500.00
93	94	1	2010105043	active	200.00	200.00
94	95	2	2010105044	active	500.00	500.00
95	96	1	2010105045	active	200.00	200.00
96	97	2	2010105046	suspended	500.00	500.00
97	98	1	2010105047	suspended	200.00	200.00
26	27	1	201000000026	active	300.00	300.00
55	56	2	2010105005	active	500.00	500.00
27	28	3	201000000027	active	300.00	300.00
21	22	3	201000000021	active	300.00	300.00
98	99	1	2010105048	suspended	200.00	200.00
99	100	1	2010105049	active	200.00	200.00
100	101	2	2010105050	suspended	500.00	500.00
101	102	2	2010105051	active	500.00	500.00
102	103	3	2010105052	active	1000.00	1000.00
103	104	3	2010105053	active	1000.00	1000.00
104	105	2	2010105054	active	500.00	500.00
105	106	1	2010105055	active	200.00	200.00
106	107	2	2010105056	active	500.00	500.00
107	108	2	2010105057	active	500.00	500.00
108	109	1	2010105058	suspended	200.00	200.00
109	110	1	2010105059	active	200.00	200.00
110	111	2	2010105060	suspended_debt	500.00	500.00
111	112	1	2010105061	active	200.00	200.00
112	113	1	2010105062	active	200.00	200.00
113	114	1	2010105063	active	200.00	200.00
114	115	1	2010105064	active	200.00	200.00
115	116	2	2010105065	active	500.00	500.00
116	117	1	2010105066	suspended	200.00	200.00
117	118	2	2010105067	suspended	500.00	500.00
118	119	2	2010105068	active	500.00	500.00
119	120	2	2010105069	active	500.00	500.00
120	121	1	2010105070	suspended	200.00	200.00
121	122	2	2010105071	active	500.00	500.00
122	123	1	2010105072	active	200.00	200.00
123	124	2	2010105073	suspended_debt	500.00	500.00
124	125	3	2010105074	suspended_debt	1000.00	1000.00
125	126	2	2010105075	active	500.00	500.00
126	127	2	2010105076	active	500.00	500.00
127	128	1	2010105077	active	200.00	200.00
128	129	1	2010105078	suspended	200.00	200.00
129	130	2	2010105079	active	500.00	500.00
130	131	2	2010105080	active	500.00	500.00
131	132	3	2010105081	suspended_debt	1000.00	1000.00
132	133	2	2010105082	suspended	500.00	500.00
133	134	2	2010105083	suspended	500.00	500.00
134	135	1	2010105084	active	200.00	200.00
135	136	1	2010105085	active	200.00	200.00
136	137	3	2010105086	active	1000.00	1000.00
137	138	2	2010105087	active	500.00	500.00
138	139	1	2010105088	suspended	200.00	200.00
139	140	3	2010105089	suspended	1000.00	1000.00
140	141	2	2010105090	active	500.00	500.00
141	142	1	2010105091	suspended	200.00	200.00
142	143	2	2010105092	active	500.00	500.00
143	144	2	2010105093	suspended	500.00	500.00
144	145	1	2010105094	suspended_debt	200.00	200.00
145	146	2	2010105095	active	500.00	500.00
146	147	2	2010105096	active	500.00	500.00
147	148	1	2010105097	suspended_debt	200.00	200.00
148	149	3	2010105098	suspended	1000.00	1000.00
149	150	2	2010105099	active	500.00	500.00
150	151	1	2010105100	active	200.00	200.00
151	152	1	201099999999	active	200.00	200.00
152	152	1	201099999998	active	200.00	200.00
\.


--
-- Data for Name: contract_addon; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.contract_addon (id, contract_id, service_package_id, purchased_date, expiry_date, is_active, price_paid) FROM stdin;
1	53	4	2026-04-28	2026-04-30	t	0.00
2	54	4	2026-04-28	2026-04-30	t	0.00
3	55	4	2026-04-28	2026-04-30	t	0.00
4	56	4	2026-04-28	2026-04-30	t	0.00
5	59	4	2026-04-28	2026-04-30	t	0.00
6	60	4	2026-04-28	2026-04-30	t	0.00
7	71	4	2026-04-28	2026-04-30	t	0.00
8	73	4	2026-04-28	2026-04-30	t	0.00
9	79	4	2026-04-28	2026-04-30	t	0.00
10	81	4	2026-04-28	2026-04-30	t	0.00
11	82	4	2026-04-28	2026-04-30	t	0.00
12	83	4	2026-04-28	2026-04-30	t	0.00
13	84	4	2026-04-28	2026-04-30	t	0.00
14	85	4	2026-04-28	2026-04-30	t	0.00
15	87	4	2026-04-28	2026-04-30	t	0.00
16	90	4	2026-04-28	2026-04-30	t	0.00
17	94	4	2026-04-28	2026-04-30	t	0.00
18	95	4	2026-04-28	2026-04-30	t	0.00
19	101	4	2026-04-28	2026-04-30	t	0.00
20	104	4	2026-04-28	2026-04-30	t	0.00
21	105	4	2026-04-28	2026-04-30	t	0.00
22	106	4	2026-04-28	2026-04-30	t	0.00
23	107	4	2026-04-28	2026-04-30	t	0.00
24	109	4	2026-04-28	2026-04-30	t	0.00
25	111	4	2026-04-28	2026-04-30	t	0.00
26	113	4	2026-04-28	2026-04-30	t	0.00
27	115	4	2026-04-28	2026-04-30	t	0.00
28	121	4	2026-04-28	2026-04-30	t	0.00
29	125	4	2026-04-28	2026-04-30	t	0.00
30	127	4	2026-04-28	2026-04-30	t	0.00
31	130	4	2026-04-28	2026-04-30	t	0.00
32	134	4	2026-04-28	2026-04-30	t	0.00
33	136	4	2026-04-28	2026-04-30	t	0.00
34	140	4	2026-04-28	2026-04-30	t	0.00
35	150	4	2026-04-28	2026-04-30	t	0.00
\.


--
-- Data for Name: contract_consumption; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.contract_consumption (contract_id, service_package_id, rateplan_id, starting_date, ending_date, consumed, quota_limit, is_billed, bill_id) FROM stdin;
1	3	1	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
2	5	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
2	6	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
2	7	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
3	1	1	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
4	3	2	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
4	5	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
4	6	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
6	1	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
6	5	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
6	6	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
6	7	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
8	1	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
8	5	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
8	6	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
8	7	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
9	1	1	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
10	1	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
10	6	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
10	7	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
11	1	1	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
12	3	2	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
12	5	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
14	5	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
14	6	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
14	7	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
15	5	3	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
15	6	3	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
16	5	3	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
16	6	3	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
19	1	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
19	2	2	2026-04-28	2026-04-30	0.0000	10000.0000	f	\N
19	3	2	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
19	4	2	2026-04-28	2026-04-30	0.0000	10000.0000	f	\N
19	5	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
19	7	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
20	1	1	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
20	3	1	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
21	5	3	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
21	7	3	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
22	6	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
22	7	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
24	6	3	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
24	7	3	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
25	5	3	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
25	7	3	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
27	5	3	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
27	6	3	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
27	7	3	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
28	6	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
29	5	3	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
29	6	3	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
29	7	3	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
30	1	1	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
31	1	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
31	3	2	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
31	5	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
31	6	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
31	7	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
32	1	1	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
32	3	1	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
33	1	1	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
33	3	1	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
34	1	1	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
30	3	1	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
29	3	3	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
29	1	3	2026-04-28	2026-04-30	230.0000	2000.0000	f	\N
28	7	2	2026-04-28	2026-04-30	1.0000	100.0000	f	\N
28	1	2	2026-04-28	2026-04-30	152.0000	2000.0000	f	\N
28	3	2	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
27	3	3	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
27	1	3	2026-04-28	2026-04-30	547.0000	2000.0000	f	\N
26	3	1	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
26	1	1	2026-04-28	2026-04-30	108.0000	2000.0000	f	\N
25	1	3	2026-04-28	2026-04-30	225.0000	2000.0000	f	\N
25	6	3	2026-04-28	2026-04-30	2000.0000	2000.0000	f	\N
25	3	3	2026-04-28	2026-04-30	2.0000	500.0000	f	\N
24	2	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
24	3	3	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
24	1	3	2026-04-28	2026-04-30	323.0000	2000.0000	f	\N
23	3	1	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
23	1	1	2026-04-28	2026-04-30	273.0000	2000.0000	f	\N
22	1	2	2026-04-28	2026-04-30	201.0000	2000.0000	f	\N
22	3	2	2026-04-28	2026-04-30	2.0000	500.0000	f	\N
21	6	3	2026-04-28	2026-04-30	2000.0000	2000.0000	f	\N
21	3	3	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
21	1	3	2026-04-28	2026-04-30	244.0000	2000.0000	f	\N
17	1	2	2026-04-28	2026-04-30	252.0000	2000.0000	f	\N
17	6	2	2026-04-28	2026-04-30	2000.0000	2000.0000	f	\N
17	5	2	2026-04-28	2026-04-30	100.0000	100.0000	f	\N
16	3	3	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
15	3	3	2026-04-28	2026-04-30	2.0000	500.0000	f	\N
14	2	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
14	3	2	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
14	1	2	2026-04-28	2026-04-30	280.0000	2000.0000	f	\N
34	3	1	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
35	1	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
35	3	2	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
35	6	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
35	7	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
36	1	1	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
36	3	1	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
37	1	1	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
37	3	1	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
38	1	1	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
38	3	1	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
39	1	1	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
39	3	1	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
40	1	1	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
40	3	1	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
41	1	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
41	3	2	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
41	5	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
41	6	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
41	7	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
42	1	1	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
42	3	1	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
43	1	3	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
43	3	3	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
43	5	3	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
43	6	3	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
43	7	3	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
44	1	3	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
44	3	3	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
44	5	3	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
44	7	3	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
45	1	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
45	3	2	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
45	6	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
45	7	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
46	1	1	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
46	3	1	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
47	1	3	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
47	3	3	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
47	6	3	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
47	7	3	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
48	1	2	2026-04-28	2026-04-30	0.0000	2000.0000	f	\N
48	3	2	2026-04-28	2026-04-30	0.0000	500.0000	f	\N
48	5	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
48	7	2	2026-04-28	2026-04-30	0.0000	100.0000	f	\N
1	1	1	2026-03-01	2026-03-31	310.0000	1000.0000	t	17
1	3	1	2026-03-01	2026-03-31	42.0000	100.0000	t	17
1	1	1	2026-04-01	2026-04-30	350.0000	0.0000	t	33
1	3	1	2026-04-01	2026-04-30	45.0000	0.0000	t	33
2	1	2	2026-04-01	2026-04-30	620.0000	0.0000	t	34
2	2	2	2026-04-01	2026-04-30	2100.0000	0.0000	t	34
2	3	2	2026-04-01	2026-04-30	85.0000	0.0000	t	34
2	4	2	2026-04-01	2026-04-30	50.0000	0.0000	t	34
2	5	2	2026-04-01	2026-04-30	120.0000	0.0000	t	34
2	6	2	2026-04-01	2026-04-30	400.0000	0.0000	t	34
2	7	2	2026-04-01	2026-04-30	30.0000	0.0000	t	34
3	1	1	2026-04-01	2026-04-30	180.0000	0.0000	t	35
3	3	1	2026-04-01	2026-04-30	22.0000	0.0000	t	35
4	1	2	2026-04-01	2026-04-30	480.0000	0.0000	t	36
4	2	2	2026-04-01	2026-04-30	1800.0000	0.0000	t	36
4	3	2	2026-04-01	2026-04-30	65.0000	0.0000	t	36
4	4	2	2026-04-01	2026-04-30	30.0000	0.0000	t	36
4	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	36
4	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	36
4	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	36
5	1	1	2026-04-01	2026-04-30	95.0000	0.0000	t	37
5	3	1	2026-04-01	2026-04-30	12.0000	0.0000	t	37
6	1	2	2026-04-01	2026-04-30	750.0000	0.0000	t	38
6	2	2	2026-04-01	2026-04-30	3200.0000	0.0000	t	38
6	3	2	2026-04-01	2026-04-30	110.0000	0.0000	t	38
6	4	2	2026-04-01	2026-04-30	50.0000	0.0000	t	38
6	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	38
6	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	38
6	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	38
7	1	1	2026-04-01	2026-04-30	210.0000	0.0000	t	39
7	3	1	2026-04-01	2026-04-30	18.0000	0.0000	t	39
8	1	2	2026-04-01	2026-04-30	390.0000	0.0000	t	40
8	2	2	2026-04-01	2026-04-30	1500.0000	0.0000	t	40
8	3	2	2026-04-01	2026-04-30	55.0000	0.0000	t	40
8	4	2	2026-04-01	2026-04-30	20.0000	0.0000	t	40
8	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	40
8	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	40
8	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	40
9	1	1	2026-04-01	2026-04-30	140.0000	0.0000	t	41
9	3	1	2026-04-01	2026-04-30	8.0000	0.0000	t	41
10	1	2	2026-04-01	2026-04-30	510.0000	0.0000	t	42
10	2	2	2026-04-01	2026-04-30	2400.0000	0.0000	t	42
10	3	2	2026-04-01	2026-04-30	75.0000	0.0000	t	42
10	4	2	2026-04-01	2026-04-30	40.0000	0.0000	t	42
10	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	42
10	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	42
10	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	42
11	1	1	2026-04-01	2026-04-30	980.0000	0.0000	t	43
11	3	1	2026-04-01	2026-04-30	190.0000	0.0000	t	43
12	1	2	2026-04-01	2026-04-30	290.0000	0.0000	t	44
12	2	2	2026-04-01	2026-04-30	900.0000	0.0000	t	44
12	3	2	2026-04-01	2026-04-30	35.0000	0.0000	t	44
12	4	2	2026-04-01	2026-04-30	15.0000	0.0000	t	44
12	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	44
12	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	44
12	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	44
47	5	3	2026-04-28	2026-04-30	31.0000	100.0000	f	\N
45	2	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
45	5	2	2026-04-28	2026-04-30	10.0000	100.0000	f	\N
44	6	3	2026-04-28	2026-04-30	2000.0000	2000.0000	f	\N
41	4	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
41	2	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
14	1	2	2026-04-01	2026-04-30	430.0000	0.0000	t	45
14	2	2	2026-04-01	2026-04-30	1200.0000	0.0000	t	45
14	3	2	2026-04-01	2026-04-30	60.0000	0.0000	t	45
14	4	2	2026-04-01	2026-04-30	25.0000	0.0000	t	45
14	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	45
14	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	45
14	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	45
15	1	3	2026-04-01	2026-04-30	820.0000	0.0000	t	46
15	2	3	2026-04-01	2026-04-30	3800.0000	0.0000	t	46
15	3	3	2026-04-01	2026-04-30	145.0000	0.0000	t	46
15	4	3	2026-04-01	2026-04-30	50.0000	0.0000	t	46
15	5	3	2026-04-01	2026-04-30	80.0000	0.0000	t	46
15	6	3	2026-04-01	2026-04-30	320.0000	0.0000	t	46
15	7	3	2026-04-01	2026-04-30	20.0000	0.0000	t	46
16	1	3	2026-04-01	2026-04-30	950.0000	0.0000	t	47
16	2	3	2026-04-01	2026-04-30	4900.0000	0.0000	t	47
16	3	3	2026-04-01	2026-04-30	180.0000	0.0000	t	47
16	4	3	2026-04-01	2026-04-30	50.0000	0.0000	t	47
16	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	47
16	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	47
16	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	47
17	1	2	2026-04-01	2026-04-30	340.0000	0.0000	t	48
17	2	2	2026-04-01	2026-04-30	1100.0000	0.0000	t	48
17	3	2	2026-04-01	2026-04-30	48.0000	0.0000	t	48
17	4	2	2026-04-01	2026-04-30	10.0000	0.0000	t	48
17	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	48
17	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	48
17	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	48
21	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	79
21	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	79
21	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	79
22	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	80
22	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	80
24	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	82
24	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	82
25	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	83
25	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	83
25	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	83
31	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
31	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
31	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
35	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
35	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
41	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
41	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
41	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
43	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
44	5	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
44	7	3	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
48	5	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
48	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
47	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
47	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
45	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
19	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	f	\N
19	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	f	\N
19	3	2	2026-04-01	2026-04-30	0.0000	500.0000	f	\N
19	7	2	2026-04-01	2026-04-30	0.0000	100.0000	f	\N
44	4	3	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
44	4	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
44	2	3	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
44	2	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
47	7	3	2026-04-01	2026-04-30	1.0000	100.0000	f	\N
27	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	85
47	4	3	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
47	4	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
47	2	3	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
47	2	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
27	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	85
27	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	85
28	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	86
28	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	86
29	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	87
29	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	87
29	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	87
29	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	87
30	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	88
47	5	3	2026-04-01	2026-04-30	100.0000	100.0000	f	\N
45	7	2	2026-04-01	2026-04-30	1.0000	100.0000	f	\N
45	5	2	2026-04-01	2026-04-30	100.0000	100.0000	f	\N
44	6	3	2026-04-01	2026-04-30	2000.0000	2000.0000	f	\N
44	3	3	2026-04-01	2026-04-30	2.0000	500.0000	f	\N
44	1	3	2026-04-01	2026-04-30	171.0000	2000.0000	f	\N
43	7	3	2026-04-01	2026-04-30	1.0000	100.0000	f	\N
43	1	3	2026-04-01	2026-04-30	221.0000	2000.0000	f	\N
42	3	1	2026-04-01	2026-04-30	1.0000	500.0000	f	\N
41	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
41	3	2	2026-04-01	2026-04-30	1.0000	500.0000	f	\N
41	5	2	2026-04-01	2026-04-30	73.0000	100.0000	f	\N
39	1	1	2026-04-01	2026-04-30	371.0000	2000.0000	f	\N
19	5	2	2026-04-01	2026-04-30	41.0000	100.0000	f	\N
22	7	2	2026-04-01	2026-04-30	1.0000	100.0000	t	80
22	5	2	2026-04-01	2026-04-30	100.0000	100.0000	t	80
27	4	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
27	2	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
1	1	1	2026-04-28	2026-04-30	233.0000	2000.0000	f	\N
11	3	1	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
34	1	1	2026-04-01	2026-04-30	461.0000	2000.0000	f	\N
19	6	2	2026-04-01	2026-04-30	2000.0000	2000.0000	f	\N
19	6	2	2026-04-28	2026-04-30	2000.0000	2000.0000	f	\N
22	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	80
22	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	80
5	1	1	2026-04-28	2026-04-30	88.0000	2000.0000	f	\N
5	3	1	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
4	4	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
4	2	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
4	7	2	2026-04-28	2026-04-30	1.0000	100.0000	f	\N
4	1	2	2026-04-28	2026-04-30	212.0000	2000.0000	f	\N
2	4	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
2	2	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
2	3	2	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
2	1	2	2026-04-28	2026-04-30	252.0000	2000.0000	f	\N
22	5	2	2026-04-28	2026-04-30	100.0000	100.0000	f	\N
22	4	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
7	3	1	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
7	1	1	2026-04-28	2026-04-30	177.0000	2000.0000	f	\N
9	3	1	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
48	3	2	2026-04-01	2026-04-30	2.0000	500.0000	f	\N
28	5	2	2026-04-28	2026-04-30	30.0000	100.0000	f	\N
28	4	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
28	2	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
48	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
48	4	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
48	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
48	2	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
48	6	2	2026-04-01	2026-04-30	2000.0000	2000.0000	f	\N
48	6	2	2026-04-28	2026-04-30	2000.0000	2000.0000	f	\N
32	3	1	2026-04-01	2026-04-30	2.0000	500.0000	f	\N
48	1	2	2026-04-01	2026-04-30	644.0000	2000.0000	f	\N
15	4	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
15	2	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
15	7	3	2026-04-28	2026-04-30	1.0000	100.0000	f	\N
22	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	80
6	4	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
6	2	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
6	3	2	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
38	3	1	2026-04-01	2026-04-30	1.0000	500.0000	f	\N
3	3	1	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
24	4	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
35	5	2	2026-04-01	2026-04-30	100.0000	100.0000	f	\N
35	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
35	4	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
35	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
35	2	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
35	1	2	2026-04-01	2026-04-30	52.0000	2000.0000	f	\N
16	4	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
16	2	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
16	7	3	2026-04-28	2026-04-30	1.0000	100.0000	f	\N
23	1	1	2026-04-01	2026-04-30	107.0000	2000.0000	t	81
23	3	1	2026-04-01	2026-04-30	2.0000	500.0000	t	81
24	7	3	2026-04-01	2026-04-30	1.0000	100.0000	t	82
24	5	3	2026-04-01	2026-04-30	100.0000	100.0000	t	82
24	4	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	82
24	2	3	2026-04-01	2026-04-30	6624.0000	10000.0000	t	82
24	3	3	2026-04-01	2026-04-30	1.0000	500.0000	t	82
26	1	1	2026-04-01	2026-04-30	97.0000	2000.0000	t	84
26	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	84
27	4	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	85
27	2	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	85
27	3	3	2026-04-01	2026-04-30	1.0000	500.0000	t	85
27	1	3	2026-04-01	2026-04-30	251.0000	2000.0000	t	85
47	3	3	2026-04-01	2026-04-30	2.0000	500.0000	f	\N
46	1	1	2026-04-01	2026-04-30	446.0000	2000.0000	f	\N
42	1	1	2026-04-01	2026-04-30	517.0000	2000.0000	f	\N
41	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
40	1	1	2026-04-01	2026-04-30	675.0000	2000.0000	f	\N
40	3	1	2026-04-01	2026-04-30	3.0000	500.0000	f	\N
38	1	1	2026-04-01	2026-04-30	552.0000	2000.0000	f	\N
37	1	1	2026-04-01	2026-04-30	113.0000	2000.0000	f	\N
37	3	1	2026-04-01	2026-04-30	3.0000	500.0000	f	\N
36	3	1	2026-04-01	2026-04-30	2.0000	500.0000	f	\N
36	1	1	2026-04-01	2026-04-30	272.0000	2000.0000	f	\N
35	3	2	2026-04-01	2026-04-30	2.0000	500.0000	f	\N
35	5	2	2026-04-28	2026-04-30	100.0000	100.0000	f	\N
34	3	1	2026-04-01	2026-04-30	3.0000	500.0000	f	\N
33	3	1	2026-04-01	2026-04-30	3.0000	500.0000	f	\N
10	4	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
10	2	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
10	3	2	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
10	5	2	2026-04-28	2026-04-30	100.0000	100.0000	f	\N
31	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
31	4	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
31	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
31	2	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
53	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	90
8	4	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
8	2	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
8	3	2	2026-04-28	2026-04-30	1.0000	500.0000	f	\N
12	6	2	2026-04-28	2026-04-30	2000.0000	2000.0000	f	\N
53	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	90
25	4	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
25	2	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
17	7	2	2026-04-28	2026-04-30	1.0000	100.0000	f	\N
17	4	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
17	2	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
43	4	3	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
43	4	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
43	5	3	2026-04-01	2026-04-30	58.0000	100.0000	f	\N
43	2	3	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
43	2	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
29	4	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
29	2	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
45	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
45	4	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
45	3	2	2026-04-01	2026-04-30	1.0000	500.0000	f	\N
21	4	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
21	2	3	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
21	4	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	79
21	2	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	79
21	3	3	2026-04-01	2026-04-30	1.0000	500.0000	t	79
21	1	3	2026-04-01	2026-04-30	319.0000	2000.0000	t	79
25	4	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	83
25	2	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	83
25	3	3	2026-04-01	2026-04-30	1.0000	500.0000	t	83
25	1	3	2026-04-01	2026-04-30	306.0000	2000.0000	t	83
28	5	2	2026-04-01	2026-04-30	100.0000	100.0000	t	86
28	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	86
28	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	86
28	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	86
28	1	2	2026-04-01	2026-04-30	92.0000	2000.0000	t	86
29	4	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	87
29	2	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	87
29	3	3	2026-04-01	2026-04-30	1.0000	500.0000	t	87
30	3	1	2026-04-01	2026-04-30	2.0000	500.0000	t	88
20	1	1	2026-04-01	2026-04-30	517.0000	2000.0000	t	89
20	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	89
54	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	91
54	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	91
55	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	92
55	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	92
55	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	92
56	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	93
58	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	94
58	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	94
58	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	94
59	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	95
60	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	96
60	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	96
60	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	96
60	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	96
60	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	96
68	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	99
68	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	99
68	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	99
68	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	99
70	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	101
70	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	101
71	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	102
71	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	102
73	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	104
73	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	104
73	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	104
73	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	104
76	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	105
76	2	3	2026-04-01	2026-04-30	0.0000	10000.0000	t	105
76	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	105
76	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	105
76	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	105
77	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	106
77	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	106
77	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	106
77	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	106
79	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	107
79	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	107
80	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	108
80	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	108
80	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	108
80	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	108
81	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	109
81	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	109
81	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	109
81	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	109
82	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	110
82	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	110
82	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	110
82	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	110
82	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	110
83	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	111
83	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	111
83	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	111
83	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	111
84	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	112
84	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	112
84	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	112
87	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	114
88	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	115
88	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	115
88	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	115
90	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	116
90	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	116
90	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	116
91	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	117
91	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	117
91	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	117
91	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	117
92	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	118
92	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	118
94	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	120
94	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	120
94	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	120
94	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	120
99	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	122
101	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	123
101	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	123
101	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	123
101	4	2	2026-04-01	2026-04-30	20000.0000	20000.0000	t	123
101	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	123
102	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	124
102	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	124
103	3	3	2026-04-01	2026-04-30	0.0000	500.0000	t	125
103	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	125
104	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	126
104	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	126
104	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	126
104	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	126
106	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	128
106	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	128
106	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	128
107	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	129
107	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	129
107	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	129
107	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	129
107	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	129
109	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	130
109	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	130
111	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	131
111	3	1	2026-04-01	2026-04-30	0.0000	500.0000	t	131
115	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	135
115	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	135
115	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	135
115	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	135
118	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	136
118	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	136
118	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	136
119	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	137
119	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	137
119	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	137
121	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	138
121	2	2	2026-04-01	2026-04-30	0.0000	10000.0000	t	138
121	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	138
121	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	138
121	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	138
121	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	138
125	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	140
125	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	140
125	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	140
126	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	141
126	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	141
126	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	141
126	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	141
129	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	143
129	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	143
129	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	143
130	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	144
130	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	144
130	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	144
130	4	2	2026-04-01	2026-04-30	20000.0000	20000.0000	t	144
130	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	144
130	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	144
130	7	2	2026-04-01	2026-04-30	1.0000	100.0000	t	144
134	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	145
121	4	2	2026-04-01	2026-04-30	16712.0000	20000.0000	t	138
122	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	139
122	1	1	2026-04-01	2026-04-30	182.0000	2000.0000	t	139
125	5	2	2026-04-01	2026-04-30	100.0000	100.0000	t	140
125	4	2	2026-04-01	2026-04-30	20000.0000	20000.0000	t	140
125	2	2	2026-04-01	2026-04-30	9696.0000	10000.0000	t	140
125	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	140
126	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	141
126	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	141
126	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	141
127	4	1	2026-04-01	2026-04-30	10000.0000	10000.0000	t	142
127	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	142
127	1	1	2026-04-01	2026-04-30	71.0000	2000.0000	t	142
129	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	143
129	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	143
129	7	2	2026-04-01	2026-04-30	1.0000	100.0000	t	143
129	1	2	2026-04-01	2026-04-30	64.0000	2000.0000	t	143
134	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	145
134	4	1	2026-04-01	2026-04-30	10000.0000	10000.0000	t	145
135	1	1	2026-04-01	2026-04-30	534.0000	2000.0000	t	146
135	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	146
136	1	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	147
136	2	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	147
136	3	3	2026-04-01	2026-04-30	1.0000	500.0000	t	147
136	4	3	2026-04-01	2026-04-30	20000.0000	20000.0000	t	147
136	5	3	2026-04-01	2026-04-30	0.0000	100.0000	t	147
136	6	3	2026-04-01	2026-04-30	0.0000	2000.0000	t	147
136	7	3	2026-04-01	2026-04-30	0.0000	100.0000	t	147
137	1	2	2026-04-01	2026-04-30	152.0000	2000.0000	t	148
137	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	148
137	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	148
137	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	148
137	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	148
137	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	148
137	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	148
140	1	2	2026-04-01	2026-04-30	119.0000	2000.0000	t	149
140	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	149
140	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	149
140	4	2	2026-04-01	2026-04-30	20000.0000	20000.0000	t	149
140	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	149
140	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	149
140	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	149
142	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	150
142	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	150
77	6	2	2026-04-01	2026-04-30	2000.0000	2000.0000	t	106
77	7	2	2026-04-01	2026-04-30	1.0000	100.0000	t	106
79	4	1	2026-04-01	2026-04-30	220.0000	10000.0000	t	107
80	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	108
80	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	108
80	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	108
81	6	2	2026-04-01	2026-04-30	2000.0000	2000.0000	t	109
81	4	2	2026-04-01	2026-04-30	20000.0000	20000.0000	t	109
81	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	109
82	4	2	2026-04-01	2026-04-30	414.0000	20000.0000	t	110
82	6	2	2026-04-01	2026-04-30	2000.0000	2000.0000	t	110
83	4	2	2026-04-01	2026-04-30	20000.0000	20000.0000	t	111
83	2	2	2026-04-01	2026-04-30	9979.0000	10000.0000	t	111
83	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	111
84	4	3	2026-04-01	2026-04-30	20000.0000	20000.0000	t	112
84	2	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	112
84	3	3	2026-04-01	2026-04-30	1.0000	500.0000	t	112
84	1	3	2026-04-01	2026-04-30	209.0000	2000.0000	t	112
85	4	1	2026-04-01	2026-04-30	10000.0000	10000.0000	t	113
85	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	113
85	1	1	2026-04-01	2026-04-30	145.0000	2000.0000	t	113
87	4	1	2026-04-01	2026-04-30	10000.0000	10000.0000	t	114
87	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	114
88	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	115
88	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	115
88	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	115
88	1	2	2026-04-01	2026-04-30	49.0000	2000.0000	t	115
90	4	2	2026-04-01	2026-04-30	20000.0000	20000.0000	t	116
90	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	116
71	4	1	2026-04-01	2026-04-30	10000.0000	10000.0000	t	102
72	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	103
72	1	1	2026-04-01	2026-04-30	182.0000	2000.0000	t	103
73	4	2	2026-04-01	2026-04-30	20000.0000	20000.0000	t	104
73	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	104
73	1	2	2026-04-01	2026-04-30	187.0000	2000.0000	t	104
76	4	3	2026-04-01	2026-04-30	8194.0000	10000.0000	t	105
46	3	1	2026-04-01	2026-04-30	4.0000	500.0000	f	\N
45	1	2	2026-04-01	2026-04-30	213.0000	2000.0000	f	\N
45	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	f	\N
43	3	3	2026-04-01	2026-04-30	2.0000	500.0000	f	\N
39	3	1	2026-04-01	2026-04-30	2.0000	500.0000	f	\N
33	1	1	2026-04-01	2026-04-30	763.0000	2000.0000	f	\N
32	1	1	2026-04-01	2026-04-30	517.0000	2000.0000	f	\N
31	1	2	2026-04-01	2026-04-30	456.0000	2000.0000	f	\N
31	3	2	2026-04-01	2026-04-30	3.0000	500.0000	f	\N
24	5	3	2026-04-28	2026-04-30	93.0000	100.0000	f	\N
22	2	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
76	5	3	2026-04-01	2026-04-30	100.0000	100.0000	t	105
19	4	2	2026-04-01	2026-04-30	6309.0000	10000.0000	f	\N
17	3	2	2026-04-28	2026-04-30	2.0000	500.0000	f	\N
16	1	3	2026-04-28	2026-04-30	312.0000	2000.0000	f	\N
15	1	3	2026-04-28	2026-04-30	438.0000	2000.0000	f	\N
14	4	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
12	4	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
12	2	2	2026-04-28	2026-04-30	10000.0000	10000.0000	f	\N
12	7	2	2026-04-28	2026-04-30	1.0000	100.0000	f	\N
12	1	2	2026-04-28	2026-04-30	219.0000	2000.0000	f	\N
53	4	1	2026-04-01	2026-04-30	10000.0000	10000.0000	t	90
54	4	1	2026-04-01	2026-04-30	10000.0000	10000.0000	t	91
55	1	2	2026-04-01	2026-04-30	186.0000	2000.0000	t	92
55	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	92
55	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	92
55	4	2	2026-04-01	2026-04-30	20000.0000	20000.0000	t	92
56	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	93
56	4	1	2026-04-01	2026-04-30	10000.0000	10000.0000	t	93
58	1	2	2026-04-01	2026-04-30	264.0000	2000.0000	t	94
58	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	94
58	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	94
58	7	2	2026-04-01	2026-04-30	1.0000	100.0000	t	94
59	4	1	2026-04-01	2026-04-30	10000.0000	10000.0000	t	95
59	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	95
60	4	3	2026-04-01	2026-04-30	36.0000	20000.0000	t	96
60	6	3	2026-04-01	2026-04-30	2000.0000	2000.0000	t	96
63	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	97
63	1	1	2026-04-01	2026-04-30	71.0000	2000.0000	t	97
66	1	1	2026-04-01	2026-04-30	143.0000	2000.0000	t	98
66	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	98
68	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	99
68	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	99
68	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	99
69	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	100
69	1	1	2026-04-01	2026-04-30	301.0000	2000.0000	t	100
70	5	2	2026-04-01	2026-04-30	100.0000	100.0000	t	101
70	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	101
70	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	101
70	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	101
70	1	2	2026-04-01	2026-04-30	234.0000	2000.0000	t	101
77	4	2	2026-04-01	2026-04-30	7209.0000	10000.0000	t	106
90	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	116
90	1	2	2026-04-01	2026-04-30	327.0000	2000.0000	t	116
91	4	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	117
91	2	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	117
91	3	3	2026-04-01	2026-04-30	1.0000	500.0000	t	117
92	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	118
92	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	118
92	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	118
92	1	2	2026-04-01	2026-04-30	104.0000	2000.0000	t	118
92	6	2	2026-04-01	2026-04-30	2000.0000	2000.0000	t	118
93	1	1	2026-04-01	2026-04-30	568.0000	2000.0000	t	119
93	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	119
94	4	2	2026-04-01	2026-04-30	20000.0000	20000.0000	t	120
94	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	120
94	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	120
95	4	1	2026-04-01	2026-04-30	10000.0000	10000.0000	t	121
95	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	121
95	1	1	2026-04-01	2026-04-30	177.0000	2000.0000	t	121
99	1	1	2026-04-01	2026-04-30	301.0000	2000.0000	t	122
101	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	123
101	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	123
102	6	3	2026-04-01	2026-04-30	2000.0000	2000.0000	t	124
102	7	3	2026-04-01	2026-04-30	1.0000	100.0000	t	124
102	5	3	2026-04-01	2026-04-30	100.0000	100.0000	t	124
102	4	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	124
102	2	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	124
103	5	3	2026-04-01	2026-04-30	68.0000	100.0000	t	125
103	4	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	125
103	2	3	2026-04-01	2026-04-30	10000.0000	10000.0000	t	125
103	7	3	2026-04-01	2026-04-30	1.0000	100.0000	t	125
103	1	3	2026-04-01	2026-04-30	33.0000	2000.0000	t	125
104	7	2	2026-04-01	2026-04-30	1.0000	100.0000	t	126
104	4	2	2026-04-01	2026-04-30	329.0000	20000.0000	t	126
104	6	2	2026-04-01	2026-04-30	2000.0000	2000.0000	t	126
105	4	1	2026-04-01	2026-04-30	10000.0000	10000.0000	t	127
105	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	127
105	1	1	2026-04-01	2026-04-30	45.0000	2000.0000	t	127
106	4	2	2026-04-01	2026-04-30	20000.0000	20000.0000	t	128
106	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	128
106	7	2	2026-04-01	2026-04-30	1.0000	100.0000	t	128
106	1	2	2026-04-01	2026-04-30	234.0000	2000.0000	t	128
107	4	2	2026-04-01	2026-04-30	66.0000	20000.0000	t	129
107	6	2	2026-04-01	2026-04-30	2000.0000	2000.0000	t	129
109	4	1	2026-04-01	2026-04-30	10000.0000	10000.0000	t	130
111	4	1	2026-04-01	2026-04-30	271.0000	10000.0000	t	131
112	3	1	2026-04-01	2026-04-30	2.0000	500.0000	t	132
112	1	1	2026-04-01	2026-04-30	132.0000	2000.0000	t	132
113	4	1	2026-04-01	2026-04-30	10000.0000	10000.0000	t	133
113	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	133
113	1	1	2026-04-01	2026-04-30	70.0000	2000.0000	t	133
114	1	1	2026-04-01	2026-04-30	432.0000	2000.0000	t	134
114	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	134
115	4	2	2026-04-01	2026-04-30	20000.0000	20000.0000	t	135
115	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	135
115	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	135
118	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	136
118	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	136
118	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	136
118	1	2	2026-04-01	2026-04-30	183.0000	2000.0000	t	136
119	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	137
119	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	137
119	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	137
119	1	2	2026-04-01	2026-04-30	96.0000	2000.0000	t	137
142	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	150
142	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	150
142	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	150
142	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	150
142	7	2	2026-04-01	2026-04-30	1.0000	100.0000	t	150
145	1	2	2026-04-01	2026-04-30	97.0000	2000.0000	t	151
145	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	151
145	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	151
145	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	151
145	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	151
145	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	151
145	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	151
146	1	2	2026-04-01	2026-04-30	169.0000	2000.0000	t	152
146	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	152
146	3	2	2026-04-01	2026-04-30	1.0000	500.0000	t	152
146	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	152
146	5	2	2026-04-01	2026-04-30	100.0000	100.0000	t	152
146	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	152
146	7	2	2026-04-01	2026-04-30	0.0000	100.0000	t	152
149	1	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	153
149	2	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	153
149	3	2	2026-04-01	2026-04-30	0.0000	500.0000	t	153
149	4	2	2026-04-01	2026-04-30	10000.0000	10000.0000	t	153
149	5	2	2026-04-01	2026-04-30	0.0000	100.0000	t	153
149	6	2	2026-04-01	2026-04-30	0.0000	2000.0000	t	153
149	7	2	2026-04-01	2026-04-30	2.0000	100.0000	t	153
150	1	1	2026-04-01	2026-04-30	0.0000	2000.0000	t	154
150	3	1	2026-04-01	2026-04-30	1.0000	500.0000	t	154
150	4	1	2026-04-01	2026-04-30	10000.0000	10000.0000	t	154
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
1	1	/invoices/feb26_contract1.pdf	2026-04-28 18:30:20.990344
2	2	/invoices/feb26_contract2.pdf	2026-04-28 18:30:20.990344
3	3	/invoices/feb26_contract3.pdf	2026-04-28 18:30:20.990344
4	4	/invoices/feb26_contract4.pdf	2026-04-28 18:30:20.990344
5	5	/invoices/feb26_contract5.pdf	2026-04-28 18:30:20.990344
6	6	/invoices/feb26_contract6.pdf	2026-04-28 18:30:20.990344
7	7	/invoices/feb26_contract7.pdf	2026-04-28 18:30:20.990344
8	8	/invoices/feb26_contract8.pdf	2026-04-28 18:30:20.990344
9	9	/invoices/feb26_contract9.pdf	2026-04-28 18:30:20.990344
10	10	/invoices/feb26_contract10.pdf	2026-04-28 18:30:20.990344
11	11	/invoices/feb26_contract11.pdf	2026-04-28 18:30:20.990344
12	12	/invoices/feb26_contract12.pdf	2026-04-28 18:30:20.990344
13	13	/invoices/feb26_contract14.pdf	2026-04-28 18:30:20.990344
14	14	/invoices/feb26_contract15.pdf	2026-04-28 18:30:20.990344
15	15	/invoices/feb26_contract16.pdf	2026-04-28 18:30:20.990344
16	16	/invoices/feb26_contract17.pdf	2026-04-28 18:30:20.990344
17	17	/invoices/mar26_contract1.pdf	2026-04-28 18:30:20.990344
18	18	/invoices/mar26_contract2.pdf	2026-04-28 18:30:20.990344
19	158	processed/invoices/Bill_158.pdf	2026-04-28 18:43:16.404446
\.


--
-- Data for Name: msisdn_pool; Type: TABLE DATA; Schema: public; Owner: -
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
100	2010105001	f
101	2010105002	f
102	2010105003	f
103	2010105004	f
104	2010105005	f
105	2010105006	f
106	2010105007	f
107	2010105008	f
108	2010105009	f
109	2010105010	f
110	2010105011	f
111	2010105012	f
112	2010105013	f
113	2010105014	f
114	2010105015	f
115	2010105016	f
116	2010105017	f
117	2010105018	f
118	2010105019	f
119	2010105020	f
120	2010105021	f
121	2010105022	f
122	2010105023	f
123	2010105024	f
124	2010105025	f
125	2010105026	f
126	2010105027	f
127	2010105028	f
128	2010105029	f
129	2010105030	f
130	2010105031	f
131	2010105032	f
132	2010105033	f
133	2010105034	f
134	2010105035	f
135	2010105036	f
136	2010105037	f
137	2010105038	f
138	2010105039	f
139	2010105040	f
140	2010105041	f
141	2010105042	f
142	2010105043	f
143	2010105044	f
144	2010105045	f
145	2010105046	f
146	2010105047	f
147	2010105048	f
148	2010105049	f
149	2010105050	f
150	2010105051	f
151	2010105052	f
152	2010105053	f
153	2010105054	f
154	2010105055	f
155	2010105056	f
156	2010105057	f
157	2010105058	f
158	2010105059	f
159	2010105060	f
160	2010105061	f
161	2010105062	f
162	2010105063	f
163	2010105064	f
164	2010105065	f
165	2010105066	f
166	2010105067	f
167	2010105068	f
168	2010105069	f
169	2010105070	f
170	2010105071	f
171	2010105072	f
172	2010105073	f
173	2010105074	f
174	2010105075	f
175	2010105076	f
176	2010105077	f
177	2010105078	f
178	2010105079	f
179	2010105080	f
180	2010105081	f
181	2010105082	f
182	2010105083	f
183	2010105084	f
184	2010105085	f
185	2010105086	f
186	2010105087	f
187	2010105088	f
188	2010105089	f
189	2010105090	f
190	2010105091	f
191	2010105092	f
192	2010105093	f
193	2010105094	f
194	2010105095	f
195	2010105096	f
196	2010105097	f
197	2010105098	f
198	2010105099	f
199	2010105100	f
\.


--
-- Data for Name: rateplan; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.rateplan (id, name, ror_data, ror_voice, ror_sms, price) FROM stdin;
1	Basic	0.10	0.20	0.05	75.00
2	Premium Gold	0.05	0.10	0.02	370.00
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

COPY public.ror_contract (contract_id, rateplan_id, data, voice, sms, roaming_voice, roaming_data, roaming_sms, bill_id) FROM stdin;
13	1	0	0	0	0.00	0.00	0.00	\N
18	1	0	0	0	0.00	0.00	0.00	\N
1	1	4608	492	0	0.00	0.00	0.10	33
11	1	7066	408	0	63.00	0.00	0.00	43
5	1	2560	72	0	19.40	0.00	0.00	37
4	2	4993	132	0	0.00	0.00	0.00	36
2	2	2851	183	0	30.00	25.00	0.02	34
7	1	8294	120	0	0.00	0.00	0.00	39
9	1	4505	66	0	32.00	0.00	0.00	41
6	2	3965	240	0	0.00	0.00	0.00	38
3	1	5120	126	0	34.80	0.00	0.00	35
10	2	1221	138	0	12.70	0.00	0.00	42
8	2	2252	111	0	0.00	0.00	0.00	40
12	2	5240	60	0	0.00	2255.20	0.00	44
56	1	7420	0	0	0.00	0.00	0.00	93
58	2	2635	0	0	0.00	0.00	0.00	94
59	1	7633	0	0	35.80	0.00	0.00	95
60	3	\N	\N	\N	0.00	328.64	0.00	96
19	2	\N	\N	\N	0.00	4561.60	0.00	\N
63	1	14336	0	0	0.00	0.00	0.00	97
66	1	1434	0	0	0.00	0.00	0.00	98
68	2	2288	0	0	0.00	0.00	0.00	99
69	1	5428	0	0	0.00	0.00	0.00	100
70	2	\N	\N	\N	22.80	0.00	0.00	101
71	1	3518	0	0	0.00	0.00	0.05	102
72	1	7270	0	0	0.00	716.80	0.00	103
73	2	2138	0	0	0.00	0.00	0.00	104
76	3	\N	\N	\N	7.75	0.00	0.00	105
77	2	\N	\N	\N	0.00	1026.40	0.00	106
79	1	\N	\N	\N	0.00	3481.60	0.00	107
80	2	1216	0	0	0.00	0.00	0.00	108
81	2	\N	\N	\N	0.00	156.00	0.00	109
82	2	\N	\N	\N	0.00	2562.40	0.00	110
84	3	2431	0	0	0.00	0.00	0.00	112
85	1	53	0	0	0.00	0.00	0.00	113
87	1	1467	0	0	0.00	0.00	0.00	114
88	2	7857	0	0	0.00	0.00	0.00	115
90	2	2704	0	0	0.00	0.00	0.00	116
91	3	564	0	0	0.00	0.00	0.00	117
92	2	638	0	0	0.00	872.80	0.00	118
93	1	7270	0	0	0.00	0.00	0.00	119
94	2	1679	0	0	0.00	0.00	0.00	120
95	1	9342	0	0	0.00	0.00	0.00	121
99	1	7885	0	0	0.00	0.00	0.00	122
101	2	1070	0	0	0.00	0.00	0.00	123
102	3	\N	\N	\N	6.45	123.84	0.00	124
103	3	1341	0	0	0.00	0.00	0.00	125
104	2	\N	\N	\N	0.00	4405.60	0.00	126
105	1	11185	0	0	0.00	0.00	0.00	127
106	2	2755	0	0	0.00	0.00	0.00	128
107	2	\N	\N	\N	0.00	3279.20	0.00	129
109	1	\N	\N	\N	0.00	9625.60	0.00	130
111	1	\N	\N	\N	56.20	2457.60	0.00	131
112	1	\N	\N	\N	0.00	6656.00	0.00	132
113	1	16613	0	0	0.00	0.00	0.00	133
114	1	5530	0	0	0.00	0.00	0.00	134
115	2	3424	0	0	0.00	0.00	0.00	135
118	2	4479	0	0	0.00	0.00	0.00	136
119	2	2027	0	0	0.00	0.00	0.00	137
122	1	8601	0	0	0.00	0.00	0.00	139
125	2	\N	\N	\N	32.80	0.00	0.00	140
126	2	856	0	0	0.00	0.00	0.00	141
127	1	11083	0	0	0.00	0.00	0.00	142
129	2	2137	0	0	0.00	0.00	0.00	143
130	2	2908	0	0	0.00	0.00	0.00	144
134	1	15179	0	0	48.40	0.00	0.00	145
135	1	5939	0	0	0.00	0.00	0.00	146
136	3	878	0	0	0.00	0.00	0.00	147
137	2	4632	0	0	0.00	0.00	0.00	148
140	2	1016	0	0	0.00	0.00	0.00	149
142	2	2547	0	0	0.00	0.00	0.00	150
145	2	5349	0	0	0.00	0.00	0.00	151
48	2	2557	0	0	0.00	2564.80	0.00	\N
47	3	1808	0	0	0.00	0.00	0.00	\N
46	1	8397	0	0	0.00	0.00	0.00	\N
45	2	2099	0	0	0.00	0.00	0.00	\N
44	3	2251	0	0	0.00	1496.96	0.00	\N
43	3	1473	0	0	0.00	0.00	0.00	\N
42	1	17613	0	0	37.00	0.00	0.05	\N
41	2	4875	0	0	0.00	0.00	0.00	\N
40	1	12902	0	0	0.00	0.00	0.00	\N
39	1	\N	\N	\N	117.80	0.00	0.00	\N
38	1	\N	\N	\N	47.00	0.00	0.05	\N
37	1	23859	0	0	0.00	0.00	0.00	\N
36	1	19968	0	0	0.00	0.00	0.00	\N
35	2	7421	0	0	28.40	0.00	0.00	\N
34	1	8192	0	0	18.40	0.00	0.00	\N
33	1	19763	0	0	0.00	0.00	0.00	\N
32	1	23142	0	0	0.00	0.00	0.05	\N
31	2	7011	0	0	0.00	0.00	0.00	\N
30	1	\N	\N	\N	93.80	5427.20	0.00	88
29	3	4593	0	0	0.00	0.00	0.00	87
28	2	5680	0	0	0.00	0.00	0.00	86
27	3	1822	0	0	0.00	0.00	0.00	85
26	1	\N	\N	\N	0.00	0.00	0.05	84
25	3	1760	0	0	0.00	758.72	0.00	83
24	3	660	0	0	0.00	0.00	0.00	\N
23	1	\N	\N	\N	0.00	7884.80	0.00	81
22	2	\N	\N	\N	5.30	0.00	0.00	80
21	3	1268	0	0	0.00	1024.96	0.00	79
20	1	\N	\N	\N	55.80	4198.40	0.05	89
17	2	2203	72	0	3.30	5071.20	0.00	48
16	3	4672	111	0	0.00	0.00	0.00	47
15	3	3909	90	0	12.00	8.00	0.01	46
14	2	509	84	0	0.00	0.00	0.00	45
53	1	544	0	0	0.00	0.00	0.05	90
54	1	\N	\N	\N	0.00	5222.40	0.00	91
55	2	3274	0	0	0.00	0.00	0.00	92
146	2	\N	\N	\N	8.30	0.00	0.00	152
149	2	2600	0	0	0.00	0.00	0.00	153
150	1	11186	0	0	62.80	0.00	0.00	154
\.


--
-- Data for Name: service_package; Type: TABLE DATA; Schema: public; Owner: -
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
20	amir_101	123456	customer	Amir Gaber	amir.gaber11@fmrz-telecom.com	80 Makram Ebeid, Luxor	2005-11-07
21	sara_102	123456	customer	Sara Hassan	sara.hassan12@fmrz-telecom.com	70 Abbas El Akkad, Alexandria	1999-12-28
22	sara_103	123456	customer	Sara Nasr	sara.nasr13@fmrz-telecom.com	65 Cornish Rd, Cairo	1995-12-30
23	mona_104	123456	customer	Mona Zaki	mona.zaki14@fmrz-telecom.com	91 El-Nasr St, Mansoura	1994-11-26
24	layla_105	123456	customer	Layla Khattab	layla.khattab15@fmrz-telecom.com	15 Tahrir Sq, Mansoura	1991-04-15
25	amir_106	123456	customer	Amir Ezzat	amir.ezzat16@fmrz-telecom.com	32 Makram Ebeid, Giza	2010-08-11
26	hassan_107	123456	customer	Hassan Soliman	hassan.soliman17@fmrz-telecom.com	28 Tahrir Sq, Suez	2002-07-14
27	ziad_108	123456	customer	Ziad Khattab	ziad.khattab18@fmrz-telecom.com	25 Cornish Rd, Mansoura	2004-01-04
28	mohamed_109	123456	customer	Mohamed Soliman	mohamed.soliman19@fmrz-telecom.com	27 Cornish Rd, Cairo	1987-10-22
29	youssef_110	123456	customer	Youssef Fouad	youssef.fouad20@fmrz-telecom.com	71 Gameat El Dowal, Giza	1989-11-25
30	fatma_111	123456	customer	Fatma Fouad	fatma.fouad21@fmrz-telecom.com	41 Tahrir Sq, Cairo	1995-07-01
31	sara_112	123456	customer	Sara Soliman	sara.soliman22@fmrz-telecom.com	54 Makram Ebeid, Alexandria	2006-12-15
32	ibrahim_113	123456	customer	Ibrahim Gaber	ibrahim.gaber23@fmrz-telecom.com	37 Tahrir Sq, Giza	1990-06-01
33	amir_114	123456	customer	Amir Nasr	amir.nasr24@fmrz-telecom.com	46 Tahrir Sq, Giza	1985-09-15
34	salma_115	123456	customer	Salma Soliman	salma.soliman25@fmrz-telecom.com	99 El-Nasr St, Mansoura	2011-01-18
35	amir_116	123456	customer	Amir Mansour	amir.mansour26@fmrz-telecom.com	85 Tahrir Sq, Cairo	1994-07-23
36	mona_117	123456	customer	Mona Hassan	mona.hassan27@fmrz-telecom.com	34 Cornish Rd, Mansoura	2007-05-30
37	youssef_118	123456	customer	Youssef Fouad	youssef.fouad28@fmrz-telecom.com	99 Makram Ebeid, Luxor	2002-02-03
38	ahmed_119	123456	customer	Ahmed Salem	ahmed.salem29@fmrz-telecom.com	35 Makram Ebeid, Luxor	1999-08-05
39	hassan_120	123456	customer	Hassan Wahba	hassan.wahba30@fmrz-telecom.com	22 Makram Ebeid, Alexandria	2003-08-15
40	nour_121	123456	customer	Nour Ezzat	nour.ezzat31@fmrz-telecom.com	71 Cornish Rd, Alexandria	1998-07-09
41	sara_122	123456	customer	Sara Soliman	sara.soliman32@fmrz-telecom.com	39 Abbas El Akkad, Luxor	2005-12-10
42	hassan_123	123456	customer	Hassan Khattab	hassan.khattab33@fmrz-telecom.com	56 El-Nasr St, Giza	2009-08-04
43	hassan_124	123456	customer	Hassan Said	hassan.said34@fmrz-telecom.com	32 Tahrir Sq, Giza	1990-05-08
44	ahmed_125	123456	customer	Ahmed Soliman	ahmed.soliman35@fmrz-telecom.com	90 Abbas El Akkad, Cairo	1988-09-08
45	nour_126	123456	customer	Nour Mansour	nour.mansour36@fmrz-telecom.com	69 Tahrir Sq, Alexandria	1999-03-22
46	ahmed_127	123456	customer	Ahmed Zaki	ahmed.zaki37@fmrz-telecom.com	30 Gameat El Dowal, Mansoura	2001-08-25
47	mohamed_128	123456	customer	Mohamed Mansour	mohamed.mansour38@fmrz-telecom.com	79 Cornish Rd, Cairo	2006-03-06
48	omar_129	123456	customer	Omar Fouad	omar.fouad39@fmrz-telecom.com	60 Cornish Rd, Cairo	2005-11-12
49	mona_130	123456	customer	Mona Nasr	mona.nasr40@fmrz-telecom.com	96 El-Nasr St, Giza	2005-07-12
52	layla_2001	password123	customer	Layla Hassan	layla_2001@fmrz-telecom.com	26 Cornish Rd, Hurghada	1999-12-22
53	ahmed_2002	password123	customer	Ahmed Gaber	ahmed_2002@fmrz-telecom.com	27 Zamalek Dr, Suez	1975-07-23
54	mona_2003	password123	customer	Mona Gaber	mona_2003@fmrz-telecom.com	57 Cornish Rd, Luxor	1981-02-02
55	omar_2004	password123	customer	Omar Said	omar_2004@fmrz-telecom.com	78 El-Nasr St, Mansoura	1991-06-24
56	mariam_2005	password123	customer	Mariam Soliman	mariam_2005@fmrz-telecom.com	29 Cornish Rd, Aswan	2005-01-29
57	layla_2006	password123	customer	Layla Salem	layla_2006@fmrz-telecom.com	42 Gameat El Dowal, Giza	2007-02-26
58	omar_2007	password123	customer	Omar Said	omar_2007@fmrz-telecom.com	17 Cornish Rd, Cairo	2009-10-15
59	ziad_2008	password123	customer	Ziad Wahba	ziad_2008@fmrz-telecom.com	88 El-Nasr St, Suez	1994-09-03
60	tarek_2009	password123	customer	Tarek Salem	tarek_2009@fmrz-telecom.com	86 Gameat El Dowal, Giza	2007-03-25
61	tarek_2010	password123	customer	Tarek Gaber	tarek_2010@fmrz-telecom.com	41 Gameat El Dowal, Aswan	1987-08-25
62	mohamed_2011	password123	customer	Mohamed Said	mohamed_2011@fmrz-telecom.com	17 Abbas El Akkad, Giza	2001-11-02
63	fatma_2012	password123	customer	Fatma Soliman	fatma_2012@fmrz-telecom.com	93 Tahrir Sq, Giza	2009-05-29
64	salma_2013	password123	customer	Salma Moussa	salma_2013@fmrz-telecom.com	39 9th Street, Suez	1975-12-05
65	ziad_2014	password123	customer	Ziad Hassan	ziad_2014@fmrz-telecom.com	92 Maadi St, Suez	1980-10-26
66	mohamed_2015	password123	customer	Mohamed Nasr	mohamed_2015@fmrz-telecom.com	24 Tahrir Sq, Suez	1977-01-15
67	amir_2016	password123	customer	Amir Wahba	amir_2016@fmrz-telecom.com	45 El-Nasr St, Aswan	1987-03-05
68	dina_2017	password123	customer	Dina Hassan	dina_2017@fmrz-telecom.com	31 Cornish Rd, Hurghada	1974-11-25
69	layla_2018	password123	customer	Layla Salem	layla_2018@fmrz-telecom.com	10 Tahrir Sq, Giza	2003-10-05
70	ziad_2019	password123	customer	Ziad Moussa	ziad_2019@fmrz-telecom.com	29 Cornish Rd, Cairo	2000-07-30
71	ahmed_2020	password123	customer	Ahmed Salem	ahmed_2020@fmrz-telecom.com	90 Tahrir Sq, Hurghada	1974-03-06
72	mohamed_2021	password123	customer	Mohamed Zaki	mohamed_2021@fmrz-telecom.com	73 Maadi St, Hurghada	1975-10-22
73	youssef_2022	password123	customer	Youssef Badawi	youssef_2022@fmrz-telecom.com	45 Zamalek Dr, Hurghada	1973-12-31
74	khaled_2023	password123	customer	Khaled Zaki	khaled_2023@fmrz-telecom.com	61 Tahrir Sq, Suez	1985-06-28
75	sara_2024	password123	customer	Sara Wahba	sara_2024@fmrz-telecom.com	99 9th Street, Mansoura	2004-07-12
76	ahmed_2025	password123	customer	Ahmed Wahba	ahmed_2025@fmrz-telecom.com	95 El-Nasr St, Aswan	1976-12-02
77	ahmed_2026	password123	customer	Ahmed Said	ahmed_2026@fmrz-telecom.com	13 El-Nasr St, Aswan	1993-02-12
78	ahmed_2027	password123	customer	Ahmed Fouad	ahmed_2027@fmrz-telecom.com	32 Tahrir Sq, Giza	1980-09-03
79	dina_2028	password123	customer	Dina Badawi	dina_2028@fmrz-telecom.com	28 Abbas El Akkad, Giza	1971-07-21
80	ibrahim_2029	password123	customer	Ibrahim Said	ibrahim_2029@fmrz-telecom.com	73 Maadi St, Hurghada	2000-08-01
81	tarek_2030	password123	customer	Tarek Khattab	tarek_2030@fmrz-telecom.com	51 Makram Ebeid, Aswan	1988-04-02
82	tarek_2031	password123	customer	Tarek Khattab	tarek_2031@fmrz-telecom.com	84 Zamalek Dr, Suez	1979-02-08
83	dina_2032	password123	customer	Dina Zaki	dina_2032@fmrz-telecom.com	76 Gameat El Dowal, Luxor	1977-12-31
84	dina_2033	password123	customer	Dina Said	dina_2033@fmrz-telecom.com	12 Abbas El Akkad, Cairo	1982-07-27
85	mariam_2034	password123	customer	Mariam Said	mariam_2034@fmrz-telecom.com	96 Gameat El Dowal, Hurghada	2004-09-06
86	fatma_2035	password123	customer	Fatma Hamad	fatma_2035@fmrz-telecom.com	27 9th Street, Mansoura	1980-12-18
87	omar_2036	password123	customer	Omar Salem	omar_2036@fmrz-telecom.com	85 Makram Ebeid, Alexandria	2010-01-27
88	youssef_2037	password123	customer	Youssef Gaber	youssef_2037@fmrz-telecom.com	78 Gameat El Dowal, Mansoura	1980-07-26
89	ibrahim_2038	password123	customer	Ibrahim Hassan	ibrahim_2038@fmrz-telecom.com	87 Maadi St, Aswan	1978-09-07
90	mariam_2039	password123	customer	Mariam Khattab	mariam_2039@fmrz-telecom.com	36 Makram Ebeid, Aswan	1976-08-01
91	tarek_2040	password123	customer	Tarek Soliman	tarek_2040@fmrz-telecom.com	30 Abbas El Akkad, Mansoura	1977-12-15
92	dina_2041	password123	customer	Dina Zaki	dina_2041@fmrz-telecom.com	55 Makram Ebeid, Alexandria	2006-10-19
93	salma_2042	password123	customer	Salma Wahba	salma_2042@fmrz-telecom.com	83 Gameat El Dowal, Aswan	2002-01-19
94	fatma_2043	password123	customer	Fatma Said	fatma_2043@fmrz-telecom.com	26 Tahrir Sq, Alexandria	1980-07-27
95	hassan_2044	password123	customer	Hassan Fouad	hassan_2044@fmrz-telecom.com	41 El-Nasr St, Suez	1976-07-17
96	fatma_2045	password123	customer	Fatma Ezzat	fatma_2045@fmrz-telecom.com	22 Gameat El Dowal, Luxor	1982-09-24
97	omar_2046	password123	customer	Omar Said	omar_2046@fmrz-telecom.com	79 Gameat El Dowal, Aswan	1996-01-06
98	ibrahim_2047	password123	customer	Ibrahim Ezzat	ibrahim_2047@fmrz-telecom.com	29 9th Street, Mansoura	2008-06-02
99	mona_2048	password123	customer	Mona Khattab	mona_2048@fmrz-telecom.com	13 Gameat El Dowal, Alexandria	1976-08-10
100	dina_2049	password123	customer	Dina Fouad	dina_2049@fmrz-telecom.com	45 Makram Ebeid, Giza	2008-04-14
101	ahmed_2050	password123	customer	Ahmed Badawi	ahmed_2050@fmrz-telecom.com	83 Cornish Rd, Alexandria	1991-12-10
102	salma_2051	password123	customer	Salma Hamad	salma_2051@fmrz-telecom.com	19 Abbas El Akkad, Luxor	1977-10-15
103	hala_2052	password123	customer	Hala Hassan	hala_2052@fmrz-telecom.com	63 Cornish Rd, Mansoura	1982-03-17
104	sameh_2053	password123	customer	Sameh Ezzat	sameh_2053@fmrz-telecom.com	19 9th Street, Cairo	1993-04-12
105	mariam_2054	password123	customer	Mariam Gaber	mariam_2054@fmrz-telecom.com	76 Abbas El Akkad, Luxor	1988-09-15
106	fatma_2055	password123	customer	Fatma Gaber	fatma_2055@fmrz-telecom.com	50 Cornish Rd, Mansoura	2000-11-13
107	amir_2056	password123	customer	Amir Said	amir_2056@fmrz-telecom.com	62 El-Nasr St, Alexandria	1978-11-14
108	nour_2057	password123	customer	Nour Gaber	nour_2057@fmrz-telecom.com	69 Abbas El Akkad, Luxor	1982-12-19
109	tarek_2058	password123	customer	Tarek Fouad	tarek_2058@fmrz-telecom.com	33 El-Nasr St, Cairo	1997-03-03
110	ibrahim_2059	password123	customer	Ibrahim Khattab	ibrahim_2059@fmrz-telecom.com	69 Zamalek Dr, Mansoura	1994-07-09
111	tarek_2060	password123	customer	Tarek Moussa	tarek_2060@fmrz-telecom.com	53 Cornish Rd, Luxor	1975-10-07
112	ahmed_2061	password123	customer	Ahmed Gaber	ahmed_2061@fmrz-telecom.com	13 Gameat El Dowal, Mansoura	1973-07-28
113	hala_2062	password123	customer	Hala Gaber	hala_2062@fmrz-telecom.com	62 Tahrir Sq, Aswan	1999-01-27
114	layla_2063	password123	customer	Layla Said	layla_2063@fmrz-telecom.com	58 Makram Ebeid, Mansoura	1972-10-29
115	khaled_2064	password123	customer	Khaled Mansour	khaled_2064@fmrz-telecom.com	64 Makram Ebeid, Mansoura	1997-05-10
116	mona_2065	password123	customer	Mona Wahba	mona_2065@fmrz-telecom.com	14 Tahrir Sq, Suez	1977-04-27
117	sara_2066	password123	customer	Sara Mansour	sara_2066@fmrz-telecom.com	54 Gameat El Dowal, Giza	1995-06-28
118	hala_2067	password123	customer	Hala Moussa	hala_2067@fmrz-telecom.com	20 Makram Ebeid, Mansoura	1972-11-22
119	khaled_2068	password123	customer	Khaled Ezzat	khaled_2068@fmrz-telecom.com	38 Tahrir Sq, Aswan	1975-05-17
120	nour_2069	password123	customer	Nour Nasr	nour_2069@fmrz-telecom.com	90 Tahrir Sq, Suez	1973-01-18
121	mohamed_2070	password123	customer	Mohamed Hamad	mohamed_2070@fmrz-telecom.com	99 Abbas El Akkad, Mansoura	2009-08-31
122	sameh_2071	password123	customer	Sameh Khattab	sameh_2071@fmrz-telecom.com	52 Gameat El Dowal, Mansoura	1986-10-23
123	hala_2072	password123	customer	Hala Hassan	hala_2072@fmrz-telecom.com	14 Tahrir Sq, Luxor	1993-10-08
124	sara_2073	password123	customer	Sara Moussa	sara_2073@fmrz-telecom.com	96 Cornish Rd, Suez	2005-04-11
125	ziad_2074	password123	customer	Ziad Fouad	ziad_2074@fmrz-telecom.com	63 Cornish Rd, Giza	1970-04-29
126	mona_2075	password123	customer	Mona Ezzat	mona_2075@fmrz-telecom.com	95 Tahrir Sq, Cairo	2002-05-11
127	tarek_2076	password123	customer	Tarek Badawi	tarek_2076@fmrz-telecom.com	92 Abbas El Akkad, Alexandria	2002-02-10
128	nour_2077	password123	customer	Nour Ezzat	nour_2077@fmrz-telecom.com	55 Zamalek Dr, Aswan	1989-08-25
129	ziad_2078	password123	customer	Ziad Mansour	ziad_2078@fmrz-telecom.com	15 Tahrir Sq, Hurghada	2004-03-29
130	nour_2079	password123	customer	Nour Ezzat	nour_2079@fmrz-telecom.com	71 Makram Ebeid, Aswan	1973-12-28
131	mona_2080	password123	customer	Mona Hassan	mona_2080@fmrz-telecom.com	68 9th Street, Suez	1996-04-04
132	mona_2081	password123	customer	Mona Hamad	mona_2081@fmrz-telecom.com	37 Tahrir Sq, Giza	2007-08-05
133	youssef_2082	password123	customer	Youssef Gaber	youssef_2082@fmrz-telecom.com	47 Zamalek Dr, Hurghada	1976-05-18
134	tarek_2083	password123	customer	Tarek Hassan	tarek_2083@fmrz-telecom.com	38 El-Nasr St, Cairo	2010-10-20
135	mohamed_2084	password123	customer	Mohamed Khattab	mohamed_2084@fmrz-telecom.com	80 Zamalek Dr, Suez	2000-01-09
136	omar_2085	password123	customer	Omar Badawi	omar_2085@fmrz-telecom.com	64 9th Street, Aswan	1970-05-06
137	omar_2086	password123	customer	Omar Hamad	omar_2086@fmrz-telecom.com	16 Maadi St, Alexandria	1987-10-01
138	mariam_2087	password123	customer	Mariam Said	mariam_2087@fmrz-telecom.com	13 Zamalek Dr, Aswan	1985-05-28
139	sara_2088	password123	customer	Sara Gaber	sara_2088@fmrz-telecom.com	98 9th Street, Hurghada	1973-01-28
140	khaled_2089	password123	customer	Khaled Fouad	khaled_2089@fmrz-telecom.com	48 Cornish Rd, Suez	2009-07-11
141	mona_2090	password123	customer	Mona Fouad	mona_2090@fmrz-telecom.com	71 9th Street, Hurghada	1988-03-06
142	nour_2091	password123	customer	Nour Khattab	nour_2091@fmrz-telecom.com	60 Zamalek Dr, Hurghada	1996-05-08
143	mohamed_2092	password123	customer	Mohamed Khattab	mohamed_2092@fmrz-telecom.com	59 El-Nasr St, Alexandria	1993-08-03
144	fatma_2093	password123	customer	Fatma Hassan	fatma_2093@fmrz-telecom.com	88 Makram Ebeid, Suez	1989-02-06
145	omar_2094	password123	customer	Omar Moussa	omar_2094@fmrz-telecom.com	67 Makram Ebeid, Mansoura	2003-04-06
146	mohamed_2095	password123	customer	Mohamed Soliman	mohamed_2095@fmrz-telecom.com	26 El-Nasr St, Mansoura	1990-12-01
147	mohamed_2096	password123	customer	Mohamed Badawi	mohamed_2096@fmrz-telecom.com	98 Maadi St, Alexandria	1971-05-07
148	mona_2097	password123	customer	Mona Zaki	mona_2097@fmrz-telecom.com	63 El-Nasr St, Cairo	2007-12-04
149	ziad_2098	password123	customer	Ziad Moussa	ziad_2098@fmrz-telecom.com	29 Gameat El Dowal, Mansoura	1997-05-08
150	mona_2099	password123	customer	Mona Soliman	mona_2099@fmrz-telecom.com	34 Tahrir Sq, Aswan	1978-07-03
151	amir_2100	password123	customer	Amir Salem	amir_2100@fmrz-telecom.com	48 Cornish Rd, Suez	1978-09-03
152	testuser_auto	pass	customer	Test User	test@test.com	\N	\N
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

\unrestrict RwFaKbTXk7nYR5bL27HUW2WoLPEKeB2FMh47bNOgy8dDkNtB0Sdofnsrg61hotk

