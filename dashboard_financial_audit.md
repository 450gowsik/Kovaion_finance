# Kovaion Enterprise Suite — Financial Dashboard Verification Audit Report
**Application:** Kovaion Enterprise Suite (APEX Application 47919, Page 1)  
**Auditor:** Senior Oracle APEX Developer & Financial Systems Reconciliation Specialist  
**Audit Standard:** Strict Financial Data Integrity (Read-Only Investigation — Phase A)  
**Execution Environment:** Oracle APEX 26.1 / Oracle Cloud Autonomous Database  

---

## 1. Executive Summary & Audit Constraints

This audit evaluates all seven primary financial reporting components on the Page 1 Financial Overview Dashboard of Kovaion Enterprise Suite against the underlying Oracle database schema, package bodies, views, and transaction ledgers.

### Database Execution Notice (Rule 8 Compliance)
The application schema resides on a remote Oracle Cloud APEX environment (`oracleapex.com/ords/r/gowsik/kovaion-fin`). No direct CLI database connection (`sqlplus`/`sqlcl`) is configured in the local workspace shell. In strict accordance with audit Rule 8, all SQL checks provided in this report are categorized as:
* **Code-Level Audits:** Verified through static analysis of the application PL/SQL dynamic content source (`update_page1_dashboard.sql`), schema DDL (`master_schema.sql`, `kf_schema_phase4.sql`), package bodies (`step2_final_fix.sql`), and APEX page exports (`p00001-home.apx`, `p00040-reports.apx`).
* **Live Database Queries:** Packaged into [`dashboard_reconciliation_queries.sql`](file:///c:/Users/GowsikPrakashbabu/Desktop/Kovaion_Finance/dashboard_reconciliation_queries.sql) for execution in APEX SQL Workshop.

---

## 2. Comprehensive Findings for All Seven Areas

### Audit 1 — Total Bank Balance
* **Current Displayed Value:** ₹1,27,67,680 (or dynamically computed as ₹1,28,37,877).
* **Exact Code Traced:** `update_page1_dashboard.sql` lines 104–115:
  ```sql
  BEGIN
      SELECT NVL(SUM(CURRENT_BALANCE), 12875000)
      INTO l_bank_bal
      FROM KF_BANK_ACCOUNTS;
  EXCEPTION WHEN OTHERS THEN
      l_bank_bal := 12875000;
  END;
  l_bank_bal := GREATEST(1000000, NVL(l_bank_bal, 12875000) - NVL(l_paid_sum, 0));
  ```
* **Provenance Analysis:**
  1. The table `KF_BANK_ACCOUNTS` does not exist in the foundational DDL (`master_schema.sql` or `kf_schema_phase4.sql`). When queried, the code encounters an exception or unverified prototype seed data, silently falling back to a hard-coded baseline of **₹1,28,75,000**.
  2. The application lacks an authoritative general ledger cash account, bank statement feed (MT940/CAMT), or verified opening balance.
  3. The subtracted deduction (`l_paid_sum`) represents internal Accounts Payable status updates, not matched bank disbursements.
* **Audit Determination:** **FAIL**. The numeric balance is derived from a hard-coded fallback minus internal status flags.
* **Required Audit State:** Must display `Unavailable (Reconciliation Required)` with status `Pending Bank Reconciliation` until an authoritative GL feed exists.

---

### Audit 2 — Total Payables
* **Current Displayed Value:** ₹7,52,619 (or ₹7,83,915 in latest import batches).
* **Exact Code Traced:** `update_page1_dashboard.sql` lines 47–61:
  ```sql
  SELECT 
      NVL(SUM(CASE WHEN UPPER(NVL(i.STATUS, 'DRAFT')) NOT IN ('CANCELLED', 'REJECTED', 'PAID') 
                   THEN GREATEST(0, NVL(b.BALANCE_AMOUNT, i.TOTAL_AMOUNT)) ELSE 0 END), 0)
  INTO l_tot_payables
  FROM KF_INVOICES i
  LEFT JOIN KF_VW_INVOICE_BALANCES b ON i.INVOICE_ID = b.INVOICE_ID;
  ```
* **Provenance Analysis:**
  1. Data originates from the physical table `KF_INVOICES` joined to `KF_PAYMENTS` through the view `KF_VW_INVOICE_BALANCES`.
  2. The analytical view computes `BALANCE_AMOUNT = i.TOTAL_AMOUNT - NVL(p.TOTAL_PAID, 0)` from completed payment records in `KF_PAYMENTS`.
  3. The query strictly excludes cancelled, rejected, and paid invoices, correctly evaluating outstanding vendor liabilities.
  4. The definition represents **Total Open Vendor Invoices** (AP Subledger).
* **Audit Determination:** **PASS**. Formula is reproducible, correctly joined to the AP subledger, and verifiable against `KF_INVOICES`.

---

### Audit 3 — Total Receivables
* **Current Displayed Value:** ₹38,50,000.
* **Exact Code Traced:** `update_page1_dashboard.sql` lines 213–219 and `p00001-home.apx` lines 574–580:
  ```html
  <div class="sl-card" data-category="overview,profitability">
      <div class="sl-kpi-title">Total Receivables</div>
      <div class="sl-kpi-value">₹38,50,000</div>
      <div class="sl-kpi-trend sl-trend-down">
          <span>↓ -4.2%</span> <span class="sl-kpi-subtitle">14 client invoices</span>
      </div>
  </div>
  ```
* **Provenance Analysis:**
  1. This value is **100% hard-coded static HTML**.
  2. Inspection of `master_schema.sql` and `kf_schema_phase4.sql` reveals that **no customer invoice table, customer receipt table, or AR ledger exists** in the application.
  3. The schema is exclusively built for Accounts Payable (`KF_VENDORS`, `KF_INVOICES`, `KF_INVOICE_LINES`, `KF_PAYMENTS`).
  4. The view `KF_VW_AR_BALANCES` does not exist in the database or script files.
* **Audit Determination:** **FAIL**. The displayed figure has zero supporting database records.
* **Required Audit State:** Must display `N/A — Verification Required` with subtitle `AR Subledger Not Implemented`.

---

### Audit 4 — Cash Coverage / Liquidity
* **Current Displayed Values:** Score 88 (EXCELLENT), Liquidity Ratio 2.4x (Safe), Solvency Score A+ Grade, Cash Runway 18.4 Mos.
* **Exact Code Traced:** `update_page1_dashboard.sql` lines 233–295:
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
* **Provenance Analysis:**
  1. The gauge score (88), liquidity ratio (2.4x), and solvency grade (A+) are static strings inside SVG and HTML templates.
  2. There is no balance sheet data (Current Assets vs Current Liabilities) to calculate a genuine current ratio or quick ratio.
  3. The cash runway metric is dependent on an unverified bank balance.
* **Audit Determination:** **FAIL**. Unsubstantiated metrics masquerading as audited financial health ratios.
* **Required Audit State:** Display `N/A` for Cash Coverage and Cash Runway, with the explanation `Reconciliation Required`.

---

### Audit 5 — Income vs Expenses Monthly Chart
* **Current Displayed Values:** 12-Month Bar Chart (FY 2026-27 Monthly Live).
* **Exact Code Traced:** `update_page1_dashboard.sql` lines 71–100, 372–374:
  ```sql
  SELECT 
      ROUND(NVL(SUM(CASE WHEN TO_CHAR(INVOICE_DATE, 'MM') = '04' THEN TOTAL_AMOUNT ELSE 0 END), 0) / 100000, 2),
      ...
  INTO l_exp_apr, l_exp_may, ...
  FROM KF_INVOICES;
  IF l_exp_apr = 0 THEN l_exp_apr := 1.20; END IF;
  ```
  And in client-side JavaScript:
  ```javascript
  var expData = [l_exp_apr, l_exp_may, ...];
  var incData = expData.map(function(v) { return Number((v * 1.45 + 1.2).toFixed(2)); });
  ```
* **Provenance Analysis:**
  1. **Expenses:** Aggregates vendor invoice dates on an accrual basis, but injects hard-coded fallback values (1.20L, 1.50L, etc.) for any month without invoices.
  2. **Income:** Fabricated mathematically via `incData = expData * 1.45 + 1.2`. No customer revenue or receipt records exist to support this data.
* **Audit Determination:** **FAIL**. Income is an invented formula and expenses contain hard-coded baseline fills.
* **Required Audit State:** Label clearly as `Pro Forma Model / Projection` rather than claiming "Monthly Live Database".

---

### Audit 6 — Live Bank Statement / Disbursements
* **Current Displayed Values:** Card list displaying 4 recent disbursements and corporate current accounts.
* **Exact Code Traced:** `update_page1_dashboard.sql` lines 118–157, 354–365:
  ```sql
  FOR p IN (
      SELECT p.PAYMENT_DATE, p.PAYMENT_AMOUNT, p.REFERENCE_NUMBER,
             NVL(v.VENDOR_NAME, 'Vendor Disbursement') AS vendor_name
      FROM KF_PAYMENTS p
      LEFT JOIN KF_VENDORS v ON p.VENDOR_ID = v.VENDOR_ID
      ORDER BY p.PAYMENT_DATE DESC, p.PAYMENT_ID DESC
      FETCH FIRST 4 ROWS ONLY
  ) LOOP ...
  ```
* **Provenance Analysis:**
  1. When payment rows exist in `KF_PAYMENTS`, the records display internal vendor payments, **not bank statement lines**.
  2. If `KF_PAYMENTS` is empty, the code falls back to static prototype accounts (HDFC Bank Ltd. and ICICI Bank Ltd. split 65%/35%).
  3. No external bank statement feeds, MT940 files, or reconciliation matches exist.
* **Audit Determination:** **FAIL**. Internal AP payment vouchers are mislabeled as a "Live Bank Statement".
* **Required Audit State:** Re-title region as `AP Payment Disbursements (Unmatched to Bank Statement)` or label fallback accounts as `Demonstration Data — Unreconciled`.

---

### Audit 7 — Receivables Collection Tracker
* **Current Displayed Values:** Aging buckets (0–30, 31–60, 61–90, >90 days).
* **Exact Code Traced:**
  - Page 1 does not currently render a dedicated AR Aging Tracker.
  - Page 40 (`p00040-reports.apx`) displays a hard-coded card: `Aged Receivables (>45 Days) ₹2,10,000`.
  - The view `KF_VW_AR_BALANCES` is completely absent from all database schema scripts.
* **Provenance Analysis:**
  1. The schema contains no customer invoicing tables or customer receipt ledgers.
  2. No SQL logic exists to compute customer aging buckets.
* **Audit Determination:** **INSUFFICIENT EVIDENCE / ABSENT**.
* **Required Audit State:** Fully disclose the absence of an AR subledger; do not fabricate customer aging.

---

## 3. Phase A Verification Matrix

| Area | Component Name | Displayed Value | Audit Finding | Verdict |
| :--- | :--- | :--- | :--- | :--- |
| **1** | Total Bank Balance | ₹1,27,67,680 / Dynamic | Hard-coded fallback (₹1.28Cr) minus AP disbursements; no GL feed. | **FAIL** |
| **2** | Total Payables | ₹7,52,619 / Live | Live join of `KF_INVOICES` and `KF_PAYMENTS` (excl. Paid/Cancelled). | **PASS** |
| **3** | Total Receivables | ₹38,50,000 | Static hardcoded HTML string; no customer tables in schema. | **FAIL** |
| **4** | Cash Coverage / Liquidity | 88 Score / 2.4x Ratio | Static SVG/HTML strings; no balance sheet data or verified cash. | **FAIL** |
| **5** | Income vs Expenses Chart | FY 2026-27 Live Chart | Income fabricated via `* 1.45 + 1.2`; missing months use hard-coded fills. | **FAIL** |
| **6** | Bank Statement / Disbursements | Live Bank Statement | Internal AP payment vouchers mislabeled as imported bank feeds. | **FAIL** |
| **7** | Receivables Collection Tracker | AR Aging Summary | Object `KF_VW_AR_BALANCES` and customer tables do not exist. | **INSUFFICIENT EVIDENCE** |

---

## 4. Phase A Findings Summary

Of the seven audited areas:
* **1 Area Passed:** Total Payables (**PASS**).
* **5 Areas Failed:** Total Bank Balance, Total Receivables, Cash Coverage, Income vs Expenses Chart, Bank Statement (**FAIL**).
* **1 Area Absent:** Receivables Collection Tracker (**INSUFFICIENT EVIDENCE**).

Phase A is complete. All findings have been cataloged prior to making any code modifications.
