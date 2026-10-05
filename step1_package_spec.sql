CREATE OR REPLACE PACKAGE KF_PKG_INVOICE_IMPORT AS

    -- Constant collection name for APEX import preview
    C_COLLECTION_NAME CONSTANT VARCHAR2(30) := 'KF_IMPORT_PREVIEW';

    -- Parse uploaded Excel (.xlsx, .xls) or CSV file from APEX temp files,
    -- validate all business rules and populate the session collection.
    PROCEDURE PARSE_AND_PREVIEW(
        p_file_name      IN  VARCHAR2,
        p_total_rows     OUT NUMBER,
        p_valid_rows     OUT NUMBER,
        p_invalid_rows   OUT NUMBER,
        p_duplicate_rows OUT NUMBER,
        p_file_size_kb   OUT NUMBER
    );

    -- Execute final import: insert valid invoices and log errors to batches
    PROCEDURE CONFIRM_IMPORT(
        p_file_name     IN  VARCHAR2,
        p_user_name     IN  VARCHAR2,
        p_batch_id      OUT NUMBER,
        p_success_count OUT NUMBER,
        p_failed_count  OUT NUMBER,
        p_status_msg    OUT VARCHAR2
    );

    -- Utility date parser supporting Oracle dates, standard formats, and Excel numeric serial dates
    FUNCTION safe_parse_date(p_date_str IN VARCHAR2) RETURN DATE;

    -- Utility numeric parser stripping currency symbols, commas, and spaces
    FUNCTION safe_parse_number(p_num_str IN VARCHAR2) RETURN NUMBER;

END KF_PKG_INVOICE_IMPORT;
