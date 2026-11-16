CLASS zcl_vp_sample DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_oo_adt_classrun .
  PROTECTED SECTION.
  PRIVATE SECTION.
    " Update with your S/4HANA URL and SAP_COM_0008 credentials
    CONSTANTS:
      gc_s4_base_url TYPE string VALUE 'https://my406928-api.s4hana.ondemand.com',
     gc_comm_user   TYPE string VALUE 'BPA',
     gc_comm_pass   TYPE string VALUE '/FzKs9+7>>t/%E)z\BZ[vaGb]vogL}v{55hVYg/L'.
ENDCLASS.



CLASS ZCL_VP_SAMPLE IMPLEMENTATION.


   METHOD if_oo_adt_classrun~main.

    out->write( '================ 1. ACTIVE APPLICATIONS (ZVP_ONB_APP) ================' ).
    SELECT application_id,
           applicant_user,
           company_name,
           status,
           supplier,
           reviewed_by,
           review_comment
      FROM zvp_onb_app
      ORDER BY application_id DESCENDING
      INTO TABLE @DATA(lt_apps)
      UP TO 10 ROWS.

    IF lt_apps IS INITIAL.
      out->write( 'No records found in ZVP_ONB_APP.' ).
    ELSE.
      out->write( lt_apps ).
    ENDIF.


    out->write( '================ 2. ARCHIVED LOG TABLE (ZVP_ONB_APP_LOG) ================' ).
    SELECT application_id,
           applicant_user,
           company_name,
           status,
           supplier,
           company_code,
           reconciliation_gl,
           payment_terms,
           archived_by
      FROM zvp_onb_app_log
      ORDER BY application_id DESCENDING
      INTO TABLE @DATA(lt_logs)
      UP TO 10 ROWS.

    IF lt_logs IS INITIAL.
      out->write( 'No records found in ZVP_ONB_APP_LOG.' ).
    ELSE.
      out->write( lt_logs ).
    ENDIF.


    out->write( '================ 3. USER TO SUPPLIER MAP (ZVP_USER_MAP) ================' ).
    SELECT user_id,
           supplier,
           company_code,
           portal_email,
           is_active,
           valid_from
      FROM zvp_user_map
      INTO TABLE @DATA(lt_map)
      UP TO 10 ROWS.

    IF lt_map IS INITIAL.
      out->write( 'No records found in ZVP_USER_MAP.' ).
    ELSE.
      out->write( lt_map ).
    ENDIF.


    out->write( '================ 4. STATUS HISTORY (ZVP_ONB_HIST) ================' ).
    SELECT app_uuid,
           status_from,
           status_to,
           comment1,
           changed_by,
           changed_at
      FROM zvp_onb_hist
      ORDER BY changed_at DESCENDING
      INTO TABLE @DATA(lt_hist)
      UP TO 10 ROWS.

    out->write( lt_hist ).


    " Pick the latest created Supplier ID from ZVP_ONB_APP or ZVP_ONB_APP_LOG
    DATA lv_supplier TYPE c LENGTH 10.
    LOOP AT lt_apps INTO DATA(ls_app) WHERE supplier IS NOT INITIAL.
      lv_supplier = ls_app-supplier.
      EXIT.
    ENDLOOP.

    IF lv_supplier IS INITIAL.
      LOOP AT lt_logs INTO DATA(ls_log) WHERE supplier IS NOT INITIAL.
        lv_supplier = ls_log-supplier.
        EXIT.
      ENDLOOP.
    ENDIF.

    IF lv_supplier IS INITIAL.
      out->write( 'No Supplier ID found yet in ZVP_ONB_APP or ZVP_ONB_APP_LOG to check in S/4HANA.' ).
      RETURN.
    ENDIF.

    DATA(lv_bp_padded) = |{ lv_supplier ALPHA = IN }|.
    out->write( |================ 5. CHECKING S/4HANA FOR BP/SUPPLIER: { lv_bp_padded } ================| ).

    TRY.
        DATA(lo_dest)   = cl_http_destination_provider=>create_by_url( gc_s4_base_url ).
        DATA(lo_client) = cl_web_http_client_manager=>create_by_http_destination( lo_dest ).

        lo_client->get_http_request( )->set_authorization_basic(
          i_username = gc_comm_user
          i_password = gc_comm_pass ).

        " A. Check Business Partner & Supplier Company Data in API_BUSINESS_PARTNER
        DATA(lo_req_bp) = lo_client->get_http_request( ).
        lo_req_bp->set_uri_path(
          |/sap/opu/odata/sap/API_BUSINESS_PARTNER/A_BusinessPartner('{ lv_bp_padded }')| &&
          |?$expand=to_BusinessPartnerRole,to_BusinessPartnerTax,to_Supplier/to_SupplierCompany&$format=json| ).
        lo_req_bp->set_header_field( i_name = 'Accept' i_value = 'application/json' ).

        DATA(lo_resp_bp) = lo_client->execute( if_web_http_client=>get ).
        out->write( |BP API HTTP Status: { lo_resp_bp->get_status( )-code }| ).
        out->write( lo_resp_bp->get_text( ) ).

        " B. Check Linked Attachments in API_CV_ATTACHMENT_SRV
        DATA(lo_req_att) = lo_client->get_http_request( ).
        lo_req_att->set_uri_path(
          |/sap/opu/odata/sap/API_CV_ATTACHMENT_SRV/GetAllOriginals| &&
          |?BusinessObjectTypeName='BUS1006'&LinkedSAPObjectKey='{ lv_bp_padded }'&$format=json| ).
        lo_req_att->set_header_field( i_name = 'Accept' i_value = 'application/json' ).

        DATA(lo_resp_att) = lo_client->execute( if_web_http_client=>get ).
        out->write( |Attachment API HTTP Status: { lo_resp_att->get_status( )-code }| ).
        out->write( lo_resp_att->get_text( ) ).

        lo_client->close( ).

      CATCH cx_root INTO DATA(lx_err).
        out->write( |HTTP Check Error: { lx_err->get_text( ) }| ).
    ENDTRY.

  ENDMETHOD.
ENDCLASS.
