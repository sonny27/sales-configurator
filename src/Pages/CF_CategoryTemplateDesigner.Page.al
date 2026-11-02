namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Sales.Document;

page 91003 CF_CategoryTemplateDesigner
{
    Caption = 'Configuration Template Designer';
    PageType = Card;
    SourceTable = CF_ConfigTemplate;
    InsertAllowed = false;
    DeleteAllowed = false;
    ApplicationArea = All;
    UsageCategory = None;

    layout
    {
        area(Content)
        {
            group(Category)
            {
                Caption = 'Template';
                field(TemplateCode; Rec.Code)
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the template being maintained. Use Configuration Templates to create or copy a template.';
                }
                field(TemplateType; Rec."Template Type") { ApplicationArea = All; Editable = false; ToolTip = 'Specifies the item or category assignment chosen when the template was created.'; }
                field(ItemNo; Rec."Item No.") { ApplicationArea = All; Editable = false; ShowMandatory = ItemTemplate; ToolTip = 'Specifies the required inventory item for an Item No. template.'; }
                field(ItemCategoryCode; Rec."Item Category Code") { ApplicationArea = All; Editable = false; ShowMandatory = not ItemTemplate; ToolTip = 'Specifies the required item category for an Item Category template.'; }
                group(RoutingReference)
                {
                    Caption = 'Routing Reference';
                    field(ReferenceItemNo; ReferenceItemNo)
                    {
                        Caption = 'Reference Parent Item No.';
                        ApplicationArea = All;
                        Editable = not FromSalesLine;
                        TableRelation = Item where(Type = const(Inventory));
                        ToolTip = 'Select the assigned item, or an item in the assigned category, to filter routing links.';
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
                    Editable = true;
                    ToolTip = 'Specifies the configuration template description.';
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

    actions
    {
        area(Processing)
        {
            action(CopyTemplate)
            {
                Caption = 'Copy Template';
                ApplicationArea = All;
                AccessByPermission = tabledata CF_ConfiguratorBOM = M;
                Image = Copy;
                ToolTip = 'Copy this template, including options, choices and routing links, to a new or empty destination.';
                trigger OnAction()
                var
                    Wizard: Page CF_NewConfigTemplate;
                    Target: Record CF_ConfigTemplate;
                begin
                    CurrPage.SaveRecord();
                    Commit();
                    Wizard.SetCopySource(Rec);
                    if Wizard.RunModal() = Action::OK then begin
                        Wizard.GetTemplate(Target);
                        Commit();
                        Page.RunModal(Page::CF_CategoryTemplateDesigner, Target);
                    end;
                end;
            }
        }
        area(Promoted)
        {
            actionref(CopyPromoted; CopyTemplate) { }
        }
    }

    trigger OnOpenPage()
    var
        Mgt: Codeunit CF_DocumentConfigMgt;
    begin
        if not Mgt.CanMaintainTemplates() then
            Error('You need Product Configurator Setup permissions to maintain templates.');
        Rec.Get(Rec.Code);
        Rec.SetRange(Code, Rec.Code);
        ItemTemplate := Rec."Template Type" = Rec."Template Type"::SalesLineItem;
        if ItemTemplate and not FromSalesLine then
            ReferenceItemNo := Rec."Item No.";
        if not FromSalesLine then
            ReferenceDate := WorkDate();
        CurrPage.Editable(true);
    end;

    trigger OnAfterGetCurrRecord()
    begin
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
        TemplateMgt.CheckReference(Rec.Code, ReferenceItemNo);
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
        TemplateMgt: Codeunit CF_TemplateMgt;
        ItemTemplate: Boolean;
        FromSalesLine: Boolean;
        ReferenceItemNo: Code[20];
        ReferenceLocationCode: Code[10];
        ReferenceVariantCode: Code[10];
        ReferenceDate: Date;
}
