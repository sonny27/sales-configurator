namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Purchases.Vendor;

table 91009 CF_MaterialSupplyLine
{
    Caption = 'Configured Material Supply';
    TableType = Temporary;
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Node ID"; Guid) { Caption = 'Node ID'; }
        field(2; "Parent Node ID"; Guid) { Caption = 'Parent Node ID'; }
        field(3; Selected; Boolean) { Caption = 'Selected'; InitValue = true; }
        field(4; "Item No."; Code[20]) { Caption = 'Item No.'; TableRelation = Item; }
        field(5; Description; Text[100]) { Caption = 'Description'; }
        field(6; "Variant Code"; Code[10])
        {
            Caption = 'Variant Code';
            TableRelation = "Item Variant".Code where("Item No." = field("Item No."));
        }
        field(7; "Location Code"; Code[10]) { Caption = 'Location Code'; TableRelation = Location; }
        field(8; "Required Date"; Date) { Caption = 'Required Date'; }
        field(9; "Unit of Measure Code"; Code[10]) { Caption = 'Base Unit of Measure'; }
        field(10; "Required Quantity"; Decimal) { Caption = 'Required Quantity (Base)'; DecimalPlaces = 0 : 5; }
        field(11; "Covered Quantity"; Decimal) { Caption = 'Covered Quantity (Base)'; DecimalPlaces = 0 : 5; }
        field(12; "Shortage Quantity"; Decimal) { Caption = 'Shortage Quantity (Base)'; DecimalPlaces = 0 : 5; }
        field(13; "Replenishment System"; Enum "SKU Replenishment System") { Caption = 'Replenishment System'; }
        field(14; "Vendor No."; Code[20]) { Caption = 'Vendor No.'; TableRelation = Vendor; }
        field(15; "Transfer-from Code"; Code[10])
        {
            Caption = 'Transfer-from Code';
            TableRelation = Location where("Use As In-Transit" = const(false));
        }
        field(16; Processed; Boolean) { Caption = 'Processed'; }
    }

    keys
    {
        key(PK; "Node ID") { Clustered = true; }
        key(ItemDate; "Item No.", "Required Date", "Variant Code", "Location Code") { }
    }
}
