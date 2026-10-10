*&---------------------------------------------------------------------*
*& Report ZTR_DEVELOPER_HANDOVER
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT ZTR_DEVELOPER_HANDOVER.

TABLES: e070,
        e071,
        e07t,
        tadir.

SELECTION-SCREEN: BEGIN OF BLOCK b1 WITH FRAME .
  SELECT-OPTIONS: s_class    FOR tadir-devclass,
                  s_pgmid    FOR e071-pgmid,
                  s_object   FOR e071-object,
                  s_obname   FOR e071-obj_name,
                  s_truser   FOR e070-as4user DEFAULT sy-uname,
                  s_trkorr   FOR e070-trkorr,
                  s_adate    FOR e070-as4date.
SELECTION-SCREEN: END OF BLOCK b1 .


INITIALIZATION.

START-OF-SELECTION.

END-OF-SELECTION.

DATA lt_developer_handover TYPE TABLE OF ztr_developer_alv.
DATA ls_developer_handover TYPE ztr_developer_alv.
DATA lo_salv               TYPE REF TO cl_salv_table.

SELECT e070~trkorr,
       e070~as4user   AS truser,
       e070~as4date,
       e070~as4time,
       e07t~as4text,
       e071~pgmid,
       e071~object,
       e071~obj_name,
       e071~objfunc,
       tadir~devclass
  FROM e070
         INNER JOIN
           e071 ON e070~trkorr = e071~trkorr
             INNER JOIN
               tadir ON  e071~pgmid    = tadir~pgmid
                     AND e071~object   = tadir~object   " CUST 查不出来
                     AND e071~obj_name = tadir~obj_name
                 LEFT JOIN
                   e07t ON  e070~trkorr = e07t~trkorr
                        AND e07t~langu  = @sy-langu
  INTO TABLE @DATA(lt_e070)
  WHERE as4user        IN @s_truser
    AND as4date        IN @s_adate
    AND e070~trkorr    IN @s_trkorr
    AND e071~pgmid     IN @s_pgmid
    AND e071~object    IN @s_object
    AND e071~obj_name  IN @s_obname
    AND tadir~devclass IN @s_class.

MOVE-CORRESPONDING lt_e070 TO lt_developer_handover.

SORT lt_developer_handover BY devclass object obj_name objfunc pgmid.
DELETE ADJACENT DUPLICATES FROM lt_developer_handover COMPARING devclass object obj_name objfunc pgmid.

TRY.
    cl_salv_table=>factory( IMPORTING r_salv_table = lo_salv
                            CHANGING  t_table      = lt_developer_handover ).
  CATCH cx_salv_msg.
ENDTRY.

lo_salv->get_columns( )->set_optimize( abap_true ).
lo_salv->get_functions( )->set_all( abap_true ).
lo_salv->get_display_settings( )->set_striped_pattern( abap_true ).
lo_salv->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>row_column ).

lo_salv->display( ).