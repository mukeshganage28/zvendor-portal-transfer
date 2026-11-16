@EndUserText.label: 'Onboarding action parameter - approval'
define abstract entity ZA_VP_OnbApprove
{
  @EndUserText.label: 'BP Grouping'
  @UI.defaultValue: 'BP02'
  BusinessPartnerGrouping : abap.char(4);

  @EndUserText.label: 'BP Category (2 = Organization)'
  @UI.defaultValue: '2'
  BusinessPartnerCategory : abap.char(1);

  @EndUserText.label: 'Region (State)'
  @UI.defaultValue: 'MH'
  Region                  : abap.char(3);

  @EndUserText.label: 'Company Code'
  @UI.defaultValue: '1810'
  CompanyCode             : abap.char(4);

  @EndUserText.label: 'Reconciliation GL Account'
  @UI.defaultValue: '21311000'
  ReconciliationAccount   : abap.char(10);

  @EndUserText.label: 'Purchasing Organization'
  @UI.defaultValue: '1810'
  PurchasingOrganization  : abap.char(4);

  @EndUserText.label: 'Purchase Order Currency'
  @UI.defaultValue: 'INR'
  PurchaseOrderCurrency   : abap.cuky(5);

  @EndUserText.label: 'Payment Terms'
  @UI.defaultValue: '0001'
  PaymentTerms            : abap.char(4);

  @EndUserText.label: 'Comment'
  @UI.multiLineText: true
  Comment1                : abap.string(0);
}
