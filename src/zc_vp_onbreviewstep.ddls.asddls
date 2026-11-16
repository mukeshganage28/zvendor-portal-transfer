@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Vendor onboarding approval step (reviewer)'
@UI.headerInfo: { typeName: 'Approval Level', typeNamePlural: 'Approval Levels' }
@UI.presentationVariant: [{ sortOrder: [{ by: 'LevelNo', direction: #ASC }] }]
define view entity ZC_VP_OnbReviewStep
  as projection on ZI_VP_OnbAprStep
{
      @UI.hidden: true
  key StepUuid,
      @UI.hidden: true
      AppUuid,
      @UI.lineItem: [{ position: 10, label: 'Level' }]
      LevelNo,
      @UI.lineItem: [{ position: 20, label: 'Level Name' }]
      LevelName,
      @UI.lineItem: [{ position: 30, label: 'Status' }]
      StepStatus,
      @UI.lineItem: [{ position: 40, label: 'Decided By' }]
      DecidedBy,
      @UI.lineItem: [{ position: 50, label: 'Decided At' }]
      DecidedAt,
      @UI.lineItem: [{ position: 60, label: 'Comment' }]
      Comment1,
      @UI.hidden: true
      LocalLastChangedAt,

      _Application : redirected to parent ZC_VP_OnbReview
}
