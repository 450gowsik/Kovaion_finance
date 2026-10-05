-- =========================================================================
-- MAKE PAGE 40 (FINANCIAL REPORTS) 100% DYNAMIC & LIVE FROM KF_INVOICES
-- =========================================================================
-- Instructions:
-- 1. In APEX Page Designer, open Page 40 (Reports).
-- 2. Click on the region: 'Financial Reports Overview' (under Body).
-- 3. In the right property panel, change Type to: 'PL/SQL Dynamic Content'
-- 4. In PL/SQL Code, select all (Ctrl+A), paste this code, and click Save.
-- 5. Refresh Page 40!
-- =========================================================================

DECLARE
    l_tot_billed   NUMBER := 0;
    l_tot_paid     NUMBER := 0;
    l_tot_pending  NUMBER := 0;
    l_tot_overdue  NUMBER := 0;
    l_inv_cnt      NUMBER := 0;
    l_paid_cnt     NUMBER := 0;
    l_pend_cnt     NUMBER := 0;
    l_over_cnt     NUMBER := 0;
    l_eff_pct      NUMBER := 0;
    l_html         CLOB;
BEGIN
    -- Query live totals from KF_INVOICES and KF_PAYMENTS
    SELECT 
        NVL(SUM(TOTAL_AMOUNT), 0),
        COUNT(*),
        NVL(SUM(CASE WHEN STATUS = 'PAID' THEN TOTAL_AMOUNT ELSE 0 END), 0),
        NVL(COUNT(CASE WHEN STATUS = 'PAID' THEN 1 END), 0),
        NVL(SUM(CASE WHEN STATUS IN ('PENDING', 'PENDING_APPROVAL') THEN TOTAL_AMOUNT ELSE 0 END), 0),
        NVL(COUNT(CASE WHEN STATUS IN ('PENDING', 'PENDING_APPROVAL') THEN 1 END), 0),
        NVL(SUM(CASE WHEN STATUS = 'OVERDUE' THEN TOTAL_AMOUNT ELSE 0 END), 0),
        NVL(COUNT(CASE WHEN STATUS = 'OVERDUE' THEN 1 END), 0)
    INTO 
        l_tot_billed, l_inv_cnt,
        l_tot_paid, l_paid_cnt,
        l_tot_pending, l_pend_cnt,
        l_tot_overdue, l_over_cnt
    FROM KF_INVOICES;

    -- If KF_PAYMENTS has disbursed records, use actual payments for realized balance
    BEGIN
        SELECT NVL(SUM(PAYMENT_AMOUNT), 0)
        INTO l_tot_paid
        FROM KF_PAYMENTS;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    IF l_tot_billed > 0 THEN
        l_eff_pct := ROUND((l_tot_paid / l_tot_billed) * 100, 1);
    ELSE
        l_eff_pct := 0;
    END IF;

    l_html := '<div class="bqe-reports-page">
        <div class="rep-header">
            <div class="rep-title-area">
                <h1>Executive Financial Reports</h1>
                <div class="rep-subtitle">Comprehensive audits, outstanding balances, and reconciliation logs &bull; Live from Database</div>
            </div>
        </div>

        <div class="rep-summary-grid">
            <!-- 1. Total Invoiced / Billed -->
            <div class="rep-summary-card">
                <div class="rep-summary-label">Total Invoiced / Billed</div>
                <div class="rep-summary-val">₹' || TRIM(TO_CHAR(l_tot_billed, '99,99,99,990')) || '</div>
                <div class="rep-summary-sub">&bull; ' || l_inv_cnt || ' invoices live on file</div>
            </div>

            <!-- 2. Realized / Paid Balances -->
            <div class="rep-summary-card">
                <div class="rep-summary-label">Total Realized / Paid</div>
                <div class="rep-summary-val">₹' || TRIM(TO_CHAR(l_tot_paid, '99,99,99,990')) || '</div>
                <div class="rep-summary-sub">&bull; ' || l_eff_pct || '% Settlement Ratio</div>
            </div>

            <!-- 3. Outstanding / Pending -->
            <div class="rep-summary-card">
                <div class="rep-summary-label">Outstanding / Pending Approval</div>
                <div class="rep-summary-val">₹' || TRIM(TO_CHAR(l_tot_pending, '99,99,99,990')) || '</div>
                <div class="rep-summary-sub" style="color: #f59e0b;">&bull; ' || l_pend_cnt || ' invoices awaiting clearance</div>
            </div>
        </div>
    </div>';

    RETURN l_html;
END;
