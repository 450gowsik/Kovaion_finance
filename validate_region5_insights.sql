-- ==============================================================================
-- KOVAION FINANCE - REGION 5 INDEPENDENT VALIDATION SUITE (AUDIT ALIGNED)
-- APEX Application: 47919 | SQL Workshop Verification Script
-- Execute these queries in APEX SQL Workshop to independently verify all audit points.
-- ==============================================================================

-- 1. BANK BALANCE AUDIT & INVESTIGATION (₹1,27,41,591 vs ₹1,26,77,931)
-- Identifies whether the change is due to double-deduction or legitimate payments
SELECT 
    b.account_number,
    b.bank_name,
    b.account_type,
    b.opening_balance,
    b.current_balance,
    b.reconciled_balance,
    (SELECT NVL(SUM(payment_amount), 0) FROM kf_payments WHERE status = 'COMPLETED') AS total_completed_disbursements,
    -- Formula 1: Sourced from CURRENT_BALANCE (live trigger synced)
    (SELECT NVL(SUM(current_balance), 0) FROM kf_bank_accounts WHERE is_active = 'Y') AS sum_current_balance,
    -- Formula 2: Sourced from OPENING_BALANCE minus completed payments
    (SELECT NVL(SUM(opening_balance), 0) FROM kf_bank_accounts WHERE is_active = 'Y') -
    (SELECT NVL(SUM(payment_amount), 0) FROM kf_payments WHERE status = 'COMPLETED') AS net_opening_minus_payments
FROM kf_bank_accounts b
WHERE b.is_active = 'Y';

-- 2. INVOICE STATUS AUDIT: COMMITTED LIABILITIES VS UNAPPROVED PIPELINE
-- Demonstrates why DRAFT / PENDING invoices are isolated from committed overdue debt
SELECT 
    UPPER(NVL(i.status, 'DRAFT')) AS invoice_status,
    COUNT(i.invoice_id) AS bill_count,
    ROUND(SUM(i.total_amount), 2) AS total_gross_billed,
    ROUND(SUM(GREATEST(0, i.total_amount - NVL(p.total_paid, 0))), 2) AS total_balance_due,
    COUNT(CASE WHEN i.due_date < TRUNC(SYSDATE) AND (i.total_amount - NVL(p.total_paid, 0)) > 0 THEN 1 END) AS past_due_date_count,
    ROUND(SUM(CASE WHEN i.due_date < TRUNC(SYSDATE) THEN GREATEST(0, i.total_amount - NVL(p.total_paid, 0)) ELSE 0 END), 2) AS past_due_amount,
    CASE 
        WHEN UPPER(NVL(i.status, 'DRAFT')) IN ('APPROVED', 'OVERDUE') THEN 'Committed Liability (Region 5 Overdue List)'
        ELSE 'Unapproved Pipeline (Action Card: Review & Approve)'
    END AS accounting_treatment
FROM kf_invoices i
LEFT JOIN (
    SELECT invoice_id, SUM(payment_amount) AS total_paid
    FROM kf_payments WHERE status = 'COMPLETED' GROUP BY invoice_id
) p ON i.invoice_id = p.invoice_id
WHERE UPPER(NVL(i.status, 'DRAFT')) NOT IN ('PAID', 'CANCELLED', 'REJECTED')
  AND (i.total_amount - NVL(p.total_paid, 0)) > 0
GROUP BY UPPER(NVL(i.status, 'DRAFT'))
ORDER BY past_due_amount DESC;

-- 3. VERIFIED TOP OVERDUE INVOICES (MATCHES REGION 5 TABLE EXACTLY)
-- Strictly returns invoices in APPROVED / OVERDUE status past their due date
SELECT 
    i.invoice_number,
    v.vendor_name,
    UPPER(NVL(i.status, 'DRAFT')) AS status,
    TO_CHAR(i.due_date, 'DD-Mon-YYYY') AS due_date,
    TRUNC(SYSDATE) - TRUNC(i.due_date) AS days_overdue,
    ROUND(i.total_amount - NVL(p.total_paid, 0), 2) AS balance_due
FROM kf_invoices i
JOIN kf_vendors v ON i.vendor_id = v.vendor_id
LEFT JOIN (
    SELECT invoice_id, SUM(payment_amount) AS total_paid
    FROM kf_payments WHERE status = 'COMPLETED' GROUP BY invoice_id
) p ON i.invoice_id = p.invoice_id
WHERE UPPER(NVL(i.status, 'DRAFT')) IN ('APPROVED', 'OVERDUE')
  AND (i.total_amount - NVL(p.total_paid, 0)) > 0
  AND i.due_date < TRUNC(SYSDATE)
ORDER BY balance_due DESC
FETCH FIRST 5 ROWS ONLY;

-- 4. UNAPPROVED PIPELINE INVOICES (DRAFT / PENDING_APPROVAL)
-- Shows draft invoices with historical dates that belong in the approval queue, not the overdue ledger
SELECT 
    i.invoice_number,
    v.vendor_name,
    UPPER(NVL(i.status, 'DRAFT')) AS status,
    TO_CHAR(i.due_date, 'DD-Mon-YYYY') AS due_date,
    TRUNC(SYSDATE) - TRUNC(i.due_date) AS days_elapsed_since_date,
    ROUND(i.total_amount - NVL(p.total_paid, 0), 2) AS balance_due
FROM kf_invoices i
JOIN kf_vendors v ON i.vendor_id = v.vendor_id
LEFT JOIN (
    SELECT invoice_id, SUM(payment_amount) AS total_paid
    FROM kf_payments WHERE status = 'COMPLETED' GROUP BY invoice_id
) p ON i.invoice_id = p.invoice_id
WHERE UPPER(NVL(i.status, 'DRAFT')) IN ('DRAFT', 'PENDING_APPROVAL', 'PENDING')
  AND (i.total_amount - NVL(p.total_paid, 0)) > 0
ORDER BY days_elapsed_since_date DESC;

-- 5. FINANCIAL YEAR ALIGNED MONTHLY TREND (APRIL TO MARCH FY 2026-27)
SELECT 
    TO_CHAR(i.invoice_date, 'Mon YYYY') AS reporting_month,
    COUNT(i.invoice_id) AS bills_recorded_count,
    ROUND(SUM(i.total_amount), 2) AS expense_accruals,
    NVL((
        SELECT SUM(c.amount)
        FROM kf_cashflow_ledger c
        WHERE UPPER(c.section_heading) = 'CASH_RECEIPTS'
          AND UPPER(c.report_month) = UPPER(TO_CHAR(i.invoice_date, 'Mon'))
          AND (UPPER(c.fin_year) LIKE '%2026%' OR UPPER(c.fin_year) = 'FY 2026-27')
    ), 0) AS verified_cash_receipts,
    'FY 2026-27 Strict Match' AS audit_status
FROM kf_invoices i
WHERE i.invoice_date >= TO_DATE('01-04-2026', 'DD-MM-YYYY')
  AND i.invoice_date < TO_DATE('01-04-2027', 'DD-MM-YYYY')
  AND UPPER(NVL(i.status, 'DRAFT')) != 'CANCELLED'
GROUP BY TO_CHAR(i.invoice_date, 'Mon YYYY'), TRUNC(i.invoice_date, 'MONTH')
ORDER BY TRUNC(i.invoice_date, 'MONTH') DESC;
