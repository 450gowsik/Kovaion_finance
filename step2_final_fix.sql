CREATE OR REPLACE PACKAGE BODY KF_PKG_INVOICE_IMPORT AS

    FUNCTION safe_parse_date(p_date_str IN VARCHAR2) RETURN DATE IS
        l_str VARCHAR2(100);
    BEGIN
        IF p_date_str IS NULL THEN
            RETURN NULL;
        END IF;

        l_str := TRIM(p_date_str);

        BEGIN
            RETURN TO_DATE(l_str, 'DD-MON-YYYY');
        EXCEPTION WHEN OTHERS THEN NULL; END;

        BEGIN
            RETURN TO_DATE(l_str, 'YYYY-MM-DD');
        EXCEPTION WHEN OTHERS THEN NULL; END;

        BEGIN
            RETURN TO_DATE(l_str, 'DD/MM/YYYY');
        EXCEPTION WHEN OTHERS THEN NULL; END;

        BEGIN
            RETURN TO_DATE(l_str, 'MM/DD/YYYY');
        EXCEPTION WHEN OTHERS THEN NULL; END;

        BEGIN
            RETURN TO_DATE(l_str, 'DD-MM-YYYY');
        EXCEPTION WHEN OTHERS THEN NULL; END;

        BEGIN
            RETURN TO_DATE(l_str, 'DD-Mon-YY');
        EXCEPTION WHEN OTHERS THEN NULL; END;

        -- Excel Serial Date (e.g., 45321)
        BEGIN
            IF REGEXP_LIKE(l_str, '^[0-9]{4,6}$') THEN
                RETURN TO_DATE('01-JAN-1900', 'DD-MON-YYYY') + (TO_NUMBER(l_str) - 2);
            END IF;
        EXCEPTION WHEN OTHERS THEN NULL; END;

        RETURN NULL;
    END safe_parse_date;

    FUNCTION safe_parse_number(p_num_str IN VARCHAR2) RETURN NUMBER IS
        l_cleaned VARCHAR2(100);
    BEGIN
        IF p_num_str IS NULL THEN
            RETURN 0;
        END IF;
        l_cleaned := REGEXP_REPLACE(p_num_str, '[^0-9.-]', '');
        IF l_cleaned IS NULL OR l_cleaned = '-' OR l_cleaned = '.' THEN
            RETURN 0;
        END IF;
        RETURN TO_NUMBER(l_cleaned);
    EXCEPTION
        WHEN OTHERS THEN
            RETURN 0;
    END safe_parse_number;

    PROCEDURE PARSE_AND_PREVIEW(
        p_file_name      IN  VARCHAR2,
        p_total_rows     OUT NUMBER,
        p_valid_rows     OUT NUMBER,
        p_invalid_rows   OUT NUMBER,
        p_duplicate_rows OUT NUMBER,
        p_file_size_kb   OUT NUMBER
    ) IS
        l_blob        BLOB;
        l_mime_type   VARCHAR2(255);
        
        l_total       NUMBER := 0;
        l_valid       NUMBER := 0;
        l_invalid     NUMBER := 0;
        l_duplicates  NUMBER := 0;
        
        l_status_flag VARCHAR2(20);
        l_err_msg     VARCHAR2(4000);
        
        l_vendor_id   NUMBER;
        l_vendor_stat VARCHAR2(50);
        
        l_inv_num     VARCHAR2(100);
        l_vendor_raw  VARCHAR2(255);
        l_vname       VARCHAR2(255);
        l_vcode       VARCHAR2(50);
        l_inv_date    DATE;
        l_due_date    DATE;
        
        l_subtotal    NUMBER;
        l_tax         NUMBER;
        l_total_amt   NUMBER;
        l_clean_status VARCHAR2(50);
        l_status_raw  VARCHAR2(50);
        
        C_COLLECTION_NAME CONSTANT VARCHAR2(50) := 'KF_IMPORT_PREVIEW';
    BEGIN
        BEGIN
            SELECT blob_content, mime_type, ROUND(DBMS_LOB.GETLENGTH(blob_content) / 1024, 1)
            INTO l_blob, l_mime_type, p_file_size_kb
            FROM apex_application_temp_files
            WHERE name = p_file_name;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20001, 'Uploaded file not found in APEX temp storage: ' || p_file_name);
        END;

        IF apex_collection.collection_exists(C_COLLECTION_NAME) THEN
            apex_collection.delete_collection(C_COLLECTION_NAME);
        END IF;
        apex_collection.create_collection(C_COLLECTION_NAME);

        FOR rec IN (
            SELECT line_number,
                   TRIM(col001) AS c1,
                   TRIM(col002) AS c2,
                   TRIM(col003) AS c3,
                   TRIM(col004) AS c4,
                   TRIM(col005) AS c5,
                   TRIM(col006) AS c6,
                   TRIM(col007) AS c7,
                   TRIM(col008) AS c8,
                   TRIM(col009) AS c9,
                   TRIM(col010) AS c10,
                   TRIM(col011) AS c11,
                   TRIM(col012) AS c12,
                   TRIM(col013) AS c13,
                   TRIM(col014) AS c14,
                   TRIM(col015) AS c15,
                   TRIM(col016) AS c16,
                   TRIM(col017) AS c17,
                   TRIM(col018) AS c18,
                   TRIM(col019) AS c19,
                   TRIM(col020) AS c20,
                   TRIM(col021) AS c21,
                   TRIM(col022) AS c22
            FROM TABLE(
                apex_data_parser.parse(
                    p_content   => l_blob,
                    p_file_name => p_file_name,
                    p_skip_rows => 1
                )
            )
        ) LOOP
            -- Determine if this row has content
            IF rec.c1 IS NOT NULL OR rec.c2 IS NOT NULL OR rec.c4 IS NOT NULL THEN
                l_status_flag := 'VALID';
                l_err_msg := NULL;
                l_vendor_id := NULL;

                -- Skip header duplicates or empty invoice numbers
                IF rec.c1 = 'Invoice No.' OR rec.c1 = 'Invoice Number' OR rec.c1 = '-' OR rec.c1 = '0' THEN
                    CONTINUE;
                END IF;

                -- AUTO-DETECT FORMAT:
                -- Check if it's the 26-column Excel Tracker (c10, c14, c18, or c22 has data)
                IF rec.c10 IS NOT NULL OR rec.c14 IS NOT NULL OR rec.c18 IS NOT NULL OR rec.c22 IS NOT NULL THEN
                    -- Format A: 26-Column Excel Tracker
                    l_inv_num    := rec.c1;
                    l_vendor_raw := rec.c4;
                    l_inv_date   := safe_parse_date(rec.c2);
                    l_due_date   := safe_parse_date(rec.c2);
                    l_subtotal   := safe_parse_number(rec.c10);
                    l_tax        := safe_parse_number(rec.c11) + safe_parse_number(rec.c12) + safe_parse_number(rec.c13);
                    l_total_amt  := safe_parse_number(rec.c14);
                    
                    IF l_total_amt <= 0 THEN
                        l_total_amt := safe_parse_number(rec.c18);
                    END IF;
                    IF l_total_amt <= 0 THEN
                        l_total_amt := l_subtotal + l_tax;
                    END IF;
                    IF l_total_amt <= 0 AND safe_parse_number(rec.c22) > 0 THEN
                        l_total_amt := safe_parse_number(rec.c22);
                    END IF;
                    
                    l_status_raw := rec.c21;
                ELSE
                    -- Format B: 7-Column CSV (Invoice No, Vendor, Inv Date, Due Date, Subtotal, Tax, Status)
                    l_inv_num    := rec.c1;
                    l_vendor_raw := rec.c2;
                    l_inv_date   := safe_parse_date(rec.c3);
                    l_due_date   := safe_parse_date(rec.c4);
                    l_subtotal   := safe_parse_number(rec.c5);
                    l_tax        := safe_parse_number(rec.c6);
                    l_total_amt  := l_subtotal + l_tax;
                    l_status_raw := rec.c7;
                END IF;

                -- Validate Invoice Number
                IF l_inv_num IS NULL THEN
                    l_status_flag := 'ERROR';
                    l_err_msg := 'Invoice Number is required. ';
                END IF;

                -- Validate / Auto-create Vendor
                IF l_vendor_raw IS NULL THEN
                    l_status_flag := 'ERROR';
                    l_err_msg := l_err_msg || 'Vendor Name is required. ';
                ELSE
                    -- Extract vendor name and code if format is "Name / Code"
                    IF INSTR(l_vendor_raw, '/') > 0 THEN
                        l_vname := TRIM(SUBSTR(l_vendor_raw, 1, INSTR(l_vendor_raw, '/') - 1));
                        l_vcode := TRIM(SUBSTR(l_vendor_raw, INSTR(l_vendor_raw, '/') + 1));
                    ELSE
                        l_vname := TRIM(l_vendor_raw);
                        l_vcode := SUBSTR(REGEXP_REPLACE(UPPER(l_vname), '[^A-Z0-9]', ''), 1, 8);
                    END IF;

                    IF l_vcode IS NULL OR LENGTH(l_vcode) = 0 THEN
                        l_vcode := 'VND';
                    END IF;

                    BEGIN
                        SELECT VENDOR_ID, STATUS
                        INTO l_vendor_id, l_vendor_stat
                        FROM KF_VENDORS
                        WHERE UPPER(TRIM(VENDOR_NAME)) = UPPER(TRIM(l_vname))
                           OR UPPER(TRIM(VENDOR_CODE)) = UPPER(TRIM(l_vcode))
                           OR UPPER(TRIM(VENDOR_NAME)) = UPPER(TRIM(l_vendor_raw))
                           OR UPPER(TRIM(VENDOR_CODE)) = UPPER(TRIM(l_vendor_raw))
                        FETCH FIRST 1 ROWS ONLY;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            DECLARE
                                l_cand_code VARCHAR2(50) := l_vcode;
                                l_exists    NUMBER;
                                l_suf       NUMBER := 1;
                            BEGIN
                                LOOP
                                    SELECT COUNT(*) INTO l_exists
                                    FROM KF_VENDORS
                                    WHERE UPPER(VENDOR_CODE) = UPPER(l_cand_code);
                                    
                                    IF l_exists = 0 THEN
                                        EXIT;
                                    ELSE
                                        l_cand_code := SUBSTR(l_vcode, 1, 6) || '_' || l_suf;
                                        l_suf := l_suf + 1;
                                    END IF;
                                END LOOP;

                                INSERT INTO KF_VENDORS (VENDOR_NAME, VENDOR_CODE, STATUS, CREATED_BY)
                                VALUES (l_vname, l_cand_code, 'ACTIVE', 'SYSTEM_IMPORT')
                                RETURNING VENDOR_ID INTO l_vendor_id;
                                l_vendor_stat := 'ACTIVE';
                            EXCEPTION
                                WHEN OTHERS THEN
                                    BEGIN
                                        SELECT VENDOR_ID INTO l_vendor_id
                                        FROM KF_VENDORS
                                        WHERE UPPER(TRIM(VENDOR_NAME)) = UPPER(TRIM(l_vname))
                                        FETCH FIRST 1 ROWS ONLY;
                                    EXCEPTION
                                        WHEN OTHERS THEN
                                            l_cand_code := 'V_' || TO_CHAR(SYSTIMESTAMP, 'HH24MISSFF2');
                                            INSERT INTO KF_VENDORS (VENDOR_NAME, VENDOR_CODE, STATUS, CREATED_BY)
                                            VALUES (l_vname, l_cand_code, 'ACTIVE', 'SYSTEM_IMPORT')
                                            RETURNING VENDOR_ID INTO l_vendor_id;
                                    END;
                            END;
                    END;
                END IF;

                -- Fallback Dates
                IF l_inv_date IS NULL THEN
                    l_inv_date := SYSDATE;
                END IF;
                IF l_due_date IS NULL THEN
                    l_due_date := l_inv_date + 30;
                END IF;
                IF l_due_date < l_inv_date THEN
                    l_due_date := l_inv_date;
                END IF;

                -- Map Status cleanly to database check constraint
                CASE UPPER(TRIM(l_status_raw))
                    WHEN 'PAID' THEN l_clean_status := 'PAID';
                    WHEN 'OVERDUE' THEN l_clean_status := 'OVERDUE';
                    WHEN 'DRAFT' THEN l_clean_status := 'DRAFT';
                    WHEN 'PARTIALLY_PAID' THEN l_clean_status := 'PARTIALLY_PAID';
                    WHEN 'PARTIALLY PAID' THEN l_clean_status := 'PARTIALLY_PAID';
                    WHEN 'APPROVED' THEN l_clean_status := 'APPROVED';
                    WHEN 'REJECTED' THEN l_clean_status := 'REJECTED';
                    WHEN 'CANCELLED' THEN l_clean_status := 'CANCELLED';
                    WHEN 'PENDING' THEN l_clean_status := 'PENDING_APPROVAL';
                    WHEN 'PENDING_APPROVAL' THEN l_clean_status := 'PENDING_APPROVAL';
                    ELSE
                        IF l_due_date < TRUNC(SYSDATE) AND l_total_amt > 0 THEN
                            l_clean_status := 'OVERDUE';
                        ELSE
                            l_clean_status := 'PENDING_APPROVAL';
                        END IF;
                END CASE;

                -- Ensure subtotal consistency
                IF l_subtotal <= 0 AND l_total_amt > 0 THEN
                    l_subtotal := ROUND(l_total_amt / 1.18, 2);
                    l_tax      := l_total_amt - l_subtotal;
                END IF;

                l_total := l_total + 1;
                IF l_status_flag = 'VALID' THEN
                    l_valid := l_valid + 1;
                ELSE
                    l_invalid := l_invalid + 1;
                END IF;

                apex_collection.add_member(
                    p_collection_name => C_COLLECTION_NAME,
                    p_c001 => l_inv_num,
                    p_c002 => l_vname,
                    p_c003 => TO_CHAR(l_inv_date, 'YYYY-MM-DD'),
                    p_c004 => TO_CHAR(l_due_date, 'YYYY-MM-DD'),
                    p_c005 => TO_CHAR(l_subtotal, '999999990.00'),
                    p_c006 => TO_CHAR(l_tax, '999999990.00'),
                    p_c007 => l_clean_status,
                    p_c008 => l_status_flag,
                    p_c009 => RTRIM(l_err_msg),
                    p_n001 => l_vendor_id,
                    p_n002 => l_total_amt,
                    p_n003 => rec.line_number,
                    p_n004 => l_subtotal,
                    p_n005 => l_tax
                );
            END IF;
        END LOOP;

        p_total_rows     := l_total;
        p_valid_rows     := l_valid;
        p_invalid_rows   := l_invalid;
        p_duplicate_rows := 0;
    END PARSE_AND_PREVIEW;


    PROCEDURE CONFIRM_IMPORT(
        p_file_name     IN  VARCHAR2,
        p_user_name     IN  VARCHAR2,
        p_batch_id      OUT NUMBER,
        p_success_count OUT NUMBER,
        p_failed_count  OUT NUMBER,
        p_status_msg    OUT VARCHAR2
    ) IS
        l_batch_id    NUMBER;
        l_success     NUMBER := 0;
        l_failed      NUMBER := 0;
        l_total       NUMBER := 0;
        l_new_inv_id  NUMBER;
        l_fy_id       NUMBER;
        l_user        VARCHAR2(100) := NVL(p_user_name, 'APEX_USER');
        l_sql_err     VARCHAR2(1000);
        l_clean_filename VARCHAR2(255);
        l_file_type   VARCHAR2(50);

        l_row_num     NUMBER;
        l_inv_num     VARCHAR2(100);
        l_vendor_id   NUMBER;
        l_inv_date    DATE;
        l_due_date    DATE;
        l_subtotal    NUMBER;
        l_tax         NUMBER;
        l_total_amt   NUMBER;
        l_status_val  VARCHAR2(50);
        l_status_flag VARCHAR2(20);
        l_err_msg     VARCHAR2(1000);
        l_tax_rate    NUMBER;
        C_COLLECTION_NAME CONSTANT VARCHAR2(50) := 'KF_IMPORT_PREVIEW';
    BEGIN
        IF NOT apex_collection.collection_exists(C_COLLECTION_NAME) THEN
            DECLARE
                l_p_tot NUMBER;
                l_p_val NUMBER;
                l_p_inv NUMBER;
                l_p_dup NUMBER;
                l_p_sz  NUMBER;
            BEGIN
                PARSE_AND_PREVIEW(
                    p_file_name      => p_file_name,
                    p_total_rows     => l_p_tot,
                    p_valid_rows     => l_p_val,
                    p_invalid_rows   => l_p_inv,
                    p_duplicate_rows => l_p_dup,
                    p_file_size_kb   => l_p_sz
                );
            EXCEPTION
                WHEN OTHERS THEN
                    RAISE_APPLICATION_ERROR(-20002, 'No preview data available to import. Please upload a file first.');
            END;
        END IF;

        l_clean_filename := p_file_name;
        IF l_clean_filename IS NULL THEN
            BEGIN
                SELECT filename INTO l_clean_filename
                FROM apex_application_temp_files
                ORDER BY created_on DESC
                FETCH FIRST 1 ROWS ONLY;
            EXCEPTION
                WHEN OTHERS THEN
                    l_clean_filename := 'Import_Invoices.xlsx';
            END;
        END IF;

        IF LOWER(l_clean_filename) LIKE '%.csv' THEN
            l_file_type := 'CSV';
        ELSE
            l_file_type := 'EXCEL';
        END IF;

        -- 1. Create entry in KF_IMPORT_BATCHES
        INSERT INTO KF_IMPORT_BATCHES (
            FILE_NAME,
            FILE_TYPE,
            PROCESSING_STATUS,
            TOTAL_ROWS,
            SUCCESS_ROWS,
            FAILED_ROWS,
            UPLOADED_BY,
            UPLOADED_DATE
        ) VALUES (
            l_clean_filename,
            l_file_type,
            'PROCESSING',
            0,
            0,
            0,
            l_user,
            SYSTIMESTAMP
        ) RETURNING BATCH_ID INTO l_batch_id;

        p_batch_id := l_batch_id;

        -- 2. AUTOMATIC WIPE: Clear old data so the freshly uploaded file completely replaces it!
        -- The user never needs to run manual DELETE commands in SQL Commands!
        DELETE FROM KF_PAYMENTS;
        DELETE FROM KF_INVOICE_LINES;
        DELETE FROM KF_INVOICES;

        -- 3. Process rows from preview collection
        FOR r IN (
            SELECT seq_id,
                   c001 AS inv_number,
                   c002 AS vendor_ref,
                   TO_DATE(c003, 'YYYY-MM-DD') AS inv_date,
                   TO_DATE(c004, 'YYYY-MM-DD') AS due_date,
                   NVL(n004, safe_parse_number(c005)) AS subtotal,
                   NVL(n005, safe_parse_number(c006)) AS tax,
                   c007 AS status_val,
                   c008 AS status_flag,
                   c009 AS err_msg,
                   n001 AS vendor_id,
                   NVL(n002, 0) AS total_amt,
                   n003 AS file_line_num
            FROM apex_collections
            WHERE collection_name = C_COLLECTION_NAME
            ORDER BY seq_id
        ) LOOP
            l_total := l_total + 1;

            l_row_num     := NVL(r.file_line_num, r.seq_id);
            l_inv_num     := r.inv_number;
            l_vendor_id   := r.vendor_id;
            l_inv_date    := r.inv_date;
            l_due_date    := r.due_date;
            l_subtotal    := r.subtotal;
            l_tax         := r.tax;
            l_total_amt   := r.total_amt;
            l_status_val  := r.status_val;
            l_status_flag := r.status_flag;
            l_err_msg     := SUBSTR(r.err_msg, 1, 1000);

            IF l_status_flag = 'VALID' AND l_vendor_id IS NOT NULL THEN
                BEGIN
                    -- Determine Fiscal Year
                    BEGIN
                        SELECT FISCAL_YEAR_ID INTO l_fy_id
                        FROM KF_FISCAL_YEARS
                        WHERE l_inv_date BETWEEN START_DATE AND END_DATE
                          AND ROWNUM = 1;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            SELECT FISCAL_YEAR_ID INTO l_fy_id
                            FROM KF_FISCAL_YEARS
                            WHERE STATUS = 'ACTIVE' AND ROWNUM = 1;
                    END;

                    IF l_subtotal > 0 THEN
                        l_tax_rate := ROUND((l_tax / l_subtotal) * 100, 2);
                    ELSE
                        l_tax_rate := 0;
                    END IF;

                    -- Insert Fresh Invoice
                    INSERT INTO KF_INVOICES (
                        INVOICE_NUMBER,
                        VENDOR_ID,
                        FISCAL_YEAR_ID,
                        INVOICE_DATE,
                        DUE_DATE,
                        CURRENCY,
                        SUBTOTAL,
                        TAX_AMOUNT,
                        TDS_AMOUNT,
                        TOTAL_AMOUNT,
                        STATUS,
                        SOURCE_TYPE,
                        CREATED_BY,
                        CREATED_DATE
                    ) VALUES (
                        l_inv_num,
                        l_vendor_id,
                        l_fy_id,
                        l_inv_date,
                        l_due_date,
                        'INR',
                        l_subtotal,
                        l_tax,
                        0,
                        l_total_amt,
                        l_status_val,
                        'IMPORT',
                        l_user,
                        SYSTIMESTAMP
                    ) RETURNING INVOICE_ID INTO l_new_inv_id;

                    -- Insert Line Item
                    INSERT INTO KF_INVOICE_LINES (
                        INVOICE_ID,
                        LINE_NUMBER,
                        DESCRIPTION,
                        QUANTITY,
                        UNIT_PRICE,
                        TAX_RATE,
                        TAX_AMOUNT,
                        LINE_TOTAL
                    ) VALUES (
                        l_new_inv_id,
                        1,
                        'Imported Item - ' || l_inv_num,
                        1,
                        GREATEST(0, l_subtotal),
                        GREATEST(0, l_tax_rate),
                        GREATEST(0, l_tax),
                        GREATEST(0, l_total_amt)
                    );

                    -- If status is PAID, insert payment record
                    IF l_status_val = 'PAID' AND l_total_amt > 0 THEN
                        INSERT INTO KF_PAYMENTS (
                            INVOICE_ID,
                            VENDOR_ID,
                            PAYMENT_DATE,
                            PAYMENT_AMOUNT,
                            PAYMENT_METHOD,
                            REFERENCE_NUMBER,
                            STATUS,
                            CREATED_BY
                        ) VALUES (
                            l_new_inv_id,
                            l_vendor_id,
                            NVL(l_due_date, SYSDATE),
                            l_total_amt,
                            'BANK_TRANSFER',
                            'IMPORT-' || SUBSTR(l_inv_num, 1, 40),
                            'COMPLETED',
                            l_user
                        );
                    END IF;

                    l_success := l_success + 1;

                EXCEPTION
                    WHEN OTHERS THEN
                        l_sql_err := SUBSTR(SQLERRM, 1, 950);
                        l_failed := l_failed + 1;

                        BEGIN
                            INSERT INTO KF_IMPORT_ERRORS (
                                BATCH_ID,
                                ROW_NUMBER,
                                COLUMN_NAME,
                                ERROR_MESSAGE,
                                RAW_VALUE
                            ) VALUES (
                                l_batch_id,
                                l_row_num,
                                'INVOICE_NUMBER',
                                'Database error: ' || l_sql_err,
                                'Invoice: ' || l_inv_num || ', Subtotal: ' || l_subtotal || ', Total: ' || l_total_amt
                            );
                        EXCEPTION WHEN OTHERS THEN NULL; END;
                END;
            ELSE
                l_failed := l_failed + 1;
                BEGIN
                    INSERT INTO KF_IMPORT_ERRORS (
                        BATCH_ID,
                        ROW_NUMBER,
                        COLUMN_NAME,
                        ERROR_MESSAGE,
                        RAW_VALUE
                    ) VALUES (
                        l_batch_id,
                        l_row_num,
                        'INVOICE_NUMBER',
                        NVL(l_err_msg, 'Validation failed: Invalid vendor or status'),
                        'Invoice: ' || l_inv_num || ', Subtotal: ' || l_subtotal || ', Total: ' || l_total_amt
                    );
                EXCEPTION WHEN OTHERS THEN NULL; END;
            END IF;
        END LOOP;

        -- 4. Update Batch summary
        UPDATE KF_IMPORT_BATCHES
        SET TOTAL_ROWS = l_total,
            SUCCESS_ROWS = l_success,
            FAILED_ROWS = l_failed,
            PROCESSING_STATUS = CASE 
                WHEN l_failed = 0 THEN 'COMPLETED'
                WHEN l_success = 0 THEN 'FAILED'
                ELSE 'COMPLETED_WITH_ERRORS'
            END,
            COMPLETED_DATE = SYSTIMESTAMP
        WHERE BATCH_ID = l_batch_id;

        COMMIT;

        -- 5. Clean up preview collection and temp file
        apex_collection.delete_collection(C_COLLECTION_NAME);
        IF p_file_name IS NOT NULL THEN
            DELETE FROM apex_application_temp_files WHERE name = p_file_name;
        ELSE
            DELETE FROM apex_application_temp_files;
        END IF;

        p_success_count := l_success;
        p_failed_count  := l_failed;
        p_status_msg    := 'Import completed. Successfully imported: ' || l_success || ' invoices. Errors/Duplicates: ' || l_failed || '.';
    END CONFIRM_IMPORT;

END KF_PKG_INVOICE_IMPORT;
