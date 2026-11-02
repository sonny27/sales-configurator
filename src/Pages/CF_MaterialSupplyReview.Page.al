namespace CloudFactory.SalesConfigurator;

page 91015 CF_MaterialSupplyReview
{
    Caption = 'Create Material Supply';
    PageType = Worksheet;
    SourceTable = CF_MaterialSupplyLine;
    SourceTableView = sorting("Item No.", "Required Date", "Variant Code", "Location Code");
    InsertAllowed = false;
    DeleteAllowed = false;
    LinksAllowed = false;

    layout
    {
        area(Content)
        {
            group(Options)
            {
                Caption = 'Review';
                field(ReceiptPolicy; ReceiptPolicy)
                {
                    ApplicationArea = All;
                    Caption = 'Material Receipt Policy';
                    Editable = false;
                    ToolTip = 'Specifies whether late purchase/transfer receipts cover demand. Change this in Sales Configurator Setup, then reopen this review.';
                }
                field(Instructions; InstructionsLbl)
                {
                    ApplicationArea = All;
                    Caption = 'Confirmation';
                    Editable = false;
                    MultiLine = true;
                    ToolTip = 'Review the selected shortages and missing vendor/source-location settings before confirming.';
                }
            }
            repeater(Lines)
            {
                field(Selected; Rec.Selected)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies whether to create supply for this shortage. All shortages are selected initially.';
                }
                field(ItemNo; Rec."Item No.")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the material to replenish.';
                }
                field(Description; Rec.Description)
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the material description.';
                }
                field(VariantCode; Rec."Variant Code")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the configured material variant.';
                }
                field(LocationCode; Rec."Location Code")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the location where the material is required.';
                }
                field(RequiredDate; Rec."Required Date")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies when the material is needed, using native parent lead-time and component offset calculations.';
                }
                field(RequiredQuantity; Rec."Required Quantity")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies demand in the base unit after netting finished-item and subassembly supply.';
                }
                field(CoveredQuantity; Rec."Covered Quantity")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the demand covered by available unreserved inventory and scheduled supply under the selected receipt policy.';
                }
                field(ShortageQuantity; Rec."Shortage Quantity")
                {
                    ApplicationArea = All;
                    Editable = false;
                    Style = Unfavorable;
                    ToolTip = 'Specifies the remaining quantity to purchase or transfer, in the base unit.';
                }
                field(UnitOfMeasure; Rec."Unit of Measure Code")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies the base unit used for all quantities in this review.';
                }
                field(ReplenishmentSystem; Rec."Replenishment System")
                {
                    ApplicationArea = All;
                    Editable = false;
                    ToolTip = 'Specifies Purchase or Transfer, resolved using native SKU settings with Item fallback.';
                }
                field(VendorNo; Rec."Vendor No.")
                {
                    ApplicationArea = All;
                    Editable = IsPurchase;
                    ToolTip = 'Specifies the purchase vendor. Defaults from SKU/Item settings and can be entered or changed for this creation only.';
                }
                field(TransferFromCode; Rec."Transfer-from Code")
                {
                    ApplicationArea = All;
                    Editable = IsTransfer;
                    ToolTip = 'Specifies the transfer source location. Defaults from the SKU and can be entered or changed for this creation only. Source stock is still required before shipping.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(SelectAll)
            {
                ApplicationArea = All;
                Caption = 'Select All';
                Image = SelectEntries;
                ToolTip = 'Select all shortages in this review.';

                trigger OnAction()
                begin
                    Rec.ModifyAll(Selected, true);
                    CurrPage.Update(false);
                end;
            }
            action(ClearSelection)
            {
                ApplicationArea = All;
                Caption = 'Clear Selection';
                Image = ClearFilter;
                ToolTip = 'Clear selection so that you can select individual shortages.';

                trigger OnAction()
                begin
                    Rec.ModifyAll(Selected, false);
                    CurrPage.Update(false);
                end;
            }
        }
        area(Promoted)
        {
            actionref(SelectAllPromoted; SelectAll) { }
            actionref(ClearSelectionPromoted; ClearSelection) { }
        }
    }

    trigger OnAfterGetRecord()
    begin
        UpdateEditable();
    end;

    trigger OnAfterGetCurrRecord()
    begin
        UpdateEditable();
    end;

    trigger OnQueryClosePage(CloseAction: Action): Boolean
    var
        SupplyMgt: Codeunit CF_MaterialSupplyMgt;
    begin
        if CloseAction in [Action::OK, Action::LookupOK] then begin
            CurrPage.SaveRecord();
            SupplyMgt.CheckSelected(Rec);
        end;
        exit(true);
    end;

    procedure SetLines(var Lines: Record CF_MaterialSupplyLine temporary; Policy: Enum CF_MaterialReceiptPolicy)
    begin
        Rec.Copy(Lines, true);
        Rec.SetFilter("Shortage Quantity", '>0');
        Rec.SetFilter("Replenishment System", '%1|%2',
            Rec."Replenishment System"::Purchase, Rec."Replenishment System"::Transfer);
        ReceiptPolicy := Policy;
    end;

    local procedure UpdateEditable()
    begin
        IsPurchase := Rec."Replenishment System" = Rec."Replenishment System"::Purchase;
        IsTransfer := Rec."Replenishment System" = Rec."Replenishment System"::Transfer;
    end;

    var
        ReceiptPolicy: Enum CF_MaterialReceiptPolicy;
        IsPurchase: Boolean;
        IsTransfer: Boolean;
        InstructionsLbl: Label 'All shortages are selected. Clear any you do not want. Choose OK to confirm creation of actual purchase/transfer orders; Cancel creates nothing. Quantities are in base units. This does not apply the configuration or create production orders.';
}
