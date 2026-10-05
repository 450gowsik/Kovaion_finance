-- ========================================================
-- SYNC PAYMENT FLOW FOR ALL IMPORTED INVOICES
-- Populates KF_PAYMENTS so Reports & Payment Flow show real data
-- ========================================================

INSERT INTO KF_PAYMENTS (
    INVOICE_ID,
    VENDOR_ID,
    PAYMENT_DATE,
    PAYMENT_AMOUNT,
    PAYMENT_METHOD,
    REFERENCE_NUMBER,
    STATUS,
    CREATED_BY
)
SELECT 
    i.INVOICE_ID,
    i.VENDOR_ID,
    NVL(i.DUE_DATE, i.INVOICE_DATE),
    GREATEST(0.01, i.TOTAL_AMOUNT),
    'BANK_TRANSFER',
    'PAY-' || SUBSTR(i.INVOICE_NUMBER, 1, 40),
    'COMPLETED',
    'SYSTEM_IMPORT'
FROM KF_INVOICES i
WHERE i.STATUS = 'PAID'
  AND i.TOTAL_AMOUNT > 0
  AND NOT EXISTS (
      SELECT 1 FROM KF_PAYMENTS p WHERE p.INVOICE_ID = i.INVOICE_ID
  );

COMMIT;
