namespace CloudFactory.SalesConfigurator;

table 91008 CF_PromiseContext
{
    Caption = 'Configured Order Promising Context';
    DataClassification = CustomerContent;
    fields
    {
        field(1; ID; Guid) { Caption = 'ID'; }
        field(2; "Source Line ID"; Guid) { Caption = 'Source Line ID'; }
        field(3; "Document No."; Code[20]) { Caption = 'Document No.'; }
        field(4; "Document Line No."; Integer) { Caption = 'Document Line No.'; }
        field(5; "Parent Item No."; Code[20]) { Caption = 'Parent Item No.'; }
        field(6; "Parent Variant Code"; Code[10]) { Caption = 'Parent Variant Code'; }
        field(7; Snapshot; Blob) { Caption = 'Snapshot'; }
    }
    keys
    {
        key(PK; ID) { Clustered = true; }
    }
}
