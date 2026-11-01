namespace CloudFactory.SalesConfigurator;

using Microsoft.Manufacturing.Document;

tableextension 91000 CF_ProductionOrder extends "Production Order"
{
    fields
    {
        field(91000; CF_DocumentType; Enum CF_ConfigDocumentType)
        {
            Caption = 'Configuration Document Type';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(91001; CF_SourceTableId; Integer)
        {
            Caption = 'Configuration Source Table ID';
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(91002; CF_SourceLineId; Guid)
        {
            Caption = 'Configuration Source Line ID';
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(91003; CF_DocumentNo; Code[20])
        {
            Caption = 'Configuration Document No.';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(91004; CF_DocumentLineNo; Integer)
        {
            Caption = 'Configuration Document Line No.';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(91005; CF_ParentItemNo; Code[20])
        {
            Caption = 'Configuration Parent Item No.';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(91006; CF_ParentVariantCode; Code[10])
        {
            Caption = 'Configuration Parent Variant Code';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(91007; CF_ConfigSnapshot; Blob)
        {
            Caption = 'Configuration Snapshot';
            DataClassification = CustomerContent;
        }
        field(91008; CF_ConfigVersion; Integer)
        {
            Caption = 'Configuration Version';
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(91009; CF_RebuildAllowed; Boolean)
        {
            Caption = 'Configuration Rebuild In Progress';
            DataClassification = SystemMetadata;
            Editable = false;
        }
    }
    keys
    {
        key(CF_Source; CF_SourceTableId, CF_SourceLineId, CF_ConfigVersion)
        {
        }
    }
}
