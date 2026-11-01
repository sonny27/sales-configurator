namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Sales.Document;

page 91003 CF_CategoryTemplateDesigner
{
    Caption = 'Category Template Designer';
    PageType = Card;
    SourceTable = "Item Category";
    SourceTableTemporary = true;
    InsertAllowed = false;
    DeleteAllowed = false;
    ApplicationArea = All;
    UsageCategory = Administration;

    layout
    {
        area(Content)
        {
            group(Category)
            {
                Caption = 'Item Category';
                field(ItemCategoryCode; SelectedCategory)
                {
                    Caption = 'Item Category Code';
                    ApplicationArea = All;
                    Editable = not FromSalesLine;
                    TableRelation = "Item Category";
                    ToolTip = 'Select the category whose shared default template you want to maintain. This does not change any item or sales line.';
                    trigger OnValidate()
                    var
                        ItemCategory: Record "Item Category";
                    begin
                        ItemCategory.Get(SelectedCategory);
                        if Rec.Code <> '' then
                            Rec.Delete(false);
                        Rec := ItemCategory;
                        Rec.Insert(false);
                        Clear(ReferenceItemNo);
                        Clear(ReferenceLocationCode);
                        Clear(ReferenceVariantCode);
                        UpdateRoutingContext();
                        CurrPage.Update(false);
                    end;
                }
                group(RoutingReference)
                {
                    Caption = 'Routing Reference';
                    field(ReferenceItemNo; ReferenceItemNo)
                    {
                        Caption = 'Reference Parent Item No.';
                        ApplicationArea = All;
                        Editable = not FromSalesLine;
                        TableRelation = Item where("Item Category Code" = field(Code), Type = const(Inventory));
                        ToolTip = 'Select a parent item in this category to filter routing links. This reference does not make the shared template item-specific.';
                        trigger OnValidate()
                        begin
                            Clear(ReferenceVariantCode);
                            CheckReference();
                            UpdateRoutingContext();
                            CurrPage.Update(false);
                        end;
                    }
                    field(ReferenceLocationCode; ReferenceLocationCode)
                    {
                        Caption = 'Reference Location Code';
                        ApplicationArea = All;
                        Editable = not FromSalesLine;
                        TableRelation = Location;
                        ToolTip = 'Specifies the optional location used to resolve the reference SKU.';
                        trigger OnValidate()
                        begin
                            UpdateRoutingContext();
                        end;
                    }
                    field(ReferenceVariantCode; ReferenceVariantCode)
                    {
                        Caption = 'Reference Variant Code';
                        ApplicationArea = All;
                        Editable = not FromSalesLine;
                        Lookup = true;
                        ToolTip = 'Specifies the optional variant of the reference parent item used to resolve its SKU.';
                        trigger OnLookup(var Text: Text): Boolean
                        var
                            Variant: Record "Item Variant";
                            Variants: Page "Item Variants";
                        begin
                            CheckReference();
                            if ReferenceItemNo = '' then
                                Error('Select a reference parent item before selecting its variant.');
                            Variant.SetRange("Item No.", ReferenceItemNo);
                            Variants.SetTableView(Variant);
                            Variants.LookupMode(true);
                            if Variants.RunModal() = Action::LookupOK then begin
                                Variants.GetRecord(Variant);
                                ReferenceVariantCode := Variant.Code;
                                Text := ReferenceVariantCode;
                                UpdateRoutingContext();
                            end;
                            exit(true);
                        end;
                        trigger OnValidate()
                        begin
                            CheckReference();
                            UpdateRoutingContext();
                        end;
                    }
                    field(ReferenceDate; ReferenceDate)
                    {
                        Caption = 'Routing Reference Date';
                        ApplicationArea = All;
                        Editable = not FromSalesLine;
                        ToolTip = 'Specifies the version-selection date. Sales-line setup uses its shipment/due date; standalone setup requires a reference date.';
                        trigger OnValidate()
                        begin
                            UpdateRoutingContext();
                        end;
                    }
                }
                field(CategoryDescription; Rec.Description)
                {
                    Caption = 'Description';
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the standard item category description.';
                }
            }
            part(Options; CF_CategoryTemplateOptions)
            {
                Caption = 'Options';
                ApplicationArea = All;
                SubPageLink = "Item Category Code" = field(Code);
            }
            part(Choices; CF_CategoryTemplateChoices)
            {
                Caption = 'Choices for Selected Option';
                ApplicationArea = All;
                Provider = Options;
                SubPageLink = "Item Category Code" = field("Item Category Code"), "Configuration Option" = field("Configuration Option");
            }
        }
    }

    trigger OnOpenPage()
    var
        Mgt: Codeunit CF_DocumentConfigMgt;
        ItemCategory: Record "Item Category";
    begin
        if not Mgt.CanMaintainTemplates() then
            Error('You need Product Configurator Setup permissions to maintain category templates.');
        if Rec.Code <> '' then
            ItemCategory.Get(Rec.Code)
        else
            if not ItemCategory.FindFirst() then
                Error('Create an Item Category before maintaining a category template.');
        Rec := ItemCategory;
        Rec.Insert(false);
        if not FromSalesLine then
            ReferenceDate := WorkDate();
        CurrPage.Editable(true);
    end;

    trigger OnAfterGetCurrRecord()
    begin
        SelectedCategory := Rec.Code;
        UpdateRoutingContext();
    end;

    procedure SetSalesLineContext(SalesLine: Record "Sales Line")
    begin
        FromSalesLine := true;
        ReferenceItemNo := SalesLine."No.";
        ReferenceLocationCode := SalesLine."Location Code";
        ReferenceVariantCode := SalesLine."Variant Code";
        ReferenceDate := SalesLine."Shipment Date";
    end;

    local procedure CheckReference()
    var
        Item: Record Item;
        Variant: Record "Item Variant";
    begin
        if ReferenceItemNo = '' then begin
            if ReferenceVariantCode <> '' then
                Error('Select a reference parent item before entering its variant.');
            exit;
        end;
        Item.Get(ReferenceItemNo);
        Item.TestField("Item Category Code", Rec.Code);
        Item.TestField(Type, Item.Type::Inventory);
        if ReferenceVariantCode <> '' then
            Variant.Get(ReferenceItemNo, ReferenceVariantCode);
    end;

    local procedure UpdateRoutingContext()
    begin
        CurrPage.Options.Page.SetRoutingContext(ReferenceItemNo, ReferenceLocationCode, ReferenceVariantCode, ReferenceDate,
            (ReferenceItemNo <> '') and (FromSalesLine or (ReferenceDate <> 0D)));
    end;

    var
        SelectedCategory: Code[20];
        FromSalesLine: Boolean;
        ReferenceItemNo: Code[20];
        ReferenceLocationCode: Code[10];
        ReferenceVariantCode: Code[10];
        ReferenceDate: Date;
}
