namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;
using Microsoft.Manufacturing.Routing;

table 91000 CF_ConfiguratorBOM
{
    Caption = 'Configurator Options';
    DataClassification = CustomerContent;
    LookupPageId = CF_ConfiguratorBOMSetup;
    DrillDownPageId = CF_ConfiguratorBOMSetup;

    fields
    {
        field(1; "Item Category Code"; Code[20])
        {
            Caption = 'Item Category Code';
            TableRelation = "Item Category";
            NotBlank = true;
        }
        field(2; "Configuration Option"; Code[10])
        {
            Caption = 'Configuration Option';
            NotBlank = true;
        }
        field(3; "Option Description"; Text[250])
        {
            Caption = 'Option Description';
        }
        field(4; "Quantity per Unit"; Decimal)
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
        field(5; "Display Order"; Integer)
        {
            Caption = 'Display Order';
        }
        field(6; Mandatory; Boolean)
        {
            Caption = 'Mandatory (Legacy)';
            Editable = false;
        }
        field(7; Enabled; Boolean)
        {
            Caption = 'Enabled';
            InitValue = true;
        }
        field(8; "Routing Link Code"; Code[10])
        {
            Caption = 'Routing Link Code';
            TableRelation = "Routing Link";
        }
        field(9; "Default Choice Code"; Code[20])
        {
            Caption = 'Default Choice Code';
            TableRelation = CF_OptionChoiceLookup.Code where("Item Category Code" = field("Item Category Code"), "Configuration Option" = field("Configuration Option"), Selectable = const(true));
            trigger OnValidate()
            begin
                CheckDefaultChoice();
            end;
        }
    }
    keys
    {
        key(PK; "Item Category Code", "Configuration Option") { Clustered = true; }
        key(Display; "Item Category Code", "Display Order", "Configuration Option") { }
    }
    trigger OnInsert()
    begin
        CheckSetup();
    end;

    trigger OnModify()
    begin
        CheckSetup();
    end;

    trigger OnDelete()
    var
        Choice: Record CF_OptionChoiceLookup;
    begin
        Choice.SetRange("Item Category Code", "Item Category Code");
        Choice.SetRange("Configuration Option", "Configuration Option");
        if not Choice.IsEmpty() then
            Error('Delete the choices for category %1, option %2 before deleting the option.', "Item Category Code", "Configuration Option");
    end;

    trigger OnRename()
    begin
        Error('Configuration option identifiers cannot be renamed. Create a new option instead.');
    end;

    procedure RequiresChoice(): Boolean
    var
        Choice: Record CF_OptionChoiceLookup;
    begin
        Choice.SetRange("Item Category Code", "Item Category Code");
        Choice.SetRange("Configuration Option", "Configuration Option");
        Choice.SetRange(Selectable, true);
        Choice.SetFilter("Mandatory Values", '<>%1', CF_MandatoryValues::None);
        exit(not Choice.IsEmpty());
    end;

    local procedure CheckSetup()
    var
        Category: Record "Item Category";
        RoutingLink: Record "Routing Link";
    begin
        TestField("Item Category Code");
        TestField("Configuration Option");
        Category.Get("Item Category Code");
        Validate("Quantity per Unit");
        if "Routing Link Code" <> '' then
            RoutingLink.Get("Routing Link Code");
        CheckDefaultChoice();
    end;

    local procedure CheckDefaultChoice()
    var
        Choice: Record CF_OptionChoiceLookup;
        Mgt: Codeunit CF_DocumentConfigMgt;
    begin
        if "Default Choice Code" = '' then
            exit;
        if not Choice.Get("Item Category Code", "Configuration Option", "Default Choice Code") then
            Error('Default choice %1 does not exist for category %2, option %3.', "Default Choice Code", "Item Category Code", "Configuration Option");
        Choice.TestField(Selectable, true);
        Mgt.ValidateItem(Choice."Item No.", Choice."Variant Code", Choice."Unit of Measure Code");
    end;
}
