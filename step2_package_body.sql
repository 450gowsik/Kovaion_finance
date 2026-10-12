CREATE OR REPLACE PACKAGE BODY KF_PKG_INVOICE_IMPORT AS

    FUNCTION safe_parse_date(p_date_str IN VARCHAR2) RETURN DATE IS
        l_str VARCHAR2(100);
    BEGIN
        IF p_date_str IS NULL THEN
            RETURN NULL;
        END IF;

        l_str := TRIM(p_date_str);

        -- Standard APEX/Oracle format DD-MON-YYYY or DD-Mon-YY
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
        -- Strip currency symbols, commas, spaces, currency codes
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
        l_dup_count   NUMBER;
        
        l_inv_date    DATE;
        l_due_date    DATE;
        
        l_subtotal    NUMBER;
        l_tax         NUMBER;
        l_total_amt   NUMBER;
        l_clean_status VARCHAR2(50);
        
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
                   TRIM(col001) AS inv_number,
                   TRIM(col004) AS vendor_ref,
                   TRIM(col002) AS inv_date_str,
                   TRIM(col002) AS due_date_str,
                   TRIM(col007) AS subtotal_str,
                   TRIM(col008) AS tax_cgst_str,
                   TRIM(col009) AS tax_sgst_str,
                   TRIM(col010) AS inv_val_str,
                   TRIM(col012) AS paid_str
            FROM TABLE(
                apex_data_parser.parse(
                    p_content   => l_blob,
                    p_file_name => p_file_name,
                    p_skip_rows => 1
                )
            )
        ) LOOP
            IF rec.inv_number IS NOT NULL OR rec.vendor_ref IS NOT NULL THEN
                l_total := l_total + 1;
                l_status_flag := 'VALID';
                l_err_msg := NULL;
                l_vendor_id := NULL;

                IF rec.inv_number = '-' OR rec.inv_number = '0' THEN
                    CONTINUE;
                END IF;

                IF rec.inv_number IS NULL THEN
                    l_status_flag := 'ERROR';
                    l_err_msg := 'Invoice Number is required. ';
                END IF;

                IF rec.vendor_ref IS NULL THEN
                    l_status_flag := 'ERROR';
                    l_err_msg := l_err_msg || 'Vendor Name/Code is required. ';
                ELSE
                    BEGIN
                        SELECT VENDOR_ID, STATUS
                        INTO l_vendor_id, l_vendor_stat
                        FROM KF_VENDORS
                        WHERE (UPPER(TRIM(VENDOR_NAME)) = UPPER(TRIM(rec.vendor_ref))
                            OR UPPER(TRIM(VENDOR_CODE)) = UPPER(TRIM(rec.vendor_ref)))
                          AND ROWNUM = 1;

                        IF l_vendor_stat != 'ACTIVE' THEN
                            l_status_flag := 'ERROR';
                            l_err_msg := l_err_msg || 'Vendor is not ACTIVE (' || l_vendor_stat || '). ';
                        END IF;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            DECLARE
                                l_base_code      VARCHAR2(30);
                                l_cand_code      VARCHAR2(50);
                                l_exists         NUMBER;
                                l_suf            NUMBER := 1;
                            BEGIN
                                l_base_code := SUBSTR(REGEXP_REPLACE(UPPER(TRIM(rec.vendor_ref)), '[^A-Z0-9]', ''), 1, 8);
                                IF l_base_code IS NULL OR LENGTH(l_base_code) = 0 THEN
                                    l_base_code := 'VND';
                                END IF;
                                
                                l_cand_code := l_base_code;
                                
                                LOOP
                                    SELECT COUNT(*) INTO l_exists
                                    FROM KF_VENDORS
                                    WHERE UPPER(VENDOR_CODE) = UPPER(l_cand_code);
                                    
                                    IF l_exists = 0 THEN
                                        EXIT;
                                    ELSE
                                        l_cand_code := SUBSTR(l_base_code, 1, 6) || '_' || l_suf;
                                        l_suf := l_suf + 1;
                                    END IF;
                                END LOOP;

                                INSERT INTO KF_VENDORS (VENDOR_NAME, VENDOR_CODE, STATUS, CREATED_BY)
                                VALUES (TRIM(rec.vendor_ref), l_cand_code, 'ACTIVE', 'SYSTEM_IMPORT')
                                RETURNING VENDOR_ID INTO l_vendor_id;
                                l_vendor_stat := 'ACTIVE';
                            EXCEPTION
                                WHEN DUP_VAL_ON_INDEX THEN
                                    BEGIN
                                        SELECT VENDOR_ID, STATUS INTO l_vendor_id, l_vendor_stat
                                        FROM KF_VENDORS
                                        WHERE UPPER(TRIM(VENDOR_NAME)) = UPPER(TRIM(rec.vendor_ref))
                                           OR UPPER(TRIM(VENDOR_CODE)) = UPPER(TRIM(rec.vendor_ref))
                                           OR UPPER(VENDOR_CODE) = UPPER(l_cand_code)
                                        FETCH FIRST 1 ROWS ONLY;
                                    EXCEPTION
                                        WHEN OTHERS THEN
                                            l_cand_code := 'V_' || TO_CHAR(SYSTIMESTAMP, 'HH24MISSFF2');
                                            INSERT INTO KF_VENDORS (VENDOR_NAME, VENDOR_CODE, STATUS, CREATED_BY)
                                            VALUES (TRIM(rec.vendor_ref), l_cand_code, 'ACTIVE', 'SYSTEM_IMPORT')
                                            RETURNING VENDOR_ID INTO l_vendor_id;
                                            l_vendor_stat := 'ACTIVE';
                                    END;
                            END;
                    END;
                END IF;

                IF l_vendor_id IS NOT NULL AND rec.inv_number IS NOT NULL THEN
                    SELECT COUNT(*) INTO l_dup_count
                    FROM KF_INVOICES
                    WHERE UPPER(INVOICE_NUMBER) = UPPER(rec.inv_number)
                      AND VENDOR_ID = l_vendor_id;

                    IF l_dup_count > 0 THEN
                        l_status_flag := 'DUPLICATE';
                        l_err_msg := l_err_msg || 'Duplicate: Invoice #' || rec.inv_number || ' already exists for vendor. ';
                    END IF;
                END IF;

                l_inv_date := safe_parse_date(rec.inv_date_str);
                l_due_date := safe_parse_date(rec.due_date_str);

                IF l_inv_date IS NULL THEN
                    l_inv_date := SYSDATE;
                END IF;
                IF l_due_date IS NULL THEN
                    l_due_date := NVL(l_inv_date, SYSDATE) + 30;
                END IF;
                IF l_due_date < l_inv_date THEN
                    l_due_date := l_inv_date;
                END IF;

                l_subtotal := safe_parse_number(rec.subtotal_str);
                l_tax      := safe_parse_number(rec.tax_cgst_str) + safe_parse_number(rec.tax_sgst_str);
                l_total_amt := safe_parse_number(rec.inv_val_str);
                
                IF l_total_amt <= 0 THEN
                    l_total_amt := l_subtotal + l_tax;
                END IF;

                IF safe_parse_number(rec.paid_str) >= l_total_amt AND l_total_amt > 0 THEN
                    l_clean_status := 'PAID';
                ELSIF safe_parse_number(rec.paid_str) > 0 THEN
                    l_clean_status := 'PARTIALLY_PAID';
                ELSIF l_due_date < SYSDATE THEN
                    l_clean_status := 'OVERDUE';
                ELSE
                    l_clean_status := 'APPROVED';
                END IF;

                IF l_status_flag = 'VALID' THEN
                    l_valid := l_valid + 1;
                ELSIF l_status_flag = 'DUPLICATE' THEN
                    l_duplicates := l_duplicates + 1;
                ELSE
                    l_invalid := l_invalid + 1;
                END IF;

                apex_collection.add_member(
                    p_collection_name => C_COLLECTION_NAME,
                    p_c001 => rec.inv_number,
                    p_c002 => rec.vendor_ref,
                    p_c003 => TO_CHAR(NVL(l_inv_date, SYSDATE), 'YYYY-MM-DD'),
                    p_c004 => TO_CHAR(NVL(l_due_date, SYSDATE + 30), 'YYYY-MM-DD'),
                    p_c005 => TO_CHAR(l_subtotal, '999999990.00'),
                    p_c006 => TO_CHAR(l_tax, '999999990.00'),
                    p_c007 => l_clean_status,
                    p_c008 => l_status_flag,
                    p_c009 => RTRIM(l_err_msg),
                    p_n001 => l_vendor_id,
                    p_n002 => l_total_amt,
                    p_n003 => rec.line_number
                );
            END IF;
        END LOOP;

        p_total_rows     := l_total;
        p_valid_rows     := l_valid;
        p_invalid_rows   := l_invalid;
        p_duplicate_rows := l_duplicates;
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
        l_col_name    VARCHAR2(100);
        l_file_type   VARCHAR2(50);

        -- Local scalar variables for row-level DML
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

        -- 1. Determine file type
        IF LOWER(p_file_name) LIKE '%.csv' THEN
            l_file_type := 'CSV';
        ELSIF LOWER(p_file_name) LIKE '%.xlsx' THEN
            l_file_type := 'EXCEL_XLSX';
        ELSE
            l_file_type := 'EXCEL_XLS';
        END IF;

        -- 2. Create entry in KF_IMPORT_BATCHES
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
            p_file_name,
            l_file_type,
            'PROCESSING',
            0,
            0,
            0,
            l_user,
            SYSTIMESTAMP
        ) RETURNING BATCH_ID INTO l_batch_id;

        p_batch_id := l_batch_id;

        -- 3. Process rows from preview collection
        FOR r IN (
            SELECT seq_id,
                   c001 AS inv_number,
                   c002 AS vendor_ref,
                   TO_DATE(c003, 'YYYY-MM-DD') AS inv_date,
                   TO_DATE(c004, 'YYYY-MM-DD') AS due_date,
                   TO_NUMBER(c005) AS subtotal,
                   TO_NUMBER(c006) AS tax,
                   c007 AS status_val,
                   c008 AS status_flag,
                   c009 AS err_msg,
                   n001 AS vendor_id,
                   n002 AS total_amt,
                   n003 AS file_line_num
            FROM apex_collections
            WHERE collection_name = C_COLLECTION_NAME
            ORDER BY seq_id
        ) LOOP
            l_total := l_total + 1;

            -- Assign to local scalar variables
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

                    -- Insert Header into KF_INVOICES using scalar variables
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

                    -- Calculate tax rate
                    IF l_subtotal > 0 THEN
                        l_tax_rate := ROUND((l_tax / l_subtotal) * 100, 2);
                    ELSE
                        l_tax_rate := 0;
                    END IF;

                    -- Insert default line into KF_INVOICE_LINES using scalar variables
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
                        'Imported item for invoice ' || l_inv_num,
                        1,
                        GREATEST(0, l_subtotal),
                        GREATEST(0, l_tax_rate),
                        GREATEST(0, l_tax),
                        GREATEST(0, l_total_amt)
                    );

                    l_success := l_success + 1;
                EXCEPTION
                    WHEN OTHERS THEN
                        l_failed := l_failed + 1;
                        l_sql_err := SUBSTR(SQLERRM, 1, 1000);
                        INSERT INTO KF_IMPORT_ERRORS (
                            BATCH_ID,
                            ROW_NUMBER,
                            COLUMN_NAME,
                            ERROR_MESSAGE,
                            RAW_VALUE,
                            CREATED_DATE
                        ) VALUES (
                            l_batch_id,
                            l_row_num,
                            'DATABASE_INSERT',
                            l_sql_err,
                            l_inv_num,
                            SYSTIMESTAMP
                        );
                END;
            ELSE
                -- Log validation failure or duplicate to KF_IMPORT_ERRORS
                l_failed := l_failed + 1;
                IF l_status_flag = 'DUPLICATE' THEN
                    l_col_name := 'INVOICE_NUMBER';
                ELSE
                    l_col_name := 'VALIDATION';
                END IF;

                INSERT INTO KF_IMPORT_ERRORS (
                    BATCH_ID,
                    ROW_NUMBER,
                    COLUMN_NAME,
                    ERROR_MESSAGE,
                    RAW_VALUE,
                    CREATED_DATE
                ) VALUES (
                    l_batch_id,
                    l_row_num,
                    l_col_name,
                    l_err_msg,
                    l_inv_num,
                    SYSTIMESTAMP
                );
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
        DELETE FROM apex_application_temp_files WHERE name = p_file_name;

        p_success_count := l_success;
        p_failed_count  := l_failed;
        p_status_msg    := 'Import completed. Successfully imported: ' || l_success || ' invoices. Errors/Duplicates: ' || l_failed || '.';
    END CONFIRM_IMPORT;

END KF_PKG_INVOICE_IMPORT;