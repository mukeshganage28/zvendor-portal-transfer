    CLASS lhc_PoAck DEFINITION INHERITING FROM cl_abap_behavior_handler.
      PRIVATE SECTION.
        METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
          IMPORTING REQUEST requested_authorizations FOR PoAck RESULT result.
        METHODS setDefaults FOR DETERMINE ON MODIFY
          IMPORTING keys FOR PoAck~setDefaults.
        METHODS validatePurchaseOrder FOR VALIDATE ON SAVE
          IMPORTING keys FOR PoAck~validatePurchaseOrder.
    ENDCLASS.

    CLASS lhc_PoAck IMPLEMENTATION.

      METHOD get_global_authorizations.
        " only mapped portal users may create
        IF requested_authorizations-%create = if_abap_behv=>mk-on.
          result-%create = COND #( WHEN zcl_vp_util=>current_supplier( ) IS INITIAL
                                   THEN if_abap_behv=>auth-unauthorized
                                   ELSE if_abap_behv=>auth-allowed ).
        ENDIF.
*    IF requested_authorizations-%create = if_abap_behv=>mk-on.
*      result-%create = if_abap_behv=>auth-allowed.
*    ENDIF.

      ENDMETHOD.

      METHOD setDefaults.
        DATA(lv_supplier) = zcl_vp_util=>current_supplier( ).
        MODIFY ENTITIES OF zi_vp_poacknowledgement IN LOCAL MODE
          ENTITY PoAck
            UPDATE FIELDS ( Supplier Status AllMatch )
            WITH VALUE #( FOR key IN keys
                          ( %tky     = key-%tky
                            Supplier = lv_supplier
                            Status   = 'N'          " your initial status
                            AllMatch = abap_false ) ).
      ENDMETHOD.

  METHOD validatePurchaseOrder.
    READ ENTITIES OF zi_vp_poacknowledgement IN LOCAL MODE
      ENTITY PoAck
        FIELDS ( PurchaseOrder ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_ack).

    LOOP AT lt_ack INTO DATA(ls_ack).
      IF zcl_vp_util=>po_accessible( CONV #( ls_ack-PurchaseOrder ) ) = abap_false.
        APPEND VALUE #( %tky = ls_ack-%tky ) TO failed-poack.
        APPEND VALUE #( %tky = ls_ack-%tky
                        %element-PurchaseOrder = if_abap_behv=>mk-on
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = |Purchase order { ls_ack-PurchaseOrder } is not accessible| ) )
               TO reported-poack.
        CONTINUE.
      ENDIF.

      " only one acknowledgement per PO
      SELECT SINGLE @abap_true FROM zvp_po_ack
        WHERE purchase_order = @ls_ack-PurchaseOrder
          AND ack_uuid      <> @ls_ack-AckUUID
        INTO @DATA(lv_exists).
      IF lv_exists = abap_true.
        APPEND VALUE #( %tky = ls_ack-%tky ) TO failed-poack.
        APPEND VALUE #( %tky = ls_ack-%tky
                        %element-PurchaseOrder = if_abap_behv=>mk-on
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = |Purchase order { ls_ack-PurchaseOrder } is already acknowledged| ) )
               TO reported-poack.
      ENDIF.
      CLEAR lv_exists.
    ENDLOOP.
  ENDMETHOD.

    ENDCLASS.


CLASS lhc_PoAckItem DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS validateItem FOR VALIDATE ON SAVE
      IMPORTING keys FOR PoAckItem~validateItem.
ENDCLASS.

CLASS lhc_PoAckItem IMPLEMENTATION.

  METHOD validateItem.
    DATA lt_ack_keys TYPE TABLE FOR READ IMPORT zi_vp_poacknowledgement\\PoAck.
    DATA lv_po       TYPE zvp_po_ack-purchase_order.
    DATA lv_error    TYPE string.

    READ ENTITIES OF zi_vp_poacknowledgement IN LOCAL MODE
      ENTITY PoAckItem
        FIELDS ( AckUUID PurchaseOrderItem OrderedQuantity OrderUnit
                 ConfirmedQuantity ConfirmedDate ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_items).
    IF lt_items IS INITIAL.
      RETURN.
    ENDIF.

    lt_ack_keys = VALUE #( FOR ls_i IN lt_items ( AckUUID = ls_i-AckUUID ) ).
    SORT lt_ack_keys BY AckUUID.
    DELETE ADJACENT DUPLICATES FROM lt_ack_keys COMPARING AckUUID.

    READ ENTITIES OF zi_vp_poacknowledgement IN LOCAL MODE
      ENTITY PoAck
        FIELDS ( PurchaseOrder ) WITH lt_ack_keys
      RESULT DATA(lt_ack).

    LOOP AT lt_items INTO DATA(ls_item).
      CLEAR lv_error.
      lv_po = VALUE #( lt_ack[ AckUUID = ls_item-AckUUID ]-PurchaseOrder OPTIONAL ).

      IF ls_item-ConfirmedQuantity <= 0.
        lv_error = 'Confirmed quantity must be greater than 0'.
      ELSEIF ls_item-ConfirmedDate IS INITIAL.
        lv_error = 'Enter the confirmed delivery date'.
      ELSE.
        " ordered values sent by the app must match the purchase order
        SELECT SINGLE OrderQuantity, PurchaseOrderQuantityUnit
          FROM I_PurchaseOrderItemAPI01 WITH PRIVILEGED ACCESS
          WHERE PurchaseOrder     = @lv_po
            AND PurchaseOrderItem = @ls_item-PurchaseOrderItem
          INTO @DATA(ls_po_item).
        IF sy-subrc <> 0.
          lv_error = |Item { ls_item-PurchaseOrderItem ALPHA = OUT } does not exist in PO { lv_po }|.
        ELSEIF ls_item-OrderedQuantity <> ls_po_item-OrderQuantity
            OR ls_item-OrderUnit       <> ls_po_item-PurchaseOrderQuantityUnit.
          lv_error = |Item { ls_item-PurchaseOrderItem ALPHA = OUT }: ordered quantity does not match the purchase order|.
        ENDIF.
      ENDIF.

      IF lv_error IS NOT INITIAL.
        APPEND VALUE #( %tky = ls_item-%tky ) TO failed-poackitem.
        APPEND VALUE #( %tky = ls_item-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = lv_error ) )
               TO reported-poackitem.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.


    CLASS lsc_zi_vp_poacknowledgement DEFINITION INHERITING FROM cl_abap_behavior_saver.
      PROTECTED SECTION.
        METHODS save_modified REDEFINITION.
    ENDCLASS.

    CLASS lsc_zi_vp_poacknowledgement IMPLEMENTATION.
      METHOD save_modified.
        " additional save: log an activity row per created acknowledgement
        DATA lt_activity TYPE STANDARD TABLE OF zvp_activity WITH EMPTY KEY.
        LOOP AT create-poack INTO DATA(ls_new).
          APPEND zcl_vp_util=>new_activity(
                   iv_supplier = ls_new-Supplier
                   iv_text     = |Acknowledgement created for PO { ls_new-PurchaseOrder }|
                   iv_type     = 'PO_ACK'
                   iv_id       = CONV #( ls_new-PurchaseOrder ) ) TO lt_activity.
        ENDLOOP.
        IF lt_activity IS NOT INITIAL.
          INSERT zvp_activity FROM TABLE @lt_activity.
        ENDIF.
      ENDMETHOD.
    ENDCLASS.
