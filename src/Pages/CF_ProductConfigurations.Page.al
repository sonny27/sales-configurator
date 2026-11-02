namespace CloudFactory.SalesConfigurator;

using Microsoft.Manufacturing.Document;
using Microsoft.Sales.Document;

page 91007 CF_ProductConfigurations
{
    Caption = 'Product Configurations';
    ApplicationArea = All;
    UsageCategory = Lists;
    PageType = List;
    SourceTable = CF_ProductConfigHeader;
    SourceTableView = sorting("Document Type", "Source Table ID", "Document No.", "Document Line No.");
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    layout
    {
        area(Content)
        {
            repeater(Configurations)
            {
                field(ConfigurationNo; Rec."No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the unique configuration number. Each row represents one configured document line.';
                    trigger OnDrillDown()
                    begin
                        OpenConfigurator();
                    end;
                }
                field(DocumentType; Rec."Document Type") { ApplicationArea = All; ToolTip = 'Specifies the source document type.'; }
                field(DocumentNo; Rec."Document No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the current source sales quote or order number.';
                    trigger OnDrillDown()
                    begin
                        OpenSourceSalesOrder();
                    end;
                }
                field(DocumentLineNo; Rec."Document Line No.") { ApplicationArea = All; ToolTip = 'Specifies the source sales quote or order line number.'; }
                field(CustomerNo; SalesHeader."Sell-to Customer No.") { ApplicationArea = All; Caption = 'Customer No.'; ToolTip = 'Specifies the customer on the current source sales document.'; }
                field(CustomerName; SalesHeader."Sell-to Customer Name") { ApplicationArea = All; Caption = 'Customer Name'; ToolTip = 'Specifies the customer name on the current source sales document.'; }
                field(ParentItemNo; Rec."Parent Item No.") { ApplicationArea = All; ToolTip = 'Specifies the configured parent item.'; }
                field(ParentVariantCode; Rec."Parent Variant Code") { ApplicationArea = All; ToolTip = 'Specifies the configured parent item variant.'; }
                field(SalesDescription; SalesLine.Description) { ApplicationArea = All; Caption = 'Sales Line Description'; ToolTip = 'Specifies the description on the current source sales line.'; }
                field(SalesQuantity; SalesLine.Quantity) { ApplicationArea = All; Caption = 'Sales Quantity'; ToolTip = 'Specifies the current sales line quantity.'; }
                field(SalesUOM; SalesLine."Unit of Measure Code") { ApplicationArea = All; Caption = 'Sales Unit of Measure'; ToolTip = 'Specifies the unit of measure on the source sales line.'; }
                field(LocationCode; SalesLine."Location Code") { ApplicationArea = All; Caption = 'Location Code'; ToolTip = 'Specifies the location on the current source sales line.'; }
                field(ShipmentDate; SalesLine."Shipment Date") { ApplicationArea = All; Caption = 'Shipment Date'; ToolTip = 'Specifies the current source sales line shipment date.'; }
                field(ItemCategoryCode; Rec."Item Category Code") { ApplicationArea = All; ToolTip = 'Specifies the source parent item category.'; }
                field(TemplateCode; Rec."Template Code") { ApplicationArea = All; ToolTip = 'Specifies the original template retained by this saved configuration.'; }
                field(TemplateAssignment; Rec."Template Assignment") { ApplicationArea = All; ToolTip = 'Specifies whether the original template was assigned by item or category.'; }
                field(SavedOptions; Rec."Saved Options")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the number of saved options. Open Product Configurator to view all choices.';
                    trigger OnDrillDown()
                    begin
                        OpenConfigurator();
                    end;
                }
                field(CreatedAt; Rec.SystemCreatedAt) { ApplicationArea = All; Caption = 'Created At'; ToolTip = 'Specifies when the configuration header was created, or backfilled for an existing configuration.'; }
                field(LinkedProductionOrderNo; LinkedProductionOrderNo)
                {
                    ApplicationArea = Manufacturing;
                    Caption = 'Linked Production Order No.';
                    ToolTip = 'Specifies a linked production order. Drill down to see all linked orders.';
                    trigger OnDrillDown()
                    begin
                        OpenLinkedOrders();
                    end;
                }
                field(LinkedProductionOrderStatus; LinkedProductionOrderStatus) { ApplicationArea = Manufacturing; Caption = 'Linked Production Order Status'; ToolTip = 'Specifies the status of the displayed linked production order.'; }
                field(LinkedOrderCount; LinkedOrderCount) { ApplicationArea = Manufacturing; Caption = 'Linked Production Orders'; ToolTip = 'Specifies the number of linked production orders across all statuses.'; }
                field(SourceAvailable; SourceAvailable) { ApplicationArea = All; Caption = 'Source Sales Line Exists'; ToolTip = 'Specifies whether the current source sales line can be found. Sales details are unavailable when the source has been deleted.'; }
            }
        }
    }
    actions
    {
        area(Processing)
        {
            action(OpenConfiguration)
            {
                Caption = 'Product Configurator';
                ApplicationArea = All;
                Image = Setup;
                ToolTip = 'Open all configuration choices for the selected source sales line.';
                trigger OnAction()
                begin
                    OpenConfigurator();
                end;
            }
            action(DeleteConfiguration)
            {
                Caption = 'Delete Configuration';
                ApplicationArea = All;
                AccessByPermission = tabledata CF_DocumentLineProductConfig = D;
                Image = Delete;
                ToolTip = 'Delete the configuration header and all its saved choices. Linked production orders must be deleted first.';
                trigger OnAction()
                var
                    SourceSalesLine: Record "Sales Line";
                begin
                    GetSourceSalesLine(SourceSalesLine);
                    Mgt.DeleteConfiguration(SourceSalesLine);
                    CurrPage.Update(false);
                end;
            }
        }
        area(Navigation)
        {
            action(OpenSalesOrder)
            {
                Caption = 'Sales Document';
                ApplicationArea = All;
                Image = Order;
                ToolTip = 'Open the current source sales quote or order.';
                trigger OnAction()
                begin
                    OpenSourceSalesOrder();
                end;
            }
            action(LinkedProductionOrders)
            {
                Caption = 'Linked Production Orders';
                ApplicationArea = Manufacturing;
                Image = Production;
                ToolTip = 'Open the linked production order or a filtered list of all linked orders.';
                trigger OnAction()
                begin
                    OpenLinkedOrders();
                end;
            }
            action(SalesConfiguratorSetup)
            {
                Caption = 'Sales Configurator Setup';
                ApplicationArea = All;
                Image = Setup;
                AccessByPermission = tabledata CF_SalesConfiguratorSetup = R;
                RunObject = page CF_SalesConfiguratorSetup;
                ToolTip = 'View the document/line-based configuration numbering policy.';
            }
        }
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Manage';
                actionref(OpenConfigurationPromoted; OpenConfiguration) { }
                actionref(DeleteConfigurationPromoted; DeleteConfiguration) { }
                actionref(OpenSalesOrderPromoted; OpenSalesOrder) { }
                actionref(LinkedOrdersPromoted; LinkedProductionOrders) { }
            }
        }
    }
    trigger OnAfterGetRecord()
    begin
        UpdateSourceDetails();
    end;

    trigger OnAfterGetCurrRecord()
    begin
        UpdateSourceDetails();
    end;

    local procedure UpdateSourceDetails()
    var
        ProductionOrder: Record "Production Order";
    begin
        Clear(SalesLine);
        Clear(SalesHeader);
        Clear(LinkedProductionOrderNo);
        Clear(LinkedProductionOrderStatus);
        Clear(LinkedOrderCount);
        SourceAvailable := false;
        if (Rec."Document Type" in [CF_ConfigDocumentType::SalesOrder, CF_ConfigDocumentType::SalesQuote]) and
           (Rec."Source Table ID" = Database::"Sales Line") and not IsNullGuid(Rec."Source Line SystemId")
        then
            if SalesLine.GetBySystemId(Rec."Source Line SystemId") then begin
                SourceAvailable := true;
                if not SalesHeader.Get(SalesLine."Document Type", SalesLine."Document No.") then
                    Error(SourceHeaderMissingErr, SalesLine."Document No.");
            end;
        Mgt.FilterLinkedProductionOrders(Rec."Source Table ID", Rec."Source Line SystemId", ProductionOrder);
        LinkedOrderCount := ProductionOrder.Count();
        if ProductionOrder.FindFirst() then begin
            LinkedProductionOrderNo := ProductionOrder."No.";
            LinkedProductionOrderStatus := Format(ProductionOrder.Status);
        end;
    end;

    local procedure OpenLinkedOrders()
    var
        SourceSalesLine: Record "Sales Line";
    begin
        GetSourceSalesLine(SourceSalesLine);
        Mgt.OpenLinkedProductionOrders(SourceSalesLine);
        CurrPage.Update(false);
    end;

    local procedure GetSourceSalesLine(var SourceSalesLine: Record "Sales Line")
    var
        Config: Record CF_DocumentLineProductConfig;
    begin
        Rec.GetConfigIdentity(Config);
        Mgt.GetSource(Config, SourceSalesLine);
    end;

    local procedure OpenConfigurator()
    var
        SourceSalesLine: Record "Sales Line";
    begin
        GetSourceSalesLine(SourceSalesLine);
        Mgt.OpenConfigurator(SourceSalesLine);
        CurrPage.Update(false);
    end;

    local procedure OpenSourceSalesOrder()
    var
        Config: Record CF_DocumentLineProductConfig;
    begin
        Rec.GetConfigIdentity(Config);
        Mgt.OpenSalesOrder(Config);
    end;

    var
        Mgt: Codeunit CF_DocumentConfigMgt;
        SalesLine: Record "Sales Line";
        SalesHeader: Record "Sales Header";
        SourceAvailable: Boolean;
        LinkedProductionOrderNo: Code[20];
        LinkedProductionOrderStatus: Text;
        LinkedOrderCount: Integer;
        SourceHeaderMissingErr: Label 'The source sales document %1 no longer exists.', Comment = '%1 = sales document number';
}
