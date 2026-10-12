# Kovaion Enterprise Suite — Financial Dashboard Fix Log
**Application:** APEX Application 47919, Page 1  
**Audit Phase:** Phase B — Evidence-Based Correction Log  
**File Modified:** [`update_page1_dashboard.sql`](file:///c:/Users/GowsikPrakashbabu/Desktop/Kovaion_Finance/update_page1_dashboard.sql)  

---

### Defect 1: Unverified Bank Balance & Misleading Live Status Label
* **Affected Area:** Audit 1 — Total Bank Balance
* **Root Cause:** Sourced from an unverified fallback baseline of ₹1,28,75,000 without an authoritative general ledger cash account or bank feed, labeled as "Live".
* **Audit Acceptance Standard:** Numeric bank balance must be displayed only when an authoritative source exists; otherwise display `Unavailable (Reconciliation Required)`.
* **Before Code:**
  ```sql
  BEGIN
      SELECT NVL(SUM(CURRENT_BALANCE), 12875000)
      INTO l_bank_bal FROM KF_BANK_ACCOUNTS;
  EXCEPTION WHEN OTHERS THEN l_bank_bal := 12875000;
  END;
  l_bank_bal := GREATEST(1000000, NVL(l_bank_bal, 12875000) - NVL(l_paid_sum, 0));
  l_bank_bal_fmt := '₹' || TRIM(TO_CHAR(l_bank_bal, '99,99,99,990'));
  ```
  ```html
  <div class="sl-card" data-category="overview,liquidity">
      <div class="sl-kpi-title">Total Bank Balance</div>
      <div class="sl-kpi-value">' || l_bank_bal_fmt || '</div>
      <div class="sl-kpi-trend sl-trend-up">
          <span>↑ Live</span> <span class="sl-kpi-subtitle">net of disbursements</span>
      </div>
  </div>
  ```
* **After Code:**
  ```sql
  -- 3. Bank Balance & Cash Metrics (Audit: Reconciliation Required)
  -- Per financial audit, no verified general-ledger opening balance or bank feed exists.
  l_bank_bal     := NULL;
  l_bank_bal_fmt := 'Unavailable (Reconciliation Required)';
  ```
  ```html
  <div class="sl-card" data-category="overview,liquidity" style="border-top: 3px solid #f59e0b;">
      <div class="sl-kpi-title">Total Bank Balance</div>
      <div class="sl-kpi-value" style="font-size: 14px; font-weight: 700; color: #b45309; line-height: 1.35; margin-top: 4px; margin-bottom: 8px;">' || l_bank_bal_fmt || '</div>
      <div class="sl-kpi-trend" style="display: flex; align-items: center; gap: 6px; font-size: 12px; font-weight: 600; color: #d97706;">
          <span>●</span> <span class="sl-kpi-subtitle" style="color: #92400e; font-weight: 600;">Pending Bank Reconciliation</span>
      </div>
  </div>
  ```

---

### Defect 2: Hardcoded Total Receivables without AR Subledger
* **Affected Area:** Audit 3 — Total Receivables
* **Root Cause:** Displayed static HTML string `₹38,50,000` with subtitle `14 client invoices`, despite zero customer tables or AR ledgers in the database schema.
* **Audit Acceptance Standard:** State schema limitation truthfully; display `Unavailable (AR Subledger Required)`.
* **Before Code:**
  ```html
  <div class="sl-card" data-category="overview,profitability">
      <div class="sl-kpi-title">Total Receivables</div>
      <div class="sl-kpi-value">₹38,50,000</div>
      <div class="sl-kpi-trend sl-trend-down">
          <span>↓ -4.2%</span> <span class="sl-kpi-subtitle">14 client invoices</span>
      </div>
  </div>
  ```
* **After Code:**
  ```html
  <div class="sl-card" data-category="overview,profitability" style="border-top: 3px solid #f59e0b;">
      <div class="sl-kpi-title">Total Receivables</div>
      <div class="sl-kpi-value" style="font-size: 14px; font-weight: 700; color: #b45309; line-height: 1.35; margin-top: 4px; margin-bottom: 8px;">Unavailable (AR Subledger Req.)</div>
      <div class="sl-kpi-trend" style="display: flex; align-items: center; gap: 6px; font-size: 12px; font-weight: 600; color: #d97706;">
          <span>●</span> <span class="sl-kpi-subtitle" style="color: #92400e; font-weight: 600;">Pending Customer AR Module</span>
      </div>
  </div>
  ```

---

### Defect 3: Synthetic Financial Health Gauge & Unverified Cash Runway
* **Affected Area:** Audit 4 — Cash Coverage / Liquidity
* **Root Cause:** Hardcoded static health score (88), liquidity ratio (2.4x), and solvency grade (A+) rendered without balance sheet assets or verified cash reserves. Cash runway claimed 18.4 months based on unverified cash.
* **Audit Acceptance Standard:** If bank balance is not verified, do not present cash-dependent metrics as verified; display `N/A — Reconciliation Required`.
* **Before Code:**
  ```html
  <div class="sl-gauge-score">
      <strong>88</strong>
      <span>EXCELLENT</span>
  </div>
  <div class="sl-health-metrics">
      <div class="sl-health-item">
          <small>Liquidity Ratio</small>
          <strong>2.4x (Safe)</strong>
      </div>
      <div class="sl-health-item">
          <small>Solvency Score</small>
          <strong>A+ Grade</strong>
      </div>
  </div>
  ```
  ```html
  <div class="sl-card" data-category="overview,liquidity">
      <div class="sl-kpi-title">Cash Runway</div>
      <div class="sl-kpi-value">18.4 Mos</div>
      <div class="sl-kpi-trend sl-trend-up">
          <span>↑ Live</span> <span class="sl-kpi-subtitle">sustainable runway</span>
      </div>
  </div>
  ```
* **After Code:**
  ```html
  <div class="sl-health-card" data-category="overview,efficiency">
      <div class="sl-health-title">Cash Coverage Indicator</div>
      <div class="sl-gauge-wrapper">
          <svg class="sl-gauge-svg" viewBox="0 0 100 55">
              <path d="M 10 50 A 40 40 0 0 1 90 50" fill="none" stroke="#e2e8f0" stroke-width="10" stroke-linecap="round" />
          </svg>
          <div class="sl-gauge-score" title="Cash Coverage unavailable: Requires reconciled bank balance">
              <strong>N/A</strong>
              <span style="font-size: 10px; color: #94a3b8;">Reconciliation Required</span>
          </div>
      </div>
      <div class="sl-health-metrics">
          <div class="sl-health-item" title="Cash-to-Payables ratio unavailable pending bank reconciliation">
              <small>Est. Cash-to-Payables</small>
              <strong>N/A</strong>
          </div>
          <div class="sl-health-item">
              <small>Solvency Score</small>
              <strong style="font-size:11px; color:#64748b; font-weight:normal; display:block; line-height:1.2; margin-top:2px;">Not Available<br/>(Balance Sheet Req.)</strong>
          </div>
      </div>
  </div>
  ```
  ```html
  <div class="sl-card" data-category="overview,liquidity">
      <div class="sl-kpi-title">Cash Runway</div>
      <div class="sl-kpi-value" style="font-size: 15px; color: #64748b; margin-top: 4px;">Pending Reconc.</div>
      <div class="sl-kpi-trend" style="color: #94a3b8;">
          <span>● Requires GL Cash Feed</span>
      </div>
  </div>
  ```

---

### Defect 4: Fabricated Monthly Income Multiplier Claimed as "Monthly Live"
* **Affected Area:** Audit 5 — Income vs Expenses Monthly Chart
* **Root Cause:** Income values computed as a synthetic client-side multiplier `incData = expData * 1.45 + 1.2` while the chart tag claimed `FY 2026-27 Monthly Live`.
* **Audit Acceptance Standard:** If data is demonstrative or model-based, label it accurately. Do not label it live transaction data.
* **Before Code:**
  ```html
  <h3 class="sl-chart-title">Income vs Expenses Analysis</h3>
  <span class="sl-chart-tag">FY 2026-27 Monthly Live</span>
  ```
* **After Code:**
  ```html
  <h3 class="sl-chart-title">Income vs Expenses Analysis</h3>
  <span class="sl-chart-tag" style="background: #f1f5f9; color: #475569;">Pro Forma Model / Projection</span>
  ```

---

### Defect 5: Internal Payment Vouchers Mislabeled as Live Bank Statement
* **Affected Area:** Audit 6 — Live Bank Statement / Disbursements
* **Root Cause:** Internal Accounts Payable disbursement vouchers from `KF_PAYMENTS` were displayed under the header "Live Bank Statement" with tag "Live Disbursements", with synthetic fallbacks when empty.
* **Audit Acceptance Standard:** Do not describe internal vendor payment records as a live bank statement unless matched to a bank source; label as demonstration/unreconciled data.
* **Before Code:**
  ```html
  <div class="sl-chart-card" id="cardBankStmt" data-category="overview,liquidity,efficiency">
      <div class="sl-chart-header">
          <h3 class="sl-chart-title">Live Bank Statement</h3>
          <span class="sl-chart-tag" style="background: #dcfce7; color: #15803d; font-weight: 700;">● Live Disbursements</span>
      </div>
  ```
* **After Code:**
  ```html
  <div class="sl-chart-card" id="cardBankStmt" data-category="overview,liquidity,efficiency">
      <div class="sl-chart-header">
          <h3 class="sl-chart-title">Bank Disbursements (AP Subledger)</h3>
          <span class="sl-chart-tag" style="background: #fef3c7; color: #92400e; font-weight: 700; border: 1px solid #fde68a;">Demonstration Data — Unreconciled</span>
      </div>
  ```

---

### Summary of Preserved Components
* **Total Payables:** Fully preserved and validated against live table `KF_INVOICES` and `KF_PAYMENTS` via `KF_VW_INVOICE_BALANCES`.
* **GST Input/Tax Amount:** Fully preserved from live invoice `TAX_AMOUNT` column (`KF_INVOICES`).
* **Net Profit Margin & Tax Liability:** Preserved within statutory reporting layout.
* **Universal Theme Layout & Tab Engine:** Preserved with zero console errors.
