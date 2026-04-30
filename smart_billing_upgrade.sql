
-- ============================================================================
-- FMRZ SMART BILLING UPGRADE: CLOUD-HARDENED STABILIZATION (NEON)
-- ============================================================================
-- This script ensures your Cloud DB is 100% synced with local logic.
-- Features: Split Rating, Promotional Savings, and Math Precision.

BEGIN;

ALTER TABLE bill ALTER COLUMN data_usage TYPE BIGINT;
ALTER TABLE ror_contract ALTER COLUMN data TYPE BIGINT;
ALTER TABLE ror_contract ALTER COLUMN roaming_data TYPE BIGINT;

ALTER TABLE bill ADD COLUMN IF NOT EXISTS overage_charge NUMERIC(12,2) DEFAULT 0.00;
ALTER TABLE bill ADD COLUMN IF NOT EXISTS roaming_charge NUMERIC(12,2) DEFAULT 0.00;
ALTER TABLE bill ADD COLUMN IF NOT EXISTS promotional_discount NUMERIC(12,2) DEFAULT 0.00;
ALTER TYPE contract_status ADD VALUE IF NOT EXISTS 'suspended_debt';

ALTER TABLE cdr ADD COLUMN IF NOT EXISTS rated_service_id INTEGER;

-- Fix MSISDN Recycling Index (Conditional Uniqueness)
DROP INDEX IF EXISTS contract_msisdn_active_idx;
ALTER TABLE contract DROP CONSTRAINT IF EXISTS contract_msisdn_key;
CREATE UNIQUE INDEX IF NOT EXISTS contract_msisdn_active_idx ON contract (msisdn) WHERE (status != 'terminated');

-- 2. RATING ENGINE (Split Domestic/Roaming)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rate_cdr(p_cdr_id integer)
 RETURNS void
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
$$ LANGUAGE plpgsql;

-- 3. BILLING ENGINE (Math Precision & Savings)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS get_dashboard_stats();
CREATE OR REPLACE FUNCTION get_dashboard_stats()
    RETURNS TABLE (
                      total_customers  BIGINT,
                      total_contracts  BIGINT,
                      active_contracts BIGINT,
                      suspended_contracts BIGINT,
                      suspended_debt_contracts BIGINT,
                      terminated_contracts BIGINT,
                      total_cdrs       BIGINT
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
            (SELECT COUNT(*) FROM cdr);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.generate_bill(p_contract_id integer, p_billing_period_start date)
 RETURNS integer
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

      SELECT 
        COALESCE(voice + data + sms, 0),
        COALESCE(roaming_voice + roaming_data + roaming_sms, 0)
      INTO v_overage_charge, v_roaming_charge
      FROM ror_contract WHERE contract_id = p_contract_id AND bill_id IS NULL;

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
      
      -- Update ror_contract to link to this bill
      UPDATE ror_contract SET bill_id = v_bill_id WHERE contract_id = p_contract_id AND bill_id IS NULL;
      UPDATE contract_consumption SET bill_id = v_bill_id, is_billed = TRUE WHERE contract_id = p_contract_id AND starting_date = p_billing_period_start;
      
      RETURN v_bill_id;
  END;
$$ LANGUAGE plpgsql;

-- 4. REPORTING (Invoice Support)
-- ----------------------------------------------------------------------------
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
BEGIN
    SELECT contract_id INTO v_contract_id FROM bill WHERE id = p_bill_id;
    
    RETURN QUERY
    -- Bundled usage
    SELECT 
        sp.type::TEXT, sp.name::TEXT, cc.quota_limit::INTEGER, cc.consumed::INTEGER,
        0::NUMERIC(12,4), 0::NUMERIC(12,2), sp.is_roaming, (sp.name ~* 'Welcome|Gift|Bonus'),
        'Bundle item'::TEXT
    FROM contract_consumption cc JOIN service_package sp ON cc.service_package_id = sp.id
    WHERE cc.bill_id = p_bill_id
    
    UNION ALL
    -- Voice overage
    SELECT 'voice', 'Overage - Voice', NULL, rc.voice::INTEGER, rp.ror_voice,
           ROUND((rc.voice * rp.ror_voice)::NUMERIC, 2), FALSE, FALSE, 'Overage min'
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.bill_id = p_bill_id AND rc.voice > 0
    
    UNION ALL
    -- Data overage (Bytes to MB in consumed, but price per GB)
    SELECT 'data', 'Overage - Data', NULL, (rc.data / 1048576)::INTEGER, rp.ror_data,
           ROUND((rc.data / 1073741824.0 * rp.ror_data)::NUMERIC, 2), FALSE, FALSE, 'Overage data'
    FROM ror_contract rc JOIN rateplan rp ON rc.rateplan_id = rp.id
    WHERE rc.bill_id = p_bill_id AND rc.data > 0;
END;
$$ LANGUAGE plpgsql;

COMMIT;
