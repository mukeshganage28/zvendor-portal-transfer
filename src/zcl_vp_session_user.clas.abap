
CLASS zcl_vp_session_user DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_rap_query_provider.

ENDCLASS.


CLASS zcl_vp_session_user IMPLEMENTATION.

  METHOD if_rap_query_provider~select.

    DATA lt_result TYPE STANDARD TABLE OF
      zce_vp_sessionuser WITH EMPTY KEY.

    DATA ls_user TYPE zce_vp_sessionuser.

    "Actual user authenticated for this OData request
    ls_user-UserId =
      cl_abap_context_info=>get_user_technical_name( ).

    TRY.
        ls_user-DisplayName =
          cl_abap_context_info=>get_user_formatted_name( ).

      CATCH cx_abap_context_info_error.
        ls_user-DisplayName = ls_user-UserId.
    ENDTRY.

    IF io_request->is_data_requested( ).

      DATA(lv_skip) =
        io_request->get_paging( )->get_offset( ).

      DATA(lv_top) =
        io_request->get_paging( )->get_page_size( ).

      IF lv_skip = 0 AND lv_top <> 0.
        APPEND ls_user TO lt_result.
      ENDIF.

      io_response->set_data( lt_result ).

    ENDIF.

    IF io_request->is_total_numb_of_rec_requested( ).
      io_response->set_total_number_of_records( 1 ).
    ENDIF.

  ENDMETHOD.

ENDCLASS.

