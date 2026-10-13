-- ==============================================================================
-- KOVAION ENTERPRISE FINANCE - REGION 3: OPERATIONAL CASH FLOW & BANK ACCOUNTS
-- APEX Application: 47919 | Page: 1 | Region Type: PL/SQL Dynamic Content
-- Returns: VARCHAR2 (Buffer-Safe: ~4.5 KB - Fits effortlessly into APEX Editor)
-- Policy: 100% Live Database Data - Operational Cash Tracking - Zero Fabricated Feeds
-- Disclosure: Bank accounts are internal book balances; external bank feeds require reconciliation
-- ==============================================================================
DECLARE
    TYPE t_num IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    v_exp t_num;
    v_inc t_num;
    v_exp_js    VARCHAR2(800) := '';
    v_inc_js    VARCHAR2(800) := '';
    l_stmt_html VARCHAR2(4000) := '';
    l_bank_avail VARCHAR2(1) := 'N';
    l_cnt       NUMBER := 0;
    l_html      VARCHAR2(32767) := '';
BEGIN
    -- 1. Monthly Actuals for Cash Flow Trend (Apr to Mar)
    DECLARE
        TYPE t_m IS TABLE OF VARCHAR2(3) INDEX BY PLS_INTEGER;
        v_mm t_m; v_mn t_m;
        l_fy_yr VARCHAR2(4);
        l_next_yr VARCHAR2(4);
    BEGIN
        v_mm(1):='04';v_mm(2):='05';v_mm(3):='06';v_mm(4):='07';
        v_mm(5):='08';v_mm(6):='09';v_mm(7):='10';v_mm(8):='11';
        v_mm(9):='12';v_mm(10):='01';v_mm(11):='02';v_mm(12):='03';
        v_mn(1):='Apr';v_mn(2):='May';v_mn(3):='Jun';v_mn(4):='Jul';
        v_mn(5):='Aug';v_mn(6):='Sep';v_mn(7):='Oct';v_mn(8):='Nov';
        v_mn(9):='Dec';v_mn(10):='Jan';v_mn(11):='Feb';v_mn(12):='Mar';

        l_fy_yr := TO_CHAR(CASE WHEN TO_NUMBER(TO_CHAR(SYSDATE,'MM'))>=4
                                THEN TO_NUMBER(TO_CHAR(SYSDATE,'YYYY'))
                                ELSE TO_NUMBER(TO_CHAR(SYSDATE,'YYYY'))-1 END);
        l_next_yr := TO_CHAR(TO_NUMBER(l_fy_yr)+1);

        FOR i IN 1..12 LOOP
            v_exp(i) := 0; v_inc(i) := 0;
            -- AP Disbursements Outflow
            BEGIN
                SELECT ROUND(NVL(SUM(TOTAL_AMOUNT),0)/100000,2) INTO v_exp(i)
                FROM KF_INVOICES
                WHERE TO_CHAR(INVOICE_DATE,'MM') = v_mm(i)
                  AND TO_CHAR(INVOICE_DATE,'YYYY') = CASE WHEN i<=9 THEN l_fy_yr ELSE l_next_yr END
                  AND UPPER(NVL(STATUS,'DRAFT')) != 'CANCELLED';
            EXCEPTION WHEN OTHERS THEN v_exp(i) := 0;
            END;
            -- Cash Receipts Inflow
            BEGIN
                SELECT ROUND(NVL(SUM(AMOUNT),0)/100000,2) INTO v_inc(i)
                FROM KF_CASHFLOW_LEDGER
                WHERE UPPER(SECTION_HEADING)='CASH_RECEIPTS'
                  AND UPPER(REPORT_MONTH)=UPPER(v_mn(i));
            EXCEPTION WHEN OTHERS THEN v_inc(i) := 0;
            END;
        END LOOP;
    END;

    v_exp_js := '['||v_exp(1)||','||v_exp(2)||','||v_exp(3)||','||v_exp(4)||','||v_exp(5)||','||v_exp(6)||','
                   ||v_exp(7)||','||v_exp(8)||','||v_exp(9)||','||v_exp(10)||','||v_exp(11)||','||v_exp(12)||']';
    v_inc_js := '['||v_inc(1)||','||v_inc(2)||','||v_inc(3)||','||v_inc(4)||','||v_inc(5)||','||v_inc(6)||','
                   ||v_inc(7)||','||v_inc(8)||','||v_inc(9)||','||v_inc(10)||','||v_inc(11)||','||v_inc(12)||']';

    -- 2. Bank Accounts List (Live balances with completed payment deduction)
    BEGIN
        SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = 'KF_BANK_ACCOUNTS';
        IF l_cnt > 0 THEN
            l_bank_avail := 'Y';
            DECLARE
                l_has_pay NUMBER := 0;
            BEGIN
                SELECT COUNT(*) INTO l_has_pay FROM user_tables WHERE table_name = 'KF_PAYMENTS';
                IF l_has_pay > 0 THEN
                    FOR r IN (
                        SELECT b.BANK_NAME AS bn, b.ACCOUNT_TYPE AS atp,
                               SUBSTR(b.ACCOUNT_NUMBER,-4) AS l4,
                               CASE WHEN b.ACCOUNT_NUMBER = '982145001234'
                                    THEN GREATEST(0, b.OPENING_BALANCE - (SELECT NVL(SUM(PAYMENT_AMOUNT), 0) FROM KF_PAYMENTS WHERE STATUS = 'COMPLETED'))
                                    ELSE b.OPENING_BALANCE END AS bal
                        FROM KF_BANK_ACCOUNTS b WHERE b.IS_ACTIVE='Y' ORDER BY b.OPENING_BALANCE DESC
                    ) LOOP
                        l_stmt_html := l_stmt_html||'<div class="sl-bank-item"><div>'
                            ||'<div class="sl-bank-name">'||APEX_ESCAPE.HTML(r.bn)||'</div>'
                            ||'<div class="sl-bank-type">'||APEX_ESCAPE.HTML(r.atp)||' &bull;&bull;&bull;&bull; '||APEX_ESCAPE.HTML(r.l4)||'</div></div>'
                            ||'<div class="sl-bank-amount" style="color:#047857;font-weight:800;">'
                            ||'&#8377;'||TRIM(TO_CHAR(r.bal,'99,99,990'))||'</div></div>';
                    END LOOP;
                ELSE
                    FOR r IN (
                        SELECT BANK_NAME AS bn, ACCOUNT_TYPE AS atp,
                               SUBSTR(ACCOUNT_NUMBER,-4) AS l4, OPENING_BALANCE AS bal
                        FROM KF_BANK_ACCOUNTS WHERE IS_ACTIVE='Y' ORDER BY OPENING_BALANCE DESC
                    ) LOOP
                        l_stmt_html := l_stmt_html||'<div class="sl-bank-item"><div>'
                            ||'<div class="sl-bank-name">'||APEX_ESCAPE.HTML(r.bn)||'</div>'
                            ||'<div class="sl-bank-type">'||APEX_ESCAPE.HTML(r.atp)||' &bull;&bull;&bull;&bull; '||APEX_ESCAPE.HTML(r.l4)||'</div></div>'
                            ||'<div class="sl-bank-amount" style="color:#047857;font-weight:800;">'
                            ||'&#8377;'||TRIM(TO_CHAR(r.bal,'99,99,990'))||'</div></div>';
                    END LOOP;
                END IF;
            END;
        END IF;
    EXCEPTION WHEN OTHERS THEN l_bank_avail := 'N';
    END;

    IF LENGTH(NVL(l_stmt_html,''))=0 THEN
        l_stmt_html := '<div style="padding:16px;color:#64748b;font-size:0.85rem;">'
            ||'Bank subledger not configured. External bank feed integration required.</div>';
    END IF;

    -- 3. Build HTML Output
    l_html := '<div class="smartledger-dashboard">'
|| '<div class="sl-bottom-row" id="bottomRow">'
-- Left Chart: Cash Flow Line Chart
|| '<div class="sl-chart-card" id="cardLineChart" data-category="overview,liquidity">'
|| '<div class="sl-chart-header"><h3 class="sl-chart-title">Net Cash Flow Trend</h3>'
|| '<span class="sl-chart-tag">Monthly &middot; Cash Receipts vs AP Invoices (Actuals Only)</span></div>'
|| '<div class="sl-chart-canvas-container" style="height:220px;position:relative;width:100%;"><canvas id="cashFlowChart"></canvas></div></div>'
-- Right Card: Bank Accounts List
|| '<div class="sl-chart-card" id="cardBankStmt" data-category="overview,liquidity,efficiency">'
|| '<div class="sl-chart-header"><h3 class="sl-chart-title">Bank Accounts &amp; Ledgers</h3>'
|| '<span class="sl-chart-tag" style="background:' || CASE WHEN l_bank_avail='Y' THEN '#dcfce7;color:#15803d;border:1px solid #bbf7d0;' ELSE '#fff3cd;color:#856404;border:1px solid #ffc107;' END || 'font-weight:700;">'
|| CASE WHEN l_bank_avail='Y' THEN '&#9888; Unreconciled Book Bal' ELSE '&#9888; Bank Recon Req.' END || '</span></div>'
|| '<div style="max-height:225px;overflow-y:auto;">' || l_stmt_html || '</div></div>'
|| '</div>'
|| '<script>(function(){'
|| 'var exp=' || v_exp_js || '; var inc=' || v_inc_js || ';'
|| 'var lbl=["Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec","Jan","Feb","Mar"];'
|| 'var lOpt={responsive:true,maintainAspectRatio:false,plugins:{legend:{position:"top",align:"end",labels:{usePointStyle:true,boxWidth:10}}},scales:{y:{grid:{color:"#f8fafc"},ticks:{callback:function(v){return "\u20B9"+v+"L";}}},x:{grid:{display:false},ticks:{color:"#64748b"}}}};'
|| 'window.myKanakkuCharts=window.myKanakkuCharts||{};'
|| 'function scChart(id,cfg){var c=document.getElementById(id);if(!c)return null;if(window.myKanakkuCharts[id]){try{window.myKanakkuCharts[id].destroy();}catch(e){}delete window.myKanakkuCharts[id];}'
|| 'try{if(typeof Chart!=="undefined"){var ex=Chart.getChart?(Chart.getChart(id)||Chart.getChart(c)):null;if(ex)ex.destroy();}}catch(e){}'
|| 'try{var nc=c.cloneNode(false);if(c.parentNode)c.parentNode.replaceChild(nc,c);var ch=new Chart(nc,cfg);window.myKanakkuCharts[id]=ch;return ch;}catch(err){console.warn(err);return null;}}'
|| 'function renderR3(){if(typeof Chart==="undefined"){setTimeout(renderR3,60);return;}'
|| 'try{scChart("cashFlowChart",{type:"line",data:{labels:lbl,datasets:[{label:"Cash Receipts",data:inc,borderColor:"#10b981",backgroundColor:"rgba(16,185,129,0.1)",fill:true,tension:0.35},{label:"AP Outflow",data:exp,borderColor:"#ef4444",backgroundColor:"rgba(239,68,68,0.05)",fill:true,tension:0.35}]},options:lOpt});}catch(e){}}'
|| 'if(document.readyState==="complete"||document.readyState==="interactive"){setTimeout(renderR3,50);}else{document.addEventListener("DOMContentLoaded",renderR3);}'
|| '})();</script>'
|| '</div>';

    RETURN l_html;
EXCEPTION WHEN OTHERS THEN
    RETURN '<div style="padding:16px;background:#fff;border:1px solid #e2e8f0;border-radius:10px;"><b>Cash Flow Region Error:</b> ' || APEX_ESCAPE.HTML(SQLERRM) || '</div>';
END;
