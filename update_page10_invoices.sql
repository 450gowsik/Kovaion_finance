DECLARE
    v_total NUMBER := 0;
    v_pending NUMBER := 0;
    v_approved NUMBER := 0;
    v_overdue NUMBER := 0;
    v_paid NUMBER := 0;
    v_rejected NUMBER := 0;
    l_html CLOB;
BEGIN
    SELECT 
        COUNT(*),
        NVL(SUM(CASE WHEN UPPER(NVL(STATUS, 'DRAFT')) IN ('PENDING_APPROVAL', 'PENDING', 'DRAFT') THEN 1 ELSE 0 END), 0),
        NVL(SUM(CASE WHEN UPPER(NVL(STATUS, 'DRAFT')) = 'APPROVED' THEN 1 ELSE 0 END), 0),
        NVL(SUM(CASE WHEN UPPER(NVL(STATUS, 'DRAFT')) = 'OVERDUE' THEN 1 ELSE 0 END), 0),
        NVL(SUM(CASE WHEN UPPER(NVL(STATUS, 'DRAFT')) = 'PAID' THEN 1 ELSE 0 END), 0),
        NVL(SUM(CASE WHEN UPPER(NVL(STATUS, 'DRAFT')) = 'REJECTED' THEN 1 ELSE 0 END), 0)
    INTO v_total, v_pending, v_approved, v_overdue, v_paid, v_rejected
    FROM KF_INVOICES
    WHERE UPPER(NVL(STATUS, 'DRAFT')) != 'CANCELLED';

    l_html := '<div class="kanakku-invoices-page"><div class="knk-kpi-grid">' ||
              
              '<div class="knk-kpi-card"><div class="knk-kpi-top"><div><div class="knk-kpi-label">Total Invoices</div><div class="knk-kpi-val">' || v_total || '</div></div>' ||
              '<div class="knk-kpi-icon purple"><svg width="22" height="22" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/></svg></div></div></div>' ||
              
              '<div class="knk-kpi-card"><div class="knk-kpi-top"><div><div class="knk-kpi-label">Pending Approval</div><div class="knk-kpi-val">' || v_pending || '</div></div>' ||
              '<div class="knk-kpi-icon orange"><svg width="22" height="22" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg></div></div></div>' ||
              
              '<div class="knk-kpi-card"><div class="knk-kpi-top"><div><div class="knk-kpi-label">Approved</div><div class="knk-kpi-val">' || v_approved || '</div></div>' ||
              '<div class="knk-kpi-icon blue"><svg width="22" height="22" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg></div></div></div>' ||
              
              '<div class="knk-kpi-card"><div class="knk-kpi-top"><div><div class="knk-kpi-label">Overdue</div><div class="knk-kpi-val">' || v_overdue || '</div></div>' ||
              '<div class="knk-kpi-icon red"><svg width="22" height="22" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg></div></div></div>' ||
              
              '<div class="knk-kpi-card"><div class="knk-kpi-top"><div><div class="knk-kpi-label">Paid</div><div class="knk-kpi-val">' || v_paid || '</div></div>' ||
              '<div class="knk-kpi-icon green"><svg width="22" height="22" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg></div></div></div>' ||
              
              '<div class="knk-kpi-card"><div class="knk-kpi-top"><div><div class="knk-kpi-label">Rejected</div><div class="knk-kpi-val">' || v_rejected || '</div></div>' ||
              '<div class="knk-kpi-icon" style="background: rgba(255,255,255,0.2);"><svg width="22" height="22" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg></div></div></div>' ||
              
              '</div></div>';
              
    RETURN l_html;
END;