-- ==============================================================================
-- KOVAION ENTERPRISE FINANCE - REGION 2: OPERATIONAL FLOWS & AP BREAKDOWN (CHARTS)
-- APEX Application: 47919 | Page: 1 | Region Type: PL/SQL Dynamic Content
-- Returns: VARCHAR2 (Buffer-Safe: ~5.2 KB - Fits effortlessly into APEX Editor)
-- Policy: 100% Live Database Data - Sourced from Receipts & AP Invoices
-- Disclosure: Displays operational cash receipts and AP invoices, NOT audited revenue
-- ==============================================================================
DECLARE
    TYPE t_num IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    v_exp t_num;
    v_inc t_num;
    v_exp_js    VARCHAR2(800) := '';
    v_inc_js    VARCHAR2(800) := '';
    l_tot_pay   NUMBER := 0;
    l_tot_paid  NUMBER := 0;
    l_tot_gst   NUMBER := 0;
    l_tot_over  NUMBER := 0;
    l_pay_fmt   VARCHAR2(60);
    l_paid_fmt  VARCHAR2(60);
    l_gst_fmt   VARCHAR2(60);
    l_over_fmt  VARCHAR2(60);
    l_tax_col   VARCHAR2(30) := NULL;
    l_cnt       NUMBER := 0;
    l_html      VARCHAR2(32767) := '';
BEGIN
    -- 1. Donut Chart Breakdown (Accounts for partial completed payments)
    BEGIN
        SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = 'KF_PAYMENTS';
        IF l_cnt > 0 THEN
            EXECUTE IMMEDIATE '
                SELECT 
                    NVL(SUM(GREATEST(0, i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0))), 0),
                    NVL(SUM(CASE WHEN i.DUE_DATE < TRUNC(SYSDATE) 
                                 THEN GREATEST(0, i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)) ELSE 0 END), 0)
                FROM KF_INVOICES i
                LEFT JOIN (
                    SELECT INVOICE_ID, SUM(PAYMENT_AMOUNT) AS TOTAL_PAID
                    FROM KF_PAYMENTS
                    WHERE STATUS = ''COMPLETED''
                    GROUP BY INVOICE_ID
                ) p ON i.INVOICE_ID = p.INVOICE_ID
                WHERE UPPER(NVL(i.STATUS, ''DRAFT'')) NOT IN (''PAID'', ''CANCELLED'', ''REJECTED'')'
            INTO l_tot_pay, l_tot_over;

            EXECUTE IMMEDIATE
                'SELECT NVL(SUM(PAYMENT_AMOUNT), 0) FROM KF_PAYMENTS WHERE STATUS = ''COMPLETED'''
            INTO l_tot_paid;
        ELSE
            SELECT 
                NVL(SUM(TOTAL_AMOUNT), 0),
                NVL(SUM(CASE WHEN DUE_DATE < TRUNC(SYSDATE) THEN TOTAL_AMOUNT ELSE 0 END), 0)
            INTO l_tot_pay, l_tot_over
            FROM KF_INVOICES
            WHERE UPPER(NVL(STATUS, 'DRAFT')) NOT IN ('PAID', 'CANCELLED', 'REJECTED');
            l_tot_paid := 0;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        l_tot_pay := 0; l_tot_paid := 0; l_tot_over := 0;
    END;

    -- Dynamic GST Column Detection (Handles TAX_AMOUNT, GST_AMOUNT, or COALESCE if both exist)
    DECLARE
        l_has_tax NUMBER := 0;
        l_has_gst NUMBER := 0;
        l_tax_sql VARCHAR2(500);
    BEGIN
        SELECT COUNT(CASE WHEN column_name = 'TAX_AMOUNT' THEN 1 END),
               COUNT(CASE WHEN column_name = 'GST_AMOUNT' THEN 1 END)
        INTO l_has_tax, l_has_gst
        FROM user_tab_columns
        WHERE table_name = 'KF_INVOICES';

        IF l_has_tax > 0 AND l_has_gst > 0 THEN
            l_tax_sql := 'SELECT NVL(SUM(COALESCE(TAX_AMOUNT, GST_AMOUNT, 0)), 0) FROM KF_INVOICES WHERE UPPER(NVL(STATUS, ''DRAFT'')) != ''CANCELLED''';
        ELSIF l_has_tax > 0 THEN
            l_tax_sql := 'SELECT NVL(SUM(TAX_AMOUNT), 0) FROM KF_INVOICES WHERE UPPER(NVL(STATUS, ''DRAFT'')) != ''CANCELLED''';
        ELSIF l_has_gst > 0 THEN
            l_tax_sql := 'SELECT NVL(SUM(GST_AMOUNT), 0) FROM KF_INVOICES WHERE UPPER(NVL(STATUS, ''DRAFT'')) != ''CANCELLED''';
        ELSE
            l_tax_sql := NULL;
        END IF;

        IF l_tax_sql IS NOT NULL THEN
            EXECUTE IMMEDIATE l_tax_sql INTO l_tot_gst;
        ELSE
            l_tot_gst := 0;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        l_tot_gst := 0;
    END;

    l_pay_fmt  := '&#8377;'||TRIM(TO_CHAR(l_tot_pay,'99,99,99,990'));
    l_paid_fmt := '&#8377;'||TRIM(TO_CHAR(l_tot_paid,'99,99,99,990'));
    l_gst_fmt  := '&#8377;'||TRIM(TO_CHAR(l_tot_gst,'99,99,99,990'));
    l_over_fmt := '&#8377;'||TRIM(TO_CHAR(l_tot_over,'99,99,99,990'));

    -- 2. 12-Month Bar Chart (Actuals from KF_INVOICES + KF_CASHFLOW_LEDGER; empty months = 0.0)
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
            -- Actual AP Expenses by month (accruals)
            BEGIN
                SELECT ROUND(NVL(SUM(TOTAL_AMOUNT),0)/100000,2) INTO v_exp(i)
                FROM KF_INVOICES
                WHERE TO_CHAR(INVOICE_DATE,'MM') = v_mm(i)
                  AND TO_CHAR(INVOICE_DATE,'YYYY') = CASE WHEN i<=9 THEN l_fy_yr ELSE l_next_yr END
                  AND UPPER(NVL(STATUS,'DRAFT')) != 'CANCELLED';
            EXCEPTION WHEN OTHERS THEN v_exp(i) := 0;
            END;
            -- Actual Cash Receipts from KF_CASHFLOW_LEDGER
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

    -- 3. Build HTML Output
    l_html := '<div class="smartledger-dashboard">'
|| '<div class="sl-charts-row" id="chartsRow">'
-- Left Chart: Bar Chart (Transparently disclosed as Cash Receipts vs AP Invoices)
|| '<div class="sl-chart-card" id="cardBarChart" data-category="overview,profitability">'
|| '<div class="sl-chart-header"><h3 class="sl-chart-title">Cash Receipts vs AP Invoices</h3>'
|| '<span class="sl-chart-tag">FY 2026-27 &middot; Operational Receipts vs AP Accruals</span></div>'
|| '<div class="sl-chart-canvas-container" style="height:250px;position:relative;width:100%;"><canvas id="incomeExpensesChart"></canvas></div></div>'
-- Right Chart: Donut Chart
|| '<div class="sl-chart-card" id="cardDonutChart" data-category="overview,taxation,efficiency">'
|| '<div class="sl-chart-header"><h3 class="sl-chart-title">AP Expense Breakdown</h3><span class="sl-chart-tag">Live Subledger</span></div>'
|| '<div class="sl-chart-canvas-container" style="height:170px;position:relative;width:100%;"><canvas id="expensesDonutChart"></canvas></div>'
|| '<div class="sl-donut-legend">'
|| '<div class="sl-legend-item"><div class="sl-legend-label"><span class="sl-legend-dot" style="background:#3b82f6;"></span>Open Payables</div><span class="sl-legend-val">' || l_pay_fmt || '</span></div>'
|| '<div class="sl-legend-item"><div class="sl-legend-label"><span class="sl-legend-dot" style="background:#10b981;"></span>Paid</div><span class="sl-legend-val">' || l_paid_fmt || '</span></div>'
|| '<div class="sl-legend-item"><div class="sl-legend-label"><span class="sl-legend-dot" style="background:#f59e0b;"></span>GST / Tax</div><span class="sl-legend-val">' || l_gst_fmt || '</span></div>'
|| '<div class="sl-legend-item"><div class="sl-legend-label"><span class="sl-legend-dot" style="background:#ec4899;"></span>Overdue</div><span class="sl-legend-val">' || l_over_fmt || '</span></div>'
|| '</div></div>'
|| '</div>'
|| '<script>(function(){'
|| 'var exp=' || v_exp_js || '; var inc=' || v_inc_js || ';'
|| 'var lbl=["Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec","Jan","Feb","Mar"];'
|| 'var sOpt={responsive:true,maintainAspectRatio:false,plugins:{legend:{position:"top",align:"end",labels:{usePointStyle:true,boxWidth:10}}},scales:{y:{grid:{color:"#f1f5f9"},ticks:{callback:function(v){return "\u20B9"+v+"L";}}},x:{grid:{display:false},ticks:{color:"#64748b"}}}};'
|| 'window.myKanakkuCharts=window.myKanakkuCharts||{};'
|| 'function scChart(id,cfg){var c=document.getElementById(id);if(!c)return null;if(window.myKanakkuCharts[id]){try{window.myKanakkuCharts[id].destroy();}catch(e){}delete window.myKanakkuCharts[id];}'
|| 'try{if(typeof Chart!=="undefined"){var ex=Chart.getChart?(Chart.getChart(id)||Chart.getChart(c)):null;if(ex)ex.destroy();}}catch(e){}'
|| 'try{var nc=c.cloneNode(false);if(c.parentNode)c.parentNode.replaceChild(nc,c);var ch=new Chart(nc,cfg);window.myKanakkuCharts[id]=ch;return ch;}catch(err){console.warn(err);return null;}}'
|| 'function renderR2(){if(typeof Chart==="undefined"){setTimeout(renderR2,60);return;}'
|| 'try{scChart("incomeExpensesChart",{type:"bar",data:{labels:lbl,datasets:[{label:"Cash Receipts",data:inc,backgroundColor:"#4f46e5",borderRadius:6,barPercentage:0.6,categoryPercentage:0.7},{label:"AP Invoices",data:exp,backgroundColor:"#f97316",borderRadius:6,barPercentage:0.6,categoryPercentage:0.7}]},options:sOpt});}catch(e){}'
|| 'try{scChart("expensesDonutChart",{type:"doughnut",data:{labels:["Open Payables","Paid","GST/Tax","Overdue"],datasets:[{data:[' || l_tot_pay || ',' || l_tot_paid || ',' || l_tot_gst || ',' || l_tot_over || '],backgroundColor:["#3b82f6","#10b981","#f59e0b","#ec4899"],borderWidth:3,borderColor:"#fff"}]},options:{responsive:true,maintainAspectRatio:false,cutout:"70%",plugins:{legend:{display:false}}}});}catch(e){}}'
|| 'if(document.readyState==="complete"||document.readyState==="interactive"){setTimeout(renderR2,50);}else{document.addEventListener("DOMContentLoaded",renderR2);}'
|| '})();</script>'
|| '</div>';

    RETURN l_html;
EXCEPTION WHEN OTHERS THEN
    RETURN '<div style="padding:16px;background:#fff;border:1px solid #e2e8f0;border-radius:10px;"><b>Charts Region Error:</b> ' || APEX_ESCAPE.HTML(SQLERRM) || '</div>';
END;
