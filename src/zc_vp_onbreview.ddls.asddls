// Procurement reviewer projection of the onboarding BO.
// No DCL on purpose: reviewers must see ALL applications (the vendor projection
// ZC_VP_OnbApplication stays restricted to the applicant's own row).
// Access to this service is controlled by its IAM app / business catalog,
// which you assign only to the procurement (reviewer) business role.
@AccessControl.authorizationCheck: #NOT_ALLOWED
@EndUserText.label: 'Vendor onboarding application (reviewer)'
@Metadata.allowExtensions: true
define root view entity ZC_VP_OnbReview
  provider contract transactional_query
  as projection on ZI_VP_OnbApplication
{
  key AppUuid,
      ApplicationId,
      ApplicantUser,
      Status,
      CurrentStep,
      CompanyName,
      ContactPerson,
      Email,
      Phone,
      LegalName,
      @ObjectModel.text.element: ['CompanyTypeText']
      CompanyType,
      _CompanyType.Description as CompanyTypeText,
      AddressLine,
      City,
      Region,
      Country,
      PostalCode,
      Gstin,
      Pan,
      MsmeNumber,
      BankName,
      AccountHolderName,
      BankAccountNumber,
      Ifsc,
      SubmittedAt,
      ReviewedBy,
      ReviewedAt,
      ReviewComment,
      Supplier,
      CurrentLevel,
      _CurrentLevel.LevelName as CurrentLevelName,
      TotalLevels,
      _MyApproval.IsMine      as IsPendingWithMe,
_LaterLevel.HasLaterLevel as HasLaterLevel,      
      LocalCreatedBy,
      LocalCreatedAt,
      LocalLastChangedBy,
      LocalLastChangedAt,
      LastChangedAt,

      _Document : redirected to composition child ZC_VP_OnbReviewDoc,
      _History      : redirected to composition child ZC_VP_OnbReviewHist,
      _ApprovalStep : redirected to composition child ZC_VP_OnbReviewStep,
      _CompanyType,
      _CurrentLevel
}
where Status <> 'Draft'
