"! Approval levels + approvers for the onboarding reviewer app.
"! EDIT the VALUE #( ) blocks, then run with F9 (Run As > ABAP Application (Console)).
"! Safe to run again (MODIFY). Rows you remove from the lists are NOT deleted -
"! set is_active = abap_false instead, or delete them explicitly at the end.
"!
"! Leave a user constant blank to use the user who runs this class
"! (handy for testing all levels alone).
CLASS zcl_vp_onb_apr_setup DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    CONSTANTS:
      gc_level1_user TYPE zvp_onb_approver-approver_user VALUE 'CB9980000100',   "jes EDIT e.g. 'CB9980000123'
      gc_level2_user TYPE zvp_onb_approver-approver_user VALUE 'CB9980000005',   "ramesh
      gc_level3_user TYPE zvp_onb_approver-approver_user VALUE 'CB9980000002'.    "gavin

ENDCLASS.



CLASS ZCL_VP_ONB_APR_SETUP IMPLEMENTATION.


  METHOD if_oo_adt_classrun~main.
    DATA lt_level    TYPE STANDARD TABLE OF zvp_onb_aprlvl   WITH EMPTY KEY.
    DATA lt_approver TYPE STANDARD TABLE OF zvp_onb_approver WITH EMPTY KEY.

    DATA(lv_me) = CONV zvp_onb_approver-approver_user( cl_abap_context_info=>get_user_technical_name( ) ).
    GET TIME STAMP FIELD DATA(lv_ts).

    "--- 1) levels: number of levels = number of active rows
    lt_level = VALUE #(
      ( level_no = '01' level_name = 'Procurement'      is_active = abap_true )
*      ( level_no = '02' level_name = 'Finance'          is_active = abap_true )
*      ( level_no = '03' level_name = 'Compliance / CFO' is_active = abap_true )
      ).

    "--- 2) approvers per level (several per level = any one of them may decide)
    lt_approver = VALUE #(
      ( level_no = '01' approver_user = COND #( WHEN gc_level1_user IS INITIAL THEN lv_me ELSE gc_level1_user )
        approver_name = 'Procurement approver' is_active = abap_true valid_from = '20200101' valid_to = '99991231' )
*      ( level_no = '02' approver_user = COND #( WHEN gc_level2_user IS INITIAL THEN lv_me ELSE gc_level2_user )
*        approver_name = 'Finance approver'     is_active = abap_true valid_from = '20200101' valid_to = '99991231' )
*      ( level_no = '03' approver_user = COND #( WHEN gc_level3_user IS INITIAL THEN lv_me ELSE gc_level3_user )
*        approver_name = 'Compliance approver'  is_active = abap_true valid_from = '20200101' valid_to = '99991231' )
        ).

    LOOP AT lt_level ASSIGNING FIELD-SYMBOL(<ls_level>).
      <ls_level>-local_last_changed_at = lv_ts.
      <ls_level>-last_changed_at       = lv_ts.
    ENDLOOP.
    LOOP AT lt_approver ASSIGNING FIELD-SYMBOL(<ls_appr>).
      <ls_appr>-local_last_changed_at = lv_ts.
      <ls_appr>-last_changed_at       = lv_ts.
    ENDLOOP.

    delete from zvp_onb_aprlvl.
    delete from zvp_onb_approver.

    MODIFY zvp_onb_aprlvl   FROM TABLE @lt_level.
    MODIFY zvp_onb_approver FROM TABLE @lt_approver.
    COMMIT WORK.

    out->write( |Your technical user: { lv_me }| ).
    out->write( |ZVP_ONB_APRLVL  : { lines( lt_level ) } level(s)| ).
    out->write( |ZVP_ONB_APPROVER: { lines( lt_approver ) } approver row(s)| ).

    SELECT l~level_no, l~level_name, l~is_active, a~approver_user, a~approver_name
      FROM zvp_onb_aprlvl AS l
      LEFT OUTER JOIN zvp_onb_approver AS a ON a~level_no = l~level_no
      ORDER BY l~level_no, a~approver_user
      INTO TABLE @DATA(lt_show).
    out->write( lt_show ).
  ENDMETHOD.
ENDCLASS.
