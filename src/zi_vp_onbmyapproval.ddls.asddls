// Approval levels of the logged-on user (one row per level).
// Used for the "Pending With Me" flag in the reviewer app.
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Vendor onboarding - my approval levels'
define view entity ZI_VP_OnbMyApproval
  as select from zvp_onb_approver
{
  key level_no                                   as LevelNo,
      cast( 'X' as abap_boolean preserving type ) as IsMine
}
where approver_user = $session.user
  and is_active     = 'X'
  and valid_from   <= $session.system_date
  and (
       valid_to    >= $session.system_date
    or valid_to     = '00000000'
  )
