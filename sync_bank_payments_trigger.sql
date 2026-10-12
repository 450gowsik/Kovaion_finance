-- ==============================================================================
-- KOVAION ENTERPRISE SUITE — LIVE BANK SYNCHRONIZATION TRIGGER
-- Application: 47919 | Oracle APEX 26.1 / Oracle Autonomous Database
-- Target: Oracle APEX -> SQL Workshop -> SQL Commands
-- ==============================================================================
-- Purpose:
-- Automatically syncs KF_BANK_ACCOUNTS and KF_BANK_TRANSACTIONS whenever
-- payments are recorded or updated in KF_PAYMENTS or Page 10!
-- ==============================================================================

CREATE OR REPLACE TRIGGER TRG_KF_SYNC_BANK_PAYMENTS
AFTER INSERT OR UPDATE OR DELETE ON KF_PAYMENTS
FOR EACH ROW
BEGIN
    -- 1. When a new payment is COMPLETED, deduct from HDFC Bank Operating Account
    IF INSERTING AND :NEW.STATUS = 'COMPLETED' THEN
        UPDATE KF_BANK_ACCOUNTS 
        SET CURRENT_BALANCE = CURRENT_BALANCE - :NEW.PAYMENT_AMOUNT,
            RECONCILED_BALANCE = RECONCILED_BALANCE - :NEW.PAYMENT_AMOUNT,
            LAST_RECONCILED_DATE = SYSDATE
        WHERE ACCOUNT_NUMBER = '982145001234';

        -- Insert matching Debit transaction into Bank Ledger
        INSERT INTO KF_BANK_TRANSACTIONS (
            ACCOUNT_ID, TRANSACTION_DATE, VALUE_DATE, TRANSACTION_TYPE, AMOUNT,
            REFERENCE_NUMBER, DESCRIPTION, COUNTERPARTY_NAME, CATEGORY, RECONCILIATION_STATUS
        ) VALUES (
            (SELECT ACCOUNT_ID FROM KF_BANK_ACCOUNTS WHERE ACCOUNT_NUMBER = '982145001234'),
            NVL(:NEW.PAYMENT_DATE, SYSDATE),
            SYSDATE,
            'DR',
            :NEW.PAYMENT_AMOUNT,
            NVL(:NEW.REFERENCE_NUMBER, 'DISB-' || :NEW.PAYMENT_ID),
            'Vendor Disbursement Settlement',
            (SELECT VENDOR_NAME FROM KF_VENDORS WHERE VENDOR_ID = :NEW.VENDOR_ID),
            'VENDOR_PAYMENT',
            'RECONCILED'
        );

    -- 2. When an existing payment status changes to COMPLETED
    ELSIF UPDATING AND :NEW.STATUS = 'COMPLETED' AND (:OLD.STATUS IS NULL OR :OLD.STATUS != 'COMPLETED') THEN
        UPDATE KF_BANK_ACCOUNTS 
        SET CURRENT_BALANCE = CURRENT_BALANCE - :NEW.PAYMENT_AMOUNT,
            RECONCILED_BALANCE = RECONCILED_BALANCE - :NEW.PAYMENT_AMOUNT,
            LAST_RECONCILED_DATE = SYSDATE
        WHERE ACCOUNT_NUMBER = '982145001234';

    -- 3. When a payment is cancelled or deleted, refund the bank balance
    ELSIF (DELETING AND :OLD.STATUS = 'COMPLETED') 
       OR (UPDATING AND :OLD.STATUS = 'COMPLETED' AND :NEW.STATUS != 'COMPLETED') THEN
        UPDATE KF_BANK_ACCOUNTS 
        SET CURRENT_BALANCE = CURRENT_BALANCE + :OLD.PAYMENT_AMOUNT,
            RECONCILED_BALANCE = RECONCILED_BALANCE + :OLD.PAYMENT_AMOUNT,
            LAST_RECONCILED_DATE = SYSDATE
        WHERE ACCOUNT_NUMBER = '982145001234';
    END IF;
END;
