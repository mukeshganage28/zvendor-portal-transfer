@EndUserText.label: 'Current SAP Session User'
@ObjectModel.query.implementedBy: 'ABAP:ZCL_VP_SESSION_USER'
define custom entity ZCE_VP_SessionUser
{
  key UserId   : abap.char(12);
      DisplayName : abap.char(80);
}
