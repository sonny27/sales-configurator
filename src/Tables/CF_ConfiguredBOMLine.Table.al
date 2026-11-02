namespace CloudFactory.SalesConfigurator;

using Microsoft.Foundation.Enums;
using Microsoft.Manufacturing.ProductionBOM;

table 91005 CF_ConfiguredBOMLine
{
    Caption = 'Configured BOM Preview Line';
    TableType = Temporary;
    DataClassification = CustomerContent;

    fields
    {
        // Matching standard field IDs allow copying BOM setup without running master-data validation.
        field(1; "Production BOM No."; Code[20]) { Caption = 'Production BOM No.'; }
        field(2; "Line No."; Integer) { Caption = 'Line No.'; }
        field(3; "Version Code"; Code[20]) { Caption = 'Version Code'; }
        field(10; Type; Enum "Production BOM Line Type") { Caption = 'Type'; }
        field(11; "No."; Code[20]) { Caption = 'No.'; }
        field(12; Description; Text[100]) { Caption = 'Description'; }
        field(13; "Unit of Measure Code"; Code[10]) { Caption = 'Unit of Measure Code'; }
        field(15; Position; Code[10]) { Caption = 'Position'; }
        field(16; "Position 2"; Code[10]) { Caption = 'Position 2'; }
        field(17; "Position 3"; Code[10]) { Caption = 'Position 3'; }
        field(18; "Lead-Time Offset"; DateFormula) { Caption = 'Lead-Time Offset'; }
        field(19; "Routing Link Code"; Code[10]) { Caption = 'Routing Link Code'; }
        field(20; "Scrap %"; Decimal) { Caption = 'Scrap %'; DecimalPlaces = 0 : 5; }
        field(21; "Variant Code"; Code[10]) { Caption = 'Variant Code'; }
        field(23; "Description 2"; Text[50]) { Caption = 'Description 2'; }
        field(28; "Starting Date"; Date) { Caption = 'Starting Date'; }
        field(29; "Ending Date"; Date) { Caption = 'Ending Date'; }
        field(40; Length; Decimal) { Caption = 'Length'; DecimalPlaces = 0 : 5; }
        field(41; Width; Decimal) { Caption = 'Width'; DecimalPlaces = 0 : 5; }
        field(42; Weight; Decimal) { Caption = 'Weight'; DecimalPlaces = 0 : 5; }
        field(43; Depth; Decimal) { Caption = 'Depth'; DecimalPlaces = 0 : 5; }
        field(44; "Calculation Formula"; Enum "Quantity Calculation Formula") { Caption = 'Calculation Formula'; }
        field(45; "Quantity per"; Decimal) { Caption = 'Quantity per'; DecimalPlaces = 0 : 5; }
        field(100; Configured; Boolean) { Caption = 'Configured Addition'; }
        field(101; "Configuration Option"; Code[10]) { Caption = 'Configuration Option'; }
        field(102; "Choice Code"; Code[20]) { Caption = 'Choice Code'; }
        field(103; Indentation; Integer) { Caption = 'Level'; }
        field(104; "Parent BOM Unit of Measure"; Code[10]) { Caption = 'Parent BOM Unit of Measure'; }
    }
    keys
    {
        key(PK; "Line No.") { Clustered = true; }
    }
}
