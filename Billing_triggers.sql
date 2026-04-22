
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