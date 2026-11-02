namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;

table 91007 CF_ConfigTemplate
{
    Caption = 'Configuration Template';
    DataClassification = CustomerContent;
    LookupPageId = CF_ConfigTemplates;
    DrillDownPageId = CF_ConfigTemplates;
    fields
    {
        field(1; Code; Code[20]) { Caption = 'Template Code'; NotBlank = true; }
        field(2; Description; Text[100]) { Caption = 'Description'; }
        field(3; "Template Type"; Enum CF_TemplateAssignment) { Caption = 'Template Type'; }
        field(4; "Item No."; Code[20]) { Caption = 'Item No.'; TableRelation = Item where(Type = const(Inventory)); }
        field(5; "Item Category Code"; Code[20]) { Caption = 'Item Category Code'; TableRelation = "Item Category"; }
    }
    keys
    {
        key(PK; Code) { Clustered = true; }
        key(Assignment; "Template Type", "Item No.", "Item Category Code") { Unique = true; }
    }
    trigger OnInsert()
    begin
        if IsTemporary() then
            exit;
        CheckAssignment();
        if Code = '' then
            Code := GetAssignmentNo();
        TestField(Code);
    end;

    trigger OnModify()
    begin
        if IsTemporary() then
            exit;
        if (Code <> xRec.Code) or ("Template Type" <> xRec."Template Type") or
           ("Item No." <> xRec."Item No.") or ("Item Category Code" <> xRec."Item Category Code")
        then
            Error('Template identity and assignment cannot be changed. Copy the template to a new assignment instead.');
        CheckAssignment();
    end;

    trigger OnRename()
    begin
        if IsTemporary() then
            exit;
        Error('Template codes cannot be renamed. Copy the template instead.');
    end;

    trigger OnDelete()
    var
        Options: Record CF_ConfiguratorBOM;
        Choices: Record CF_OptionChoiceLookup;
        Config: Record CF_ProductConfigHeader;
    begin
        if IsTemporary() then
            exit;
        Options.SetRange("Item Category Code", Code);
        Choices.SetRange("Item Category Code", Code);
        if not Options.IsEmpty() or not Choices.IsEmpty() then
            Error('Delete all options and choices before deleting template %1.', Code);
        Config.SetRange("Template Code", Code);
        if not Config.IsEmpty() then
            Error('Template %1 is referenced by saved configurations and cannot be deleted.', Code);
    end;

    procedure CheckAssignment()
    var
        Item: Record Item;
        Category: Record "Item Category";
    begin
        case "Template Type" of
            "Template Type"::SalesLineItem:
                begin
                    TestField("Item No.");
                    TestField("Item Category Code", '');
                    Item.Get("Item No.");
                    Item.TestField(Type, Item.Type::Inventory);
                    if Description = '' then
                        Description := Item.Description;
                end;
            "Template Type"::ItemCategory:
                begin
                    TestField("Item Category Code");
                    TestField("Item No.", '');
                    Category.Get("Item Category Code");
                    if Description = '' then
                        Description := Category.Description;
                end;
        end;
    end;

    procedure GetAssignmentNo(): Code[20]
    begin
        if "Template Type" = "Template Type"::SalesLineItem then
            exit("Item No.");
        exit("Item Category Code");
    end;
}
