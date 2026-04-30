
-- MASS UPDATE FOR HIGH-DENSITY USAGE SIMULATION
BEGIN;

-- 1. Temporary table for random values
CREATE TEMP TABLE bill_updates AS
SELECT 
    id,
    (random() * 450 + 50)::INT as v_usage,
    (random() * 4900 + 100)::BIGINT as d_usage,
    (random() * 90 + 10)::INT as s_usage,
    (random() * 150)::NUMERIC(12,2) as o_charge,
    (random() * 400)::NUMERIC(12,2) as r_charge
FROM bill
WHERE id BETWEEN 312 AND 360;

-- 2. Apply updates and recalculate totals
UPDATE bill b
SET 
    voice_usage = u.v_usage,
    data_usage = u.d_usage,
    sms_usage = u.s_usage,
    overage_charge = u.o_charge,
    roaming_charge = u.r_charge,
    taxes = ROUND((recurring_fees + u.o_charge + u.r_charge - promotional_discount) * 0.14, 2),
    total_amount = ROUND((recurring_fees + u.o_charge + u.r_charge - promotional_discount) * 1.14, 2)
FROM bill_updates u
WHERE b.id = u.id;

-- 3. Ensure Bob's bill is EXTRA massive as requested
UPDATE bill
SET 
    voice_usage = 1255,
    data_usage = 53687, -- 50GB in MB
    sms_usage = 150,
    overage_charge = 500.00,
    roaming_charge = 1200.00,
    taxes = ROUND((recurring_fees + 1700.00) * 0.14, 2),
    total_amount = ROUND((recurring_fees + 1700.00) * 1.14, 2)
WHERE id = 353;

COMMIT;
