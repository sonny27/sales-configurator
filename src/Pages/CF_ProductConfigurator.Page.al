namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;
using Microsoft.Manufacturing.Document;
using Microsoft.Sales.Document;

page 91002 CF_ProductConfigurator
{
    Caption = 'Product Configurator';
    PageType = Worksheet;
    SourceTable = CF_DocumentLineProductConfig;
    SourceTableTemporary = true;
    InsertAllowed = false;
    DeleteAllowed = false;
    ApplicationArea = All;
    layout
    {
        area(Content)
        {
            group(Source)
            {
                Caption = 'Sales Document Line';
                field(ConfigurationNo; Rec."Configuration No.") { ApplicationArea = All; Editable = false; ToolTip = 'Specifies the originating document number and line number. The number is saved on Apply and retained when a quote becomes an order.'; }
                field(DocumentNo; SalesLine."Document No.") { ApplicationArea = All; Caption = 'Sales Document No.'; Editable = false; ToolTip = 'Specifies the source sales quote or order.'; }
                field(DocumentLineNo; SalesLine."Line No.") { ApplicationArea = All; Caption = 'Line No.'; Editable = false; ToolTip = 'Specifies the source sales line.'; }
                field(ParentItemNo; SalesLine."No.") { ApplicationArea = All; Caption = 'Parent Item No.'; Editable = false; ToolTip = 'Specifies the finished item. Configuration never changes this item.'; }
                field(ItemCategoryCode; ItemCategoryCode) { ApplicationArea = All; Caption = 'Item Category Code'; Editable = false; ToolTip = 'Specifies the parent item category used to load shared template options and defaults.'; }
                field(LinkedProductionOrderNo; LinkedProductionOrderNo)
                {
                    ApplicationArea = Manufacturing;
                    Caption = 'Linked Production Order No.';
                    Editable = false;
                    Visible = HasLinkedProductionOrder;
                    ToolTip = 'Specifies a linked production order. Use Linked Production Orders to view all links.';
                    trigger OnDrillDown()
                    begin
                        OpenLinkedOrders();
                    end;
                }
                field(LinkedProductionOrderStatus; LinkedProductionOrderStatus)
                {
                    ApplicationArea = Manufacturing;
                    Caption = 'Linked Production Order Status';
                    Editable = false;
                    Visible = HasLinkedProductionOrder;
                    ToolTip = 'Specifies the status of the displayed linked production order.';
                }
                field(TemplateMessage; TemplateMessage)
                {
                    ApplicationArea = All;
                    ShowCaption = false;
                    Editable = false;
                    Visible = NoOptions;
                    Style = Attention;
                    ToolTip = 'Explains why no template options are available and how to set them up.';
                }
            }
            repeater(Options)
            {
                field(ConfigurationOption; Rec."Configuration Option") { ApplicationArea = All; StyleExpr = LineStyle; ToolTip = 'Specifies the configuration option. Obsolete saved options remain visible until explicitly cleared.'; }
                field(OptionDescription; Rec."Option Description") { ApplicationArea = All; ToolTip = 'Specifies the option description.'; }
                field(ChoiceCode; Rec."Choice Code")
                {
                    ApplicationArea = All;
                    Editable = CanEdit;
                    ShowMandatory = ChoiceCodeRequired;
                    ToolTip = 'Select or type a selectable choice for this category and option. Clear optional choices to remove their components.';
                    trigger OnLookup(var Text: Text): Boolean
                    begin
                        if Mgt.LookupChoice(Rec) then begin
                            Text := Rec."Choice Code";
                            SaveTemporaryRow();
                        end;
                        exit(true);
                    end;

                    trigger OnValidate()
                    begin
                        SaveTemporaryRow();
                    end;
                }
                field(QuantityPerUnit; Rec."Quantity per Unit")
                {
                    ApplicationArea = All;
                    Editable = CanEdit;
                    ShowMandatory = QuantityRequired;
                    ToolTip = 'Specifies positive component quantity in the selected component UOM per finished item base unit.';
                    trigger OnValidate()
                    begin
                        SaveTemporaryRow();
                    end;
                }
                field(ComponentItemNo; Rec."Component Item No.") { ApplicationArea = All; ToolTip = 'Specifies the resolved item snapshot. Reselect the choice explicitly to accept a changed setup mapping.'; }
                field(ComponentDescription; ComponentDescription) { ApplicationArea = All; Caption = 'Component Description'; Editable = false; ToolTip = 'Specifies the current component item description.'; }
                field(ComponentVariantCode; Rec."Component Variant Code") { ApplicationArea = All; ToolTip = 'Specifies the resolved component variant.'; }
                field(ComponentUOMCode; Rec."Component UOM Code") { ApplicationArea = All; ToolTip = 'Specifies the resolved component UOM.'; }
                field(RoutingLinkCode; Rec."Routing Link Code")
                {
                    ApplicationArea = All;
                    Editable = CanEdit;
                    ToolTip = 'Select an optional link assigned to an operation on the effective parent item/SKU routing and certified version for the sales shipment date.';
                    trigger OnLookup(var Text: Text): Boolean
                    begin
                        if Mgt.LookupRoutingLink(Rec) then begin
                            Text := Rec."Routing Link Code";
                            SaveTemporaryRow();
                        end;
                        exit(true);
                    end;
                    trigger OnValidate()
                    begin
                        SaveTemporaryRow();
                    end;
                }
            }
        }
    }
    actions
    {
        area(Processing)
        {
            action(CategoryTemplateSetup)
            {
                Caption = 'BOM Template Setup';
                ApplicationArea = All;
                AccessByPermission = tabledata CF_ConfiguratorBOM = M;
                Visible = CanSetup;
                Enabled = ItemCategoryCode <> '';
                Image = Setup;
                ToolTip = 'Maintain the shared template for the parent item category. Template changes are saved separately from this temporary sales-line configuration.';
                trigger OnAction()
                begin
                    CurrPage.SaveRecord();
                    Mgt.OpenCategoryTemplate(ItemCategoryCode, SalesLine);
                    Mgt.RefreshTemplate(SalesLine, Rec);
                    UpdateTemplateMessage();
                    CurrPage.Update(false);
                end;
            }
            action(LoadPreviousSalesConfiguration)
            {
                Caption = 'Load Previous Sales Configuration';
                ApplicationArea = All;
                Image = CopyDocument;
                Ellipsis = true;
                Enabled = CanEdit;
                ToolTip = 'Replace temporary choices with a saved configuration for the same item. The picker defaults to this customer; its customer filter can be cleared. Apply Configuration is still required to save.';
                trigger OnAction()
                begin
                    CurrPage.SaveRecord();
                    if Mgt.LookupPreviousConfiguration(SalesLine, Rec) then begin
                        UpdateTemplateMessage();
                        UpdateProductionContext();
                        CurrPage.Update(false);
                    end;
                end;
            }
            action(ApplyConfiguration)
            {
                Caption = 'Apply Configuration';
                ApplicationArea = All;
                Image = Approve;
                Enabled = CanEdit;
                ToolTip = 'Validate mandatory options and mappings, save this line configuration atomically, and close.';
                trigger OnAction()
                begin
                    CurrPage.SaveRecord();
                    Mgt.Save(SalesLine, Rec);
                    CurrPage.Close();
                end;
            }
            action(CancelConfiguration)
            {
                Caption = 'Cancel';
                ApplicationArea = All;
                Image = Cancel;
                ToolTip = 'Discard temporary changes and close without saving configuration.';
                trigger OnAction()
                begin
                    CurrPage.Close();
                end;
            }
            action(DeleteConfiguration)
            {
                Caption = 'Delete Configuration';
                ApplicationArea = All;
                AccessByPermission = tabledata CF_DocumentLineProductConfig = D;
                Image = Delete;
                ToolTip = 'Delete all saved configuration choices for this sales line and close. Linked production orders must be deleted first.';
                trigger OnAction()
                begin
                    if Mgt.DeleteConfiguration(SalesLine) then
                        CurrPage.Close()
                    else begin
                        UpdateProductionContext();
                        CurrPage.Update(false);
                    end;
                end;
            }
            action(LinkedProductionOrders)
            {
                Caption = 'Linked Production Orders';
                ApplicationArea = Manufacturing;
                Image = Production;
                Visible = HasLinkedProductionOrder;
                ToolTip = 'Open the linked production order, or a filtered list when more than one production order is linked.';
                trigger OnAction()
                begin
                    OpenLinkedOrders();
                end;
            }
            action(ShowNewConfiguredBOM)
            {
                Caption = 'Show New Configured BOM';
                ApplicationArea = Manufacturing;
                Image = BOM;
                Ellipsis = true;
                ToolTip = 'Preview the effective parent item/SKU BOM plus current configuration choices, including unsaved edits. No master BOM or saved configuration is changed.';
                trigger OnAction()
                begin
                    CurrPage.SaveRecord();
                    Mgt.ShowConfiguredBOM(SalesLine, Rec);
                end;
            }
        }
        area(Promoted)
        {
            actionref(ApplyConfigurationPromoted; ApplyConfiguration) { }
            actionref(CancelConfigurationPromoted; CancelConfiguration) { }
            actionref(CategoryTemplateSetupPromoted; CategoryTemplateSetup) { }
            actionref(LoadPreviousConfigPromoted; LoadPreviousSalesConfiguration) { }
            actionref(DeleteConfigurationPromoted; DeleteConfiguration) { }
            actionref(LinkedProductionOrdersPromoted; LinkedProductionOrders) { }
            actionref(ShowConfiguredBOMPromoted; ShowNewConfiguredBOM) { }
        }
    }
    trigger OnOpenPage()
    var
        Item: Record Item;
    begin
        Item.Get(SalesLine."No.");
        ItemCategoryCode := Item."Item Category Code";
        CanSetup := Mgt.CanMaintainTemplates();
        Mgt.Load(SalesLine, Rec);
        UpdateTemplateMessage();
        UpdateProductionContext();
        if HasLinkedProductionOrder then
            Message(LinkedProductionOrderMsg, LinkedProductionOrderNo, LinkedProductionOrderStatus);
    end;

    trigger OnAfterGetRecord()
    var
        Item: Record Item;
    begin
        ChoiceCodeRequired := Rec.RequiresChoice();
        QuantityRequired := Rec.RequiresQuantity();
        LineStyle := Rec.GetStyleText();
        Clear(ComponentDescription);
        if Rec."Component Item No." <> '' then
            if Item.Get(Rec."Component Item No.") then
                ComponentDescription := Item.Description
            else
                ComponentDescription := MissingItemLbl;
    end;

    procedure SetSalesLine(SourceSalesLine: Record "Sales Line")
    begin
        SalesLine := SourceSalesLine;
    end;

    local procedure UpdateProductionContext()
    var
        ProductionOrder: Record "Production Order";
    begin
        Clear(LinkedProductionOrderNo);
        Clear(LinkedProductionOrderStatus);
        HasLinkedProductionOrder := Mgt.GetLinkedProductionOrders(SalesLine, ProductionOrder);
        CanEdit := not HasLinkedProductionOrder;
        if HasLinkedProductionOrder then begin
            LinkedProductionOrderNo := ProductionOrder."No.";
            LinkedProductionOrderStatus := Format(ProductionOrder.Status);
        end;
    end;

    local procedure OpenLinkedOrders()
    begin
        Mgt.OpenLinkedProductionOrders(SalesLine);
        UpdateProductionContext();
        CurrPage.Update(false);
    end;

    local procedure UpdateTemplateMessage()
    begin
        NoOptions := Rec.IsEmpty();
        if ItemCategoryCode = '' then
            TemplateMessage := StrSubstNo(NoCategoryLbl, SalesLine."No.")
        else
            TemplateMessage := StrSubstNo(NoTemplateLbl, ItemCategoryCode);
    end;

    local procedure SaveTemporaryRow()
    begin
        Rec.Modify();
        CurrPage.Update(false);
    end;

    var
        SalesLine: Record "Sales Line";
        Mgt: Codeunit CF_DocumentConfigMgt;
        CanEdit: Boolean;
        HasLinkedProductionOrder: Boolean;
        LinkedProductionOrderNo: Code[20];
        LinkedProductionOrderStatus: Text;
        LinkedProductionOrderMsg: Label 'This configuration is read-only because production order %1 (%2) is linked. Use Linked Production Orders to navigate to the orders. Delete all linked orders before editing or deleting this configuration.', Comment = '%1 = production order number, %2 = status';
        LineStyle: Text;
        ChoiceCodeRequired: Boolean;
        QuantityRequired: Boolean;
        CanSetup: Boolean;
        NoOptions: Boolean;
        ItemCategoryCode: Code[20];
        TemplateMessage: Text;
        NoCategoryLbl: Label 'Item %1 has no Item Category Code. Assign a category on the Item Card, then reopen Product Configurator.';
        NoTemplateLbl: Label 'No enabled options are available for category %1. A setup user can define them through BOM Template Setup.';
        ComponentDescription: Text[100];
        MissingItemLbl: Label 'Missing component item - configuration is invalid';
}
