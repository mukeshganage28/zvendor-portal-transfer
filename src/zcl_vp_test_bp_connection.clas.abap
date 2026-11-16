CLASS zcl_vp_test_bp_connection DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

ENDCLASS.


CLASS zcl_vp_test_bp_connection IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    CONSTANTS:

      lc_scenario TYPE if_com_management=>ty_cscn_id
        VALUE 'ZVP_BP_OUT',

      lc_service TYPE if_com_management=>ty_cscn_outb_srv_id
        VALUE 'ZVP_BP_API_REST'.

    TRY.

        "Use the communication system shown in your screenshot.
        DATA(lo_destination) =
          cl_http_destination_provider=>create_by_comm_arrangement(
            comm_scenario  = lc_scenario
            service_id     = lc_service
            comm_system_id = 'ZVP_BP_SELF'
          ).

        DATA(lo_client) =
          cl_web_http_client_manager=>create_by_http_destination(
            lo_destination
          ).

        DATA(lo_request) = lo_client->get_http_request( ).

        "No SET_URI_PATH here.
        "The request uses the URL configured in the arrangement.

        lo_request->set_header_field(
          i_name  = 'Accept'
          i_value = 'application/json'
        ).

        lo_request->set_header_field(
          i_name  = 'x-csrf-token'
          i_value = 'Fetch'
        ).

        DATA(lo_response) =
          lo_client->execute( if_web_http_client=>get ).

        DATA(ls_status) = lo_response->get_status( ).

        DATA(lv_content_type) =
          lo_response->get_header_field( 'content-type' ).

        DATA(lv_location) =
          lo_response->get_header_field( 'location' ).

        DATA(lv_token) =
          lo_response->get_header_field( 'x-csrf-token' ).

        out->write(
          |HTTP status: { ls_status-code } { ls_status-reason }|
        ).

        out->write(
          |Content-Type: { lv_content_type }|
        ).

        IF lv_location IS NOT INITIAL.
          out->write( |Location: { lv_location }| ).
        ENDIF.

        IF ls_status-code >= 200 AND ls_status-code < 300.

          out->write( 'GET request completed successfully.' ).

          IF lv_token IS INITIAL
             OR lv_token = 'Required'
             OR lv_token = 'required'.

            out->write(
              'A usable CSRF token was not returned.'
            ).

          ELSE.

            "Do not print the token value.
            out->write(
              'A CSRF token was returned; its value is hidden.'
            ).

          ENDIF.

        ELSE.

          out->write( '--- Server response body ---' ).

          DATA(lv_response_body) = lo_response->get_text( ).

          IF lv_response_body IS INITIAL.
            out->write( 'The response body is empty.' ).
          ELSE.
            out->write( lv_response_body ).
          ENDIF.

        ENDIF.

        lo_client->close( ).

      CATCH cx_root INTO DATA(lx_error).

        out->write(
          |Connection error: { lx_error->get_text( ) }|
        ).

    ENDTRY.

  ENDMETHOD.

ENDCLASS.
