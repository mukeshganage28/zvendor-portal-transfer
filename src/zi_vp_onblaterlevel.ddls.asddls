@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'ZI_VP_OnbLaterLevel'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_VP_OnbLaterLevel
  as select from zvp_onb_aprstep as Step
    inner join   zvp_onb_app     as App on  App.app_uuid      = Step.app_uuid
                                         and Step.level_no     > App.current_level
{
  key Step.app_uuid                                as AppUuid,
      cast( 'X' as abap_boolean preserving type )  as HasLaterLevel
}
where App.current_level <> '00'
group by Step.app_uuid
