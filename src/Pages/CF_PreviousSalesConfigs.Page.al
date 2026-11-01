namespace CloudFactory.SalesConfigurator;

using Microsoft.Sales.Document;

page 91008 CF_PreviousSalesConfigs
{
    Caption = 'Previous Sales Configurations';
    PageType = List;
    SourceTable = "Sales Line";
    SourceTableTemporary = true;
    SourceTableView = sorting("Document Type", "Document No.", "Line No.") order(descending);
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    layout
    {
        area(Content)
        {
            group(Context)
            {
                Caption = 'Configuration Selection';
                field(ParentItemNo; TargetSalesLine."No.") { ApplicationArea = All; Caption = 'Parent Item No.'; ToolTip = 'Specifies the required parent item. This restriction cannot be removed.'; }
                field(CustomerFilter; CustomerFilterText) { ApplicationArea = All; Caption = 'Customer Filter'; ToolTip = 'Shows the current customer filter. Use Clear Customer Filter or the filter pane to include other customers.'; }
                field(NoMatchesMessage; NoMatchesMsg)
                {
                    ApplicationArea = All;
                    ShowCaption = false;
                    Visible = NoMatches;
                    ToolTip = 'Explains how to broaden the search when there are no matching saved configurations.';
                }
            }
            repeater(PreviousConfigurations)
            {
                field(ConfigurationNo; ConfigurationNo) { ApplicationArea = All; Caption = 'Configuration No.'; ToolTip = 'Specifies the unique number of the previous saved product configuration.'; }
                field(DocumentNo; Rec."Document No.") { ApplicationArea = All; ToolTip = 'Specifies the previous sales order.'; }
                field(LineNo; Rec."Line No.") { ApplicationArea = All; ToolTip = 'Specifies the configured sales line. Select this row to load all its saved options.'; }
                field(CustomerNo; Rec."Sell-to Customer No.") { ApplicationArea = All; Caption = 'Customer No.'; ToolTip = 'Specifies the previous sales order customer. Its initial filter can be removed.'; }
                field(CustomerName; SalesHeader."Sell-to Customer Name") { ApplicationArea = All; Caption = 'Customer Name'; ToolTip = 'Specifies the customer name on the previous order.'; }
                field(OrderDate; SalesHeader."Order Date") { ApplicationArea = All; Caption = 'Order Date'; ToolTip = 'Specifies the previous sales order date.'; }
                field(ItemNo; Rec."No.") { ApplicationArea = All; Caption = 'Item No.'; ToolTip = 'Specifies the same parent item as the current sales line.'; }
                field(VariantCode; Rec."Variant Code") { ApplicationArea = All; ToolTip = 'Specifies the previous parent item variant. Loaded choices are validated for the current variant and routing.'; }
                field(Description; Rec.Description) { ApplicationArea = All; ToolTip = 'Specifies the previous sales line description.'; }
                field(Quantity; Rec.Quantity) { ApplicationArea = All; ToolTip = 'Specifies the previous sales quantity for reference. Loading does not change the current sales quantity.'; }
                field(UnitOfMeasureCode; Rec."Unit of Measure Code") { ApplicationArea = All; ToolTip = 'Specifies the previous sales unit of measure for reference.'; }
                field(LocationCode; Rec."Location Code") { ApplicationArea = All; ToolTip = 'Specifies the previous location for reference. Loading validates routing against the current location.'; }
                field(ShipmentDate; Rec."Shipment Date") { ApplicationArea = All; ToolTip = 'Specifies the previous shipment date for reference.'; }
                field(SavedOptionCount; SavedOptionCount) { ApplicationArea = All; Caption = 'Saved Options'; ToolTip = 'Specifies the number of saved configuration options on this sales line.'; }
            }
        }
    }
    actions
    {
        area(Processing)
        {
            action(ClearCustomerFilter)
            {
                Caption = 'Clear Customer Filter';
                ApplicationArea = All;
                Image = ClearFilter;
                ToolTip = 'Include saved configurations from all customers. The same-item restriction remains enforced.';
                trigger OnAction()
                begin
                    Rec.SetRange("Sell-to Customer No.");
                    UpdateFilterContext();
                    CurrPage.Update(false);
                end;
            }
            action(ViewSavedChoices)
            {
                Caption = 'View Saved Configuration';
                ApplicationArea = All;
                Image = List;
                ToolTip = 'Open the saved configuration summary. Use Product Configurator there to review its choices.';
                trigger OnAction()
                var
                    Config: Record CF_DocumentLineProductConfig;
                begin
                    Mgt.FilterSalesLine(Rec, Config);
                    if Config.IsEmpty() then
                        Error(NoSavedChoicesErr);
                    Mgt.OpenConfigurationSummary(CF_ConfigDocumentType::SalesOrder, Database::"Sales Line", Rec.SystemId, true);
                end;
            }
        }
        area(Promoted)
        {
            actionref(ClearCustomerFilterPromoted; ClearCustomerFilter) { }
            actionref(ViewSavedChoicesPromoted; ViewSavedChoices) { }
        }
    }
    trigger OnOpenPage()
    begin
        Mgt.GetPreviousSalesConfigurations(TargetSalesLine, Rec);
        Rec.FilterGroup(2);
        Rec.SetRange("Document Type", Rec."Document Type"::Order);
        Rec.SetRange(Type, Rec.Type::Item);
        Rec.SetRange("No.", TargetSalesLine."No.");
        Rec.FilterGroup(0);
        Rec.SetRange("Sell-to Customer No.", TargetSalesLine."Sell-to Customer No.");
        UpdateFilterContext();
    end;

    trigger OnAfterGetRecord()
    var
        Config: Record CF_DocumentLineProductConfig;
        Header: Record CF_ProductConfigHeader;
    begin
        Clear(SalesHeader);
        if not SalesHeader.Get(Rec."Document Type", Rec."Document No.") then
            Error(SourceHeaderMissingErr, Rec."Document No.");
        Mgt.FilterSalesLine(Rec, Config);
        SavedOptionCount := Config.Count();
        Clear(ConfigurationNo);
        Header.SetRange("Document Type", CF_ConfigDocumentType::SalesOrder);
        Header.SetRange("Source Table ID", Database::"Sales Line");
        Header.SetRange("Source Line SystemId", Rec.SystemId);
        if Header.FindFirst() then
            ConfigurationNo := Header."No.";
    end;

    trigger OnAfterGetCurrRecord()
    begin
        UpdateFilterContext();
    end;

    procedure SetSalesLine(SalesLine: Record "Sales Line")
    begin
        TargetSalesLine := SalesLine;
    end;

    local procedure UpdateFilterContext()
    begin
        CustomerFilterText := Rec.GetFilter("Sell-to Customer No.");
        if CustomerFilterText = '' then
            CustomerFilterText := AllCustomersLbl;
        NoMatches := Rec.IsEmpty();
    end;

    var
        TargetSalesLine: Record "Sales Line";
        SalesHeader: Record "Sales Header";
        Mgt: Codeunit CF_DocumentConfigMgt;
        CustomerFilterText: Text;
        SavedOptionCount: Integer;
        ConfigurationNo: Code[100];
        NoMatches: Boolean;
        AllCustomersLbl: Label 'All customers';
        NoMatchesMsg: Label 'No saved configurations match the current filters. Clear Customer Filter to search other customers for this item. Only retained Sales Order configurations are available.';
        NoSavedChoicesErr: Label 'The selected sales line no longer has saved configuration choices.';
        SourceHeaderMissingErr: Label 'The previous sales order %1 no longer exists. Reopen the configuration picker.', Comment = '%1 = previous order';
}
