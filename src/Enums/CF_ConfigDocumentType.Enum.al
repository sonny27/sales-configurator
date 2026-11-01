namespace CloudFactory.SalesConfigurator;

enum 91000 CF_ConfigDocumentType
{
    Extensible = true;

    value(0; SalesOrder)
    {
        Caption = 'Sales Order';
    }
    value(1; SalesQuote)
    {
        Caption = 'Sales Quote';
    }
}
