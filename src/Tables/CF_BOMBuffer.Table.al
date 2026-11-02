namespace CloudFactory.SalesConfigurator;

using Microsoft.Foundation.Enums;
using Microsoft.Inventory.BOM;
using Microsoft.Inventory.Item;
using Microsoft.Manufacturing.ProductionBOM;
using Microsoft.Manufacturing.MachineCenter;
using Microsoft.Manufacturing.WorkCenter;

table 91006 CF_BOMBuffer
{
    Caption = 'Configured BOM Buffer';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Source Line ID"; Guid) { Caption = 'Source Line ID'; }
        field(2; "Node ID"; Guid) { Caption = 'Node ID'; }
        field(3; "Parent Node ID"; Guid) { Caption = 'Parent Node ID'; }
        field(4; "Sort Order"; Integer) { Caption = 'Sort Order'; }
        field(5; Indentation; Integer) { Caption = 'Level'; }
        field(6; Type; Enum "BOM Type") { Caption = 'Type'; }
        field(7; "No."; Code[20])
        {
            Caption = 'No.';
            TableRelation = if (Type = const(Item)) Item
            else if (Type = const(CF_ProductionBOM)) "Production BOM Header"
            else if (Type = const("Work Center")) "Work Center"
            else if (Type = const("Machine Center")) "Machine Center";
        }
        field(8; Description; Text[100]) { Caption = 'Description'; }
        field(9; "Unit of Measure Code"; Code[10])
        {
            Caption = 'Unit of Measure Code';
            TableRelation = if (Type = const(Item)) "Item Unit of Measure".Code where("Item No." = field("No."));
        }
        field(10; "Variant Code"; Code[10])
        {
            Caption = 'Variant Code';
            TableRelation = if (Type = const(Item)) "Item Variant".Code where("Item No." = field("No."));
        }
        field(11; "Quantity per"; Decimal) { Caption = 'Quantity per Parent Base Unit'; DecimalPlaces = 0 : 5; }
        field(12; "Scrap %"; Decimal) { Caption = 'Scrap %'; DecimalPlaces = 0 : 5; MinValue = 0; }
        field(13; "Routing Link Code"; Code[10]) { Caption = 'Routing Link Code'; TableRelation = Microsoft.Manufacturing.Routing."Routing Link"; }
        field(14; "Calculation Formula"; Enum "Quantity Calculation Formula") { Caption = 'Calculation Formula'; }
        field(15; Length; Decimal) { Caption = 'Length'; DecimalPlaces = 0 : 5; }
        field(16; Width; Decimal) { Caption = 'Width'; DecimalPlaces = 0 : 5; }
        field(17; Depth; Decimal) { Caption = 'Depth'; DecimalPlaces = 0 : 5; }
        field(18; Weight; Decimal) { Caption = 'Weight'; DecimalPlaces = 0 : 5; }
        field(19; "Lead-Time Offset"; DateFormula) { Caption = 'Lead-Time Offset'; }
        field(20; Position; Code[10]) { Caption = 'Position'; }
        field(21; "Position 2"; Code[10]) { Caption = 'Position 2'; }
        field(22; "Position 3"; Code[10]) { Caption = 'Position 3'; }
        field(23; "Description 2"; Text[50]) { Caption = 'Description 2'; }
        field(24; "Configuration Option"; Code[10]) { Caption = 'Configuration Option'; }
        field(25; "Choice Code"; Code[20]) { Caption = 'Choice Code'; }
        field(26; "Selection ID"; Guid) { Caption = 'Selection ID'; }
        field(27; "Choice Root"; Boolean) { Caption = 'Choice Root'; }
        field(28; "Configuration No."; Code[100]) { Caption = 'Configuration No.'; }
        field(29; Revision; Integer) { Caption = 'Revision'; }
        field(30; "Source Context"; Text[250]) { Caption = 'Source Context'; }
        field(31; "Choice Signature"; Blob) { Caption = 'Choice Signature'; }
        field(32; "Generated Date"; Date) { Caption = 'Generated Date'; }
        field(33; "Location Code"; Code[10]) { Caption = 'Location Code'; }
        field(34; "Base BOM"; Code[20]) { Caption = 'Base BOM'; }
        field(35; "Base Routing"; Code[20]) { Caption = 'Base Routing'; }
        field(36; "Base Selection Set"; Boolean) { Caption = 'Base Selection Set'; }
        field(37; "Configurator Added"; Boolean) { Caption = 'Configurator Added'; }
        field(38; "Direct Addition"; Boolean) { Caption = 'Direct Addition'; }
    }
    keys
    {
        key(PK; "Source Line ID", "Node ID") { Clustered = true; }
        key(Tree; "Source Line ID", "Sort Order") { Unique = true; }
    }

    procedure IsComponent(): Boolean
    begin
        exit(Type in [Type::Item, Type::CF_ProductionBOM]);
    end;

    procedure OpenCard()
    var
        Item: Record Item;
        BOM: Record "Production BOM Header";
        WorkCenter: Record "Work Center";
        MachineCenter: Record "Machine Center";
    begin
        case Type of
            Type::Item:
                begin
                    Item.Get("No.");
                    Page.RunModal(Page::"Item Card", Item);
                end;
            Type::CF_ProductionBOM:
                begin
                    BOM.Get("No.");
                    Page.RunModal(Page::"Production BOM", BOM);
                end;
            Type::"Work Center":
                begin
                    WorkCenter.Get("No.");
                    Page.RunModal(Page::"Work Center Card", WorkCenter);
                end;
            Type::"Machine Center":
                begin
                    MachineCenter.Get("No.");
                    Page.RunModal(Page::"Machine Center Card", MachineCenter);
                end;
            else
                Error(UnsupportedCardTypeErr, Type);
        end;
    end;

    procedure CopyBOMFields(BOMLine: Record "Production BOM Line")
    begin
        "Routing Link Code" := BOMLine."Routing Link Code";
        "Calculation Formula" := BOMLine."Calculation Formula";
        Length := BOMLine.Length;
        Width := BOMLine.Width;
        Depth := BOMLine.Depth;
        Weight := BOMLine.Weight;
        "Scrap %" := BOMLine."Scrap %";
        "Lead-Time Offset" := BOMLine."Lead-Time Offset";
        Position := BOMLine.Position;
        "Position 2" := BOMLine."Position 2";
        "Position 3" := BOMLine."Position 3";
        "Description 2" := BOMLine."Description 2";
    end;

    var
        UnsupportedCardTypeErr: Label 'Cannot open a card for BOM row type %1.', Comment = '%1 = BOM row type';
}
