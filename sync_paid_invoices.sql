-- =========================================================================
-- ONE-TIME SYNC: POPULATE KF_PAYMENTS FOR ALREADY-PAID INVOICES
-- =========================================================================
-- Run this in Oracle APEX -> SQL Workshop -> SQL Commands
-- This ensures that invoices already marked 'PAID' on Page 10 have 
-- matching records in the KF_PAYMENTS subledger table.
-- =========================================================================

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
    SYSDATE,
    i.TOTAL_AMOUNT,
    'BANK_TRANSFER',
    'PAY-' || SUBSTR(i.INVOICE_NUMBER, 1, 40),
    'COMPLETED',
    USER
FROM KF_INVOICES i
WHERE UPPER(NVL(i.STATUS, 'DRAFT')) = 'PAID'
  AND NOT EXISTS (
      SELECT 1 FROM KF_PAYMENTS p WHERE p.INVOICE_ID = i.INVOICE_ID
  );

COMMIT;

-- Verify results
SELECT p.PAYMENT_ID, p.INVOICE_ID, i.INVOICE_NUMBER, p.PAYMENT_AMOUNT, p.STATUS
FROM KF_PAYMENTS p
JOIN KF_INVOICES i ON p.INVOICE_ID = i.INVOICE_ID
ORDER BY p.PAYMENT_ID DESC;
