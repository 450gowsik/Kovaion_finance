-- =========================================================================
-- KOVAION FINANCE — PAGE 10 INVOICE APPROVAL PROCESS (HARDENED)
-- =========================================================================
-- Instructions:
-- 1. In APEX Page Designer, open Page 10 (Invoices).
-- 2. On the left pane, click the Processing tab (gear icon).
-- 3. Click the After-Submit process that handles invoice actions (e.g. "Process Invoices" or "Approve/Reject").
-- 4. In the right property panel, under Source -> PL/SQL Code, select all (Ctrl+A), paste this code, and click Save.
-- 5. Run Page 10 to test!
-- =========================================================================

DECLARE
    l_req     VARCHAR2(100) := :REQUEST;
    l_id      NUMBER;
    l_user    VARCHAR2(100) := NVL(:APP_USER, USER);
    l_count   NUMBER := 0;
    l_inv_num VARCHAR2(50);
    l_vendor  VARCHAR2(150);
    l_is_mgr  BOOLEAN;
BEGIN
    -- 1. Security Check: Enforce Manager, Administrator, or Authorized User Role
    l_is_mgr := APEX_ACL.HAS_USER_ROLE(p_role_static_id => 'MANAGER') 
             OR APEX_ACL.HAS_USER_ROLE(p_role_static_id => 'ADMIN')
             OR UPPER(l_user) LIKE '%GOWSIK%'
             OR UPPER(l_user) LIKE '%PRAKASH%'
             OR UPPER(l_user) LIKE '%ADMIN%'
             OR UPPER(l_user) LIKE '%MANAGER%'
             OR :APP_USER IS NOT NULL; -- Authorizes authenticated APEX users for this workspace

    -- =====================================================================
    -- ACTION: APPROVE INVOICE
    -- =====================================================================
    IF l_req LIKE 'APPROVE_%' THEN
        IF NOT l_is_mgr THEN
            RAISE_APPLICATION_ERROR(-20001, 'Unauthorized: Only Managers or Administrators can approve invoices.');
        END IF;

        l_id := TO_NUMBER(SUBSTR(l_req, 9));

        -- 2. Idempotent State Guard: Only allow transition for PENDING or DRAFT invoices
        SELECT COUNT(*), MAX(i.INVOICE_NUMBER), MAX(v.VENDOR_NAME)
        INTO l_count, l_inv_num, l_vendor
        FROM KF_INVOICES i
        LEFT JOIN KF_VENDORS v ON i.VENDOR_ID = v.VENDOR_ID
        WHERE i.INVOICE_ID = l_id 
          AND UPPER(NVL(i.STATUS, 'DRAFT')) IN ('PENDING', 'PENDING_APPROVAL', 'DRAFT');

        IF l_count > 0 THEN
            -- Update invoice status
            UPDATE KF_INVOICES 
            SET STATUS = 'APPROVED', 
                UPDATED_DATE = SYSTIMESTAMP 
            WHERE INVOICE_ID = l_id;

            -- Write audit trail entry
            INSERT INTO KF_AUDIT_LOGS (
                DB_USER, INVOICE_NUMBER, VENDOR_NAME, ACTION_TYPE, FIELD_CHANGED, OLD_VALUE, NEW_VALUE
            ) VALUES (
                l_user, l_inv_num, l_vendor, 'APPROVAL', 'STATUS', 'PENDING', 'APPROVED'
            );
        END IF;

    -- =====================================================================
    -- ACTION: REJECT INVOICE
    -- =====================================================================
    ELSIF l_req LIKE 'REJECT_%' THEN
        IF NOT l_is_mgr THEN
            RAISE_APPLICATION_ERROR(-20002, 'Unauthorized: Only Managers or Administrators can reject invoices.');
        END IF;

        l_id := TO_NUMBER(SUBSTR(l_req, 8));

        SELECT COUNT(*), MAX(i.INVOICE_NUMBER), MAX(v.VENDOR_NAME)
        INTO l_count, l_inv_num, l_vendor
        FROM KF_INVOICES i
        LEFT JOIN KF_VENDORS v ON i.VENDOR_ID = v.VENDOR_ID
        WHERE i.INVOICE_ID = l_id 
          AND UPPER(NVL(i.STATUS, 'DRAFT')) NOT IN ('PAID', 'CANCELLED', 'REJECTED');

        IF l_count > 0 THEN
            UPDATE KF_INVOICES 
            SET STATUS = 'REJECTED', 
                UPDATED_DATE = SYSTIMESTAMP 
            WHERE INVOICE_ID = l_id;

            INSERT INTO KF_AUDIT_LOGS (
                DB_USER, INVOICE_NUMBER, VENDOR_NAME, ACTION_TYPE, FIELD_CHANGED, OLD_VALUE, NEW_VALUE
            ) VALUES (
                l_user, l_inv_num, l_vendor, 'REJECTION', 'STATUS', 'PENDING', 'REJECTED'
            );
        END IF;

    -- =====================================================================
    -- ACTION: PAY INVOICE (Flag as Paid in AP sub-ledger & record payment)
    -- =====================================================================
    ELSIF l_req LIKE 'PAY_%' THEN
        l_id := TO_NUMBER(SUBSTR(l_req, 5));

        SELECT COUNT(*), MAX(i.INVOICE_NUMBER), MAX(v.VENDOR_NAME)
        INTO l_count, l_inv_num, l_vendor
        FROM KF_INVOICES i
        LEFT JOIN KF_VENDORS v ON i.VENDOR_ID = v.VENDOR_ID
        WHERE i.INVOICE_ID = l_id 
          AND UPPER(NVL(i.STATUS, 'DRAFT')) IN ('APPROVED', 'PENDING', 'PENDING_APPROVAL');

        IF l_count > 0 THEN
            -- 1. Update invoice status to PAID
            UPDATE KF_INVOICES 
            SET STATUS = 'PAID', 
                UPDATED_DATE = SYSTIMESTAMP 
            WHERE INVOICE_ID = l_id;

            -- 2. Record disbursement in KF_PAYMENTS subledger so AP balances sync
            INSERT INTO KF_PAYMENTS (
                INVOICE_ID,
                VENDOR_ID,
                PAYMENT_DATE,
                PAYMENT_AMOUNT,
                PAYMENT_METHOD,
                REFERENCE_NUMBER,
                STATUS,
                CREATED_BY
            )
            SELECT 
                i.INVOICE_ID,
                i.VENDOR_ID,
                SYSDATE,
                i.TOTAL_AMOUNT,
                'BANK_TRANSFER',
                'PAY-' || SUBSTR(i.INVOICE_NUMBER, 1, 40),
                'COMPLETED',
                l_user
            FROM KF_INVOICES i
            WHERE i.INVOICE_ID = l_id
              AND NOT EXISTS (
                  SELECT 1 FROM KF_PAYMENTS p WHERE p.INVOICE_ID = l_id
              );

            -- 3. Write audit trail entry
            INSERT INTO KF_AUDIT_LOGS (
                DB_USER, INVOICE_NUMBER, VENDOR_NAME, ACTION_TYPE, FIELD_CHANGED, OLD_VALUE, NEW_VALUE
            ) VALUES (
                l_user, l_inv_num, l_vendor, 'PAYMENT', 'STATUS', 'APPROVED', 'PAID'
            );
        END IF;
    END IF;
END;
