@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Approval step'
define view entity ZI_VP_OnbAprStep
  as select from zvp_onb_aprstep
  association to parent ZI_VP_OnbApplication as _Application
    on $projection.AppUuid = _Application.AppUuid
{
  key step_uuid             as StepUuid,
      app_uuid              as AppUuid,
      level_no              as LevelNo,
      level_name            as LevelName,
      step_status           as StepStatus,
      decided_by            as DecidedBy,
      decided_at            as DecidedAt,
      comment1              as Comment1,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,

      _Application
}
