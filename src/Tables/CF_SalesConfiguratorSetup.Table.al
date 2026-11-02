namespace CloudFactory.SalesConfigurator;

using Microsoft.Foundation.NoSeries;
using Microsoft.Manufacturing.Document;

table 91004 CF_SalesConfiguratorSetup
{
    Caption = 'Sales Configurator Setup';
    DataClassification = CustomerContent;
    LookupPageId = CF_SalesConfiguratorSetup;
    DrillDownPageId = CF_SalesConfiguratorSetup;
    fields
    {
        field(1; "Primary Key"; Code[10]) { Caption = 'Primary Key'; Editable = false; }
        field(2; "Product Configuration Nos."; Code[20])
        {
            Caption = 'Product Configuration Nos. (Legacy)';
            Editable = false;
            TableRelation = "No. Series" where("Default Nos." = const(true));
        }
        field(3; "Default Prod. Order Status"; Enum "Create Production Order Status")
        {
            Caption = 'Default Production Order Status';
            InitValue = "Firm Planned";
            ValuesAllowed = 1, 2, 3;
            trigger OnValidate()
            begin
                CheckProductionOrderStatus();
            end;
        }
        field(4; Enable; Boolean)
        {
            Caption = 'Enable';
            InitValue = false;
        }
        field(5; "Config. Template Assign By"; Enum CF_TemplateAssignment)
        {
            Caption = 'Config. Template Assign By';
            InitValue = ItemCategory;
        }
        field(6; "Material Receipt Policy"; Enum CF_MaterialReceiptPolicy)
        {
            Caption = 'Material Receipt Policy';
            InitValue = OnTime;
        }
    }
    keys
    {
        key(PK; "Primary Key") { Clustered = true; }
    }
    trigger OnInsert()
    begin
        TestField("Primary Key", '');
        CheckProductionOrderStatus();
    end;

    trigger OnModify()
    begin
        CheckProductionOrderStatus();
    end;

    trigger OnRename()
    begin
        Error(SingletonRenameErr);
    end;

    procedure CheckProductionOrderStatus()
    begin
        if not ("Default Prod. Order Status" in ["Default Prod. Order Status"::Planned,
            "Default Prod. Order Status"::"Firm Planned", "Default Prod. Order Status"::Released])
        then
            Error(InvalidProductionStatusErr);
    end;

    var
        SingletonRenameErr: Label 'The Sales Configurator Setup primary key cannot be renamed.';
        InvalidProductionStatusErr: Label 'Default Production Order Status must be Planned, Firm Planned, or Released.';
}
