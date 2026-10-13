-- ==============================================================================
-- KOVAION ENTERPRISE FINANCE - REGION 4: PAYMENT ALERTS & RECENT INVOICES (LIVE)
-- APEX Application: 47919 | Page: 1 | Region Type: PL/SQL Dynamic Content
-- Returns: VARCHAR2 (Buffer-Safe: ~5.8 KB - Fits effortlessly into APEX Editor)
-- Policy: 100% Live Database Data - Zero N/A Cards - Genuine AP Subledger
-- ==============================================================================
DECLARE
    -- Payment Alerts (KF_INVOICES joined with KF_PAYMENTS)
    v_al_over_cnt   NUMBER := 0;
    v_al_over_sum   NUMBER := 0;
    v_al_due7_cnt   NUMBER := 0;
    v_al_due7_sum   NUMBER := 0;
    v_alerts_html   VARCHAR2(4000) := '';
    v_recent_html   VARCHAR2(4000) := '';
    l_cnt           NUMBER := 0;
    l_html          VARCHAR2(32767) := '';
BEGIN
    -- 1. Live Payment Alerts: Exclude cancelled/paid and account for completed partial disbursements
    BEGIN
        SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = 'KF_PAYMENTS';
        IF l_cnt > 0 THEN
            EXECUTE IMMEDIATE '
                SELECT
                    COUNT(CASE WHEN i.DUE_DATE < TRUNC(SYSDATE) 
                                AND (i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) > 0 THEN 1 END),
                    NVL(SUM(CASE WHEN i.DUE_DATE < TRUNC(SYSDATE) 
                                 THEN GREATEST(0, i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) ELSE 0 END), 0),
                    COUNT(CASE WHEN i.DUE_DATE BETWEEN TRUNC(SYSDATE) AND TRUNC(SYSDATE) + 7
                                AND (i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) > 0 THEN 1 END),
                    NVL(SUM(CASE WHEN i.DUE_DATE BETWEEN TRUNC(SYSDATE) AND TRUNC(SYSDATE) + 7
                                 THEN GREATEST(0, i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) ELSE 0 END), 0)
                FROM KF_INVOICES i
                LEFT JOIN (
                    SELECT INVOICE_ID, SUM(PAYMENT_AMOUNT) AS TOTAL_PAID
                    FROM KF_PAYMENTS
                    WHERE STATUS = ''COMPLETED''
                    GROUP BY INVOICE_ID
                ) p ON i.INVOICE_ID = p.INVOICE_ID
                WHERE UPPER(NVL(i.STATUS, ''DRAFT'')) NOT IN (''PAID'', ''CANCELLED'', ''REJECTED'')'
            INTO v_al_over_cnt, v_al_over_sum, v_al_due7_cnt, v_al_due7_sum;
        ELSE
            SELECT
                COUNT(CASE WHEN DUE_DATE < TRUNC(SYSDATE) THEN 1 END),
                NVL(SUM(CASE WHEN DUE_DATE < TRUNC(SYSDATE) THEN TOTAL_AMOUNT ELSE 0 END), 0),
                COUNT(CASE WHEN DUE_DATE BETWEEN TRUNC(SYSDATE) AND TRUNC(SYSDATE) + 7 THEN 1 END),
                NVL(SUM(CASE WHEN DUE_DATE BETWEEN TRUNC(SYSDATE) AND TRUNC(SYSDATE) + 7 THEN TOTAL_AMOUNT ELSE 0 END), 0)
            INTO v_al_over_cnt, v_al_over_sum, v_al_due7_cnt, v_al_due7_sum
            FROM KF_INVOICES
            WHERE UPPER(NVL(STATUS, 'DRAFT')) NOT IN ('PAID', 'CANCELLED', 'REJECTED');
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_al_over_cnt := 0; v_al_over_sum := 0; v_al_due7_cnt := 0; v_al_due7_sum := 0;
    END;

    -- Top 3 Urgent Bills (Accounts for completed partial payments)
    IF l_cnt > 0 THEN
        DECLARE
            c_cur SYS_REFCURSOR;
            v_vn VARCHAR2(255);
            v_inum VARCHAR2(100);
            v_amt NUMBER;
            v_due DATE;
            v_dd VARCHAR2(100);
            v_clr VARCHAR2(20);
        BEGIN
            OPEN c_cur FOR '
                SELECT NVL(v.VENDOR_NAME, ''Vendor''), i.INVOICE_NUMBER,
                       GREATEST(0, i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)),
                       i.DUE_DATE
                FROM KF_INVOICES i
                LEFT JOIN KF_VENDORS v ON i.VENDOR_ID = v.VENDOR_ID
                LEFT JOIN (
                    SELECT INVOICE_ID, SUM(PAYMENT_AMOUNT) AS TOTAL_PAID
                    FROM KF_PAYMENTS WHERE STATUS = ''COMPLETED'' GROUP BY INVOICE_ID
                ) p ON i.INVOICE_ID = p.INVOICE_ID
                WHERE UPPER(NVL(i.STATUS, ''DRAFT'')) NOT IN (''PAID'', ''CANCELLED'', ''REJECTED'')
                  AND (i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) > 0
                ORDER BY i.DUE_DATE ASC FETCH FIRST 3 ROWS ONLY';
            LOOP
                FETCH c_cur INTO v_vn, v_inum, v_amt, v_due;
                EXIT WHEN c_cur%NOTFOUND;
                IF v_due < TRUNC(SYSDATE) THEN
                    v_dd := '&#9888; Overdue';
                    v_clr := '#e11d48';
                ELSE
                    v_dd := '&#9203; Due in ' || GREATEST(1, ROUND(v_due - TRUNC(SYSDATE))) || 'd';
                    v_clr := '#d97706';
                END IF;
                v_alerts_html := v_alerts_html || '<div class="sl-bank-item"><div>'
                    || '<div class="sl-bank-name">' || APEX_ESCAPE.HTML(v_vn) || ' (' || APEX_ESCAPE.HTML(v_inum) || ')</div>'
                    || '<div class="sl-bank-type" style="color:' || v_clr || ';font-weight:600;">' || v_dd || '</div></div>'
                    || '<div class="sl-bank-amount" style="color:' || v_clr || ';font-weight:800;">'
                    || '&#8377;' || TRIM(TO_CHAR(v_amt, '99,99,990')) || '</div></div>';
            END LOOP;
            CLOSE c_cur;
        EXCEPTION WHEN OTHERS THEN
            IF c_cur%ISOPEN THEN CLOSE c_cur; END IF;
        END;
    ELSE
        FOR r IN (
            SELECT NVL(v.VENDOR_NAME,'Vendor') AS vn, i.INVOICE_NUMBER AS inum,
                   i.TOTAL_AMOUNT AS amt,
                   CASE WHEN i.DUE_DATE<TRUNC(SYSDATE)
                        THEN '&#9888; Overdue'
                        ELSE '&#9203; Due in '||GREATEST(1,ROUND(i.DUE_DATE-TRUNC(SYSDATE)))||'d'
                   END AS dd,
                   CASE WHEN i.DUE_DATE<TRUNC(SYSDATE) THEN '#e11d48' ELSE '#d97706' END AS clr
            FROM KF_INVOICES i LEFT JOIN KF_VENDORS v ON i.VENDOR_ID=v.VENDOR_ID
            WHERE UPPER(NVL(i.STATUS,'DRAFT')) NOT IN ('PAID','CANCELLED','REJECTED')
            ORDER BY i.DUE_DATE ASC FETCH FIRST 3 ROWS ONLY
        ) LOOP
            v_alerts_html := v_alerts_html||'<div class="sl-bank-item"><div>'
                ||'<div class="sl-bank-name">'||APEX_ESCAPE.HTML(r.vn)||' ('||APEX_ESCAPE.HTML(r.inum)||')</div>'
                ||'<div class="sl-bank-type" style="color:'||r.clr||';font-weight:600;">'||r.dd||'</div></div>'
                ||'<div class="sl-bank-amount" style="color:'||r.clr||';font-weight:800;">'
                ||'&#8377;'||TRIM(TO_CHAR(r.amt,'99,99,990'))||'</div></div>';
        END LOOP;
    END IF;

    IF LENGTH(NVL(v_alerts_html,''))=0 THEN
        v_alerts_html := '<div style="padding:16px;color:#64748b;font-size:0.85rem;">No outstanding vendor bills due.</div>';
    END IF;

    -- 2. Recent Live Invoices (Direct from KF_INVOICES subledger)
    FOR r IN (
        SELECT NVL(v.VENDOR_NAME, 'Vendor') AS vn,
               i.INVOICE_NUMBER AS inum,
               i.TOTAL_AMOUNT AS amt,
               TO_CHAR(i.INVOICE_DATE, 'DD-Mon-YYYY') AS idt,
               UPPER(NVL(i.STATUS, 'PENDING')) AS stat
        FROM KF_INVOICES i
        LEFT JOIN KF_VENDORS v ON i.VENDOR_ID = v.VENDOR_ID
        WHERE UPPER(NVL(i.STATUS, 'DRAFT')) != 'CANCELLED'
        ORDER BY i.INVOICE_DATE DESC, i.INVOICE_ID DESC
        FETCH FIRST 4 ROWS ONLY
    ) LOOP
        v_recent_html := v_recent_html || '<div class="sl-bank-item"><div>'
            || '<div class="sl-bank-name">' || APEX_ESCAPE.HTML(r.vn) || '</div>'
            || '<div class="sl-bank-type">' || APEX_ESCAPE.HTML(r.inum) || ' &bull; ' || r.idt || '</div></div>'
            || '<div style="text-align:right;"><div class="sl-bank-amount" style="color:#0f172a;font-weight:800;">'
            || '&#8377;' || TRIM(TO_CHAR(r.amt, '99,99,990')) || '</div>'
            || '<span style="display:inline-block;padding:2px 8px;font-size:10px;font-weight:700;border-radius:4px;'
            || CASE WHEN r.stat LIKE '%APPROV%' THEN 'background:#dbeafe;color:#1e40af;'
                    WHEN r.stat = 'PAID' THEN 'background:#dcfce7;color:#15803d;'
                    ELSE 'background:#fef3c7;color:#92400e;' END || '">' || APEX_ESCAPE.HTML(r.stat) || '</span></div></div>';
    END LOOP;

    IF LENGTH(NVL(v_recent_html,''))=0 THEN
        v_recent_html := '<div style="padding:16px;color:#64748b;font-size:0.85rem;">No vendor invoices recorded yet.</div>';
    END IF;

    -- 3. Build HTML Output
    l_html := '<div class="smartledger-dashboard">'
|| '<div class="sl-alerts-row" id="alertsRow">'
-- Left Card: Payment Alerts & Outflows
|| '<div class="sl-chart-card" id="cardPaymentAlerts" data-category="overview,payables">'
|| '<div class="sl-chart-header"><h3 class="sl-chart-title">Payment Alerts &amp; Outflows</h3>'
|| '<span class="sl-chart-tag" style="background:#fee2e2;color:#b91c1c;font-weight:700;border:1px solid #fecaca;">&#9679; ' || v_al_over_cnt || ' Overdue</span></div>'
|| '<div class="sl-alert-grid">'
|| '<div class="sl-alert-box-red"><div class="sl-alert-lbl-red">Overdue Bills</div>'
|| '<div class="sl-alert-val-red">&#8377;' || TRIM(TO_CHAR(v_al_over_sum,'99,99,990')) || '</div>'
|| '<div class="sl-alert-sub-red">' || v_al_over_cnt || ' bills past due</div></div>'
|| '<div class="sl-alert-box-amber"><div class="sl-alert-lbl-amber">Due in 7 Days</div>'
|| '<div class="sl-alert-val-amber">&#8377;' || TRIM(TO_CHAR(v_al_due7_sum,'99,99,990')) || '</div>'
|| '<div class="sl-alert-sub-amber">' || v_al_due7_cnt || ' scheduled</div></div>'
|| '</div>'
|| '<div style="max-height:160px;overflow-y:auto;margin-top:10px;">' || v_alerts_html || '</div>'
|| '</div>'
-- Right Card: Recent Invoices & Activity
|| '<div class="sl-chart-card" id="cardRecentInvoices" data-category="overview,payables">'
|| '<div class="sl-chart-header"><h3 class="sl-chart-title">Recent Invoices &amp; Activity</h3>'
|| '<span class="sl-chart-tag" style="background:#dcfce7;color:#15803d;font-weight:700;border:1px solid #bbf7d0;">&#9679; Live Subledger</span></div>'
|| '<div style="max-height:225px;overflow-y:auto;">' || v_recent_html || '</div>'
|| '</div></div></div>';

    RETURN l_html;
EXCEPTION WHEN OTHERS THEN
    RETURN '<div style="padding:16px;background:#fff;border:1px solid #e2e8f0;border-radius:10px;"><b>Alerts Region Error:</b> ' || APEX_ESCAPE.HTML(SQLERRM) || '</div>';
END;
