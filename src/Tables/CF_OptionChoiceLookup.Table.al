namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;
using Microsoft.Manufacturing.ProductionBOM;
using Microsoft.Foundation.UOM;

table 91001 CF_OptionChoiceLookup
{
    Caption = 'Configurator Choices';
    DataClassification = CustomerContent;
    LookupPageId = CF_OptionChoiceLookup;
    DrillDownPageId = CF_OptionChoiceLookup;
    fields
    {
        field(1; "Item Category Code"; Code[20])
        {
            Caption = 'Template Code';
            TableRelation = CF_ConfigTemplate;
            NotBlank = true;
        }
        field(2; "Configuration Option"; Code[10])
        {
            Caption = 'Configuration Option';
            TableRelation = CF_ConfiguratorBOM."Configuration Option" where("Item Category Code" = field("Item Category Code"));
            NotBlank = true;
        }
        field(3; Code; Code[20])
        {
            Caption = 'Choice Code';
            NotBlank = true;
        }
        field(4; "Item No."; Code[20])
        {
            Caption = 'No.';
            TableRelation = if (Type = const(Item)) Item where(Type = filter(Inventory | "Non-Inventory"))
            else if (Type = const("Production BOM")) "Production BOM Header";
            NotBlank = true;
            trigger OnValidate()
            var
                Item: Record Item;
                BOMHeader: Record "Production BOM Header";
                Mgt: Codeunit CF_DocumentConfigMgt;
            begin
                "Variant Code" := '';
                if Type = Type::"Production BOM" then begin
                    BOMHeader.Get("Item No.");
                    "Unit of Measure Code" := BOMHeader."Unit of Measure Code";
                end else begin
                    Item.Get("Item No.");
                    Mgt.ValidateItem("Item No.", '', Item."Base Unit of Measure");
                    "Unit of Measure Code" := Item."Base Unit of Measure";
                end;
                if (Description = '') or ("Item No." <> xRec."Item No.") then
                    if Type = Type::"Production BOM" then
                        Description := BOMHeader.Description
                    else
                        Description := Item.Description;
            end;
        }
        field(5; Description; Text[250])
        {
            Caption = 'Description';
        }
        field(6; "Variant Code"; Code[10])
        {
            Caption = 'Variant Code';
            TableRelation = "Item Variant".Code where("Item No." = field("Item No."));
            trigger OnValidate()
            begin
                CheckMapping();
            end;
        }
        field(7; "Unit of Measure Code"; Code[10])
        {
            Caption = 'Unit of Measure Code';
            TableRelation = if (Type = const(Item)) "Item Unit of Measure".Code where("Item No." = field("Item No."))
            else "Unit of Measure";
            trigger OnValidate()
            begin
                CheckMapping();
            end;
        }
        field(8; "Display Order"; Integer)
        {
            Caption = 'Display Order';
        }
        field(9; Selectable; Boolean)
        {
            Caption = 'Selectable';
            InitValue = true;
        }
        field(10; "Mandatory Values"; Enum CF_MandatoryValues)
        {
            Caption = 'Mandatory Values (Legacy)';
            Editable = false;
            InitValue = ChoiceCode;
        }
        field(11; Type; Enum "Production BOM Line Type")
        {
            Caption = 'Type';
            InitValue = Item;
            ValuesAllowed = 1, 2;
            trigger OnValidate()
            begin
                if Type <> xRec.Type then begin
                    Clear("Item No.");
                    Clear("Variant Code");
                    Clear("Unit of Measure Code");
                    Clear(Description);
                end;
            end;
        }
        field(12; "Quantity per Unit"; Decimal)
        {
            Caption = 'Default Quantity';
            InitValue = 1;
            DecimalPlaces = 0 : 5;
            MinValue = 0;
            trigger OnValidate()
            begin
                if "Quantity per Unit" < 0 then
                    FieldError("Quantity per Unit", NonnegativeQuantityErr);
                if "Quantity per Unit" = 0 then
                    CheckQuantitySetup()
                else
                    CheckQuantity("Quantity per Unit");
            end;
        }
        field(13; "Min. Max. Quantity Behavior"; Enum CF_MinMaxQtyBehavior)
        {
            Caption = 'Min. Max. Quantity Behavior';
            InitValue = NotEnabled;
        }
        field(14; "Minimum Quantity"; Decimal)
        {
            Caption = 'Minimum Quantity';
            DecimalPlaces = 0 : 5;
            MinValue = 0;
        }
        field(15; "Maximum Quantity"; Decimal)
        {
            Caption = 'Maximum Quantity';
            DecimalPlaces = 0 : 5;
            MinValue = 0;
        }
    }
    keys
    {
        key(PK; "Item Category Code", "Configuration Option", Code) { Clustered = true; }
        key(Display; "Item Category Code", "Configuration Option", "Display Order", Code) { }
    }
    trigger OnInsert()
    begin
        CheckSetup();
    end;

    trigger OnModify()
    begin
        CheckSetup();
        if not Selectable then
            CheckNotDefault();
    end;

    trigger OnDelete()
    begin
        CheckNotDefault();
    end;

    trigger OnRename()
    begin
        Error('Choice identifiers cannot be renamed. Create a new choice instead.');
    end;

    procedure RequiresQuantity(): Boolean
    var
        OptionSetup: Record CF_ConfiguratorBOM;
    begin
        OptionSetup.Get("Item Category Code", "Configuration Option");
        exit(OptionSetup.RequiresQuantity());
    end;

    procedure CheckQuantity(Quantity: Decimal)
    begin
        CheckQuantitySetup();
        if Quantity <= 0 then
            Error(PositiveQuantityErr, Code, "Configuration Option");
        if ChecksMinimum() and (Quantity < "Minimum Quantity") then
            Error(MinimumQuantityErr, Code, "Configuration Option", Quantity, "Minimum Quantity");
        if ChecksMaximum() and (Quantity > "Maximum Quantity") then
            Error(MaximumQuantityErr, Code, "Configuration Option", Quantity, "Maximum Quantity");
    end;

    local procedure ChecksMinimum(): Boolean
    begin
        exit("Min. Max. Quantity Behavior" in [CF_MinMaxQtyBehavior::MinAndMax, CF_MinMaxQtyBehavior::MinOnly]);
    end;

    local procedure ChecksMaximum(): Boolean
    begin
        exit("Min. Max. Quantity Behavior" in [CF_MinMaxQtyBehavior::MinAndMax, CF_MinMaxQtyBehavior::MaxOnly]);
    end;

    local procedure CheckQuantitySetup()
    begin
        if "Minimum Quantity" < 0 then
            FieldError("Minimum Quantity", NonnegativeQuantityErr);
        if "Maximum Quantity" < 0 then
            FieldError("Maximum Quantity", NonnegativeQuantityErr);
        if ChecksMaximum() and ("Maximum Quantity" = 0) then
            FieldError("Maximum Quantity", PositiveMaximumErr);
        if ChecksMinimum() and ChecksMaximum() and ("Minimum Quantity" > "Maximum Quantity") then
            FieldError("Minimum Quantity", MinimumExceedsMaximumErr);
    end;

    local procedure CheckSetup()
    var
        OptionSetup: Record CF_ConfiguratorBOM;
        Item: Record Item;
        BOMHeader: Record "Production BOM Header";
    begin
        TestField("Item Category Code");
        TestField("Configuration Option");
        TestField(Code);
        OptionSetup.Get("Item Category Code", "Configuration Option");
        Validate("Quantity per Unit");
        if "Unit of Measure Code" = '' then begin
            if Type = Type::"Production BOM" then begin
                BOMHeader.Get("Item No.");
                "Unit of Measure Code" := BOMHeader."Unit of Measure Code";
            end else begin
                Item.Get("Item No.");
                "Unit of Measure Code" := Item."Base Unit of Measure";
            end;
        end;
        CheckMapping();
    end;

    procedure CheckMapping()
    var
        Mgt: Codeunit CF_DocumentConfigMgt;
        BOMHeader: Record "Production BOM Header";
        UnitOfMeasure: Record "Unit of Measure";
    begin
        if not (Type in [Type::Item, Type::"Production BOM"]) then
            FieldError(Type, 'must be Item or Production BOM');
        if Type = Type::"Production BOM" then begin
            BOMHeader.Get("Item No.");
            TestField("Variant Code", '');
            TestField("Unit of Measure Code");
            UnitOfMeasure.Get("Unit of Measure Code");
        end else
            Mgt.ValidateItem("Item No.", "Variant Code", "Unit of Measure Code");
    end;

    local procedure CheckNotDefault()
    var
        OptionSetup: Record CF_ConfiguratorBOM;
    begin
        if OptionSetup.Get("Item Category Code", "Configuration Option") then
            if OptionSetup."Default Choice Code" = Code then
                Error('Choice %1 is the default for category %2, option %3. Clear or change the default before deleting or disabling this choice.',
                    Code, "Item Category Code", "Configuration Option");
    end;

    var
        PositiveQuantityErr: Label 'Quantity per unit must be positive for choice %1, option %2.', Comment = '%1 = choice code, %2 = configuration option';
        NonnegativeQuantityErr: Label 'must be zero or positive';
        PositiveMaximumErr: Label 'must be positive when maximum checking is enabled';
        MinimumExceedsMaximumErr: Label 'must not exceed Maximum Quantity when checking both limits';
        MinimumQuantityErr: Label 'Choice %1, option %2: quantity per finished base unit %3 is below the minimum quantity %4.', Comment = '%1 = choice code, %2 = configuration option, %3 = entered quantity, %4 = minimum quantity';
        MaximumQuantityErr: Label 'Choice %1, option %2: quantity per finished base unit %3 exceeds the maximum quantity %4.', Comment = '%1 = choice code, %2 = configuration option, %3 = entered quantity, %4 = maximum quantity';
}
