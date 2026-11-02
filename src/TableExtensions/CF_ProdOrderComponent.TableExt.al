namespace CloudFactory.SalesConfigurator;

using Microsoft.Manufacturing.Document;

tableextension 91001 CF_ProdOrderComponent extends "Prod. Order Component"
{
    fields
    {
        field(91000; CF_ConfiguredComponent; Boolean)
        {
            Caption = 'Configured Component';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(91001; CF_ConfigSelectionId; Guid)
        {
            Caption = 'Configuration Selection ID';
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(91002; CF_ConfigOption; Code[10])
        {
            Caption = 'Configuration Option';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(91004; CF_ProductionBOMChoice; Boolean)
        {
            Caption = 'Exploded Configuration BOM Component';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(91005; CF_BOMNodeId; Guid)
        {
            Caption = 'Configuration BOM Node ID';
            DataClassification = SystemMetadata;
            Editable = false;
        }
    }
    keys
    {
        key(CF_Selection; Status, "Prod. Order No.", "Prod. Order Line No.", CF_ConfigSelectionId)
        {
        }
    }
}
