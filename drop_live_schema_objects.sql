-- ==============================================================================
-- CLEANUP / DROP LIVE SUBLEDGER OBJECTS
-- Target: Oracle APEX -> SQL Workshop -> SQL Commands
-- ==============================================================================
-- Safely drops any newly created AR and Banking tables/views
-- ==============================================================================

BEGIN
    -- Drop Analytical View first
    FOR v IN (SELECT view_name FROM user_views WHERE view_name = 'KF_VW_AR_BALANCES') LOOP
        EXECUTE IMMEDIATE 'DROP VIEW ' || v.view_name;
    END LOOP;

    -- Drop AR and Bank Tables in reverse dependency order
    FOR t IN (
        SELECT table_name FROM user_tables 
        WHERE table_name IN (
            'KF_AR_PAYMENTS',
            'KF_AR_INVOICES',
            'KF_BANK_TRANSACTIONS',
            'KF_BANK_ACCOUNTS',
            'KF_CUSTOMERS'
        )
    ) LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
    END LOOP;
END;
