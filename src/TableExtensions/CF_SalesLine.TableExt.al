namespace CloudFactory.SalesConfigurator;

using Microsoft.Sales.Document;

tableextension 91002 CF_SalesLine extends "Sales Line"
{
    fields
    {
        field(91000; CF_ProductConfigurationNo; Code[100])
        {
            Caption = 'Product Configuration No.';
            DataClassification = CustomerContent;
            Editable = false;
            TableRelation = CF_ProductConfigHeader."No." where("Source Table ID" = const(37), "Source Line SystemId" = field(SystemId));
        }
    }
}
