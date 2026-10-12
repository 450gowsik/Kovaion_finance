-- ==============================================================================
-- KOVAION ENTERPRISE SUITE — FINANCIAL DASHBOARD RECONCILIATION QUERIES
-- Application: 47919 | Page 1 | Oracle APEX 26.1
-- Purpose: Read-Only Verification of All 7 Financial Dashboard Areas
-- ==============================================================================
-- Execution Instructions:
-- Run these queries in Oracle APEX -> SQL Workshop -> SQL Commands.
-- All queries are 100% READ-ONLY (SELECT statements only).
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- AUDIT 1: TOTAL BANK BALANCE & CASH LEDGER PROVENANCE
-- ------------------------------------------------------------------------------
-- Check 1.1: Verify if KF_BANK_ACCOUNTS or any bank ledger table exists
SELECT table_name, num_rows, last_analyzed
FROM user_tables
WHERE table_name IN ('KF_BANK_ACCOUNTS', 'KF_BANK_TRANSACTIONS', 'KF_CASHFLOW_LEDGER', 'KF_GL_BALANCES')
ORDER BY table_name;

-- Check 1.2: Inspect bank account records and current balance provenance
SELECT account_id, account_number, bank_name, account_type, current_balance, currency
FROM kf_bank_accounts
ORDER BY account_id;

-- Check 1.3: Inspect bank transactions to check for statement imports or reconciliation flags
SELECT transaction_id, account_id, transaction_date, transaction_type, amount, reference_number, description
FROM kf_bank_transactions
ORDER BY transaction_date DESC;

-- Check 1.4: Verify net cash from actual recorded payments
SELECT 
    COUNT(*) AS total_payment_records,
    NVL(SUM(payment_amount), 0) AS total_disbursements,
    NVL(SUM(CASE WHEN status = 'COMPLETED' THEN payment_amount ELSE 0 END), 0) AS completed_disbursements
FROM kf_payments;


-- ------------------------------------------------------------------------------
-- AUDIT 2: TOTAL PAYABLES INDEPENDENT RECONCILIATION
-- ------------------------------------------------------------------------------
-- Check 2.1: Independent invoice population breakdown by status
SELECT 
    NVL(status, 'NULL_STATUS') AS invoice_status,
    COUNT(*) AS invoice_count,
    SUM(total_amount) AS total_invoiced,
    SUM(tax_amount) AS total_tax,
    SUM(tds_amount) AS total_tds
FROM kf_invoices
GROUP BY status
ORDER BY status;

-- Check 2.2: Outstanding AP Balance calculation against KF_VW_INVOICE_BALANCES
SELECT 
    COUNT(*) AS open_invoice_count,
    SUM(i.total_amount) AS gross_open_amount,
    SUM(NVL(p.total_paid, 0)) AS total_paid_against_open,
    SUM(i.total_amount - NVL(p.total_paid, 0)) AS net_outstanding_payables
FROM kf_invoices i
LEFT JOIN (
    SELECT invoice_id, SUM(payment_amount) AS total_paid
    FROM kf_payments
    WHERE status = 'COMPLETED'
    GROUP BY invoice_id
) p ON i.invoice_id = p.invoice_id
WHERE UPPER(NVL(i.status, 'DRAFT')) NOT IN ('CANCELLED', 'REJECTED', 'PAID');

-- Check 2.3: Verify presence of duplicate payments or overpayments
SELECT invoice_id, COUNT(*) AS payment_count, SUM(payment_amount) AS sum_paid
FROM kf_payments
WHERE status = 'COMPLETED'
GROUP BY invoice_id
HAVING COUNT(*) > 1;


-- ------------------------------------------------------------------------------
-- AUDIT 3: TOTAL RECEIVABLES & CUSTOMER AR SUBLEDGER CHECK
-- ------------------------------------------------------------------------------
-- Check 3.1: Check for any customer or receivables tables in the database schema
SELECT table_name
FROM user_tables
WHERE table_name LIKE '%CUST%' 
   OR table_name LIKE '%RECEIV%' 
   OR table_name LIKE '%AR_%'
   OR table_name LIKE '%INVOICE_OUT%'
ORDER BY table_name;

-- Check 3.2: Check for any customer or receivables views (including KF_VW_AR_BALANCES)
SELECT view_name
FROM user_views
WHERE view_name LIKE '%AR%' 
   OR view_name LIKE '%RECEIV%' 
   OR view_name LIKE '%CUST%'
ORDER BY view_name;


-- ------------------------------------------------------------------------------
-- AUDIT 4: CASH COVERAGE, LIQUIDITY RATIO & SOLVENCY INPUTS
-- ------------------------------------------------------------------------------
-- Check 4.1: Inspect whether general ledger balance sheet tables exist (Current Assets / Current Liab.)
SELECT table_name
FROM user_tables
WHERE table_name LIKE '%GL%' 
   OR table_name LIKE '%BALANCE%' 
   OR table_name LIKE '%LEDGER%'
ORDER BY table_name;

-- Check 4.2: Compare available cash vs outstanding payables (Coverage Ratio test)
WITH cash_source AS (
    SELECT NVL(SUM(current_balance), 0) AS total_cash
    FROM kf_bank_accounts
),
payables_source AS (
    SELECT SUM(i.total_amount - NVL(p.total_paid, 0)) AS total_payables
    FROM kf_invoices i
    LEFT JOIN (
        SELECT invoice_id, SUM(payment_amount) AS total_paid
        FROM kf_payments WHERE status = 'COMPLETED' GROUP BY invoice_id
    ) p ON i.invoice_id = p.invoice_id
    WHERE UPPER(NVL(i.status, 'DRAFT')) NOT IN ('CANCELLED', 'REJECTED', 'PAID')
)
SELECT 
    c.total_cash,
    p.total_payables,
    CASE 
        WHEN NVL(p.total_payables, 0) > 0 THEN ROUND(c.total_cash / p.total_payables, 2)
        ELSE NULL 
    END AS computed_cash_to_payables_ratio
FROM cash_source c, payables_source p;


-- ------------------------------------------------------------------------------
-- AUDIT 5: INCOME VS EXPENSES ACTUAL MONTHLY TRANSACTIONS
-- ------------------------------------------------------------------------------
-- Check 5.1: Actual monthly vendor expenses from KF_INVOICES
SELECT 
    TO_CHAR(invoice_date, 'YYYY-MM') AS invoice_month,
    COUNT(*) AS invoice_count,
    SUM(total_amount) AS total_invoiced_expense
FROM kf_invoices
WHERE UPPER(NVL(status, 'DRAFT')) NOT IN ('CANCELLED', 'REJECTED')
GROUP BY TO_CHAR(invoice_date, 'YYYY-MM')
ORDER BY invoice_month;

-- Check 5.2: Actual cash outflows by payment month from KF_PAYMENTS
SELECT 
    TO_CHAR(payment_date, 'YYYY-MM') AS payment_month,
    COUNT(*) AS payment_count,
    SUM(payment_amount) AS total_disbursed
FROM kf_payments
WHERE status = 'COMPLETED'
GROUP BY TO_CHAR(payment_date, 'YYYY-MM')
ORDER BY payment_month;

-- Check 5.3: Actual customer income/receipts check in KF_CASHFLOW_LEDGER
SELECT 
    fin_year,
    report_month,
    section_heading,
    line_item,
    amount
FROM kf_cashflow_ledger
ORDER BY ledger_id;


-- ------------------------------------------------------------------------------
-- AUDIT 6: LIVE BANK STATEMENT & DISBURSEMENT INTEGRITY
-- ------------------------------------------------------------------------------
-- Check 6.1: Verify disbursement records in KF_PAYMENTS with vendor linkage
SELECT 
    p.payment_id,
    p.invoice_id,
    i.invoice_number,
    v.vendor_name,
    p.payment_date,
    p.payment_amount,
    p.payment_method,
    p.reference_number,
    p.status
FROM kf_payments p
LEFT JOIN kf_invoices i ON p.invoice_id = i.invoice_id
LEFT JOIN kf_vendors v ON p.vendor_id = v.vendor_id
ORDER BY p.payment_date DESC, p.payment_id DESC;

-- Check 6.2: Check for unreferenced payments or orphan invoice references
SELECT p.payment_id, p.invoice_id
FROM kf_payments p
WHERE NOT EXISTS (SELECT 1 FROM kf_invoices i WHERE i.invoice_id = p.invoice_id);


-- ------------------------------------------------------------------------------
-- AUDIT 7: RECEIVABLES AGING BUCKETS AUDIT
-- ------------------------------------------------------------------------------
-- Check 7.1: Verify if any customer open invoices exist for aging
-- (If this returns ORA-00942 or 0 rows, customer AR aging cannot be computed)
SELECT 
    CASE 
        WHEN TRUNC(SYSDATE) - TRUNC(due_date) <= 30 THEN '0-30 Days'
        WHEN TRUNC(SYSDATE) - TRUNC(due_date) BETWEEN 31 AND 60 THEN '31-60 Days'
        WHEN TRUNC(SYSDATE) - TRUNC(due_date) BETWEEN 61 AND 90 THEN '61-90 Days'
        ELSE 'Over 90 Days'
    END AS aging_bucket,
    COUNT(*) AS count_invoices,
    SUM(total_amount) AS bucket_total
FROM kf_invoices
WHERE 1=0 -- Placeholder: Replaced by customer invoice table when AR module is provisioned
GROUP BY 
    CASE 
        WHEN TRUNC(SYSDATE) - TRUNC(due_date) <= 30 THEN '0-30 Days'
        WHEN TRUNC(SYSDATE) - TRUNC(due_date) BETWEEN 31 AND 60 THEN '31-60 Days'
        WHEN TRUNC(SYSDATE) - TRUNC(due_date) BETWEEN 61 AND 90 THEN '61-90 Days'
        ELSE 'Over 90 Days'
    END;
