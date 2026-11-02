namespace CloudFactory.SalesConfigurator;

using Microsoft.Manufacturing.Document;

tableextension 91003 CF_ProdOrderLine extends "Prod. Order Line"
{
    fields
    {
        field(91000; CF_BOMNodeId; Guid)
        {
            Caption = 'Configuration BOM Node ID';
            DataClassification = SystemMetadata;
            Editable = false;
        }
    }
}
