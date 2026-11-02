namespace CloudFactory.SalesConfigurator;

using Microsoft.Sales.Document;

tableextension 91002 CF_SalesLine extends "Sales Line"
{
    fields
    {
        field(91001; CF_BaseBOMNo; Code[20])
        {
            Caption = 'Base BOM';
            DataClassification = CustomerContent;
            TableRelation = Microsoft.Manufacturing.ProductionBOM."Production BOM Header";
        }
        field(91002; CF_BaseRoutingNo; Code[20])
        {
            Caption = 'Base Routing';
            DataClassification = CustomerContent;
            TableRelation = Microsoft.Manufacturing.Routing."Routing Header";
        }
        field(91003; CF_BaseSetupSet; Boolean)
        {
            Caption = 'Base Manufacturing Selection Set';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(91000; CF_ProductConfigurationNo; Code[100])
        {
            Caption = 'Product Configuration No.';
            DataClassification = CustomerContent;
            Editable = false;
            TableRelation = CF_ProductConfigHeader."No." where("Source Table ID" = const(37), "Source Line SystemId" = field(SystemId));
        }
    }
}
