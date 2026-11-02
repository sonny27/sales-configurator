namespace CloudFactory.SalesConfigurator;

enum 91004 CF_MaterialReceiptPolicy
{
    Extensible = false;

    value(0; OnTime) { Caption = 'Receipts by Required Date'; }
    value(1; AllReceipts) { Caption = 'All Outstanding Purchase/Transfer Receipts'; }
}
