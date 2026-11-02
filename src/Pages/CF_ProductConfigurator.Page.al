namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Availability;
using Microsoft.Manufacturing.Document;
using Microsoft.Manufacturing.ProductionBOM;
using Microsoft.Manufacturing.Routing;
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
                field(BaseRouting; SalesLine.CF_BaseRoutingNo)
                {
                    ApplicationArea = Manufacturing;
                    Caption = 'Base Routing';
                    Editable = CanEdit;
                    TableRelation = "Routing Header";
                    ToolTip = 'Defaults using the item and sales location/variant SKU. Select the routing used for this configuration and its production order, or clear for no routing. Master records are not changed.';
                    trigger OnValidate()
                    begin
                        UpdateBaseSelection();
                    end;
                }
                field(BaseBOM; SalesLine.CF_BaseBOMNo)
                {
                    ApplicationArea = Manufacturing;
                    Caption = 'Base BOM';
                    Editable = CanEdit;
                    TableRelation = "Production BOM Header";
                    ToolTip = 'Defaults using the item and sales location/variant SKU. Select the base BOM for this configuration, or clear to start with selected/manual components only. Replacing an edited draft requires confirmation.';
                    trigger OnValidate()
                    begin
                        UpdateBaseSelection();
                    end;
                }
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
                field(ComponentType; Rec."Component Type") { ApplicationArea = All; ToolTip = 'Specifies Item or Production BOM from the saved choice mapping. Production BOM references are exploded by the standard manufacturing engine.'; }
                field(ComponentItemNo; Rec."Component Item No.") { ApplicationArea = All; ToolTip = 'Specifies the resolved item or production BOM number. Reselect the choice explicitly to accept a changed setup mapping.'; }
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
                field(RoutingOperation; RoutingOperation)
                {
                    ApplicationArea = All;
                    Caption = 'Routing Operation';
                    Editable = false;
                    ToolTip = 'Shows every matching operation number and description from the selected Base Routing and its effective version for the sales shipment date. Matches the row Routing Link Code; blank when no matching operation exists.';
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
                Enabled = HasParentItem;
                Image = Setup;
                ToolTip = 'Maintain the assigned item or category template. Existing saved configurations retain their original template even when setup assignment mode changes.';
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
                    if DraftMgt.ApplyConfiguration(SalesLine, Rec) then
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
                ToolTip = 'Open an isolated editable component draft with native multilevel items and read-only routing operations. Apply in that page saves the structure and current choices together without changing master BOMs or routings.';
                trigger OnAction()
                begin
                    CurrPage.SaveRecord();
                    if Mgt.ShowConfiguredBOM(SalesLine, Rec) then
                        SalesLine.GetBySystemId(SalesLine.SystemId);
                    CurrPage.Update(false);
                end;
            }
            group(Availability)
            {
                Caption = 'Availability';
                Image = ItemAvailability;
                Enabled = HasParentItem;
                action(ConfiguredAvailability)
                {
                    Caption = 'Availability';
                    ApplicationArea = All;
                    Image = ItemAvailability;
                    ToolTip = 'View availability by BOM level for the current configuration, including unapplied choices and base BOM/routing. Use the menu for other standard availability views and Order Promising.';
                    trigger OnAction()
                    begin
                        ShowBOMAvailability();
                    end;
                }
                action(OrderPromising)
                {
                    Caption = 'Order Promising';
                    ApplicationArea = OrderPromising;
                    AccessByPermission = tabledata "Order Promising Line" = R;
                    Image = OrderPromising;
                    Enabled = IsSalesOrder;
                    ToolTip = 'Open native ATP/CTP for this sales line only. CTP uses the current configured structure and native critical-component rules. Accept updates this line dates and retains its planning/reservations; it does not apply the configurator.';
                    trigger OnAction()
                    var
                        AvailabilityMgt: Codeunit CF_ConfigAvailabilityMgt;
                        CurrentSalesLine: Record "Sales Line";
                    begin
                        CurrPage.SaveRecord();
                        AvailabilityMgt.ShowPromising(SalesLine, Rec);
                        if not CurrentSalesLine.GetBySystemId(SalesLine.SystemId) then
                            Error('The source sales line no longer exists.');
                        Mgt.CopyBase(SalesLine, CurrentSalesLine);
                        SalesLine := CurrentSalesLine;
                        UpdateProductionContext();
                        CurrPage.Update(false);
                    end;
                }
                action(CreateMaterialSupply)
                {
                    Caption = 'Create Material Supply';
                    ApplicationArea = All;
                    Image = CreateDocument;
                    Enabled = IsSalesOrder;
                    ToolTip = 'Review net material shortages for the current configuration and create purchase/transfer orders using SKU/Item settings. All shortages are selected initially; missing vendors and transfer source locations can be entered in the review.';
                    trigger OnAction()
                    var
                        SupplyMgt: Codeunit CF_MaterialSupplyMgt;
                    begin
                        CurrPage.SaveRecord();
                        SupplyMgt.Open(SalesLine, Rec);
                    end;
                }
                action(AvailabilityEvent)
                {
                    Caption = 'Event';
                    ApplicationArea = Basic, Suite;
                    Image = "Event";
                    ToolTip = 'View actual and projected finished-item availability by supply and demand event, filtered to the sales-line context.';
                    trigger OnAction()
                    begin
                        ShowStandardAvailability("Item Availability Type"::"Event");
                    end;
                }
                action(AvailabilityPeriod)
                {
                    Caption = 'Period';
                    ApplicationArea = Basic, Suite;
                    Image = Period;
                    ToolTip = 'View projected finished-item availability by period without changing the sales line.';
                    trigger OnAction()
                    begin
                        ShowStandardAvailability("Item Availability Type"::Period);
                    end;
                }
                action(AvailabilityVariant)
                {
                    Caption = 'Variant';
                    ApplicationArea = Planning;
                    Image = ItemVariant;
                    ToolTip = 'View finished-item availability by variant without changing the sales line or configuration.';
                    trigger OnAction()
                    begin
                        ShowStandardAvailability("Item Availability Type"::Variant);
                    end;
                }
                action(AvailabilityLocation)
                {
                    Caption = 'Location';
                    ApplicationArea = Location;
                    Image = Warehouse;
                    ToolTip = 'View finished-item availability by location without changing the sales line or configuration.';
                    trigger OnAction()
                    begin
                        ShowStandardAvailability("Item Availability Type"::Location);
                    end;
                }
                action(AvailabilityLot)
                {
                    Caption = 'Lot';
                    ApplicationArea = ItemTracking;
                    Image = LotInfo;
                    ToolTip = 'View actual and projected finished-item availability by lot.';
                    trigger OnAction()
                    var
                        AvailabilityMgt: Codeunit CF_ConfigAvailabilityMgt;
                    begin
                        AvailabilityMgt.ShowLot(SalesLine);
                    end;
                }
                action(AvailabilityBOM)
                {
                    Caption = 'BOM Level';
                    ApplicationArea = Manufacturing;
                    Image = BOMLevel;
                    ToolTip = 'View native able-to-make figures using the current configured BOM rather than the item master BOM.';
                    trigger OnAction()
                    begin
                        ShowBOMAvailability();
                    end;
                }
                action(AvailabilityUOM)
                {
                    Caption = 'Unit of Measure';
                    ApplicationArea = Basic, Suite;
                    Image = UnitOfMeasure;
                    ToolTip = 'View finished-item availability by unit of measure without changing the sales line.';
                    trigger OnAction()
                    begin
                        ShowStandardAvailability("Item Availability Type"::UOM);
                    end;
                }
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
            group(AvailabilityPromoted)
            {
                Caption = 'Availability';
                ShowAs = SplitButton;
                actionref(ConfiguredAvailabilityPromoted; ConfiguredAvailability) { }
                actionref(OrderPromisingPromoted; OrderPromising) { }
                actionref(CreateMaterialSupplyPromoted; CreateMaterialSupply) { }
                actionref(AvailabilityEventPromoted; AvailabilityEvent) { }
                actionref(AvailabilityPeriodPromoted; AvailabilityPeriod) { }
                actionref(AvailabilityVariantPromoted; AvailabilityVariant) { }
                actionref(AvailabilityLocationPromoted; AvailabilityLocation) { }
                actionref(AvailabilityLotPromoted; AvailabilityLot) { }
                actionref(AvailabilityBOMPromoted; AvailabilityBOM) { }
                actionref(AvailabilityUOMPromoted; AvailabilityUOM) { }
            }
        }
    }
    local procedure ShowBOMAvailability()
    var
        AvailabilityMgt: Codeunit CF_ConfigAvailabilityMgt;
    begin
        CurrPage.SaveRecord();
        AvailabilityMgt.ShowBOM(SalesLine, Rec);
    end;

    local procedure ShowStandardAvailability(AvailabilityType: Enum "Item Availability Type")
    var
        AvailabilityMgt: Codeunit CF_ConfigAvailabilityMgt;
    begin
        AvailabilityMgt.ShowStandard(SalesLine, AvailabilityType);
    end;

    trigger OnOpenPage()
    var
        Item: Record Item;
    begin
        if not SalesLine.GetBySystemId(SalesLine.SystemId) then
            Error('The source sales line no longer exists.');
        Item.Get(SalesLine."No.");
        Mgt.InitializeBase(SalesLine);
        UpdateProductionContext();
        if CanEdit then
            SalesLine.CF_BaseSetupSet := true;
        HasParentItem := SalesLine."No." <> '';
        ItemCategoryCode := Item."Item Category Code";
        CanSetup := Mgt.CanMaintainTemplates();
        Mgt.Load(SalesLine, Rec);
        UpdateTemplateMessage();
        if HasLinkedProductionOrder then
            Message(LinkedProductionOrderMsg, LinkedProductionOrderNo, LinkedProductionOrderStatus);
    end;

    trigger OnAfterGetRecord()
    var
        Item: Record Item;
        BOMHeader: Record "Production BOM Header";
    begin
        ChoiceCodeRequired := Rec.RequiresChoice();
        QuantityRequired := Rec.RequiresQuantity() or ((Rec."Choice Code" <> '') and (Rec."Quantity per Unit" = 0));
        LineStyle := Rec.GetStyleText();
        RoutingOperation := Mgt.GetRoutingOperations(SalesLine, Rec."Routing Link Code");
        Clear(ComponentDescription);
        if Rec."Component Item No." <> '' then
            if Rec."Component Type" = Rec."Component Type"::"Production BOM" then begin
                if BOMHeader.Get(Rec."Component Item No.") then
                    ComponentDescription := BOMHeader.Description
                else
                    ComponentDescription := MissingItemLbl;
            end else
                if Item.Get(Rec."Component Item No.") then
                    ComponentDescription := Item.Description
                else
                    ComponentDescription := MissingItemLbl;
    end;

    procedure SetSalesLine(SourceSalesLine: Record "Sales Line")
    begin
        SalesLine := SourceSalesLine;
        IsSalesOrder := SalesLine."Document Type" = SalesLine."Document Type"::Order;
    end;

    local procedure UpdateProductionContext()
    var
        ProductionOrder: Record "Production Order";
    begin
        IsSalesOrder := SalesLine."Document Type" = SalesLine."Document Type"::Order;
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
    var
        TemplateMgt: Codeunit CF_TemplateMgt;
    begin
        NoOptions := Rec.IsEmpty();
        if TemplateMgt.AssignmentType(SalesLine) = CF_TemplateAssignment::SalesLineItem then
            TemplateMessage := StrSubstNo('No enabled template options are available for item %1. Use BOM Template Setup to create or maintain its item template.', SalesLine."No.")
        else
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

    local procedure UpdateBaseSelection()
    begin
        Mgt.ValidateBase(SalesLine);
        SalesLine.CF_BaseSetupSet := true;
        Mgt.StampBase(SalesLine, Rec);
        CurrPage.Update(false);
    end;

    var
        SalesLine: Record "Sales Line";
        Mgt: Codeunit CF_DocumentConfigMgt;
        DraftMgt: Codeunit CF_BOMDraftMgt;
        CanEdit: Boolean;
        IsSalesOrder: Boolean;
        HasLinkedProductionOrder: Boolean;
        LinkedProductionOrderNo: Code[20];
        LinkedProductionOrderStatus: Text;
        LinkedProductionOrderMsg: Label 'This configuration is read-only because production order %1 (%2) is linked. Use Linked Production Orders to navigate to the orders. Delete all linked orders before editing or deleting this configuration.', Comment = '%1 = production order number, %2 = status';
        LineStyle: Text;
        ChoiceCodeRequired: Boolean;
        QuantityRequired: Boolean;
        CanSetup: Boolean;
        HasParentItem: Boolean;
        NoOptions: Boolean;
        ItemCategoryCode: Code[20];
        TemplateMessage: Text;
        NoCategoryLbl: Label 'Item %1 has no Item Category Code. Assign a category on the Item Card, then reopen Product Configurator.';
        NoTemplateLbl: Label 'No enabled options are available for category %1. A setup user can define them through BOM Template Setup.';
        ComponentDescription: Text[100];
        RoutingOperation: Text;
        MissingItemLbl: Label 'Missing component item - configuration is invalid';
}
