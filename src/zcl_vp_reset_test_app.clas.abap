
CLASS zcl_vp_reset_test_app DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

ENDCLASS.


CLASS zcl_vp_reset_test_app IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    " Optional: Set a specific user (e.g. 'CB9980000002') to delete only that user's data,
    " or leave INITIAL ('') to wipe all onboarding applications for a completely fresh start.
    CONSTANTS lc_target_user TYPE syuname VALUE 'CB9980000002'.

    IF lc_target_user IS INITIAL.
      " 1. Delete child and dependent transactional tables
      DELETE FROM zvp_onb_doc.
      out->write( |Deleted ZVP_ONB_DOC rows: { sy-dbcnt }| ).

      DELETE FROM zvp_onb_hist.
      out->write( |Deleted ZVP_ONB_HIST rows: { sy-dbcnt }| ).

      DELETE FROM zvp_onb_aprstep.
      out->write( |Deleted ZVP_ONB_APRSTEP rows: { sy-dbcnt }| ).

      " 2. Delete unmanaged mapping, activity, and archive log tables
      DELETE FROM zvp_user_map.
      out->write( |Deleted ZVP_USER_MAP rows: { sy-dbcnt }| ).

      DELETE FROM zvp_activity WHERE related_object_type = 'ONBOARDING'.
      out->write( |Deleted ZVP_ACTIVITY rows: { sy-dbcnt }| ).

      DELETE FROM zvp_onb_app_log.
      out->write( |Deleted ZVP_ONB_APP_LOG rows: { sy-dbcnt }| ).

      " 3. Delete main onboarding application header table
      DELETE FROM zvp_onb_app.
      out->write( |Deleted ZVP_ONB_APP rows: { sy-dbcnt }| ).

    ELSE.
      " Delete records only for lc_target_user (e.g. CB9980000002)
      SELECT app_uuid FROM zvp_onb_app
        WHERE applicant_user = @lc_target_user
        INTO TABLE @DATA(lt_apps).

      IF lt_apps IS NOT INITIAL.
        DELETE FROM zvp_onb_doc     WHERE app_uuid IN ( SELECT app_uuid FROM zvp_onb_app WHERE applicant_user = @lc_target_user ).
        DELETE FROM zvp_onb_hist    WHERE app_uuid IN ( SELECT app_uuid FROM zvp_onb_app WHERE applicant_user = @lc_target_user ).
        DELETE FROM zvp_onb_aprstep WHERE app_uuid IN ( SELECT app_uuid FROM zvp_onb_app WHERE applicant_user = @lc_target_user ).
      ENDIF.

      DELETE FROM zvp_user_map    WHERE user_id        = @lc_target_user.
      DELETE FROM zvp_activity    WHERE user_id        = @lc_target_user
                                    AND related_object_type = 'ONBOARDING'.
      DELETE FROM zvp_onb_app_log WHERE applicant_user = @lc_target_user.
      DELETE FROM zvp_onb_app     WHERE applicant_user = @lc_target_user.

      out->write( |Cleaned all onboarding data for user: { lc_target_user }| ).
    ENDIF.

    COMMIT WORK.
    out->write( 'Onboarding tables cleared successfully. You can now submit a new application.' ).

  ENDMETHOD.

ENDCLASS.

