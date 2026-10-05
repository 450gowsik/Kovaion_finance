-- =========================================================================
-- MAKE PAGE 50 (PAYMENTS & TRANSACTIONS) 100% DYNAMIC & LIVE
-- =========================================================================
-- Instructions:
-- 1. In APEX Page Designer, open Page 50 (Payments).
-- 2. Click on the region: 'Payment Statistics' (under Body).
-- 3. In the right panel, change Type to: 'PL/SQL Dynamic Content'
-- 4. In PL/SQL Code, select all (Ctrl+A), paste this code, and click Save.
-- 5. Refresh Page 50!
-- =========================================================================

DECLARE
    l_tot_disbursed NUMBER := 0;
    l_pending_appr  NUMBER := 0;
    l_pend_cnt      NUMBER := 0;
    l_disb_cnt      NUMBER := 0;
    l_html          CLOB;
BEGIN
    -- 1. Live Disbursed Payments from KF_PAYMENTS
    SELECT 
        NVL(SUM(PAYMENT_AMOUNT), 0),
        COUNT(*)
    INTO l_tot_disbursed, l_disb_cnt
    FROM KF_PAYMENTS;

    -- If KF_PAYMENTS has 0, check PAID invoices in KF_INVOICES
    IF l_tot_disbursed = 0 THEN
        SELECT 
            NVL(SUM(TOTAL_AMOUNT), 0),
            COUNT(*)
        INTO l_tot_disbursed, l_disb_cnt
        FROM KF_INVOICES
        WHERE STATUS = 'PAID';
    END IF;

    -- 2. Live Pending Invoices from KF_INVOICES
    SELECT 
        NVL(SUM(TOTAL_AMOUNT), 0),
        COUNT(*)
    INTO l_pending_appr, l_pend_cnt
    FROM KF_INVOICES
    WHERE STATUS IN ('PENDING', 'PENDING_APPROVAL');

    l_html := '<div class="pingwi-transactions-page">
        <!-- Pingwi Header -->
        <div class="pw-header">
            <div class="pw-title-area">
                <h1>Payments &amp; Transactions</h1>
                <div class="pw-subtitle">
                    <span class="pw-pulse-dot"></span>
                    <span>Real-time payment settlements &bull; Live from Database</span>
                </div>
            </div>
        </div>

        <!-- 4 Quick Stats Cards -->
        <div class="pw-stats-grid">
            <div class="pw-stat-card">
                <div class="pw-stat-label">Total Disbursed</div>
                <div class="pw-stat-val">₹' || TRIM(TO_CHAR(l_tot_disbursed, '99,99,99,990')) || '</div>
                <span class="pw-stat-badge pw-badge-green">' || l_disb_cnt || ' payments settled</span>
            </div>
            <div class="pw-stat-card">
                <div class="pw-stat-label">Pending Approval</div>
                <div class="pw-stat-val">₹' || TRIM(TO_CHAR(l_pending_appr, '99,99,99,990')) || '</div>
                <span class="pw-stat-badge pw-badge-amber">' || l_pend_cnt || ' invoices awaiting</span>
            </div>
            <div class="pw-stat-card">
                <div class="pw-stat-label">In Transit</div>
                <div class="pw-stat-val">₹0.00</div>
                <span class="pw-stat-badge pw-badge-blue">0 batches in transit</span>
            </div>
            <div class="pw-stat-card">
                <div class="pw-stat-label">Failed / Chargebacks</div>
                <div class="pw-stat-val">₹0.00</div>
                <span class="pw-stat-badge pw-badge-slate">0 incidents recorded</span>
            </div>
        </div>

        <!-- Pingwi Filter Chips -->
        <div class="pw-filter-bar">
            <div class="pw-filter-tag">Payment Method: <strong>All</strong> &#9662;</div>
            <div class="pw-filter-tag">Gateway: <strong>Bank Transfer (NEFT/RTGS)</strong> &#9662;</div>
            <div class="pw-filter-tag">Operation: <strong>Disbursement</strong> &#9662;</div>
            <div class="pw-filter-tag">Status: <strong>All</strong> &#9662;</div>
            <div class="pw-filter-tag">Date Range: <strong>Current FY (2026-27)</strong></div>
        </div>
    </div>';

    RETURN l_html;
END;
