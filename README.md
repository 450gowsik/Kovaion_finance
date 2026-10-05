# Kovaion Finance

Kovaion Finance is an enterprise-grade financial operations and multi-currency accounting platform built within Oracle APEX. It is designed to streamline financial workflows across international business units (UK, India, and USA), combining robust ledger management with advanced spreadsheet integration and interactive data visualization.

---

## 🌟 Key Capabilities

* **Universal File Import Engine (`KF_PKG_INVOICE_IMPORT`):**
  * Auto-detects columns and parses both standard **7-column CSVs** and detailed **26-column Excel Tracker** files.
  * Automatic data sanitization (stripping currency symbols `₹`, `$`, formatting commas, and whitespace).
  * Auto-wipes previous staging data on each new upload to prevent duplication.
  * Resilient error capturing via `KF_IMPORT_ERRORS`.

* **Executive Dashboard (Page 1):**
  * Live KPI metric cards: Total Invoices, Total Invoiced Value, GST Collected, Total Paid, and Outstanding Balance.
  * Interactive tabbed interface (Overview, Vendor Analysis, Cashflow Trends, Recent Invoices).
  * Real-time CSS/HTML5 spend progress bars and status distributions.

* **Invoicing & Operations (Pages 10, 11, 12):**
  * Interactive Grid for searching, filtering, and exporting invoices.
  * Dedicated modal forms for manual entries and edits.
  * Drag-and-drop file upload interface.

* **Financial Reports & Analytics (Page 40):**
  * Real-time views for Invoice Balances, Aging, TDS deductions by section, and monthly cash flow.

* **Payment & Cashflow Management (Pages 50, 51):**
  * Comprehensive disbursement register with transaction reference tracking and payment mode logging (Bank Transfer, Cheque, NEFT).

---

## 📁 Repository Structure

```text
├── Kovaion_Finance_APEX_APP47919.zip  # Official APEX Application Export (App ID: 47919)
├── application.apx                    # APEX application definition
├── page-groups.apx                    # APEX page groups configuration
├── pages/                             # APEX page definitions (Pages 1, 10, 11, 12, 40, 50, 51, 9999)
├── shared-components/                 # Universal Theme assets, LOVs, lists, and auth schemes
├── .apex/                             # APEX language configuration
├── master_schema.sql                  # Core database tables, constraints & audit logs
├── kf_schema_phase4.sql               # Analytical database views & business logic
├── step1_package_spec.sql             # Import package specification
├── step2_final_fix.sql                # Universal import package body (CSV & Excel)
├── populate_payments.sql              # Synchronizes invoice payments into KF_PAYMENTS
├── update_page1_dashboard.sql         # Dynamic Executive Dashboard PL/SQL
├── update_page40_reports.sql          # Dynamic Reports PL/SQL
└── update_page50_payments.sql         # Dynamic Payments PL/SQL
```

---

## 🚀 Deployment Guide

### 1. Database Setup (Execute in Oracle SQL Workshop or SQL Developer)

Run the scripts in the following order:

1. **`master_schema.sql`** — Creates all underlying tables (`KF_VENDORS`, `KF_INVOICES`, `KF_PAYMENTS`, `KF_CASHFLOW_LEDGER`, etc.).
2. **`kf_schema_phase4.sql`** — Creates analytical views (`KF_VW_INVOICE_SUMMARY`, `KF_VW_INVOICE_BALANCES`, `KF_VW_PAYMENT_SUMMARY`, etc.).
3. **`step1_package_spec.sql`** — Compiles the `KF_PKG_INVOICE_IMPORT` package specification.
4. **`step2_final_fix.sql`** — Compiles the universal package body.
5. **`populate_payments.sql`** *(Optional)* — Populates initial payment records for any existing paid invoices.

### 2. Import APEX Application

1. Log into your Oracle APEX Workspace (e.g., `WKSP_GOWSIK`).
2. Navigate to **App Builder** > **Import**.
3. Select `Kovaion_Finance_APEX_APP47919.zip`.
4. Follow the import wizard prompts and assign an available Application ID.
5. If updating existing pages directly, execute `update_page1_dashboard.sql`, `update_page40_reports.sql`, and `update_page50_payments.sql` in SQL Commands.

---

## 🛡️ License

Internal enterprise financial software developed for Kovaion. All rights reserved.
