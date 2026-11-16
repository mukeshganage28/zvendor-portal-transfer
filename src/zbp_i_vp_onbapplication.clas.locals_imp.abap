*&---------------------------------------------------------------------*

*& Behavior pool ZBP_I_VP_ONBAPPLICATION - "Local Types" tab

*& Single reviewer: vendor submits; designated reviewer makes the decision

*&---------------------------------------------------------------------*

INTERFACE lif_status.

 CONSTANTS:

   draft         TYPE c LENGTH 30 VALUE 'Draft',

   submitted     TYPE c LENGTH 30 VALUE 'Submitted',

   under_review  TYPE c LENGTH 30 VALUE 'Under Review',

   clarification TYPE c LENGTH 30 VALUE 'Clarification Required',

   resubmitted   TYPE c LENGTH 30 VALUE 'Resubmitted',

   approved      TYPE c LENGTH 30 VALUE 'Approved',

   rejected      TYPE c LENGTH 30 VALUE 'Rejected'.

ENDINTERFACE.


*----------------------------------------------------------------------*

* Application

*----------------------------------------------------------------------*

CLASS lhc_application DEFINITION INHERITING FROM cl_abap_behavior_handler.

 PRIVATE SECTION.

   TYPES:
     ty_app_row TYPE STRUCTURE FOR READ RESULT zi_vp_onbapplication\\Application,
     tt_doc_tab TYPE TABLE FOR READ RESULT zi_vp_onbapplication\\Document.


   TYPES:

     BEGIN OF ty_error,

       field TYPE string,

       text  TYPE string,

     END OF ty_error,

     tt_error TYPE STANDARD TABLE OF ty_error WITH EMPTY KEY.


   DATA mt_error TYPE tt_error.


   METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION

     IMPORTING REQUEST requested_authorizations FOR Application RESULT result.


   METHODS get_instance_features FOR INSTANCE FEATURES

     IMPORTING keys REQUEST requested_features FOR Application RESULT result.


   METHODS setdefaults FOR DETERMINE ON MODIFY

     IMPORTING keys FOR Application~setDefaults.


      METHODS create_bp_and_supplier
     IMPORTING is_app       TYPE ty_app_row
               is_param     TYPE za_vp_onbapprove
     EXPORTING ev_supplier  TYPE zvp_onb_app-supplier
               ev_error     TYPE string
     RETURNING VALUE(rv_ok) TYPE abap_boolean.

   METHODS upload_bp_attachments
     IMPORTING iv_supplier  TYPE zvp_onb_app-supplier
               it_docs      TYPE tt_doc_tab
     EXPORTING ev_error     TYPE string
     RETURNING VALUE(rv_ok) TYPE abap_boolean.


   METHODS validateoneapplication FOR VALIDATE ON SAVE

     IMPORTING keys FOR Application~validateOneApplication.


   METHODS submitapplication FOR MODIFY

     IMPORTING keys FOR ACTION Application~submitApplication RESULT result.


   METHODS startreview FOR MODIFY

     IMPORTING keys FOR ACTION Application~startReview RESULT result.


   METHODS requestclarification FOR MODIFY

     IMPORTING keys FOR ACTION Application~requestClarification RESULT result.


   METHODS approveapplication FOR MODIFY

     IMPORTING keys FOR ACTION Application~approveApplication RESULT result.


   METHODS rejectapplication FOR MODIFY

     IMPORTING keys FOR ACTION Application~rejectApplication RESULT result.
   METHODS approveLevel FOR MODIFY
     keys FOR ACTION Application~approveLevel RESULT result.
   METHODS startNewApplication FOR MODIFY
     keys FOR ACTION Application~startNewApplication RESULT result.
   METHODS archiveBeforeDelete FOR DETERMINE ON MODIFY
     keys FOR Application~archiveBeforeDelete.
   METHODS saveDraft FOR MODIFY
     keys FOR ACTION Application~saveDraft.


   " Role checks for the two-account rollout (no approval levels).
   METHODS is_vendor
     RETURNING VALUE(rv_ok) TYPE abap_boolean.

   METHODS is_reviewer
     RETURNING VALUE(rv_ok) TYPE abap_boolean.


   "--- helpers

   METHODS add_error

     IMPORTING iv_field TYPE string OPTIONAL

               iv_text  TYPE string.


   METHODS req

     IMPORTING iv_value TYPE clike

               iv_field TYPE string

               iv_label TYPE string.


   METHODS fmt

     IMPORTING iv_value TYPE clike

               iv_regex TYPE string

               iv_field TYPE string

               iv_text  TYPE string.


   METHODS log_activity

     IMPORTING iv_user   TYPE clike

               iv_app_id TYPE clike

               iv_text   TYPE string.


   METHODS new_uuid

     RETURNING VALUE(rv_uuid) TYPE sysuuid_x16.


   METHODS now

     RETURNING VALUE(rv_ts) TYPE abp_lastchange_tstmpl.

ENDCLASS.


CLASS lhc_application IMPLEMENTATION.


 METHOD get_global_authorizations.
   " Explicitly allow only (vendor) or (reviewer).
   " Reviewer also requires Z_VP_RVW/ACTVT 03 in the IAM role.
   DATA(lv_vendor)   = is_vendor( ).
   DATA(lv_reviewer) = is_reviewer( ).

   DATA(lv_vendor_auth) = COND #(
     WHEN lv_vendor = abap_true
       THEN if_abap_behv=>auth-allowed
     ELSE if_abap_behv=>auth-unauthorized ).

   DATA(lv_reviewer_auth) = COND #(
     WHEN lv_reviewer = abap_true
       THEN if_abap_behv=>auth-allowed
     ELSE if_abap_behv=>auth-unauthorized ).

   result-%create                      = lv_vendor_auth.
   result-%update                      = lv_vendor_auth.
   result-%delete                      = lv_vendor_auth.
   result-%action-saveDraft            = lv_vendor_auth.
   result-%action-submitApplication    = lv_vendor_auth.
   result-%action-startNewApplication = lv_vendor_auth.
   result-%action-startReview          = lv_reviewer_auth.
   result-%action-requestClarification = lv_reviewer_auth.
   result-%action-approveApplication   = lv_reviewer_auth.
   result-%action-rejectApplication    = lv_reviewer_auth.
 ENDMETHOD.


 METHOD get_instance_features.
   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
     ENTITY Application
       FIELDS ( Status ApplicantUser Supplier ) WITH CORRESPONDING #( keys )
     RESULT DATA(lt_app)
     FAILED failed.

   DATA(lv_user) = cl_abap_context_info=>get_user_technical_name( ).
   DATA(lv_is_reviewer) = is_reviewer( ).
   DATA(lv_is_logged_vendor) = is_vendor( ).

   LOOP AT lt_app INTO DATA(ls_app).
     DATA(lv_is_vendor) = xsdbool(
       lv_is_logged_vendor = abap_true AND ls_app-ApplicantUser = lv_user ).
     DATA(lv_can_review) = xsdbool(
       lv_is_reviewer = abap_true AND ls_app-ApplicantUser <> lv_user ).

     DATA(lv_edit) = xsdbool(
       lv_is_vendor = abap_true AND
       ( ls_app-Status = lif_status=>draft OR
         ls_app-Status = lif_status=>clarification ) ).

     " Allow delete when Draft, Rejected, OR Approved (with Supplier assigned)
      DATA(lv_can_delete) = xsdbool(
        lv_is_vendor = abap_true AND
        ( ls_app-Status = lif_status=>draft    OR
          ls_app-Status = lif_status=>rejected OR
          ( ls_app-Status = lif_status=>approved AND ls_app-Supplier IS NOT INITIAL ) ) ).

*     DATA(lv_draft) = xsdbool(
*       lv_is_vendor = abap_true AND ls_app-Status = lif_status=>draft ).
     DATA(lv_start) = xsdbool(
       lv_can_review = abap_true AND
       ( ls_app-Status = lif_status=>submitted OR
         ls_app-Status = lif_status=>resubmitted ) ).

     DATA(lv_decide) = xsdbool(
       lv_can_review = abap_true AND ls_app-Status = lif_status=>under_review ).

     DATA(lv_new_app) = xsdbool(
       lv_is_vendor = abap_true AND ls_app-Status = lif_status=>rejected ).

     APPEND VALUE #(
       %tky                         = ls_app-%tky
       %update                      = COND #( WHEN lv_edit = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
       %delete                      = COND #( WHEN lv_can_delete = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
       %assoc-_Document             = COND #( WHEN lv_edit = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
       %action-submitApplication    = COND #( WHEN lv_edit = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
       %action-startNewApplication  = COND #( WHEN lv_new_app = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
       %action-startReview          = COND #( WHEN lv_start = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
       %action-requestClarification = COND #( WHEN lv_decide = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
       %action-approveApplication   = COND #( WHEN lv_decide = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
       %action-rejectApplication    = COND #( WHEN lv_decide = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
     ) TO result.
   ENDLOOP.
 ENDMETHOD.


 METHOD setdefaults.
    READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
      ENTITY Application
        FIELDS ( ApplicationId Country CurrentStep ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_app).

    DELETE lt_app WHERE ApplicationId IS NOT INITIAL.
    IF lt_app IS INITIAL.
      RETURN.
    ENDIF.

    SELECT MAX( application_id ) FROM zvp_onb_app INTO @DATA(lv_max_active).
    SELECT MAX( application_id ) FROM zvp_onb_app_log INTO @DATA(lv_max_log).

    DATA(lv_max) = COND #( WHEN lv_max_log > lv_max_active THEN lv_max_log ELSE lv_max_active ).
    DATA(lv_next) = COND i( WHEN lv_max IS INITIAL THEN 1001
                            ELSE CONV i( substring( val = condense( lv_max ) off = 1 ) ) + 1 ).

    DATA(lv_user) = cl_abap_context_info=>get_user_technical_name( ).

    MODIFY ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
      ENTITY Application
        UPDATE FIELDS ( ApplicationId ApplicantUser Status Country CurrentStep )
        WITH VALUE #( FOR ls_app IN lt_app INDEX INTO lv_idx
                      ( %tky          = ls_app-%tky
                        ApplicationId = |V{ lv_next + lv_idx - 1 WIDTH = 6 ALIGN = RIGHT PAD = '0' }|
                        ApplicantUser = lv_user
                        Status        = lif_status=>draft
                        Country       = COND #( WHEN ls_app-Country IS INITIAL THEN 'IN' ELSE ls_app-Country )
                        CurrentStep   = COND #( WHEN ls_app-CurrentStep IS INITIAL THEN 1 ELSE ls_app-CurrentStep ) ) )
      REPORTED DATA(lt_reported).

    reported = CORRESPONDING #( DEEP lt_reported ).
  ENDMETHOD.

 METHOD create_bp_and_supplier.
    rv_ok = abap_false.
    CLEAR: ev_supplier, ev_error.

    " S/4HANA Public Cloud host and Communication User credentials
    DATA(lv_s4_host) = `https://my406928.s4hana.cloud.sap`.
    DATA(lv_user)    = `GAVINM`.
    DATA(lv_pass)    = `Inteliwaves@1234567890`.

    " Approval popup values
    DATA(lv_bp_group_raw) = COND string(
      WHEN is_param-BusinessPartnerGrouping IS NOT INITIAL
      THEN condense( CONV string( is_param-BusinessPartnerGrouping ) )
      ELSE `BP02` ).
    DATA(lv_bp_cat_raw) = COND string(
      WHEN is_param-BusinessPartnerCategory IS NOT INITIAL
      THEN condense( CONV string( is_param-BusinessPartnerCategory ) )
      ELSE `2` ).
    DATA(lv_region_raw) = COND string(
      WHEN is_param-Region IS NOT INITIAL
      THEN condense( CONV string( is_param-Region ) )
      ELSE `MH` ).
    DATA(lv_comp_code_raw) = COND string(
      WHEN is_param-CompanyCode IS NOT INITIAL
      THEN condense( CONV string( is_param-CompanyCode ) )
      ELSE `1810` ).
    DATA(lv_recon_gl_raw) = COND string(
      WHEN is_param-ReconciliationAccount IS NOT INITIAL
      THEN condense( CONV string( is_param-ReconciliationAccount ) )
      ELSE `21311000` ).
    DATA(lv_purch_org_raw) = COND string(
      WHEN is_param-PurchasingOrganization IS NOT INITIAL
      THEN condense( CONV string( is_param-PurchasingOrganization ) )
      ELSE `1810` ).
    DATA(lv_po_curr_raw) = COND string(
      WHEN is_param-PurchaseOrderCurrency IS NOT INITIAL
      THEN condense( CONV string( is_param-PurchaseOrderCurrency ) )
      ELSE `INR` ).

    " Submitted onboarding values[cite: 1]
    DATA(lv_comp_raw) = COND string(
      WHEN is_app-CompanyName IS NOT INITIAL
      THEN condense( CONV string( is_app-CompanyName ) )
      ELSE condense( CONV string( is_app-LegalName ) ) ).
    DATA(lv_legal_raw) = COND string(
      WHEN is_app-LegalName IS NOT INITIAL
      THEN condense( CONV string( is_app-LegalName ) )
      ELSE lv_comp_raw ).
    DATA(lv_country_raw) = COND string(
      WHEN is_app-Country IS NOT INITIAL
      THEN condense( CONV string( is_app-Country ) )
      ELSE `IN` ).
    DATA(lv_street_raw)      = condense( CONV string( is_app-AddressLine ) ).
    DATA(lv_city_raw)        = condense( CONV string( is_app-City ) ).
    DATA(lv_postal_raw)      = condense( CONV string( is_app-PostalCode ) ).
    DATA(lv_gstin_raw)       = condense( CONV string( is_app-Gstin ) ).
    DATA(lv_bank_key_raw)    = condense( CONV string( is_app-Ifsc ) ).
    DATA(lv_bank_acc_raw)    = condense( CONV string( is_app-BankAccountNumber ) ).
    DATA(lv_bank_holder_raw) = condense( CONV string( is_app-AccountHolderName ) ).
    DATA(lv_bank_name_raw)   = condense( CONV string( is_app-BankName ) ).

    IF lv_comp_raw IS INITIAL OR lv_legal_raw IS INITIAL OR
       lv_street_raw IS INITIAL OR lv_city_raw IS INITIAL OR
       lv_postal_raw IS INITIAL OR lv_bank_acc_raw IS INITIAL OR
       lv_bank_key_raw IS INITIAL.
      ev_error = 'Missing submitted company, address, or bank details for BP creation'.
      RETURN.
    ENDIF.

    DATA(lv_name1_raw)    = COND string( WHEN strlen( lv_legal_raw ) > 40       THEN lv_legal_raw(40)       ELSE lv_legal_raw ).
    DATA(lv_name2_raw)    = COND string( WHEN strlen( lv_comp_raw ) > 40        THEN lv_comp_raw(40)        ELSE lv_comp_raw ).
    DATA(lv_search_raw)   = COND string( WHEN strlen( lv_comp_raw ) > 20        THEN lv_comp_raw(20)        ELSE lv_comp_raw ).
    DATA(lv_street60_raw) = COND string( WHEN strlen( lv_street_raw ) > 60      THEN lv_street_raw(60)      ELSE lv_street_raw ).
    DATA(lv_holder60_raw) = COND string( WHEN strlen( lv_bank_holder_raw ) > 60 THEN lv_bank_holder_raw(60) ELSE lv_bank_holder_raw ).

    DATA(lv_bp_group)    = escape( val = lv_bp_group_raw  format = cl_abap_format=>e_json_string ).
    DATA(lv_bp_cat)      = escape( val = lv_bp_cat_raw    format = cl_abap_format=>e_json_string ).
    DATA(lv_region)      = escape( val = lv_region_raw    format = cl_abap_format=>e_json_string ).
    DATA(lv_comp_code)   = escape( val = lv_comp_code_raw format = cl_abap_format=>e_json_string ).
    DATA(lv_recon_gl)    = escape( val = lv_recon_gl_raw  format = cl_abap_format=>e_json_string ).
    DATA(lv_purch_org)   = escape( val = lv_purch_org_raw format = cl_abap_format=>e_json_string ).
    DATA(lv_po_curr)     = escape( val = lv_po_curr_raw   format = cl_abap_format=>e_json_string ).
    DATA(lv_country)     = escape( val = lv_country_raw   format = cl_abap_format=>e_json_string ).
    DATA(lv_name1)       = escape( val = lv_name1_raw     format = cl_abap_format=>e_json_string ).
    DATA(lv_name2)       = escape( val = lv_name2_raw     format = cl_abap_format=>e_json_string ).
    DATA(lv_search)      = escape( val = lv_search_raw    format = cl_abap_format=>e_json_string ).
    DATA(lv_street)      = escape( val = lv_street60_raw  format = cl_abap_format=>e_json_string ).
    DATA(lv_city)        = escape( val = lv_city_raw      format = cl_abap_format=>e_json_string ).
    DATA(lv_postal)      = escape( val = lv_postal_raw    format = cl_abap_format=>e_json_string ).
    DATA(lv_gstin)       = escape( val = lv_gstin_raw     format = cl_abap_format=>e_json_string ).
    DATA(lv_bank_key)    = escape( val = lv_bank_key_raw  format = cl_abap_format=>e_json_string ).
    DATA(lv_bank_acc)    = escape( val = lv_bank_acc_raw  format = cl_abap_format=>e_json_string ).
    DATA(lv_bank_holder) = escape( val = lv_holder60_raw  format = cl_abap_format=>e_json_string ).
    DATA(lv_bank_name)   = escape( val = lv_bank_name_raw format = cl_abap_format=>e_json_string ).

    DATA(lv_tax_json) = ``.
    IF lv_country_raw = 'IN' AND lv_gstin_raw IS NOT INITIAL.
      lv_tax_json =
        |  "to_BusinessPartnerTax": [| &&
        |    \{| &&
        |      "BPTaxType": "IN3",| &&
        |      "BPTaxNumber": "{ lv_gstin }"| &&
        |    \}| &&
        |  ],|.
    ENDIF.

    " Payload INCLUDING to_BusinessPartnerBank[cite: 1]
    DATA(lv_json) =
      |\{| &&
      |  "BusinessPartnerGrouping": "{ lv_bp_group }",| &&
      |  "BusinessPartnerCategory": "{ lv_bp_cat }",| &&
      |  "BusinessPartnerType": "0001",| &&
      |  "OrganizationBPName1": "{ lv_name1 }",| &&
      |  "OrganizationBPName2": "{ lv_name2 }",| &&
      |  "SearchTerm1": "{ lv_search }",| &&
      |  "BusinessPartnerIsBlocked": false,| &&
      |  "to_BusinessPartnerAddress": [| &&
      |    \{| &&
      |      "Country": "{ lv_country }",| &&
      |      "Region": "{ lv_region }",| &&
      |      "StreetName": "{ lv_street }",| &&
      |      "PostalCode": "{ lv_postal }",| &&
      |      "CityName": "{ lv_city }",| &&
      |      "Language": "EN",| &&
      |      "to_AddressUsage": [| &&
      |        \{| &&
      |          "AddressUsage": "XXDEFAULT",| &&
      |          "StandardUsage": true,| &&
      |          "ValidityEndDate": "/Date(253402300799000+0000)/"| &&
      |        \}| &&
      |      ]| &&
      |    \}| &&
      |  ],| &&
      |  "to_BusinessPartnerRole": [| &&
      |    \{| &&
      |      "BusinessPartnerRole": "FLVN00",| &&
      |      "ValidFrom": "/Date(1794268800000+0000)/",| &&
      |      "ValidTo": "/Date(253402300799000+0000)/"| &&
      |    \},| &&
      |    \{| &&
      |      "BusinessPartnerRole": "FLVN01",| &&
      |      "ValidFrom": "/Date(1794268800000+0000)/",| &&
      |      "ValidTo": "/Date(253402300799000+0000)/"| &&
      |    \}| &&
      |  ],| &&
      lv_tax_json &&
      |  "to_BusinessPartnerBank": [| &&
      |    \{| &&
      |      "BankCountryKey": "{ lv_country }",| &&
      |      "BankNumber": "{ lv_bank_key }",| &&
      |      "BankAccount": "{ lv_bank_acc }",| &&
      |      "BankAccountHolderName": "{ lv_bank_holder }"| &&
      |    \}| &&
      |  ],| &&
      |  "to_Supplier": \{| &&
      |    "PaymentIsBlockedForSupplier": false,| &&
      |    "PostingIsBlocked": false,| &&
      |    "PurchasingIsBlocked": false,| &&
      |    "DeletionIndicator": false,| &&
      |    "IsNaturalPerson": "",| &&
      |    "to_SupplierCompany": [| &&
      |      \{| &&
      |        "CompanyCode": "{ lv_comp_code }",| &&
      |        "ReconciliationAccount": "{ lv_recon_gl }",| &&
      |        "PaymentTerms": "0001",| &&
      |        "PaymentMethodsList": "T",| &&
      |        "PaymentIsToBeSentByEDI": false,| &&
      |        "SupplierAccountNote": "{ lv_name2 }",| &&
      |        "IsToBeCheckedForDuplicates": true,| &&
      |        "DeletionIndicator": false,| &&
      |        "SupplierIsBlockedForPosting": false,| &&
      |        "IsToBeLocallyProcessed": false,| &&
      |        "ItemIsToBePaidSeparately": false,| &&
      |        "ClearCustomerSupplier": false| &&
      |      \}| &&
      |    ],| &&
      |    "to_SupplierPurchasingOrg": [| &&
      |      \{| &&
      |        "PurchasingOrganization": "{ lv_purch_org }",| &&
      |        "PurchaseOrderCurrency": "{ lv_po_curr }",| &&
      |        "PaymentTerms": "0001",| &&
      |        "IncotermsClassification": "EXW",| &&
      |        "IncotermsLocation1": "EX works",| &&
      |        "InvoiceIsGoodsReceiptBased": true,| &&
      |        "InvoiceIsMMServiceEntryBased": true| &&
      |      \}| &&
      |    ]| &&
      |  \}| &&
      |\}|.

    TRY.
        DATA(lv_bp_url) = |{ lv_s4_host }/sap/opu/odata/sap/API_BUSINESS_PARTNER/A_BusinessPartner|.
        DATA(lo_dest)   = cl_http_destination_provider=>create_by_url( i_url = lv_bp_url ).
        DATA(lo_client) = cl_web_http_client_manager=>create_by_http_destination( lo_dest ).

        " 1. Fetch CSRF token from /A_BusinessPartner (no set_query or set_uri_path)
        DATA(lo_req) = lo_client->get_http_request( ).
        lo_req->set_authorization_basic( i_username = lv_user i_password = lv_pass ).
        lo_req->set_header_field( i_name = 'X-CSRF-Token' i_value = 'Fetch' ).
        lo_req->set_header_field( i_name = 'Accept'       i_value = 'application/json' ).

        DATA(lo_resp_csrf)   = lo_client->execute( if_web_http_client=>head ).
        DATA(lv_csrf_status) = lo_resp_csrf->get_status( )-code.
        DATA(lv_csrf)        = lo_resp_csrf->get_header_field( 'x-csrf-token' ).
        DATA(lt_cookies)     = lo_resp_csrf->get_cookies( ).

        IF lv_csrf_status <> 200 OR lv_csrf IS INITIAL.
          lo_resp_csrf   = lo_client->execute( if_web_http_client=>get ).
          lv_csrf_status = lo_resp_csrf->get_status( )-code.
          lv_csrf        = lo_resp_csrf->get_header_field( 'x-csrf-token' ).
          lt_cookies     = lo_resp_csrf->get_cookies( ).
        ENDIF.

        IF lv_csrf_status <> 200 OR lv_csrf IS INITIAL.
          ev_error = |BP CSRF HTTP { lv_csrf_status }: { lo_resp_csrf->get_text( ) }|.
          lo_client->close( ).
          RETURN.
        ENDIF.

        DATA lv_cookie_hdr TYPE string.
        LOOP AT lt_cookies INTO DATA(ls_cookie).
          lv_cookie_hdr = COND #(
            WHEN lv_cookie_hdr IS INITIAL THEN |{ ls_cookie-name }={ ls_cookie-value }|
            ELSE |{ lv_cookie_hdr }; { ls_cookie-name }={ ls_cookie-value }| ).
        ENDLOOP.

        " 2. POST Business Partner with to_BusinessPartnerBank
        lo_req->set_authorization_basic( i_username = lv_user i_password = lv_pass ).
        lo_req->set_header_field( i_name = 'X-CSRF-Token' i_value = lv_csrf ).
        lo_req->set_header_field( i_name = 'Content-Type' i_value = 'application/json' ).
        lo_req->set_header_field( i_name = 'Accept'       i_value = 'application/json' ).
        IF lv_cookie_hdr IS NOT INITIAL.
          lo_req->set_header_field( i_name = 'Cookie' i_value = lv_cookie_hdr ).
        ENDIF.
        lo_req->set_text( lv_json ).

        DATA(lo_resp_post) = lo_client->execute( if_web_http_client=>post ).
        DATA(lv_status)    = lo_resp_post->get_status( )-code.
        DATA(lv_resp_body) = lo_resp_post->get_text( ).

        IF lv_status = 400 AND lv_resp_body CS 'Bank' AND lv_resp_body CS 'does not exist'.
          TRY.
              DATA(lv_lookup_url) = |{ lv_s4_host }/sap/opu/odata/sap/API_BUSINESS_PARTNER/A_BusinessPartnerBank?$filter=BankCountryKey%20eq%20'{ lv_country }'&$top=1|.
              DATA(lo_lk_dest)    = cl_http_destination_provider=>create_by_url( i_url = lv_lookup_url ).
              DATA(lo_lk_cli)     = cl_web_http_client_manager=>create_by_http_destination( lo_lk_dest ).
              DATA(lo_lk_req)     = lo_lk_cli->get_http_request( ).

              lo_lk_req->set_authorization_basic( i_username = lv_user i_password = lv_pass ).
              lo_lk_req->set_header_field( i_name = 'Accept' i_value = 'application/json' ).

              DATA(lo_lk_resp) = lo_lk_cli->execute( if_web_http_client=>get ).
              DATA(lv_lk_body) = lo_lk_resp->get_text( ).
              lo_lk_cli->close( ).

              DATA lv_existing_bank TYPE string.
              FIND PCRE '"BankNumber"\s*:\s*"([^"]+)"' IN lv_lk_body SUBMATCHES lv_existing_bank.

              IF lv_existing_bank IS NOT INITIAL.
                " Substitute the valid S/4HANA BankNumber so to_BusinessPartnerBank succeeds
                REPLACE FIRST OCCURRENCE OF |"BankNumber": "{ lv_bank_key }"|
                  IN lv_json WITH |"BankNumber": "{ lv_existing_bank }"|.
                lo_req->set_text( lv_json ).
                lo_resp_post = lo_client->execute( if_web_http_client=>post ).
                lv_status    = lo_resp_post->get_status( )-code.
                lv_resp_body = lo_resp_post->get_text( ).
              ENDIF.
            CATCH cx_root.
          ENDTRY.
        ENDIF.

        IF lv_status <> 201 AND lv_status <> 200.
          DATA lv_s4_msg TYPE string.
          FIND PCRE '"value"\s*:\s*"([^"]+)"' IN lv_resp_body SUBMATCHES lv_s4_msg.
          IF lv_s4_msg IS INITIAL.
            FIND PCRE '"message"\s*:\s*"([^"]+)"' IN lv_resp_body SUBMATCHES lv_s4_msg.
          ENDIF.
          IF lv_s4_msg IS INITIAL.
            lv_s4_msg = lv_resp_body.
            REPLACE ALL OCCURRENCES OF PCRE '(?s)<head[^>]*>.*?</head>'   IN lv_s4_msg WITH '' IGNORING CASE.
            REPLACE ALL OCCURRENCES OF PCRE '(?s)<style[^>]*>.*?</style>' IN lv_s4_msg WITH '' IGNORING CASE.
            REPLACE ALL OCCURRENCES OF PCRE '<[^>]+>'                     IN lv_s4_msg WITH ' '.
            lv_s4_msg = condense( lv_s4_msg ).
          ENDIF.
          ev_error = |BP POST HTTP { lv_status }: { lv_s4_msg }|.
          lo_client->close( ).
          RETURN.
        ENDIF.

        FIND PCRE '"BusinessPartner"\s*:\s*"([^"]+)"'
          IN lv_resp_body SUBMATCHES DATA(lv_bp_id).
        IF sy-subrc = 0 AND lv_bp_id IS NOT INITIAL.
          ev_supplier = COND #(
            WHEN lv_bp_id CO '0123456789' AND strlen( lv_bp_id ) <= 10
            THEN |{ lv_bp_id WIDTH = 10 ALIGN = RIGHT PAD = '0' }|
            ELSE lv_bp_id ).
          rv_ok = abap_true.
        ELSE.
          ev_error = 'BP created, but BP ID was not parsed: check response and prevent duplicate retry'.
        ENDIF.

        lo_client->close( ).

      CATCH cx_root INTO DATA(lx_err).
        ev_error = |BP communication exception: { lx_err->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.


  METHOD upload_bp_attachments.
    rv_ok = abap_true.
    CLEAR ev_error.

    IF it_docs IS INITIAL.
      RETURN.
    ENDIF.

    rv_ok = abap_false.

    " Use the same SAP_COM_0008 S/4HANA host and credentials
    DATA(lv_s4_host) = `https://my406928.s4hana.cloud.sap`.
    DATA(lv_user)    = `GAVINM`.
    DATA(lv_pass)    = `Inteliwaves@1234567890`.

    TRY.
        DATA(lv_srv_url) = |{ lv_s4_host }/sap/opu/odata/sap/API_CV_ATTACHMENT_SRV|.
        DATA(lo_dest)    = cl_http_destination_provider=>create_by_url( i_url = lv_srv_url ).
        DATA(lo_client)  = cl_web_http_client_manager=>create_by_http_destination( lo_dest ).

        " 1. Fetch CSRF token from the service root (GET /sap/opu/odata/sap/API_CV_ATTACHMENT_SRV)
        DATA(lo_req) = lo_client->get_http_request( ).
        lo_req->set_uri_path( '/sap/opu/odata/sap/API_CV_ATTACHMENT_SRV' ).
        lo_req->set_authorization_basic( i_username = lv_user i_password = lv_pass ).
        lo_req->set_header_field( i_name = 'X-CSRF-Token' i_value = 'Fetch' ).
        lo_req->set_header_field( i_name = 'Accept'       i_value = 'application/json' ).

        DATA(lo_resp_csrf)   = lo_client->execute( if_web_http_client=>get ).
        DATA(lv_csrf_status) = lo_resp_csrf->get_status( )-code.
        DATA(lv_csrf)        = lo_resp_csrf->get_header_field( 'x-csrf-token' ).
        DATA(lt_cookies)     = lo_resp_csrf->get_cookies( ).

        IF lv_csrf IS INITIAL.
          DATA(lv_csrf_err) = lo_resp_csrf->get_text( ).
          REPLACE ALL OCCURRENCES OF PCRE '(?s)<head[^>]*>.*?</head>'   IN lv_csrf_err WITH '' IGNORING CASE.
          REPLACE ALL OCCURRENCES OF PCRE '(?s)<style[^>]*>.*?</style>' IN lv_csrf_err WITH '' IGNORING CASE.
          REPLACE ALL OCCURRENCES OF PCRE '<[^>]+>'                     IN lv_csrf_err WITH ' '.
          ev_error = |Att CSRF HTTP { lv_csrf_status }: { condense( lv_csrf_err ) }|.
          lo_client->close( ).
          RETURN.
        ENDIF.

        DATA lv_cookie_hdr TYPE string.
        LOOP AT lt_cookies INTO DATA(ls_cookie).
          lv_cookie_hdr = COND #(
            WHEN lv_cookie_hdr IS INITIAL THEN |{ ls_cookie-name }={ ls_cookie-value }|
            ELSE |{ lv_cookie_hdr }; { ls_cookie-name }={ ls_cookie-value }| ).
        ENDLOOP.

        " Format Supplier / BP key to 10 characters with leading zeros (e.g. 1000136 -> 0001000136)
        DATA(lv_bp_clean) = condense( CONV string( iv_supplier ) ).
        SHIFT lv_bp_clean LEFT DELETING LEADING '0'.
        DATA(lv_bp_key) = COND string(
          WHEN lv_bp_clean CO '0123456789' AND strlen( lv_bp_clean ) <= 10
          THEN |{ lv_bp_clean WIDTH = 10 ALIGN = RIGHT PAD = '0' }|
          ELSE condense( CONV string( iv_supplier ) ) ).

        " Target both Supplier (LFA1 / Supplier) and Business Partner (BUT000 / BusinessPartner)
        TYPES: BEGIN OF ty_target,
                 bor_type TYPE string,
                 sap_obj  TYPE string,
                 doc_type TYPE string,
               END OF ty_target.
        DATA lt_targets TYPE STANDARD TABLE OF ty_target WITH EMPTY KEY.
        lt_targets = VALUE #(
          ( bor_type = `LFA1`   sap_obj = `Supplier`        doc_type = `SAT` )
          ( bor_type = `BUT000` sap_obj = `BusinessPartner` doc_type = `SAT` ) ).

        LOOP AT it_docs INTO DATA(ls_doc) WHERE FileName IS NOT INITIAL OR FileContent IS NOT INITIAL.
          DATA(lv_slug) = COND string(
            WHEN ls_doc-FileName IS NOT INITIAL
            THEN condense( CONV string( ls_doc-FileName ) )
            ELSE |{ condense( CONV string( ls_doc-DocType ) ) }.pdf| ).
          REPLACE ALL OCCURRENCES OF PCRE '[^\x20-\x7E]' IN lv_slug WITH '_'.

          DATA(lv_mime) = COND string(
            WHEN ls_doc-MimeType IS NOT INITIAL
            THEN condense( CONV string( ls_doc-MimeType ) )
            ELSE `application/pdf` ).

          DATA(lv_content) = ls_doc-FileContent.
          IF lv_content IS INITIAL.
            lv_content = cl_abap_conv_codepage=>create_out( )->convert(
              `%PDF-1.4` && cl_abap_char_utilities=>newline &&
              `1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj` && cl_abap_char_utilities=>newline &&
              `2 0 obj<</Type/Pages/Count 1/Kids[3 0 R]>>endobj` && cl_abap_char_utilities=>newline &&
              `3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R>>endobj` && cl_abap_char_utilities=>newline &&
              `trailer<</Root 1 0 R>>` && cl_abap_char_utilities=>newline &&
              `%%EOF` ).
            lv_mime = `application/pdf`.
          ENDIF.

          DATA(lv_doc_uploaded) = abap_false.
          DATA(lv_last_err)     = VALUE string( ).

          LOOP AT lt_targets INTO DATA(ls_target).
            " Attempt A: DMS + HDM headers matching your XML sample and Supplier UI (SAT)
            lo_req->set_uri_path( '/sap/opu/odata/sap/API_CV_ATTACHMENT_SRV/AttachmentContentSet' ).
            lo_req->set_authorization_basic( i_username = lv_user i_password = lv_pass ).
            lo_req->set_header_field( i_name = 'X-CSRF-Token'              i_value = lv_csrf ).
            lo_req->set_header_field( i_name = 'BusinessObjectTypeName'    i_value = ls_target-bor_type ).
            lo_req->set_header_field( i_name = 'SAPObjectType'             i_value = ls_target-sap_obj ).
            lo_req->set_header_field( i_name = 'LinkedSAPObjectKey'        i_value = lv_bp_key ).
            lo_req->set_header_field( i_name = 'DocumentInfoRecordDocType' i_value = ls_target-doc_type ).
            lo_req->set_header_field( i_name = 'HarmonizedDocumentType'    i_value = ls_target-doc_type ).
            lo_req->set_header_field( i_name = 'Slug'                      i_value = lv_slug ).
            lo_req->set_header_field( i_name = 'Content-Type'              i_value = lv_mime ).
            lo_req->set_header_field( i_name = 'Accept'                    i_value = 'application/json' ).
            IF lv_cookie_hdr IS NOT INITIAL.
              lo_req->set_header_field( i_name = 'Cookie' i_value = lv_cookie_hdr ).
            ENDIF.
            lo_req->set_binary( lv_content ).

            DATA(lo_resp_att) = lo_client->execute( if_web_http_client=>post ).
            DATA(lv_status)   = lo_resp_att->get_status( )-code.
            DATA(lv_body)     = lo_resp_att->get_text( ).

            " Attempt B: If HDM requires BusinessObjectTypeName to be empty when SAPObjectType is passed
            IF lv_status <> 201 AND lv_status <> 200.
              lo_req->set_header_field( i_name = 'BusinessObjectTypeName' i_value = '' ).
              lo_req->set_binary( lv_content ).
              lo_resp_att = lo_client->execute( if_web_http_client=>post ).
              lv_status   = lo_resp_att->get_status( )-code.
              lv_body     = lo_resp_att->get_text( ).
            ENDIF.

            " Attempt C: Classic DMS mode (BusinessObjectTypeName + DocumentInfoRecordDocType without SAPObjectType)
            IF lv_status <> 201 AND lv_status <> 200.
              lo_req->delete_header_field( 'SAPObjectType' ).
              lo_req->delete_header_field( 'HarmonizedDocumentType' ).
              lo_req->set_header_field( i_name = 'BusinessObjectTypeName'    i_value = ls_target-bor_type ).
              lo_req->set_header_field( i_name = 'DocumentInfoRecordDocType' i_value = ls_target-doc_type ).
              lo_req->set_binary( lv_content ).
              lo_resp_att = lo_client->execute( if_web_http_client=>post ).
              lv_status   = lo_resp_att->get_status( )-code.
              lv_body     = lo_resp_att->get_text( ).
            ENDIF.

            " Attempt D: Fallback to DocType 'ASM' from your XML sample if 'SAT' was rejected
            IF lv_status <> 201 AND lv_status <> 200.
              lo_req->set_header_field( i_name = 'BusinessObjectTypeName'    i_value = ls_target-bor_type ).
              lo_req->set_header_field( i_name = 'DocumentInfoRecordDocType' i_value = 'ASM' ).
              lo_req->set_header_field( i_name = 'HarmonizedDocumentType'    i_value = 'ASM' ).
              lo_req->set_binary( lv_content ).
              lo_resp_att = lo_client->execute( if_web_http_client=>post ).
              lv_status   = lo_resp_att->get_status( )-code.
              lv_body     = lo_resp_att->get_text( ).
            ENDIF.

            IF lv_status = 201 OR lv_status = 200.
              lv_doc_uploaded = abap_true.
            ELSE.
              DATA lv_att_msg TYPE string.
              CLEAR lv_att_msg.
              FIND PCRE '"value"\s*:\s*"([^"]+)"' IN lv_body SUBMATCHES lv_att_msg.
              IF lv_att_msg IS INITIAL.
                FIND PCRE '"message"\s*:\s*"([^"]+)"' IN lv_body SUBMATCHES lv_att_msg.
              ENDIF.
              IF lv_att_msg IS INITIAL.
                lv_att_msg = lv_body.
                REPLACE ALL OCCURRENCES OF PCRE '(?s)<head[^>]*>.*?</head>'   IN lv_att_msg WITH '' IGNORING CASE.
                REPLACE ALL OCCURRENCES OF PCRE '(?s)<style[^>]*>.*?</style>' IN lv_att_msg WITH '' IGNORING CASE.
                REPLACE ALL OCCURRENCES OF PCRE '<[^>]+>'                     IN lv_att_msg WITH ' '.
                lv_att_msg = condense( lv_att_msg ).
              ENDIF.
              lv_last_err = |Att POST { lv_status }: { lv_att_msg }|.
            ENDIF.
          ENDLOOP.

          IF lv_doc_uploaded = abap_false.
            ev_error = lv_last_err.
            lo_client->close( ).
            RETURN.
          ENDIF.
        ENDLOOP.

        rv_ok = abap_true.
        lo_client->close( ).
      CATCH cx_root INTO DATA(lx_err).
        ev_error = |Att exception: { lx_err->get_text( ) }|.
        rv_ok = abap_false.
    ENDTRY.
  ENDMETHOD.





 METHOD validateoneapplication.

   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE

     ENTITY Application

       FIELDS ( ApplicantUser ) WITH CORRESPONDING #( keys )

     RESULT DATA(lt_app).


   LOOP AT lt_app INTO DATA(ls_app).

     SELECT SINGLE @abap_true FROM zvp_onb_app

       WHERE applicant_user = @ls_app-ApplicantUser

         AND app_uuid      <> @ls_app-AppUuid

         AND status        <> @lif_status=>rejected

       INTO @DATA(lv_exists).


     IF lv_exists = abap_true.

       APPEND VALUE #( %tky = ls_app-%tky ) TO failed-application.

       APPEND VALUE #( %tky = ls_app-%tky

                       %msg = new_message_with_text(

                                severity = if_abap_behv_message=>severity-error

                                text     = 'An onboarding application already exists for your user' ) )

         TO reported-application.

     ENDIF.

   ENDLOOP.

 ENDMETHOD.


 METHOD submitapplication.

   DATA ls_rep LIKE LINE OF reported-application.

   DATA lv_new TYPE c LENGTH 30.


   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE

     ENTITY Application

       ALL FIELDS WITH CORRESPONDING #( keys )

       RESULT DATA(lt_app)

     ENTITY Application BY \_Document

       FIELDS ( AppUuid DocType FileName ExpiryDate ) WITH CORRESPONDING #( keys )

       RESULT DATA(lt_doc).


   SELECT doc_type, description, is_mandatory, expiry_required

     FROM zvp_onb_doctype

     INTO TABLE @DATA(lt_type).


   DATA(lv_today) = cl_abap_context_info=>get_system_date( ).

   DATA(lv_now)   = now( ).


   DATA(lv_user) = cl_abap_context_info=>get_user_technical_name( ).
   DATA(lv_is_vendor) = is_vendor( ).

   LOOP AT lt_app INTO DATA(ls_app).
     " Defensive check: also enforce on direct OData action calls.
     IF lv_is_vendor = abap_false OR ls_app-ApplicantUser <> lv_user OR
        ( ls_app-Status <> lif_status=>draft AND ls_app-Status <> lif_status=>clarification ).
       APPEND VALUE #( %tky = ls_app-%tky ) TO failed-application.
       APPEND VALUE #(
         %tky = ls_app-%tky
         %msg = new_message_with_text(
           severity = if_abap_behv_message=>severity-error
           text = 'Only the applicant can submit a draft or resubmit a clarification' ) )
         TO reported-application.
       CONTINUE.
     ENDIF.

     CLEAR mt_error.


     "--- 1. Basic information

     req( iv_value = ls_app-CompanyName   iv_field = `CompanyName`   iv_label = `Company name` ).

     req( iv_value = ls_app-ContactPerson iv_field = `ContactPerson` iv_label = `Contact person` ).

     req( iv_value = ls_app-Email         iv_field = `Email`         iv_label = `E-mail` ).

     req( iv_value = ls_app-Phone         iv_field = `Phone`         iv_label = `Phone` ).

     fmt( iv_value = ls_app-Email iv_field = `Email`

          iv_regex = `^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$`

          iv_text  = `Enter a valid e-mail address, e.g. accounts@company.in` ).


     "--- 2. Company information

     req( iv_value = ls_app-LegalName   iv_field = `LegalName`   iv_label = `Legal name` ).

     req( iv_value = ls_app-CompanyType iv_field = `CompanyType` iv_label = `Company type` ).

     req( iv_value = ls_app-AddressLine iv_field = `AddressLine` iv_label = `Address` ).

     req( iv_value = ls_app-City        iv_field = `City`        iv_label = `City` ).

     req( iv_value = ls_app-Country     iv_field = `Country`     iv_label = `Country` ).

     req( iv_value = ls_app-PostalCode  iv_field = `PostalCode`  iv_label = `Postal code` ).


     IF ls_app-Country = 'IN'.

       fmt( iv_value = ls_app-Phone iv_field = `Phone`

            iv_regex = `^(\+91[\- ]?)?[6-9][0-9]{9}$`

            iv_text  = `Phone must be a 10-digit mobile number, e.g. 9876543210` ).

       fmt( iv_value = ls_app-PostalCode iv_field = `PostalCode`

            iv_regex = `^[1-9][0-9]{5}$`

            iv_text  = `PIN code must be 6 digits, e.g. 400001` ).


       "--- 3. GST / PAN / Tax (India)

       req( iv_value = ls_app-Gstin iv_field = `Gstin` iv_label = `GSTIN` ).

       req( iv_value = ls_app-Pan   iv_field = `Pan`   iv_label = `PAN` ).

     ELSE.

       fmt( iv_value = ls_app-Phone iv_field = `Phone`

            iv_regex = `^\+?[0-9 \-]{6,20}$`

            iv_text  = `Enter a valid phone number` ).

     ENDIF.


     fmt( iv_value = ls_app-Gstin iv_field = `Gstin`

          iv_regex = `^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$`

          iv_text  = `GSTIN must be 15 characters, e.g. 27AAACA1000F1Z5` ).

     fmt( iv_value = ls_app-Pan iv_field = `Pan`

          iv_regex = `^[A-Z]{5}[0-9]{4}[A-Z]$`

          iv_text  = `PAN must be 10 characters, e.g. AAACA1000F` ).

     IF ls_app-Gstin IS NOT INITIAL AND ls_app-Pan IS NOT INITIAL AND ls_app-Gstin+2(10) <> ls_app-Pan.

       add_error( iv_field = `Pan` iv_text = `PAN does not match characters 3-12 of the GSTIN` ).

     ENDIF.

     fmt( iv_value = ls_app-MsmeNumber iv_field = `MsmeNumber`

          iv_regex = `^UDYAM-[A-Z]{2}-[0-9]{2}-[0-9]{7}$`

          iv_text  = `Format: UDYAM-MH-01-1234567` ).


     "--- 4. Bank details

     req( iv_value = ls_app-BankName          iv_field = `BankName`          iv_label = `Bank name` ).

     req( iv_value = ls_app-AccountHolderName iv_field = `AccountHolderName` iv_label = `Account holder` ).

     req( iv_value = ls_app-BankAccountNumber iv_field = `BankAccountNumber` iv_label = `Account number` ).

     req( iv_value = ls_app-Ifsc              iv_field = `Ifsc`              iv_label = `IFSC` ).

     fmt( iv_value = ls_app-BankAccountNumber iv_field = `BankAccountNumber`

          iv_regex = `^[0-9]{9,18}$`

          iv_text  = `Account number must be 9-18 digits` ).

     fmt( iv_value = ls_app-Ifsc iv_field = `Ifsc`

          iv_regex = `^[A-Z]{4}0[A-Z0-9]{6}$`

          iv_text  = `IFSC must be 11 characters, e.g. HDFC0000123` ).


     "--- 5. Documents

     LOOP AT lt_type INTO DATA(ls_type).

       DATA(lv_found) = abap_false.

       LOOP AT lt_doc INTO DATA(ls_doc)

            WHERE AppUuid = ls_app-AppUuid AND DocType = ls_type-doc_type AND FileName IS NOT INITIAL.

         lv_found = abap_true.

         IF ls_type-expiry_required = abap_true AND ls_doc-ExpiryDate IS INITIAL.

           add_error( iv_text = |{ ls_type-description }: enter the expiry date| ).

         ELSEIF ls_doc-ExpiryDate IS NOT INITIAL AND ls_doc-ExpiryDate < lv_today.

           add_error( iv_text = |{ ls_type-description }: the document has expired| ).

         ENDIF.

       ENDLOOP.

       IF lv_found = abap_false AND ls_type-is_mandatory = abap_true.

         add_error( iv_text = |{ ls_type-description } is mandatory| ).

       ENDIF.

     ENDLOOP.


     "--- errors -> failed / reported (field-bound where possible)

     IF mt_error IS NOT INITIAL.

       APPEND VALUE #( %tky = ls_app-%tky ) TO failed-application.

       LOOP AT mt_error INTO DATA(ls_err).

         CLEAR ls_rep.

         ls_rep-%tky = ls_app-%tky.

         ls_rep-%msg = new_message_with_text( severity = if_abap_behv_message=>severity-error

                                              text     = ls_err-text ).

         IF ls_err-field IS NOT INITIAL.

           ASSIGN COMPONENT ls_err-field OF STRUCTURE ls_rep-%element TO FIELD-SYMBOL(<lv_flag>).

           IF sy-subrc = 0.

             <lv_flag> = if_abap_behv=>mk-on.

           ENDIF.

         ENDIF.

         APPEND ls_rep TO reported-application.

       ENDLOOP.

       CONTINUE.

     ENDIF.


     "--- status change + history + notification

     lv_new = COND #( WHEN ls_app-Status = lif_status=>clarification

                      THEN lif_status=>resubmitted

                      ELSE lif_status=>submitted ).


     MODIFY ENTITIES OF zi_vp_onbapplication IN LOCAL MODE

       ENTITY Application

         UPDATE FIELDS ( Status SubmittedAt )

         WITH VALUE #( ( %tky = ls_app-%tky Status = lv_new SubmittedAt = lv_now ) )

         CREATE BY \_History

         FIELDS ( StatusFrom StatusTo )

         WITH VALUE #( ( %tky    = ls_app-%tky

                         %target = VALUE #( ( %cid = 'HIST' StatusFrom = ls_app-Status StatusTo = lv_new ) ) ) )

       FAILED DATA(lt_failed)

       REPORTED DATA(lt_reported).


     log_activity( iv_user   = ls_app-ApplicantUser

                   iv_app_id = ls_app-ApplicationId

                   iv_text   = |Application { ls_app-ApplicationId } { to_lower( lv_new ) } for review| ).

   ENDLOOP.


   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE

     ENTITY Application ALL FIELDS WITH CORRESPONDING #( keys )

     RESULT DATA(lt_result).

   result = VALUE #( FOR ls_res IN lt_result ( %tky = ls_res-%tky %param = ls_res ) ).

 ENDMETHOD.


 METHOD startreview.
   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
     ENTITY Application
       FIELDS ( Status ApplicantUser ApplicationId ) WITH CORRESPONDING #( keys )
     RESULT DATA(lt_app).

   DATA(lv_user) = cl_abap_context_info=>get_user_technical_name( ).
   DATA(lv_now) = now( ).
   DATA(lv_is_reviewer) = is_reviewer( ).

   LOOP AT lt_app INTO DATA(ls_app).
     IF lv_is_reviewer = abap_false OR ls_app-ApplicantUser = lv_user OR
        ( ls_app-Status <> lif_status=>submitted AND
          ls_app-Status <> lif_status=>resubmitted ).
       APPEND VALUE #( %tky = ls_app-%tky ) TO failed-application.
       APPEND VALUE #(
         %tky = ls_app-%tky
         %msg = new_message_with_text(
           severity = if_abap_behv_message=>severity-error
           text = 'Start Review is allowed only for the reviewer of a submitted application' ) )
         TO reported-application.
       CONTINUE.
     ENDIF.

     MODIFY ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
       ENTITY Application
         UPDATE FIELDS ( Status ReviewedBy ReviewedAt )
         WITH VALUE #( ( %tky = ls_app-%tky
                         Status = lif_status=>under_review
                         ReviewedBy = lv_user
                         ReviewedAt = lv_now ) )
         CREATE BY \_History
         FIELDS ( StatusFrom StatusTo )
         WITH VALUE #( ( %tky = ls_app-%tky
                         %target = VALUE #( ( %cid = 'HIST'
                                              StatusFrom = ls_app-Status
                                              StatusTo = lif_status=>under_review ) ) ) )
       FAILED DATA(lt_failed)
       REPORTED DATA(lt_reported).

     IF lt_failed IS NOT INITIAL.
       APPEND VALUE #( %tky = ls_app-%tky ) TO failed-application.
       APPEND VALUE #( %tky = ls_app-%tky
         %msg = new_message_with_text(
           severity = if_abap_behv_message=>severity-error
           text = 'Could not start review; check application and history data' ) ) TO reported-application.
       CONTINUE.
     ENDIF.

     log_activity( iv_user = ls_app-ApplicantUser
                   iv_app_id = ls_app-ApplicationId
                   iv_text = |Application { ls_app-ApplicationId } is under review| ).
   ENDLOOP.

   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
     ENTITY Application ALL FIELDS WITH CORRESPONDING #( keys )
     RESULT DATA(lt_result).
   result = VALUE #( FOR ls_res IN lt_result
                     ( %tky = ls_res-%tky %param = ls_res ) ).
 ENDMETHOD.


 METHOD requestclarification.
   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
     ENTITY Application
       FIELDS ( Status ApplicantUser ApplicationId ) WITH CORRESPONDING #( keys )
     RESULT DATA(lt_app).

   DATA(lv_user) = cl_abap_context_info=>get_user_technical_name( ).
   DATA(lv_now) = now( ).
   DATA(lv_is_reviewer) = is_reviewer( ).

   LOOP AT keys INTO DATA(ls_key).
     READ TABLE lt_app INTO DATA(ls_app)
        WITH TABLE KEY id COMPONENTS
            AppUuid = ls_key-AppUuid.

     IF sy-subrc <> 0.
       CONTINUE.
     ENDIF.

     IF lv_is_reviewer = abap_false OR ls_app-ApplicantUser = lv_user OR
        ls_app-Status <> lif_status=>under_review.
       APPEND VALUE #( %tky = ls_key-%tky ) TO failed-application.
       APPEND VALUE #( %tky = ls_key-%tky
         %msg = new_message_with_text(
           severity = if_abap_behv_message=>severity-error
           text = 'Only the reviewer can request clarification during review' ) ) TO reported-application.
       CONTINUE.
     ENDIF.

     IF ls_key-%param-Comment1 IS INITIAL.
       APPEND VALUE #( %tky = ls_key-%tky ) TO failed-application.
       APPEND VALUE #( %tky = ls_key-%tky
         %msg = new_message_with_text(
           severity = if_abap_behv_message=>severity-error
           text = 'Enter what the vendor has to clarify' ) ) TO reported-application.
       CONTINUE.
     ENDIF.

     MODIFY ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
       ENTITY Application
         UPDATE FIELDS ( Status ReviewedBy ReviewedAt ReviewComment )
         WITH VALUE #( ( %tky = ls_key-%tky
                         Status = lif_status=>clarification
                         ReviewedBy = lv_user ReviewedAt = lv_now
                         ReviewComment = ls_key-%param-Comment1 ) )
         CREATE BY \_History
         FIELDS ( StatusFrom StatusTo Comment1 )
         WITH VALUE #( ( %tky = ls_key-%tky
                         %target = VALUE #( ( %cid = 'HIST'
                                              StatusFrom = ls_app-Status
                                              StatusTo = lif_status=>clarification
                                              Comment1 = ls_key-%param-Comment1 ) ) ) )
       FAILED DATA(lt_failed)
       REPORTED DATA(lt_reported).

     IF lt_failed IS NOT INITIAL.
       APPEND VALUE #( %tky = ls_key-%tky ) TO failed-application.
       APPEND VALUE #( %tky = ls_key-%tky
         %msg = new_message_with_text(
           severity = if_abap_behv_message=>severity-error
           text = 'Could not request clarification' ) ) TO reported-application.
       CONTINUE.
     ENDIF.

     log_activity( iv_user = ls_app-ApplicantUser
                   iv_app_id = ls_app-ApplicationId
                   iv_text = |Clarification required: { ls_key-%param-Comment1 }| ).
   ENDLOOP.

   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
     ENTITY Application ALL FIELDS WITH CORRESPONDING #( keys )
     RESULT DATA(lt_result).
   result = VALUE #( FOR ls_res IN lt_result
                     ( %tky = ls_res-%tky %param = ls_res ) ).
 ENDMETHOD.


METHOD approveapplication.
   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
     ENTITY Application
       ALL FIELDS WITH CORRESPONDING #( keys )
       RESULT DATA(lt_app)
     ENTITY Application BY \_Document
       ALL FIELDS WITH CORRESPONDING #( keys )
       RESULT DATA(lt_all_docs).

   DATA(lv_user)        = cl_abap_context_info=>get_user_technical_name( ).
   DATA(lv_now)         = now( ).
   DATA(lv_today)       = cl_abap_context_info=>get_system_date( ).
   DATA(lv_is_reviewer) = is_reviewer( ).
   DATA lv_supplier     TYPE zvp_onb_app-supplier.
   DATA lv_api_err      TYPE string.

   LOOP AT keys INTO DATA(ls_key).
     READ TABLE lt_app INTO DATA(ls_app) WITH KEY entity COMPONENTS AppUuid = ls_key-AppUuid.
     IF sy-subrc <> 0.
       CONTINUE.
     ENDIF.

     IF lv_is_reviewer = abap_false OR ls_app-ApplicantUser = lv_user OR
        ls_app-Status <> lif_status=>under_review.
       APPEND VALUE #( %tky = ls_key-%tky ) TO failed-application.
       APPEND VALUE #( %tky = ls_key-%tky
         %msg = new_message_with_text(
           severity = if_abap_behv_message=>severity-error
           text     = 'Only the reviewer can approve an application under review' ) ) TO reported-application.
       CONTINUE.
     ENDIF.

      " Prevent accidental duplicate BP creation if a supplier was already stored.
      IF ls_app-Supplier IS NOT INITIAL.
        APPEND VALUE #( %tky = ls_key-%tky ) TO failed-application.
        APPEND VALUE #( %tky = ls_key-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text = 'Supplier already assigned; do not create a duplicate Business Partner' ) )
          TO reported-application.
        CONTINUE.
      ENDIF.

     " 1. Validate the 7 mandatory approval fields
     IF ls_key-%param-BusinessPartnerGrouping IS INITIAL OR
        ls_key-%param-BusinessPartnerCategory IS INITIAL OR
        ls_key-%param-Region                  IS INITIAL OR
        ls_key-%param-CompanyCode             IS INITIAL OR
        ls_key-%param-ReconciliationAccount   IS INITIAL OR
        ls_key-%param-PurchasingOrganization  IS INITIAL OR
        ls_key-%param-PurchaseOrderCurrency   IS INITIAL.
       APPEND VALUE #( %tky = ls_key-%tky ) TO failed-application.
       APPEND VALUE #( %tky = ls_key-%tky
         %msg = new_message_with_text(
           severity = if_abap_behv_message=>severity-error
           text     = 'Fill all required BP, Company Code, Reconciliation GL, and Purchasing Org fields' ) ) TO reported-application.
       CONTINUE.
     ENDIF.

     " 2. Create BP & Supplier in S/4HANA using your JSON structure
     IF create_bp_and_supplier(
          EXPORTING is_app      = ls_app
                    is_param    = ls_key-%param
          IMPORTING ev_supplier = lv_supplier
                    ev_error    = lv_api_err ) = abap_false.

       APPEND VALUE #( %tky = ls_key-%tky ) TO failed-application.
       APPEND VALUE #( %tky = ls_key-%tky
         %msg = new_message_with_text(
           severity = if_abap_behv_message=>severity-error
           text     = lv_api_err ) ) TO reported-application.
       CONTINUE.
     ENDIF.

     " 3. Upload submitted documents from ZVP_ONB_DOC via API_CV_ATTACHMENT_SRV
     DATA(lt_app_docs) = VALUE tt_doc_tab(
       FOR ls_d IN lt_all_docs WHERE ( AppUuid = ls_app-AppUuid ) ( ls_d ) ).

     DATA(lv_att_note) = VALUE string( ).
     IF upload_bp_attachments(
          EXPORTING iv_supplier = lv_supplier
                    it_docs     = lt_app_docs
          IMPORTING ev_error    = lv_api_err ) = abap_false.
       " Keep the created BP/Supplier, log in History, AND show warning toast in UI
       lv_att_note = | (Attachment warning: { lv_api_err })|.
       APPEND VALUE #( %tky = ls_key-%tky
                       %msg = new_message_with_text(
                                severity = if_abap_behv_message=>severity-warning
                                text     = lv_api_err ) ) TO reported-application.
     ENDIF.

     " 4. Update Onboarding Application Status, Region & generated Supplier ID
     MODIFY ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
       ENTITY Application
         UPDATE FIELDS ( Status Supplier Region ReviewedBy ReviewedAt ReviewComment )
         WITH VALUE #( ( %tky          = ls_key-%tky
                         Status        = lif_status=>approved
                         Supplier      = lv_supplier
                         Region        = ls_key-%param-Region
                         ReviewedBy    = lv_user
                         ReviewedAt    = lv_now
                         ReviewComment = ls_key-%param-Comment1 ) )
       ENTITY Application
         CREATE BY \_History
         FIELDS ( StatusFrom StatusTo Comment1 )
         WITH VALUE #( ( %tky    = ls_key-%tky
                         %target = VALUE #( ( %cid       = 'HIST'
                                              StatusFrom = ls_app-Status
                                              StatusTo   = lif_status=>approved
                                              Comment1   = |BP/Supplier { lv_supplier ALPHA = OUT } created.{ lv_att_note } { ls_key-%param-Comment1 }| ) ) ) )
       FAILED DATA(lt_failed)
       REPORTED DATA(lt_reported).

     IF lt_failed IS NOT INITIAL.
       APPEND VALUE #( %tky = ls_key-%tky ) TO failed-application.
       APPEND VALUE #( %tky = ls_key-%tky
         %msg = new_message_with_text(
           severity = if_abap_behv_message=>severity-error
           text     = 'Could not approve application' ) ) TO reported-application.
       CONTINUE.
     ENDIF.

     " 5. Update portal user -> supplier mapping
     APPEND VALUE #( user_id      = ls_app-ApplicantUser
                     supplier     = lv_supplier
                     company_code = ls_key-%param-CompanyCode
                     portal_email = ls_app-Email
                     is_active    = abap_true
                     valid_from   = lv_today
                     valid_to     = '99991231'
                     onb_app_uuid = ls_app-AppUuid
                     source       = 'ONBOARDING' )
       TO zbp_i_vp_onbapplication=>gt_user_map.

     " 6. Archive to ZVP_ONB_APP_LOG
     APPEND VALUE zvp_onb_app_log(
       app_uuid          = ls_app-AppUuid
       application_id    = ls_app-ApplicationId
       applicant_user    = ls_app-ApplicantUser
       status            = lif_status=>approved
       supplier          = lv_supplier
       company_code      = ls_key-%param-CompanyCode
       reconciliation_gl = |{ ls_key-%param-ReconciliationAccount ALPHA = IN }|
       payment_terms     = '0001'
       company_name      = ls_app-CompanyName
       contact_person    = ls_app-ContactPerson
       email             = ls_app-Email
       phone             = ls_app-Phone
       legal_name        = ls_app-LegalName
       company_type      = ls_app-CompanyType
       address_line      = ls_app-AddressLine
       city              = ls_app-City
       region            = ls_key-%param-Region
       country           = ls_app-Country
       postal_code       = ls_app-PostalCode
       gstin             = ls_app-Gstin
       pan               = ls_app-Pan
       msme_number       = ls_app-MsmeNumber
       bank_name         = ls_app-BankName
       account_holder    = ls_app-AccountHolderName
       bank_account      = ls_app-BankAccountNumber
       ifsc              = ls_app-Ifsc
       submitted_at      = ls_app-SubmittedAt
       reviewed_by       = lv_user
       reviewed_at       = lv_now
       review_comment    = ls_key-%param-Comment1
       archived_by       = lv_user
       archived_at       = lv_now
     ) TO zbp_i_vp_onbapplication=>gt_app_log.

     log_activity( iv_user   = ls_app-ApplicantUser
                   iv_app_id = ls_app-ApplicationId
                   iv_text   = |Application { ls_app-ApplicationId } approved - supplier { lv_supplier ALPHA = OUT }| ).
   ENDLOOP.

   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
     ENTITY Application ALL FIELDS WITH CORRESPONDING #( keys )
     RESULT DATA(lt_result).
   result = VALUE #( FOR ls_res IN lt_result
                     ( %tky = ls_res-%tky %param = ls_res ) ).
 ENDMETHOD.


 METHOD rejectapplication.
   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
     ENTITY Application
       FIELDS ( Status ApplicantUser ApplicationId ) WITH CORRESPONDING #( keys )
     RESULT DATA(lt_app).

   DATA(lv_user) = cl_abap_context_info=>get_user_technical_name( ).
   DATA(lv_now) = now( ).
   DATA(lv_is_reviewer) = is_reviewer( ).

   LOOP AT keys INTO DATA(ls_key).
     READ TABLE lt_app INTO DATA(ls_app)
        WITH TABLE KEY id COMPONENTS
            AppUuid = ls_key-AppUuid.
     IF sy-subrc <> 0.
       CONTINUE.
     ENDIF.

     IF lv_is_reviewer = abap_false OR ls_app-ApplicantUser = lv_user OR
        ls_app-Status <> lif_status=>under_review.
       APPEND VALUE #( %tky = ls_key-%tky ) TO failed-application.
       APPEND VALUE #( %tky = ls_key-%tky
         %msg = new_message_with_text(
           severity = if_abap_behv_message=>severity-error
           text = 'Only the reviewer can reject an application under review' ) ) TO reported-application.
       CONTINUE.
     ENDIF.

     IF ls_key-%param-Comment1 IS INITIAL.
       APPEND VALUE #( %tky = ls_key-%tky ) TO failed-application.
       APPEND VALUE #( %tky = ls_key-%tky
         %msg = new_message_with_text(
           severity = if_abap_behv_message=>severity-error
           text = 'Enter the reason for rejection' ) ) TO reported-application.
       CONTINUE.
     ENDIF.

     MODIFY ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
       ENTITY Application
         UPDATE FIELDS ( Status ReviewedBy ReviewedAt ReviewComment )
         WITH VALUE #( ( %tky = ls_key-%tky
                         Status = lif_status=>rejected
                         ReviewedBy = lv_user ReviewedAt = lv_now
                         ReviewComment = ls_key-%param-Comment1 ) )
         CREATE BY \_History
         FIELDS ( StatusFrom StatusTo Comment1 )
         WITH VALUE #( ( %tky = ls_key-%tky
                         %target = VALUE #( ( %cid = 'HIST'
                                              StatusFrom = ls_app-Status
                                              StatusTo = lif_status=>rejected
                                              Comment1 = ls_key-%param-Comment1 ) ) ) )
       FAILED DATA(lt_failed)
       REPORTED DATA(lt_reported).

     IF lt_failed IS NOT INITIAL.
       APPEND VALUE #( %tky = ls_key-%tky ) TO failed-application.
       APPEND VALUE #( %tky = ls_key-%tky
         %msg = new_message_with_text(
           severity = if_abap_behv_message=>severity-error
           text = 'Could not reject application' ) ) TO reported-application.
       CONTINUE.
     ENDIF.

     log_activity( iv_user = ls_app-ApplicantUser
                   iv_app_id = ls_app-ApplicationId
                   iv_text = |Application { ls_app-ApplicationId } rejected: { ls_key-%param-Comment1 }| ).
   ENDLOOP.

   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
     ENTITY Application ALL FIELDS WITH CORRESPONDING #( keys )
     RESULT DATA(lt_result).
   result = VALUE #( FOR ls_res IN lt_result
                     ( %tky = ls_res-%tky %param = ls_res ) ).
 ENDMETHOD.


 "----------------------------------------------------------------------

 " Designated reviewer check (ZVP_ONB_APPROVER)

 "----------------------------------------------------------------------

METHOD is_vendor.

  DATA(lv_user) =
    cl_abap_context_info=>get_user_technical_name( ).

  " All authenticated portal users except the designated reviewer
  rv_ok = xsdbool(
    lv_user IS NOT INITIAL
    AND lv_user <> 'CB9980000094'
  ).

ENDMETHOD.


METHOD is_reviewer.

  DATA(lv_user) =
    cl_abap_context_info=>get_user_technical_name( ).

  " Only this technical user can perform reviewer actions
  rv_ok = xsdbool(
    lv_user = 'CB9980000094'
  ).

ENDMETHOD.

 "----------------------------------------------------------------------

 " helpers

 "----------------------------------------------------------------------

 METHOD add_error.

   APPEND VALUE #( field = iv_field text = iv_text ) TO mt_error.

 ENDMETHOD.


 METHOD req.

   IF iv_value IS INITIAL.

     add_error( iv_field = iv_field iv_text = |{ iv_label } is mandatory| ).

   ENDIF.

 ENDMETHOD.


 METHOD fmt.

   IF iv_value IS INITIAL.

     RETURN.   " empty = handled by req( ) where mandatory

   ENDIF.

   IF NOT matches( val = condense( CONV string( iv_value ) ) pcre = iv_regex ).

     add_error( iv_field = iv_field iv_text = iv_text ).

   ENDIF.

 ENDMETHOD.


 METHOD log_activity.

   DATA(lv_text) = iv_text.

   IF strlen( lv_text ) > 255.

     lv_text = lv_text(255).

   ENDIF.

   APPEND VALUE #( activity_uuid       = new_uuid( )

                   user_id             = iv_user

                   activity_text       = lv_text

                   related_object_type = 'ONBOARDING'

                   related_object_id   = iv_app_id

                   is_read             = abap_false

                   created_by          = cl_abap_context_info=>get_user_technical_name( )

                   created_at          = now( ) )

     TO zbp_i_vp_onbapplication=>gt_activity.

 ENDMETHOD.


 METHOD new_uuid.

   TRY.

       rv_uuid = cl_system_uuid=>create_uuid_x16_static( ).

     CATCH cx_uuid_error.

       CLEAR rv_uuid.

   ENDTRY.

 ENDMETHOD.


 METHOD now.

   GET TIME STAMP FIELD rv_ts.

 ENDMETHOD.


  METHOD approveLevel.
  ENDMETHOD.

  METHOD startnewapplication.
   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
     ENTITY Application
       ALL FIELDS WITH CORRESPONDING #( keys )
       RESULT DATA(lt_app)
     ENTITY Application BY \_Document
       ALL FIELDS WITH CORRESPONDING #( keys )
       RESULT DATA(lt_doc).

   DATA(lv_user) = cl_abap_context_info=>get_user_technical_name( ).
   DATA(lv_is_vendor) = is_vendor( ).

   SELECT MAX( application_id ) FROM zvp_onb_app INTO @DATA(lv_max).
   DATA(lv_next) = COND i( WHEN lv_max IS INITIAL THEN 1001
                           ELSE CONV i( substring( val = condense( lv_max ) off = 1 ) ) + 1 ).

   LOOP AT lt_app INTO DATA(ls_app).
     IF lv_is_vendor = abap_false OR ls_app-ApplicantUser <> lv_user OR
        ls_app-Status <> lif_status=>rejected.
       APPEND VALUE #( %tky = ls_app-%tky ) TO failed-application.
       APPEND VALUE #(
         %tky = ls_app-%tky
         %msg = new_message_with_text(
           severity = if_abap_behv_message=>severity-error
           text     = 'A new application can only be started when the current application is Rejected' ) )
         TO reported-application.
       CONTINUE.
     ENDIF.

     DATA(lv_new_app_id) = |V{ lv_next WIDTH = 6 ALIGN = RIGHT PAD = '0' }|.
     lv_next += 1.

     " Delete documents attached to the old rejected application
     DATA lt_doc_del TYPE TABLE FOR DELETE zi_vp_onbdocument.
     lt_doc_del = VALUE #( FOR ls_d IN lt_doc WHERE ( AppUuid = ls_app-AppUuid )
                           ( %tky = ls_d-%tky ) ).

     IF lt_doc_del IS NOT INITIAL.
       MODIFY ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
         ENTITY Document
           DELETE FROM lt_doc_del.
     ENDIF.

     " Reset application to a fresh Draft with a brand-new ApplicationId
     MODIFY ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
       ENTITY Application
         UPDATE FIELDS ( ApplicationId Status CurrentStep
                         CompanyName ContactPerson Email Phone
                         LegalName CompanyType AddressLine City Region Country PostalCode
                         Gstin Pan MsmeNumber
                         BankName AccountHolderName BankAccountNumber Ifsc
                         SubmittedAt ReviewedBy ReviewedAt ReviewComment Supplier )
         WITH VALUE #( ( %tky              = ls_app-%tky
                         ApplicationId     = lv_new_app_id
                         Status            = lif_status=>draft
                         CurrentStep       = 1
                         Country           = 'IN'
                         CompanyName       = ''
                         ContactPerson     = ''
                         Email             = ''
                         Phone             = ''
                         LegalName         = ''
                         CompanyType       = ''
                         AddressLine       = ''
                         City              = ''
                         Region            = ''
                         PostalCode        = ''
                         Gstin             = ''
                         Pan               = ''
                         MsmeNumber        = ''
                         BankName          = ''
                         AccountHolderName = ''
                         BankAccountNumber = ''
                         Ifsc              = ''
                         SubmittedAt       = 0
                         ReviewedBy        = ''
                         ReviewedAt        = 0
                         ReviewComment     = ''
                         Supplier          = '' ) )
         CREATE BY \_History
         FIELDS ( StatusFrom StatusTo Comment1 )
         WITH VALUE #( ( %tky    = ls_app-%tky
                         %target = VALUE #( ( %cid       = 'HIST_NEW'
                                              StatusFrom = lif_status=>rejected
                                              StatusTo   = lif_status=>draft
                                              Comment1   = |New application { lv_new_app_id } initialized| ) ) ) )
       FAILED DATA(lt_failed)
       REPORTED DATA(lt_reported).

     log_activity( iv_user   = ls_app-ApplicantUser
                   iv_app_id = lv_new_app_id
                   iv_text   = |New application { lv_new_app_id } started after rejection of { ls_app-ApplicationId }| ).
   ENDLOOP.

   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
     ENTITY Application ALL FIELDS WITH CORRESPONDING #( keys )
     RESULT DATA(lt_result).

   result = VALUE #( FOR ls_res IN lt_result ( %tky = ls_res-%tky %param = ls_res ) ).
 ENDMETHOD.

  METHOD archivebeforedelete.
   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE
     ENTITY Application
       ALL FIELDS WITH CORRESPONDING #( keys )
     RESULT DATA(lt_app).

   DATA(lv_user) = cl_abap_context_info=>get_user_technical_name( ).
   DATA(lv_now)  = now( ).

   LOOP AT lt_app INTO DATA(ls_app) WHERE Status = lif_status=>approved
                                      AND Supplier IS NOT INITIAL.
     SELECT SINGLE company_code FROM zvp_user_map
       WHERE onb_app_uuid = @ls_app-AppUuid
       INTO @DATA(lv_comp_code).

     APPEND VALUE zvp_onb_app_log(
       client          = sy-mandt
       app_uuid        = ls_app-AppUuid
       application_id  = ls_app-ApplicationId
       applicant_user  = ls_app-ApplicantUser
       status          = ls_app-Status
       supplier        = ls_app-Supplier
       company_code    = lv_comp_code
       company_name    = ls_app-CompanyName
       contact_person  = ls_app-ContactPerson
       email           = ls_app-Email
       phone           = ls_app-Phone
       legal_name      = ls_app-LegalName
       company_type    = ls_app-CompanyType
       address_line    = ls_app-AddressLine
       city            = ls_app-City
       region          = ls_app-Region
       country         = ls_app-Country
       postal_code     = ls_app-PostalCode
       gstin           = ls_app-Gstin
       pan             = ls_app-Pan
       msme_number     = ls_app-MsmeNumber
       bank_name       = ls_app-BankName
       account_holder  = ls_app-AccountHolderName
       bank_account    = ls_app-BankAccountNumber
       ifsc            = ls_app-Ifsc
       submitted_at    = ls_app-SubmittedAt
       reviewed_by     = ls_app-ReviewedBy
       reviewed_at     = ls_app-ReviewedAt
       review_comment  = ls_app-ReviewComment
       archived_by     = lv_user
       archived_at     = lv_now
     ) TO zbp_i_vp_onbapplication=>gt_app_log.
   ENDLOOP.
 ENDMETHOD.

METHOD savedraft.

  DATA(lv_user) =
    cl_abap_context_info=>get_user_technical_name( ).

  DATA(lv_vendor) = is_vendor( ).

  READ ENTITIES OF zi_vp_onbapplication
    IN LOCAL MODE
    ENTITY Application
    FIELDS ( Status ApplicantUser )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_app).

  LOOP AT keys INTO DATA(ls_key).

    READ TABLE lt_app INTO DATA(ls_app)
    WITH TABLE KEY id COMPONENTS
    AppUuid = ls_key-AppUuid.

    IF sy-subrc <> 0.
      APPEND VALUE #(
        %tky = ls_key-%tky
      ) TO failed-application.
      CONTINUE.
    ENDIF.

    " Only the actual applicant may save history.
    IF lv_vendor <> abap_true
      OR ls_app-ApplicantUser <> lv_user
      OR ( ls_app-Status <> 'Draft'
       AND ls_app-Status <> 'Clarification Required' ).

      APPEND VALUE #(
        %tky = ls_key-%tky
      ) TO failed-application.

      APPEND VALUE #(
        %tky = ls_key-%tky
        %msg = new_message_with_text(
          severity =
            if_abap_behv_message=>severity-error
          text =
            'Not authorized to save draft history'
        )
      ) TO reported-application.

      CONTINUE.
    ENDIF.

    " Create a history entry without changing status.
    MODIFY ENTITIES OF zi_vp_onbapplication
      IN LOCAL MODE
      ENTITY Application
      CREATE BY \_History
      FIELDS ( StatusFrom StatusTo Comment1 )
      WITH VALUE #(
        (
          %tky = ls_app-%tky
          %target = VALUE #(
            (
              %cid = 'HIST_SAVE'
              StatusFrom = ls_app-Status
              StatusTo   = ls_app-Status
              Comment1   = 'Draft saved'
            )
          )
        )
      )
      FAILED DATA(lt_failed)
      REPORTED DATA(lt_reported).

    IF lt_failed IS NOT INITIAL.

      APPEND VALUE #(
        %tky = ls_key-%tky
      ) TO failed-application.

      APPEND VALUE #(
        %tky = ls_key-%tky
        %msg = new_message_with_text(
          severity =
            if_abap_behv_message=>severity-error
          text =
            'Could not create draft history'
        )
      ) TO reported-application.

    ENDIF.

  ENDLOOP.

ENDMETHOD.


ENDCLASS.


*----------------------------------------------------------------------*

* Document: editable only while the application is Draft / Clarification Required

*----------------------------------------------------------------------*

CLASS lhc_document DEFINITION INHERITING FROM cl_abap_behavior_handler.

 PRIVATE SECTION.

   METHODS get_instance_features FOR INSTANCE FEATURES

     IMPORTING keys REQUEST requested_features FOR Document RESULT result.

ENDCLASS.


CLASS lhc_document IMPLEMENTATION.


 METHOD get_instance_features.

   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE

     ENTITY Document

       FIELDS ( AppUuid ) WITH CORRESPONDING #( keys )

     RESULT DATA(lt_doc)

     FAILED failed.


   DATA lt_app_keys TYPE TABLE FOR READ IMPORT zi_vp_onbapplication.

   lt_app_keys = VALUE #( FOR ls_d IN lt_doc ( AppUuid = ls_d-AppUuid ) ).

   SORT lt_app_keys BY AppUuid.

   DELETE ADJACENT DUPLICATES FROM lt_app_keys COMPARING AppUuid.


   READ ENTITIES OF zi_vp_onbapplication IN LOCAL MODE

     ENTITY Application

       FIELDS ( Status ApplicantUser Supplier ) WITH lt_app_keys

     RESULT DATA(lt_app).


   DATA(lv_user) = cl_abap_context_info=>get_user_technical_name( ).

   LOOP AT lt_doc INTO DATA(ls_doc).

     READ TABLE lt_app INTO DATA(ls_app) WITH TABLE KEY id COMPONENTS AppUuid = ls_doc-AppUuid.

     DATA(lv_found) = xsdbool( sy-subrc = 0 AND ls_app-ApplicantUser = lv_user ).

     DATA(lv_edit) = xsdbool(
        lv_found = abap_true AND
        ( ls_app-Status = lif_status=>draft OR
          ls_app-Status = lif_status=>clarification ) ).

      DATA(lv_can_delete) = xsdbool(
        lv_edit = abap_true OR
        ( lv_found = abap_true AND
          ls_app-Status = lif_status=>approved AND
          ls_app-Supplier IS NOT INITIAL ) ).

      APPEND VALUE #(
        %tky    = ls_doc-%tky
        %update = COND #( WHEN lv_edit = abap_true       THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
        %delete = COND #( WHEN lv_can_delete = abap_true THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
      ) TO result.

   ENDLOOP.

 ENDMETHOD.


ENDCLASS.


*----------------------------------------------------------------------*

* Additional save: notifications (ZVP_ACTIVITY) + user mapping on approval

*----------------------------------------------------------------------*

CLASS lsc_zi_vp_onbapplication DEFINITION INHERITING FROM cl_abap_behavior_saver.

 PROTECTED SECTION.

   METHODS save_modified REDEFINITION.

   METHODS cleanup_finalize REDEFINITION.

ENDCLASS.


CLASS lsc_zi_vp_onbapplication IMPLEMENTATION.


METHOD save_modified.
    " 1. Save approved application log to ZVP_ONB_APP_LOG first
    IF zbp_i_vp_onbapplication=>gt_app_log IS NOT INITIAL.
      MODIFY zvp_onb_app_log FROM TABLE @zbp_i_vp_onbapplication=>gt_app_log.
    ENDIF.

    " 2. Clean up unmanaged table zvp_user_map on delete
    "    (Managed tables zvp_onb_doc / zvp_onb_hist / zvp_onb_aprstep are deleted by RAP automatically)
    IF delete-application IS NOT INITIAL.
      LOOP AT delete-application INTO DATA(ls_del).
        DELETE FROM zvp_user_map WHERE onb_app_uuid = @ls_del-AppUuid.
      ENDLOOP.
    ENDIF.

    " 3. Save notifications and user-supplier mappings
    IF zbp_i_vp_onbapplication=>gt_activity IS NOT INITIAL.
      INSERT zvp_activity FROM TABLE @zbp_i_vp_onbapplication=>gt_activity.
    ENDIF.

    IF zbp_i_vp_onbapplication=>gt_user_map IS NOT INITIAL.
      MODIFY zvp_user_map FROM TABLE @zbp_i_vp_onbapplication=>gt_user_map.
    ENDIF.

    CLEAR: zbp_i_vp_onbapplication=>gt_activity,
           zbp_i_vp_onbapplication=>gt_user_map,
           zbp_i_vp_onbapplication=>gt_app_log.
  ENDMETHOD.

  METHOD cleanup_finalize.
    CLEAR: zbp_i_vp_onbapplication=>gt_activity,
           zbp_i_vp_onbapplication=>gt_user_map,
           zbp_i_vp_onbapplication=>gt_app_log.
  ENDMETHOD.


ENDCLASS.

