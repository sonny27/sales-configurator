namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;

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
            Caption = 'Item Category Code';
            TableRelation = "Item Category";
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
            Caption = 'Item No.';
            TableRelation = Item where(Type = const(Inventory));
            NotBlank = true;
            trigger OnValidate()
            var
                Item: Record Item;
                Mgt: Codeunit CF_DocumentConfigMgt;
            begin
                Item.Get("Item No.");
                Mgt.ValidateItem("Item No.", '', Item."Base Unit of Measure");
                "Variant Code" := '';
                "Unit of Measure Code" := Item."Base Unit of Measure";
                if (Description = '') or ("Item No." <> xRec."Item No.") then
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
            TableRelation = "Item Unit of Measure".Code where("Item No." = field("Item No."));
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
            Caption = 'Mandatory Values';
            InitValue = ChoiceCode;
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
    begin
        exit("Mandatory Values" = CF_MandatoryValues::ChoiceCodeAndQuantity);
    end;

    local procedure CheckSetup()
    var
        OptionSetup: Record CF_ConfiguratorBOM;
        Item: Record Item;
    begin
        TestField("Item Category Code");
        TestField("Configuration Option");
        TestField(Code);
        OptionSetup.Get("Item Category Code", "Configuration Option");
        if "Unit of Measure Code" = '' then begin
            Item.Get("Item No.");
            "Unit of Measure Code" := Item."Base Unit of Measure";
        end;
        CheckMapping();
    end;

    local procedure CheckMapping()
    var
        Mgt: Codeunit CF_DocumentConfigMgt;
    begin
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
}
