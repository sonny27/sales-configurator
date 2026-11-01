namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;
using Microsoft.Manufacturing.Routing;

table 91002 CF_DocumentLineProductConfig
{
    Caption = 'Document Line Product Configuration';
    DataClassification = CustomerContent;
    fields
    {
        field(1; "Document Type"; Enum CF_ConfigDocumentType) { Caption = 'Document Type'; }
        field(2; "Source Table ID"; Integer) { Caption = 'Source Table ID'; Editable = false; }
        field(3; "Document No."; Code[20]) { Caption = 'Document No.'; Editable = false; }
        field(4; "Document Line No."; Integer) { Caption = 'Document Line No.'; Editable = false; }
        field(5; "Source Line SystemId"; Guid) { Caption = 'Source Line SystemId'; Editable = false; }
        field(6; "Item Category Code"; Code[20]) { Caption = 'Item Category Code'; Editable = false; TableRelation = "Item Category"; }
        field(7; "Parent Item No."; Code[20]) { Caption = 'Parent Item No.'; Editable = false; TableRelation = Item; }
        field(8; "Parent Variant Code"; Code[10]) { Caption = 'Parent Variant Code'; Editable = false; }
        field(9; "Configuration Option"; Code[10]) { Caption = 'Configuration Option'; Editable = false; }
        field(10; "Option Description"; Text[250]) { Caption = 'Option Description'; Editable = false; }
        field(11; "Choice Code"; Code[20])
        {
            Caption = 'Choice Code';
            TableRelation = CF_OptionChoiceLookup.Code where("Item Category Code" = field("Item Category Code"), "Configuration Option" = field("Configuration Option"), Selectable = const(true));
            ValidateTableRelation = false;
            trigger OnValidate()
            var
                Mgt: Codeunit CF_DocumentConfigMgt;
            begin
                Mgt.ValidateChoice(Rec);
            end;
        }
        field(12; "Component Item No."; Code[20]) { Caption = 'Component Item No.'; Editable = false; TableRelation = Item; }
        field(13; "Component Variant Code"; Code[10]) { Caption = 'Component Variant Code'; Editable = false; }
        field(14; "Component UOM Code"; Code[10]) { Caption = 'Component UOM Code'; Editable = false; }
        field(15; "Quantity per Unit"; Decimal)
        {
            Caption = 'Quantity per Finished Base Unit';
            InitValue = 1;
            DecimalPlaces = 0 : 5;
            trigger OnValidate()
            begin
                if "Quantity per Unit" <= 0 then
                    Error('Quantity per unit must be positive for option %1.', "Configuration Option");
            end;
        }
        field(16; "Routing Link Code"; Code[10])
        {
            Caption = 'Routing Link Code';
            TableRelation = "Routing Link";
            trigger OnValidate()
            var
                Mgt: Codeunit CF_DocumentConfigMgt;
            begin
                Mgt.ValidateConfigRoutingLink(Rec);
            end;
        }
        field(17; "Display Order"; Integer) { Caption = 'Display Order'; Editable = false; }
        field(18; "Configuration No."; Code[100])
        {
            Caption = 'Configuration No.';
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = lookup(CF_ProductConfigHeader."No." where("Document Type" = field("Document Type"),
                "Source Table ID" = field("Source Table ID"), "Source Line SystemId" = field("Source Line SystemId")));
        }
    }
    keys
    {
        key(PK; "Document Type", "Source Table ID", "Source Line SystemId", "Configuration Option") { Clustered = true; }
        key(Document; "Document Type", "Source Table ID", "Document No.", "Document Line No.") { }
        key(Display; "Document Type", "Source Table ID", "Source Line SystemId", "Display Order", "Configuration Option") { }
    }
    trigger OnInsert()
    begin
        CheckStoredRow();
    end;

    trigger OnModify()
    begin
        CheckStoredRow();
    end;

    trigger OnDelete()
    var
        Mgt: Codeunit CF_DocumentConfigMgt;
    begin
        if not IsTemporary() then
            Mgt.EnsureConfigEditable(Rec);
    end;

    trigger OnRename()
    begin
        Error('Configuration identity cannot be renamed.');
    end;

    procedure GetStyleText(): Text
    begin
        if RequiresChoice() then begin
            if ("Choice Code" = '') or (RequiresQuantity() and ("Quantity per Unit" <= 0)) then
                exit(Format(PageStyle::Unfavorable));
            exit(Format(PageStyle::Favorable));
        end;
        exit(Format(PageStyle::Standard));
    end;

    procedure RequiresChoice(): Boolean
    var
        OptionSetup: Record CF_ConfiguratorBOM;
    begin
        if OptionSetup.Get("Item Category Code", "Configuration Option") then
            exit(OptionSetup.Enabled and OptionSetup.RequiresChoice());
        exit(false);
    end;

    procedure RequiresQuantity(): Boolean
    var
        OptionSetup: Record CF_ConfiguratorBOM;
        Choice: Record CF_OptionChoiceLookup;
    begin
        if not OptionSetup.Get("Item Category Code", "Configuration Option") then
            exit(false);
        if not OptionSetup.Enabled then
            exit(false);
        if Choice.Get("Item Category Code", "Configuration Option", "Choice Code") then
            exit(Choice.Selectable and Choice.RequiresQuantity());
        exit(false);
    end;

    local procedure CheckStoredRow()
    var
        Mgt: Codeunit CF_DocumentConfigMgt;
    begin
        if not IsTemporary() then begin
            Mgt.EnsureConfigEditable(Rec);
            Mgt.ValidateStoredRow(Rec);
        end;
    end;
}
