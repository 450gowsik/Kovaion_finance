-- ==============================================================================
-- FIX MISSING DATABASE DEPENDENCIES FOR OLD PAGE 1 PL/SQL SCRIPT
-- ==============================================================================
-- The old PL/SQL script failed because it referenced:
-- 1. Column TAX_AMOUNT in KF_INVOICES (table only has GST_AMOUNT)
-- 2. View KF_VW_INVOICE_BALANCES (which did not exist)
--
-- Running this script adds the missing column and creates the view so the
-- PL/SQL code compiles with ZERO errors!
-- ==============================================================================

BEGIN
    -- 1. Safely add TAX_AMOUNT to KF_INVOICES if it does not exist
    BEGIN
        EXECUTE IMMEDIATE 'ALTER TABLE KF_INVOICES ADD (TAX_AMOUNT NUMBER)';
    EXCEPTION WHEN OTHERS THEN NULL; END;

    -- 2. Copy values from GST_AMOUNT into TAX_AMOUNT
    BEGIN
        EXECUTE IMMEDIATE 'UPDATE KF_INVOICES SET TAX_AMOUNT = NVL(GST_AMOUNT, 0) WHERE TAX_AMOUNT IS NULL';
        COMMIT;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    -- 3. Create the missing analytical view KF_VW_INVOICE_BALANCES
    EXECUTE IMMEDIATE '
    CREATE OR REPLACE VIEW KF_VW_INVOICE_BALANCES AS
    SELECT 
        i.INVOICE_ID,
        i.INVOICE_NUMBER,
        i.TOTAL_AMOUNT,
        NVL(p.TOTAL_PAID, 0) AS TOTAL_PAID,
        (i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) AS BALANCE_AMOUNT
    FROM KF_INVOICES i
    LEFT JOIN (
        SELECT INVOICE_ID, SUM(PAYMENT_AMOUNT) AS TOTAL_PAID
        FROM KF_PAYMENTS
        WHERE STATUS = ''COMPLETED''
        GROUP BY INVOICE_ID
    ) p ON i.INVOICE_ID = p.INVOICE_ID';
END;
