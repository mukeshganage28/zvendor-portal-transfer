@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Vendor onboarding - approval level'
define view entity ZI_VP_OnbAprLevel
  as select from zvp_onb_aprlvl
{
  key level_no   as LevelNo,
      level_name as LevelName,
      is_active  as IsActive
}
