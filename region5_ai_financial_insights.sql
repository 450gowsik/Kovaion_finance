-- KOVAION FINANCE - REGION 5: RULE-BASED FINANCIAL INTELLIGENCE ENGINE
-- APEX App: 47919 | Page: 1 | Dynamic Content (Returns CLOB) | Buffer-Safe
DECLARE
    l_cur_yr NUMBER; l_cur_mo NUMBER; l_fy_start_yr NUMBER; l_fy_end_yr NUMBER;
    l_fy_label VARCHAR2(30);
    l_appr_payables NUMBER := 0; l_appr_cnt NUMBER := 0;
    l_appr_overdue NUMBER := 0; l_appr_over_cnt NUMBER := 0;
    l_avg_days_over NUMBER := 0; l_creditor_cnt NUMBER := 0; l_overdue_pct NUMBER := 0;
    l_unappr_amt NUMBER := 0; l_unappr_cnt NUMBER := 0;
    l_tot_exposure NUMBER := 0; l_tot_bills_cnt NUMBER := 0;
    l_bank_bal NUMBER := 0; l_bank_acc_cnt NUMBER := 0;
    l_bank_avail VARCHAR2(1) := 'N'; l_coverage_ratio NUMBER := 0;
    l_ap_error VARCHAR2(500) := NULL; l_bank_error VARCHAR2(500) := NULL; l_trend_error VARCHAR2(500) := NULL;
    l_has_pay NUMBER := 0; l_has_bank NUMBER := 0; l_has_cashflow NUMBER := 0;
    l_bank_fmt VARCHAR2(100); l_pay_fmt VARCHAR2(100); l_over_fmt VARCHAR2(100); l_unappr_fmt VARCHAR2(100);
    l_timestamp_str VARCHAR2(100); l_app_id VARCHAR2(50); l_app_session VARCHAR2(100);
    l_html CLOB;

    TYPE t_overdue_rec IS RECORD (
        invoice_id NUMBER, invoice_number VARCHAR2(150), vendor_name VARCHAR2(400),
        due_date DATE, status VARCHAR2(100), days_overdue NUMBER, balance_due NUMBER
    );
    TYPE t_overdue_tbl IS TABLE OF t_overdue_rec INDEX BY PLS_INTEGER;
    l_overdue_list t_overdue_tbl; l_ov_idx NUMBER := 0;

    TYPE t_vendor_rec IS RECORD (
        vendor_name VARCHAR2(400), open_bills_count NUMBER,
        vendor_open_balance NUMBER, concentration_pct NUMBER
    );
    TYPE t_vendor_tbl IS TABLE OF t_vendor_rec INDEX BY PLS_INTEGER;
    l_vendor_list t_vendor_tbl; l_vn_idx NUMBER := 0; l_top3_conc_sum NUMBER := 0;

    TYPE t_trend_rec IS RECORD (
        month_label VARCHAR2(50), bill_cnt NUMBER, expense_amt NUMBER, receipt_amt NUMBER
    );
    TYPE t_trend_tbl IS TABLE OF t_trend_rec INDEX BY PLS_INTEGER;
    l_trend_list t_trend_tbl; l_tr_idx NUMBER := 0;

    c_dyn SYS_REFCURSOR;
    r_id NUMBER; r_num VARCHAR2(150); r_vn VARCHAR2(400); r_due DATE;
    r_stat VARCHAR2(100); r_days NUMBER; r_bal NUMBER; r_cnt NUMBER; r_pct NUMBER;
    r_lbl VARCHAR2(50); r_exp NUMBER; r_rec NUMBER;

    PROCEDURE app(p_str IN VARCHAR2) IS
    BEGIN
        IF p_str IS NOT NULL THEN
            DBMS_LOB.WRITEAPPEND(l_html, LENGTH(p_str), p_str);
        END IF;
    END app;
BEGIN
    DBMS_LOB.CREATETEMPORARY(l_html, TRUE);
    l_app_id := NVL(V('APP_ID'), '47919');
    l_app_session := NVL(V('APP_SESSION'), '0');
    l_timestamp_str := TO_CHAR(SYSTIMESTAMP, 'DD-Mon-YYYY HH24:MI:SS');

    -- Indian Financial Year (April 1 to March 31)
    l_cur_yr := TO_NUMBER(TO_CHAR(SYSDATE, 'YYYY'));
    l_cur_mo := TO_NUMBER(TO_CHAR(SYSDATE, 'MM'));
    IF l_cur_mo >= 4 THEN l_fy_start_yr := l_cur_yr; ELSE l_fy_start_yr := l_cur_yr - 1; END IF;
    l_fy_end_yr := l_fy_start_yr + 1;
    l_fy_label  := 'FY ' || l_fy_start_yr || '-' || SUBSTR(TO_CHAR(l_fy_end_yr), 3, 2);

    -- 1. Live AP Subledger: Total Exposure, Approved Overdue, Unapproved Pipeline
    BEGIN
        SELECT COUNT(*) INTO l_has_pay FROM user_tables WHERE table_name = 'KF_PAYMENTS';
        IF l_has_pay > 0 THEN
            EXECUTE IMMEDIATE '
                SELECT NVL(SUM(GREATEST(0, i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0))), 0), NVL(COUNT(i.INVOICE_ID), 0)
                FROM KF_INVOICES i
                LEFT JOIN (SELECT INVOICE_ID, SUM(PAYMENT_AMOUNT) AS TOTAL_PAID FROM KF_PAYMENTS WHERE STATUS = ''COMPLETED'' GROUP BY INVOICE_ID) p ON i.INVOICE_ID = p.INVOICE_ID
                WHERE UPPER(NVL(i.STATUS, ''DRAFT'')) NOT IN (''PAID'', ''CANCELLED'', ''REJECTED'') AND (i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) > 0'
            INTO l_tot_exposure, l_tot_bills_cnt;

            EXECUTE IMMEDIATE '
                SELECT NVL(SUM(GREATEST(0, i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0))), 0), NVL(COUNT(i.INVOICE_ID), 0),
                       NVL(SUM(CASE WHEN i.DUE_DATE < TRUNC(SYSDATE) THEN GREATEST(0, i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) ELSE 0 END), 0),
                       NVL(COUNT(CASE WHEN i.DUE_DATE < TRUNC(SYSDATE) AND (i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) > 0 THEN 1 END), 0),
                       NVL(ROUND(AVG(CASE WHEN i.DUE_DATE < TRUNC(SYSDATE) AND (i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) > 0 THEN TRUNC(SYSDATE) - TRUNC(i.DUE_DATE) END)), 0),
                       NVL(COUNT(DISTINCT i.VENDOR_ID), 0)
                FROM KF_INVOICES i
                LEFT JOIN (SELECT INVOICE_ID, SUM(PAYMENT_AMOUNT) AS TOTAL_PAID FROM KF_PAYMENTS WHERE STATUS = ''COMPLETED'' GROUP BY INVOICE_ID) p ON i.INVOICE_ID = p.INVOICE_ID
                WHERE UPPER(NVL(i.STATUS, ''DRAFT'')) IN (''APPROVED'', ''OVERDUE'') AND (i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) > 0'
            INTO l_appr_payables, l_appr_cnt, l_appr_overdue, l_appr_over_cnt, l_avg_days_over, l_creditor_cnt;

            EXECUTE IMMEDIATE '
                SELECT NVL(SUM(GREATEST(0, i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0))), 0), NVL(COUNT(i.INVOICE_ID), 0)
                FROM KF_INVOICES i
                LEFT JOIN (SELECT INVOICE_ID, SUM(PAYMENT_AMOUNT) AS TOTAL_PAID FROM KF_PAYMENTS WHERE STATUS = ''COMPLETED'' GROUP BY INVOICE_ID) p ON i.INVOICE_ID = p.INVOICE_ID
                WHERE UPPER(NVL(i.STATUS, ''DRAFT'')) IN (''DRAFT'', ''PENDING_APPROVAL'', ''PENDING'') AND (i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) > 0'
            INTO l_unappr_amt, l_unappr_cnt;
        ELSE
            SELECT NVL(SUM(TOTAL_AMOUNT), 0), NVL(COUNT(*), 0) INTO l_tot_exposure, l_tot_bills_cnt FROM KF_INVOICES WHERE UPPER(NVL(STATUS, 'DRAFT')) NOT IN ('PAID', 'CANCELLED', 'REJECTED');
            SELECT NVL(SUM(TOTAL_AMOUNT), 0), NVL(COUNT(*), 0), NVL(SUM(CASE WHEN DUE_DATE < TRUNC(SYSDATE) THEN TOTAL_AMOUNT ELSE 0 END), 0),
                   NVL(COUNT(CASE WHEN DUE_DATE < TRUNC(SYSDATE) THEN 1 END), 0), NVL(ROUND(AVG(CASE WHEN DUE_DATE < TRUNC(SYSDATE) THEN TRUNC(SYSDATE) - TRUNC(DUE_DATE) END)), 0),
                   NVL(COUNT(DISTINCT VENDOR_ID), 0)
            INTO l_appr_payables, l_appr_cnt, l_appr_overdue, l_appr_over_cnt, l_avg_days_over, l_creditor_cnt FROM KF_INVOICES WHERE UPPER(NVL(STATUS, 'DRAFT')) IN ('APPROVED', 'OVERDUE');
            SELECT NVL(SUM(TOTAL_AMOUNT), 0), NVL(COUNT(*), 0) INTO l_unappr_amt, l_unappr_cnt FROM KF_INVOICES WHERE UPPER(NVL(STATUS, 'DRAFT')) IN ('DRAFT', 'PENDING_APPROVAL', 'PENDING');
        END IF;
    EXCEPTION WHEN OTHERS THEN l_ap_error := SUBSTR(SQLERRM, 1, 400);
    END;

    IF l_appr_payables > 0 THEN l_overdue_pct := ROUND((l_appr_overdue / l_appr_payables) * 100, 1); ELSE l_overdue_pct := 0; END IF;

    -- 2. Live Bank Subledger (Prevents Double Deduction: uses CURRENT_BALANCE directly)
    BEGIN
        SELECT COUNT(*) INTO l_has_bank FROM user_tables WHERE table_name = 'KF_BANK_ACCOUNTS';
        IF l_has_bank > 0 THEN
            DECLARE l_cur_col NUMBER := 0; l_bsql VARCHAR2(1000); BEGIN
                SELECT COUNT(*) INTO l_cur_col FROM user_tab_columns WHERE table_name = 'KF_BANK_ACCOUNTS' AND column_name = 'CURRENT_BALANCE';
                IF l_cur_col > 0 THEN
                    l_bsql := 'SELECT NVL(SUM(CASE WHEN NVL(CURRENT_BALANCE, 0) > 0 THEN CURRENT_BALANCE ELSE GREATEST(0, OPENING_BALANCE - (SELECT NVL(SUM(PAYMENT_AMOUNT), 0) FROM KF_PAYMENTS WHERE STATUS = ''COMPLETED'')) END), 0), COUNT(*) FROM KF_BANK_ACCOUNTS WHERE IS_ACTIVE = ''Y''';
                ELSE
                    l_bsql := 'SELECT GREATEST(0, NVL(SUM(OPENING_BALANCE), 0) - (SELECT NVL(SUM(PAYMENT_AMOUNT), 0) FROM KF_PAYMENTS WHERE STATUS = ''COMPLETED'')), COUNT(*) FROM KF_BANK_ACCOUNTS WHERE IS_ACTIVE = ''Y''';
                END IF;
                EXECUTE IMMEDIATE l_bsql INTO l_bank_bal, l_bank_acc_cnt;
                IF l_bank_acc_cnt > 0 THEN l_bank_avail := 'Y'; ELSE l_bank_avail := 'N'; END IF;
            END;
        ELSE l_bank_avail := 'N'; END IF;
    EXCEPTION WHEN OTHERS THEN l_bank_error := SUBSTR(SQLERRM, 1, 400); l_bank_avail := 'N';
    END;

    IF l_bank_avail = 'Y' AND l_tot_exposure > 0 THEN l_coverage_ratio := ROUND(l_bank_bal / l_tot_exposure, 1); ELSE l_coverage_ratio := 0; END IF;
    l_bank_fmt   := CASE WHEN l_bank_avail = 'Y' THEN '&#8377;' || TRIM(TO_CHAR(l_bank_bal, '99,99,99,990')) WHEN l_bank_error IS NOT NULL THEN 'Query Error' ELSE 'Unavailable' END;
    l_pay_fmt    := '&#8377;' || TRIM(TO_CHAR(l_tot_exposure, '99,99,99,990'));
    l_over_fmt   := '&#8377;' || TRIM(TO_CHAR(l_appr_overdue, '99,99,99,990'));
    l_unappr_fmt := '&#8377;' || TRIM(TO_CHAR(l_unappr_amt, '99,99,99,990'));

    -- 3. Top Overdue / Aging Invoices with Status
    IF l_has_pay > 0 AND l_ap_error IS NULL THEN
        BEGIN
            OPEN c_dyn FOR '
                SELECT i.INVOICE_ID, i.INVOICE_NUMBER, NVL(v.VENDOR_NAME, ''Vendor''), i.DUE_DATE,
                       UPPER(NVL(i.STATUS, ''DRAFT'')), TRUNC(SYSDATE) - TRUNC(i.DUE_DATE), (i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0))
                FROM KF_INVOICES i JOIN KF_VENDORS v ON i.VENDOR_ID = v.VENDOR_ID
                LEFT JOIN (SELECT INVOICE_ID, SUM(PAYMENT_AMOUNT) AS TOTAL_PAID FROM KF_PAYMENTS WHERE STATUS = ''COMPLETED'' GROUP BY INVOICE_ID) p ON i.INVOICE_ID = p.INVOICE_ID
                WHERE UPPER(NVL(i.STATUS, ''DRAFT'')) IN (''APPROVED'', ''OVERDUE'') AND (i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) > 0 AND i.DUE_DATE < TRUNC(SYSDATE)
                ORDER BY (i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) DESC FETCH FIRST 5 ROWS ONLY';
            LOOP
                FETCH c_dyn INTO r_id, r_num, r_vn, r_due, r_stat, r_days, r_bal;
                EXIT WHEN c_dyn%NOTFOUND;
                l_ov_idx := l_ov_idx + 1;
                l_overdue_list(l_ov_idx).invoice_id := r_id; l_overdue_list(l_ov_idx).invoice_number := r_num;
                l_overdue_list(l_ov_idx).vendor_name := r_vn; l_overdue_list(l_ov_idx).due_date := r_due;
                l_overdue_list(l_ov_idx).status := r_stat; l_overdue_list(l_ov_idx).days_overdue := r_days;
                l_overdue_list(l_ov_idx).balance_due := r_bal;
            END LOOP;
            CLOSE c_dyn;
        EXCEPTION WHEN OTHERS THEN IF c_dyn%ISOPEN THEN CLOSE c_dyn; END IF; END;
    END IF;

    -- 4. Vendor Concentration (Numeric calculation in PL/SQL)
    IF l_has_pay > 0 AND l_tot_exposure > 0 AND l_ap_error IS NULL THEN
        BEGIN
            OPEN c_dyn FOR '
                SELECT v.VENDOR_NAME, COUNT(i.INVOICE_ID), SUM(i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0))
                FROM KF_INVOICES i JOIN KF_VENDORS v ON i.VENDOR_ID = v.VENDOR_ID
                LEFT JOIN (SELECT INVOICE_ID, SUM(PAYMENT_AMOUNT) AS TOTAL_PAID FROM KF_PAYMENTS WHERE STATUS = ''COMPLETED'' GROUP BY INVOICE_ID) p ON i.INVOICE_ID = p.INVOICE_ID
                WHERE UPPER(NVL(i.STATUS, ''DRAFT'')) NOT IN (''PAID'', ''CANCELLED'', ''REJECTED'') AND (i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) > 0
                GROUP BY v.VENDOR_NAME ORDER BY SUM(i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) DESC FETCH FIRST 5 ROWS ONLY';
            LOOP
                FETCH c_dyn INTO r_vn, r_cnt, r_bal;
                EXIT WHEN c_dyn%NOTFOUND;
                l_vn_idx := l_vn_idx + 1;
                r_pct := ROUND((r_bal / l_tot_exposure) * 100, 1);
                l_vendor_list(l_vn_idx).vendor_name := r_vn; l_vendor_list(l_vn_idx).open_bills_count := r_cnt;
                l_vendor_list(l_vn_idx).vendor_open_balance := r_bal; l_vendor_list(l_vn_idx).concentration_pct := r_pct;
                IF l_vn_idx <= 3 THEN l_top3_conc_sum := l_top3_conc_sum + r_pct; END IF;
            END LOOP;
            CLOSE c_dyn;
        EXCEPTION WHEN OTHERS THEN IF c_dyn%ISOPEN THEN CLOSE c_dyn; END IF; END;
    END IF;

    -- 5. Monthly FY Actuals (Strict April-March Financial Year Match)
    BEGIN
        SELECT COUNT(*) INTO l_has_cashflow FROM user_tables WHERE table_name = 'KF_CASHFLOW_LEDGER';
        OPEN c_dyn FOR '
            SELECT TO_CHAR(INVOICE_DATE, ''Mon YYYY'') AS M_LBL, COUNT(*), NVL(SUM(TOTAL_AMOUNT), 0)
            FROM KF_INVOICES
            WHERE INVOICE_DATE >= TO_DATE(''01-04-' || l_fy_start_yr || ''', ''DD-MM-YYYY'')
              AND INVOICE_DATE < TO_DATE(''01-04-' || l_fy_end_yr || ''', ''DD-MM-YYYY'')
              AND UPPER(NVL(STATUS, ''DRAFT'')) != ''CANCELLED''
            GROUP BY TO_CHAR(INVOICE_DATE, ''Mon YYYY''), TRUNC(INVOICE_DATE, ''MONTH'')
            ORDER BY TRUNC(INVOICE_DATE, ''MONTH'') DESC FETCH FIRST 3 ROWS ONLY';
        LOOP
            FETCH c_dyn INTO r_lbl, r_cnt, r_exp;
            EXIT WHEN c_dyn%NOTFOUND;
            l_tr_idx := l_tr_idx + 1;
            l_trend_list(l_tr_idx).month_label := r_lbl; l_trend_list(l_tr_idx).bill_cnt := r_cnt;
            l_trend_list(l_tr_idx).expense_amt := r_exp;
            r_rec := 0;
            IF l_has_cashflow > 0 THEN
                BEGIN
                    EXECUTE IMMEDIATE '
                        SELECT NVL(SUM(AMOUNT), 0) FROM KF_CASHFLOW_LEDGER
                        WHERE UPPER(SECTION_HEADING) = ''CASH_RECEIPTS'' AND UPPER(REPORT_MONTH) = UPPER(SUBSTR(:1, 1, 3))
                          AND (UPPER(FIN_YEAR) = UPPER(:2) OR UPPER(FIN_YEAR) LIKE ''%'' || :3 || ''%'')'
                    INTO r_rec USING r_lbl, l_fy_label, TO_CHAR(l_fy_start_yr);
                EXCEPTION WHEN OTHERS THEN r_rec := 0; END;
            END IF;
            l_trend_list(l_tr_idx).receipt_amt := r_rec;
        END LOOP;
        CLOSE c_dyn;
    EXCEPTION WHEN OTHERS THEN l_trend_error := SUBSTR(SQLERRM, 1, 400); IF c_dyn%ISOPEN THEN CLOSE c_dyn; END IF;
    END;

    -- 6. HTML Rendering via CLOB
    app('<div id="slAiInsightsRegion" class="sl-insights-wrapper">');
    app('<div class="sl-ai-header"><div><div class="sl-ai-title">Kovaion Rule-Based Financial Intelligence Engine</div>');
    app('<div class="sl-ai-subtitle">Deterministic AP Risk Scoring &bull; Creditor Concentration &bull; Working Capital Analytics (' || l_fy_label || ')</div>');
    app('<div class="sl-ai-badges"><span class="sl-badge-pill sl-badge-green"><span class="sl-dot-live"></span> Rule-Based Analytics Active</span>');
    app('<span class="sl-badge-pill sl-badge-amber">&#9888; External AI Unconfigured (Local SQL Rules)</span>');
    app('<span class="sl-badge-pill sl-badge-gray">&#128337; Refreshed: ' || APEX_ESCAPE.HTML(l_timestamp_str) || '</span></div></div>');
    app('<div><button type="button" onclick="location.reload();" class="sl-refresh-btn">&#8635; Re-evaluate Engine</button></div></div>');

    IF l_ap_error IS NOT NULL OR l_bank_error IS NOT NULL OR l_trend_error IS NOT NULL THEN
        app('<div class="sl-error-banner" style="background:#fef2f2;border:1px solid #fecaca;padding:12px 16px;border-radius:10px;margin-bottom:16px;font-size:12px;color:#991b1b;"><b>&#9888; Subledger Query Warnings Encountered:</b><br>');
        IF l_ap_error IS NOT NULL THEN app('&bull; AP Subledger: ' || APEX_ESCAPE.HTML(l_ap_error) || '<br>'); END IF;
        IF l_bank_error IS NOT NULL THEN app('&bull; Bank Subledger: ' || APEX_ESCAPE.HTML(l_bank_error) || '<br>'); END IF;
        IF l_trend_error IS NOT NULL THEN app('&bull; Monthly Trends: ' || APEX_ESCAPE.HTML(l_trend_error)); END IF;
        app('</div>');
    END IF;

    -- 4 KPI Cards
    app('<div class="sl-ai-kpi-grid">');
    app('<div class="sl-ai-kpi-card" style="border-top:3px solid #10b981;"><div class="sl-ai-kpi-label">Book Liquidity Ratio</div><div class="sl-ai-kpi-val" style="color:#047857;">' || l_coverage_ratio || 'x</div><div class="sl-ai-kpi-sub">Book Bal ' || l_bank_fmt || ' / Total AP ' || l_pay_fmt || '</div><div class="sl-ai-kpi-status" style="color:#b45309;">&#9888; Unreconciled Book Ratio</div></div>');
    app('<div class="sl-ai-kpi-card" style="border-top:3px solid #ef4444;"><div class="sl-ai-kpi-label">Approved Overdue AP</div><div class="sl-ai-kpi-val" style="color:#dc2626;">' || l_over_fmt || '</div><div class="sl-ai-kpi-sub">' || l_appr_over_cnt || ' of ' || l_appr_cnt || ' Approved Bills Past Due</div><div class="sl-ai-kpi-status" style="color:#64748b;">' || CASE WHEN l_appr_cnt > 0 THEN l_overdue_pct || '% Overdue Exposure' ELSE '0 Approved Bills' END || '</div></div>');
    app('<div class="sl-ai-kpi-card" style="border-top:3px solid #f59e0b;"><div class="sl-ai-kpi-label">Awaiting Approval / Draft</div><div class="sl-ai-kpi-val" style="color:#d97706;">' || l_unappr_fmt || '</div><div class="sl-ai-kpi-sub">' || l_unappr_cnt || ' Invoices Pending Review</div><div class="sl-ai-kpi-status" style="color:#d97706;">&#9203; Unapproved Pipeline</div></div>');
    app('<div class="sl-ai-kpi-card" style="border-top:3px solid #3b82f6;"><div class="sl-ai-kpi-label">Active Creditor Exposure</div><div class="sl-ai-kpi-val" style="color:#2563eb;">' || l_vn_idx || ' Creditors</div><div class="sl-ai-kpi-sub">Top 3 hold ' || l_top3_conc_sum || '% Total AP</div><div class="sl-ai-kpi-status" style="color:#2563eb;">&#9679; Across ' || l_tot_bills_cnt || ' Total Bills</div></div>');
    app('</div>');

    -- 2 Columns: Overdue Invoices Table & Vendor Concentration Bars
    app('<div class="sl-ai-grid-2col"><div class="sl-ai-card"><div class="sl-ai-card-header"><div><div class="sl-ai-card-title">Approved Overdue Payables</div><div class="sl-ai-card-sub">Ranked by balance past contract due date (committed liabilities)</div></div><span class="sl-badge-pill sl-badge-red">' || l_ov_idx || ' Approved Past Due</span></div>');
    IF l_ov_idx > 0 THEN
        app('<div class="sl-table-wrap"><table class="sl-ai-table"><thead><tr><th>Invoice #</th><th>Vendor</th><th>Due Date</th><th>Status</th><th>Aging</th><th style="text-align:right;">Balance</th><th>Action</th></tr></thead><tbody>');
        FOR i IN 1..l_ov_idx LOOP
            app('<tr><td><span class="sl-badge-code">' || APEX_ESCAPE.HTML(l_overdue_list(i).invoice_number) || '</span></td>');
            app('<td><b>' || APEX_ESCAPE.HTML(l_overdue_list(i).vendor_name) || '</b></td><td>' || TO_CHAR(l_overdue_list(i).due_date, 'DD-Mon-YYYY') || '</td>');
            app('<td><span class="sl-badge-pill ' || CASE WHEN l_overdue_list(i).status IN ('APPROVED', 'OVERDUE') THEN 'sl-badge-red' ELSE 'sl-badge-amber' END || '">' || APEX_ESCAPE.HTML(l_overdue_list(i).status) || '</span></td>');
            app('<td><span style="color:#dc2626;font-weight:700;">' || l_overdue_list(i).days_overdue || 'd</span></td><td style="text-align:right;font-weight:700;color:#0f172a;">&#8377;' || TRIM(TO_CHAR(l_overdue_list(i).balance_due, '99,99,990')) || '</td>');
            app('<td><a href="f?p=' || l_app_id || ':10:' || l_app_session || ':::10,RIR:IR_INVOICE_NUMBER:' || APEX_ESCAPE.HTML(l_overdue_list(i).invoice_number) || '" class="sl-action-link" title="Filter Invoices Register">View &rarr;</a></td></tr>');
        END LOOP;
        app('</tbody></table></div>');
    ELSE app('<div class="sl-empty-state"><div class="sl-empty-icon">&#10003;</div><div class="sl-empty-title">Zero Past-Due Obligations</div><div class="sl-empty-desc">All invoices are within approved contractual payment schedules.</div></div>');
    END IF;
    app('</div>');

    app('<div class="sl-ai-card"><div class="sl-ai-card-header"><div><div class="sl-ai-card-title">Vendor Concentration Risk</div><div class="sl-ai-card-sub">Top counterparty exposure as % of total open payables</div></div><span class="sl-badge-pill sl-badge-blue">Top ' || l_vn_idx || ' Creditors</span></div>');
    IF l_vn_idx > 0 THEN
        app('<div class="sl-vendor-list">');
        FOR i IN 1..l_vn_idx LOOP
            app('<div class="sl-vendor-item"><div class="sl-vendor-header"><div><b>' || APEX_ESCAPE.HTML(l_vendor_list(i).vendor_name) || '</b> <small style="color:#64748b;">(' || l_vendor_list(i).open_bills_count || ' bills)</small></div><div style="font-weight:700;color:#0f172a;">&#8377;' || TRIM(TO_CHAR(l_vendor_list(i).vendor_open_balance, '99,99,990')) || ' <span style="color:#64748b;font-weight:600;">(' || l_vendor_list(i).concentration_pct || '%)</span></div></div>');
            app('<div class="sl-progress-bg"><div class="sl-progress-fill" style="width:' || LEAST(100, GREATEST(5, l_vendor_list(i).concentration_pct * 3.5)) || '%;"></div></div></div>');
        END LOOP;
        app('<div class="sl-conc-footer">&#9888; <b>Top 3 Creditors</b> represent <b>' || l_top3_conc_sum || '%</b> of total pending payables.</div></div>');
    ELSE app('<div class="sl-empty-state"><div class="sl-empty-icon">&#10003;</div><div class="sl-empty-title">No Open Creditor Balances</div><div class="sl-empty-desc">No active vendor payables exist in the database.</div></div>');
    END IF;
    app('</div></div>');

    -- Monthly FY Comparison
    app('<div class="sl-ai-card" style="margin-bottom:16px;"><div class="sl-ai-card-header"><div><div class="sl-ai-card-title">Monthly Expense Accruals vs Cash Receipts (' || l_fy_label || ')</div><div class="sl-ai-card-sub">Strict April-March FY subledger comparison (KF_INVOICES vs KF_CASHFLOW_LEDGER)</div></div><span class="sl-badge-pill sl-badge-gray">' || l_fy_label || ' Actuals</span></div>');
    IF l_tr_idx > 0 THEN
        app('<div class="sl-table-wrap"><table class="sl-ai-table"><thead><tr><th>Reporting Period</th><th>Bills Recorded (AP)</th><th>Expense Accruals</th><th>Customer Cash Receipts</th><th>Data Status</th></tr></thead><tbody>');
        FOR i IN 1..l_tr_idx LOOP
            app('<tr><td><b>' || APEX_ESCAPE.HTML(l_trend_list(i).month_label) || '</b></td><td>' || l_trend_list(i).bill_cnt || ' bills recorded</td><td style="font-weight:700;color:#0f172a;">&#8377;' || TRIM(TO_CHAR(l_trend_list(i).expense_amt, '99,99,990')) || '</td>');
            app('<td style="font-weight:700;' || CASE WHEN l_trend_list(i).receipt_amt > 0 THEN 'color:#047857;' ELSE 'color:#94a3b8;' END || '">' || CASE WHEN l_trend_list(i).receipt_amt > 0 THEN '&#8377;' || TRIM(TO_CHAR(l_trend_list(i).receipt_amt, '99,99,990')) ELSE 'Unrecorded (AR unintegrated)' END || '</td>');
            app('<td>' || CASE WHEN l_trend_list(i).receipt_amt > 0 THEN '<span class="sl-badge-pill sl-badge-green">&#9679; Dual Sourced (' || l_fy_label || ')</span>' ELSE '<span class="sl-badge-pill sl-badge-amber">&#9888; AP Subledger Only</span>' END || '</td></tr>');
        END LOOP;
        app('</tbody></table></div>');
    ELSE app('<div class="sl-empty-state"><div class="sl-empty-title">No Billing Records Found for ' || l_fy_label || '</div></div>');
    END IF;
    app('</div>');

    -- Disclosures Banner
    app('<div class="sl-disclosure-banner"><div class="sl-disclosure-title">&#9888; Financial Integrity &amp; Accounting Disclosures</div><div class="sl-disclosure-grid">');
    app('<div class="sl-disclosure-item"><b>1. Unreconciled Bank Balances:</b> Total bank balance (' || l_bank_fmt || ' across ' || l_bank_acc_cnt || ' accounts) reflects internal book balances from KF_BANK_ACCOUNTS. Completed disbursements are not double-deducted. Physical bank statement reconciliation remains pending.</div>');
    app('<div class="sl-disclosure-item"><b>2. Invoice Approval Controls:</b> Draft and Pending Approval invoices (' || l_unappr_fmt || ' across ' || l_unappr_cnt || ' bills) are isolated from approved overdue liabilities to uphold accounting controls. Only approved bills constitute committed liabilities.</div>');
    app('<div class="sl-disclosure-item"><b>3. Rule-Based Intelligence:</b> Sourced deterministically from local Oracle subledgers for ' || l_fy_label || '. No external LLM or cloud API is connected. Customer receivables (AR) remain unintegrated.</div>');
    app('</div></div>');

    -- Action Cards
    app('<div class="sl-ai-actions-grid">');
    app('<div class="sl-ai-action-card"><div class="sl-action-icon" style="background:#fee2e2;color:#dc2626;">&#128181;</div><div class="sl-action-title">Review &amp; Approve Invoices</div><div class="sl-action-desc">' || l_unappr_cnt || ' invoices totaling ' || l_unappr_fmt || ' are in Draft or Pending Approval. Review and approve to release payment milestones.</div><a href="f?p=' || l_app_id || ':10:' || l_app_session || '::NO:10::" class="sl-btn-action">Review Invoices (Page 10) &rarr;</a></div>');
    app('<div class="sl-ai-action-card"><div class="sl-action-icon" style="background:#e0e7ff;color:#4f46e5;">&#128202;</div><div class="sl-action-title">Vendor Credit Concentration</div><div class="sl-action-desc">' || CASE WHEN l_vn_idx > 0 THEN APEX_ESCAPE.HTML(l_vendor_list(1).vendor_name) || ' holds ' || l_vendor_list(1).concentration_pct || '% of open payables. Manage supplier risk.' ELSE 'Monitor active vendor exposure.' END || '</div><a href="f?p=' || l_app_id || ':50:' || l_app_session || '::NO:50::" class="sl-btn-action">Manage Payments (Page 50) &rarr;</a></div>');
    app('<div class="sl-ai-action-card"><div class="sl-action-icon" style="background:#fef3c7;color:#d97706;">&#128221;</div><div class="sl-action-title">Bank Statement Reconciliation</div><div class="sl-action-desc">Audit corporate book balance (' || l_bank_fmt || ') against physical bank statements to verify cleared funds prior to releasing scheduled payments.</div><a href="f?p=' || l_app_id || ':40:' || l_app_session || '::NO:40::" class="sl-btn-action">Audit Ledgers (Page 40) &rarr;</a></div>');
    app('</div>');

    -- Always-Visible Render & Tab Smooth-Scroll JS
    app('<script>(function(){function setupInsightsRegion(){var ir=document.getElementById("slAiInsightsRegion");if(!ir)return;var apexReg=ir.closest(".t-Region");if(apexReg)apexReg.style.setProperty("display","block","important");ir.style.setProperty("display","block","important");var tabs=document.querySelectorAll(".sl-tab-btn");tabs.forEach(function(btn){btn.addEventListener("click",function(){var t=(this.getAttribute("data-tab")||this.innerText||"").toLowerCase();if(t.indexOf("insight")!==-1){ir.scrollIntoView({behavior:"smooth"});}});});}if(document.readyState==="complete"||document.readyState==="interactive"){setTimeout(setupInsightsRegion,40);}else{document.addEventListener("DOMContentLoaded",setupInsightsRegion);}})();</script>');
    app('</div>');

    RETURN l_html;
EXCEPTION WHEN OTHERS THEN
    RETURN '<div style="padding:16px;background:#fff;border:1px solid #e2e8f0;border-radius:10px;margin-bottom:16px;"><b style="color:#dc2626;">Rule-Based Financial Intelligence Engine Error:</b> ' || APEX_ESCAPE.HTML(SQLERRM) || '</div>';
END;
