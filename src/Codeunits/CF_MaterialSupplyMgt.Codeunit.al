namespace CloudFactory.SalesConfigurator;

using Microsoft.Foundation.Enums;
using Microsoft.Foundation.UOM;
using Microsoft.Inventory.Availability;
using Microsoft.Inventory.BOM.Tree;
using Microsoft.Inventory.Costing;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Planning;
using Microsoft.Inventory.Requisition;
using Microsoft.Inventory.Tracking;
using Microsoft.Inventory.Transfer;
using Microsoft.Manufacturing.ProductionBOM;
using Microsoft.Purchases.Document;
using Microsoft.Sales.Document;

codeunit 91015 CF_MaterialSupplyMgt
{
    procedure Open(SalesLine: Record "Sales Line"; var Choices: Record CF_DocumentLineProductConfig temporary)
    var
        Setup: Record CF_SalesConfiguratorSetup;
        Rows: Record CF_BOMBuffer temporary;
        Lines: Record CF_MaterialSupplyLine temporary;
        DraftMgt: Codeunit CF_BOMDraftMgt;
        Review: Page CF_MaterialSupplyReview;
    begin
        SalesLine.TestField("Document Type", SalesLine."Document Type"::Order);
        SalesLine.TestField("Drop Shipment", false);
        SalesLine.TestField("Outstanding Quantity");
        CheckSource(SalesLine, false);
        Setup.Get();
        DraftMgt.GetPreview(SalesLine, Choices, Rows);
        Calculate(SalesLine, Rows, Setup."Material Receipt Policy", Lines);
        FilterShortages(Lines);
        if Lines.IsEmpty() then begin
            Message(NoShortagesMsg);
            exit;
        end;

        Review.SetLines(Lines, Setup."Material Receipt Policy");
        Review.LookupMode(true);
        if Review.RunModal() <> Action::LookupOK then
            exit;
        CreateSelected(SalesLine, Rows, Setup."Material Receipt Policy", Lines);
    end;

    procedure Calculate(SalesLine: Record "Sales Line"; var Rows: Record CF_BOMBuffer temporary; Policy: Enum CF_MaterialReceiptPolicy; var Lines: Record CF_MaterialSupplyLine temporary)
    var
        Root: Record CF_BOMBuffer temporary;
        Reader: Record CF_MaterialSupplyLine temporary;
        DateLine: Record "Sales Line";
        Progress: Boolean;
    begin
        Lines.Reset();
        Lines.DeleteAll();
        Root.Copy(Rows, true);
        Root.Reset();
        Root.SetCurrentKey("Source Line ID", "Sort Order");
        Root.FindFirst();
        DateLine := SalesLine;
        if DateLine."Requested Delivery Date" <> 0D then begin
            DateLine.SuspendStatusCheck(true);
            DateLine.Validate("Requested Delivery Date", DateLine."Requested Delivery Date");
        end;
        if DateLine."Shipment Date" = 0D then
            DateLine."Shipment Date" := WorkDate();
        BuildNodes(Rows, Root, Lines, DateLine."Shipment Date", SalesLine."Location Code", Root."Parent Node ID");
        Lines.Get(Root."Node ID");
        SalesLine.CalcFields("Reserved Qty. (Base)");
        Lines."Required Quantity" := SalesLine."Outstanding Qty. (Base)" - SalesLine."Reserved Qty. (Base)" +
            ReservedToProposals(SalesLine);
        if Lines."Required Quantity" < 0 then
            Lines."Required Quantity" := 0;
        Lines.Modify();

        Reader.Copy(Lines, true);
        Reader.Reset();
        Reader.SetRange(Processed, false);
        while not Reader.IsEmpty() do begin
            MarkUnneededNodes(Lines);
            if Reader.IsEmpty() then
                break;
            Progress := false;
            Reader.FindSet();
            repeat
                if ItemReady(Lines, Reader."Item No.") then begin
                    ProcessItem(SalesLine, Rows, Lines, Reader."Item No.", Root."Node ID", Policy);
                    Progress := true;
                    break;
                end;
            until Reader.Next() = 0;
            if not Progress then
                Error(DependencyErr);
        end;
        Lines.Reset();
    end;

    procedure CheckSelected(var Lines: Record CF_MaterialSupplyLine temporary)
    var
        Reader: Record CF_MaterialSupplyLine temporary;
    begin
        Reader.Copy(Lines, true);
        FilterShortages(Reader);
        Reader.SetRange(Selected, true);
        if not Reader.FindSet() then
            Error(SelectShortageErr);
        repeat
            Reader.TestField("Required Date");
            case Reader."Replenishment System" of
                Reader."Replenishment System"::Purchase:
                    Reader.TestField("Vendor No.");
                Reader."Replenishment System"::Transfer:
                    begin
                        Reader.TestField("Location Code");
                        Reader.TestField("Transfer-from Code");
                        if Reader."Transfer-from Code" = Reader."Location Code" then
                            Error(SameLocationErr, Reader."Item No.");
                    end;
            end;
        until Reader.Next() = 0;
    end;

    local procedure BuildNodes(var Rows: Record CF_BOMBuffer temporary; Node: Record CF_BOMBuffer; var Lines: Record CF_MaterialSupplyLine temporary; NeededDate: Date; LocationCode: Code[10]; ParentId: Guid)
    var
        Item: Record Item;
        SKU: Record "Stockkeeping Unit";
        Components: Record CF_BOMBuffer temporary;
        Planning: Codeunit "Planning-Get Parameters";
        Tree: Codeunit CF_BOMTreeMgt;
        NativeTree: Codeunit "Calculate BOM Tree";
    begin
        Item.Get(Node."No.");
        if Item.Type <> Item.Type::Inventory then
            exit;
        Planning.AtSKU(SKU, Node."No.", Node."Variant Code", LocationCode);
        Item."Safety Lead Time" := SKU."Safety Lead Time";
        Item."Lead Time Calculation" := SKU."Lead Time Calculation";
        // This action supplies materials for the configured production output, not the finished item.
        if IsNullGuid(ParentId) then
            SKU."Replenishment System" := SKU."Replenishment System"::"Prod. Order";
        Lines.Init();
        Lines."Node ID" := Node."Node ID";
        Lines."Parent Node ID" := ParentId;
        Lines.Selected := true;
        Lines."Item No." := Item."No.";
        Lines.Description := Node.Description;
        Lines."Variant Code" := Node."Variant Code";
        Lines."Location Code" := LocationCode;
        Lines."Required Date" := NeededDate;
        Lines."Unit of Measure Code" := Item."Base Unit of Measure";
        Lines."Replenishment System" := SKU."Replenishment System";
        Lines."Vendor No." := SKU."Vendor No.";
        Lines."Transfer-from Code" := SKU."Transfer-from Code";
        Lines.Insert();
        case SKU."Replenishment System" of
            SKU."Replenishment System"::Purchase, SKU."Replenishment System"::Transfer:
                exit;
            SKU."Replenishment System"::"Prod. Order", SKU."Replenishment System"::Assembly:
                begin
                    Tree.GetComponents(Rows, Node."Node ID", Components);
                    if Components.FindSet() then
                        repeat
                            BuildNodes(Rows, Components, Lines,
                                NativeTree.CalcCompDueDate(NeededDate, Item, Components."Lead-Time Offset"),
                                SKU."Components at Location", Node."Node ID");
                        until Components.Next() = 0;
                end;
            else
                Error(UnsupportedSupplyErr, Item."No.", SKU."Replenishment System");
        end;
    end;

    local procedure ItemReady(var Lines: Record CF_MaterialSupplyLine temporary; ItemNo: Code[20]): Boolean
    var
        Reader: Record CF_MaterialSupplyLine temporary;
        Parent: Record CF_MaterialSupplyLine temporary;
    begin
        Reader.Copy(Lines, true);
        Parent.Copy(Lines, true);
        Reader.Reset();
        Reader.SetRange("Item No.", ItemNo);
        if Reader.FindSet() then
            repeat
                if not IsNullGuid(Reader."Parent Node ID") then begin
                    Parent.Get(Reader."Parent Node ID");
                    if not Parent.Processed then
                        exit(false);
                end;
            until Reader.Next() = 0;
        exit(true);
    end;

    local procedure MarkUnneededNodes(var Lines: Record CF_MaterialSupplyLine temporary)
    var
        Reader: Record CF_MaterialSupplyLine temporary;
        Parent: Record CF_MaterialSupplyLine temporary;
        Progress: Boolean;
    begin
        Reader.Copy(Lines, true);
        Parent.Copy(Lines, true);
        Reader.Reset();
        Reader.SetRange(Processed, false);
        Reader.SetRange("Required Quantity", 0);
        repeat
            Progress := false;
            if Reader.FindSet() then
                repeat
                    if IsNullGuid(Reader."Parent Node ID") then
                        Reader.Processed := true
                    else begin
                        Parent.Get(Reader."Parent Node ID");
                        Reader.Processed := Parent.Processed;
                    end;
                    if Reader.Processed then begin
                        Reader.Modify();
                        Progress := true;
                    end;
                until Reader.Next() = 0;
        until not Progress;
    end;

    local procedure ProcessItem(SalesLine: Record "Sales Line"; var Rows: Record CF_BOMBuffer temporary; var Lines: Record CF_MaterialSupplyLine temporary; ItemNo: Code[20]; RootId: Guid; Policy: Enum CF_MaterialReceiptPolicy)
    var
        Reader: Record CF_MaterialSupplyLine temporary;
        Used: Record CF_MaterialSupplyLine temporary;
        Available: Decimal;
    begin
        Reader.Copy(Lines, true);
        Used.Copy(Lines, true);
        Reader.Reset();
        Reader.SetCurrentKey("Item No.", "Required Date", "Variant Code", "Location Code");
        Reader.SetRange("Item No.", ItemNo);
        if Reader.FindSet() then
            repeat
                Used.Reset();
                Used.SetRange("Item No.", ItemNo);
                Used.SetRange("Variant Code", Reader."Variant Code");
                Used.SetRange("Location Code", Reader."Location Code");
                Used.SetRange(Processed, true);
                Used.CalcSums("Covered Quantity");
                Available := GetAvailable(Reader, Policy) - Used."Covered Quantity";
                if Reader."Node ID" = RootId then
                    if SalesLine."Shipment Date" <= Reader."Required Date" then
                        Available += SalesLine."Outstanding Qty. (Base)" - SalesLine."Reserved Qty. (Base)";
                if Available < 0 then
                    Available := 0;
                Reader."Covered Quantity" := Available;
                if Reader."Covered Quantity" > Reader."Required Quantity" then
                    Reader."Covered Quantity" := Reader."Required Quantity";
                Reader."Shortage Quantity" := Reader."Required Quantity" - Reader."Covered Quantity";
                Reader.Processed := true;
                Reader.Modify();
                if (Reader."Shortage Quantity" > 0) and
                   (Reader."Replenishment System" in [Reader."Replenishment System"::"Prod. Order",
                       Reader."Replenishment System"::Assembly])
                then
                    SetChildDemand(Rows, Lines, Reader);
            until Reader.Next() = 0;
    end;

    local procedure GetAvailable(Line: Record CF_MaterialSupplyLine; Policy: Enum CF_MaterialReceiptPolicy): Decimal
    var
        Item: Record Item;
        ATP: Codeunit "Available to Promise";
        Lookahead: DateFormula;
        Gross: Decimal;
        Receipts: Decimal;
        Available: Decimal;
    begin
        Item.Get(Line."Item No.");
        Item.SetRange("Variant Filter", Line."Variant Code");
        Item.SetRange("Location Filter", Line."Location Code");
        Item.SetRange("Drop Shipment Filter", false);
        Item.SetRange("Date Filter", 0D, Line."Required Date");
        Available := ATP.CalcQtyAvailableToPromise(Item, Gross, Receipts, 0D, "Analysis Period Type"::Day, Lookahead);
        // Worksheet proposals are not actual supply orders or firm material demand.
        Available += Item."Planning Issues (Qty.)" + Item."Planning Transfer Ship. (Qty).";
        if Policy = Policy::AllReceipts then begin
            Item.SetFilter("Date Filter", '>%1', Line."Required Date");
            Item.CalcFields("Qty. on Purch. Order", "Trans. Ord. Receipt (Qty.)", "Qty. in Transit",
                "Reserved Qty. on Purch. Orders", "Res. Qty. on Inbound Transfer");
            Available += Item."Qty. on Purch. Order" + Item."Trans. Ord. Receipt (Qty.)" + Item."Qty. in Transit" -
                Item."Reserved Qty. on Purch. Orders" - Item."Res. Qty. on Inbound Transfer";
        end;
        exit(Available);
    end;

    local procedure ReservedToProposals(SalesLine: Record "Sales Line") Quantity: Decimal
    var
        Demand: Record "Reservation Entry";
        Supply: Record "Reservation Entry";
    begin
        SalesLine.SetReservationFilters(Demand);
        Demand.SetRange(Positive, false);
        Demand.SetRange("Reservation Status", Demand."Reservation Status"::Reservation);
        if Demand.FindSet() then
            repeat
                Supply.Get(Demand."Entry No.", true);
                if Supply."Source Type" = Database::"Requisition Line" then
                    Quantity -= Demand."Quantity (Base)";
            until Demand.Next() = 0;
    end;

    local procedure SetChildDemand(var Rows: Record CF_BOMBuffer temporary; var Lines: Record CF_MaterialSupplyLine temporary; Parent: Record CF_MaterialSupplyLine)
    var
        Children: Record CF_MaterialSupplyLine temporary;
        Components: Record CF_BOMBuffer temporary;
        Node: Record CF_BOMBuffer temporary;
        Item: Record Item;
        SKU: Record "Stockkeeping Unit";
        Formula: Record "Production BOM Line" temporary;
        Tree: Codeunit CF_BOMTreeMgt;
        Planning: Codeunit "Planning-Get Parameters";
        CostMgt: Codeunit "Mfg. Cost Calculation Mgt.";
        RoutingNo: Code[20];
    begin
        Children.Copy(Lines, true);
        Children.Reset();
        Children.SetRange("Parent Node ID", Parent."Node ID");
        if Children.IsEmpty() then
            exit;
        Item.Get(Parent."Item No.");
        Planning.AtSKU(SKU, Parent."Item No.", Parent."Variant Code", Parent."Location Code");
        Node.Copy(Rows, true);
        Node.Reset();
        Node.SetRange("Node ID", Parent."Node ID");
        Node.FindFirst();
        RoutingNo := SKU."Routing No.";
        if Node."Base Selection Set" then
            RoutingNo := Node."Base Routing";
        Tree.GetComponents(Rows, Parent."Node ID", Components);
        if Components.FindSet() then
            repeat
                if Children.Get(Components."Node ID") then begin
                    Formula.Init();
                    Formula.Type := Formula.Type::Item;
                    Formula."No." := Components."No.";
                    Formula."Variant Code" := Components."Variant Code";
                    Formula."Unit of Measure Code" := Components."Unit of Measure Code";
                    Formula."Routing Link Code" := Components."Routing Link Code";
                    Formula."Scrap %" := Components."Scrap %";
                    Formula."Quantity per" := Tree.GetComponentQuantityPer(Components, 1);
                    Formula.Length := Components.Length;
                    Formula.Width := Components.Width;
                    Formula.Depth := Components.Depth;
                    Formula.Weight := Components.Weight;
                    Formula.Validate("Calculation Formula", Components."Calculation Formula");
                    Children."Required Quantity" := CostMgt.CalcCompItemQtyBase(Formula, Parent."Required Date",
                        CostMgt.CalcQtyAdjdForBOMScrap(Parent."Shortage Quantity", Item."Scrap %"), RoutingNo, true);
                    Children.Modify();
                end;
            until Components.Next() = 0;
    end;

    [CommitBehavior(CommitBehavior::Error)]
    local procedure CreateSelected(SalesLine: Record "Sales Line"; var Rows: Record CF_BOMBuffer temporary; Policy: Enum CF_MaterialReceiptPolicy; var Lines: Record CF_MaterialSupplyLine temporary)
    var
        Setup: Record CF_SalesConfiguratorSetup;
        Fresh: Record CF_MaterialSupplyLine temporary;
        Reader: Record CF_MaterialSupplyLine temporary;
        Orders: Record CF_MaterialSupplyLine temporary;
        Purchases: Record "Purchase Header" temporary;
        Transfers: Record "Transfer Header" temporary;
        PurchaseNos: Text;
        TransferNos: Text;
    begin
        CheckSelected(Lines);
        CheckSource(SalesLine, true);
        Setup.Get();
        if Setup."Material Receipt Policy" <> Policy then
            Error(ChangedReviewErr);
        Calculate(SalesLine, Rows, Policy, Fresh);
        Reader.Copy(Lines, true);
        FilterShortages(Reader);
        Reader.SetRange(Selected, true);
        Reader.FindSet();
        repeat
            if not Fresh.Get(Reader."Node ID") then
                Error(ChangedReviewErr);
            if (Fresh."Shortage Quantity" <> Reader."Shortage Quantity") or
               (Fresh."Required Quantity" <> Reader."Required Quantity") or
               (Fresh."Replenishment System" <> Reader."Replenishment System") or
               (Fresh."Unit of Measure Code" <> Reader."Unit of Measure Code") or
               (Fresh."Location Code" <> Reader."Location Code") or
               (Fresh."Required Date" <> Reader."Required Date")
            then
                Error(ChangedReviewErr);
        until Reader.Next() = 0;

        AggregateSelected(Reader, Orders);
        Orders.Reset();
        Orders.FindSet();
        repeat
            case Orders."Replenishment System" of
                Orders."Replenishment System"::Purchase:
                    CreatePurchase(Orders, Purchases);
                Orders."Replenishment System"::Transfer:
                    CreateTransfer(Orders, Transfers);
            end;
        until Orders.Next() = 0;
        Purchases.Reset();
        if Purchases.FindSet() then
            repeat
                if PurchaseNos <> '' then
                    PurchaseNos += ', ';
                PurchaseNos += Purchases."No.";
            until Purchases.Next() = 0;
        Transfers.Reset();
        if Transfers.FindSet() then
            repeat
                if TransferNos <> '' then
                    TransferNos += ', ';
                TransferNos += Transfers."No.";
            until Transfers.Next() = 0;
        Message(CreatedMsg, PurchaseNos, TransferNos);
    end;

    local procedure AggregateSelected(var Selected: Record CF_MaterialSupplyLine temporary; var Orders: Record CF_MaterialSupplyLine temporary)
    begin
        Selected.FindSet();
        repeat
            Orders.Reset();
            Orders.SetRange("Item No.", Selected."Item No.");
            Orders.SetRange("Variant Code", Selected."Variant Code");
            Orders.SetRange("Location Code", Selected."Location Code");
            Orders.SetRange("Required Date", Selected."Required Date");
            Orders.SetRange("Replenishment System", Selected."Replenishment System");
            Orders.SetRange("Vendor No.", Selected."Vendor No.");
            Orders.SetRange("Transfer-from Code", Selected."Transfer-from Code");
            if Orders.FindFirst() then begin
                Orders."Shortage Quantity" += Selected."Shortage Quantity";
                Orders.Modify();
            end else begin
                Orders := Selected;
                Orders.Insert();
            end;
        until Selected.Next() = 0;
    end;

    local procedure CreatePurchase(Line: Record CF_MaterialSupplyLine; var Created: Record "Purchase Header" temporary)
    var
        Header: Record "Purchase Header";
        PurchLine: Record "Purchase Line";
        Item: Record Item;
        NextLineNo: Integer;
    begin
        Created.Reset();
        Created.SetRange("Buy-from Vendor No.", Line."Vendor No.");
        Created.SetRange("Location Code", Line."Location Code");
        if Created.FindFirst() then
            Header.Get(Header."Document Type"::Order, Created."No.")
        else begin
            Header.Init();
            Header."Document Type" := Header."Document Type"::Order;
            Header.Insert(true);
            Header.Validate("Buy-from Vendor No.", Line."Vendor No.");
            Header.Validate("Location Code", Line."Location Code");
            Header.Modify(true);
            Created := Header;
            Created.Insert();
        end;
        PurchLine.SetRange("Document Type", Header."Document Type");
        PurchLine.SetRange("Document No.", Header."No.");
        if PurchLine.FindLast() then
            NextLineNo := PurchLine."Line No.";
        PurchLine.Init();
        PurchLine."Document Type" := Header."Document Type";
        PurchLine."Document No." := Header."No.";
        PurchLine."Line No." := NextLineNo + 10000;
        PurchLine.Validate(Type, PurchLine.Type::Item);
        PurchLine.Validate("No.", Line."Item No.");
        PurchLine.Validate("Variant Code", Line."Variant Code");
        PurchLine.Validate("Location Code", Line."Location Code");
        Item.Get(Line."Item No.");
        if Item."Purch. Unit of Measure" <> '' then
            PurchLine.Validate("Unit of Measure Code", Item."Purch. Unit of Measure")
        else
            PurchLine.Validate("Unit of Measure Code", Item."Base Unit of Measure");
        PurchLine.Validate(Quantity, OrderQuantity(Item, PurchLine."Unit of Measure Code",
            PurchLine."Qty. per Unit of Measure", Line."Shortage Quantity"));
        if PurchLine."Quantity (Base)" < Line."Shortage Quantity" then
            Error(QuantityRoundingErr, Line."Item No.");
        PurchLine.Validate("Expected Receipt Date", Line."Required Date");
        PurchLine.Insert(true);
    end;

    local procedure CreateTransfer(Line: Record CF_MaterialSupplyLine; var Created: Record "Transfer Header" temporary)
    var
        Header: Record "Transfer Header";
        TransferLine: Record "Transfer Line";
        Item: Record Item;
        NextLineNo: Integer;
    begin
        Created.Reset();
        Created.SetRange("Transfer-from Code", Line."Transfer-from Code");
        Created.SetRange("Transfer-to Code", Line."Location Code");
        if Created.FindFirst() then
            Header.Get(Created."No.")
        else begin
            Header.Init();
            Header.Insert(true);
            Header.Validate("Transfer-from Code", Line."Transfer-from Code");
            Header.Validate("Transfer-to Code", Line."Location Code");
            Header.Validate("Receipt Date", Line."Required Date");
            Header.Modify(true);
            Created := Header;
            Created.Insert();
        end;
        TransferLine.SetRange("Document No.", Header."No.");
        if TransferLine.FindLast() then
            NextLineNo := TransferLine."Line No.";
        TransferLine.Init();
        TransferLine."Document No." := Header."No.";
        TransferLine."Line No." := NextLineNo + 10000;
        TransferLine.Validate("Item No.", Line."Item No.");
        TransferLine.Validate("Variant Code", Line."Variant Code");
        Item.Get(Line."Item No.");
        TransferLine.Validate("Unit of Measure Code", Item."Base Unit of Measure");
        TransferLine.Validate(Quantity, OrderQuantity(Item, TransferLine."Unit of Measure Code",
            TransferLine."Qty. per Unit of Measure", Line."Shortage Quantity"));
        if TransferLine."Quantity (Base)" < Line."Shortage Quantity" then
            Error(QuantityRoundingErr, Line."Item No.");
        TransferLine.Validate("Receipt Date", Line."Required Date");
        TransferLine.Insert(true);
    end;

    local procedure OrderQuantity(Item: Record Item; UOM: Code[10]; QtyPerUOM: Decimal; BaseQuantity: Decimal): Decimal
    var
        UOMMgt: Codeunit "Unit of Measure Management";
        Precision: Decimal;
        BasePrecision: Decimal;
    begin
        if QtyPerUOM <= 0 then
            Error(InvalidUOMErr, Item."No.", UOM);
        Precision := UOMMgt.GetQtyRoundingPrecision(Item, UOM);
        if Precision = 0 then
            Precision := UOMMgt.QtyRndPrecision();
        BasePrecision := UOMMgt.GetQtyRoundingPrecision(Item, Item."Base Unit of Measure");
        if BasePrecision = 0 then
            BasePrecision := UOMMgt.QtyRndPrecision();
        BaseQuantity := Round(BaseQuantity, BasePrecision, '>');
        exit(Round(BaseQuantity / QtyPerUOM, Precision, '>'));
    end;

    local procedure FilterShortages(var Lines: Record CF_MaterialSupplyLine temporary)
    begin
        Lines.Reset();
        Lines.SetFilter("Shortage Quantity", '>0');
        Lines.SetFilter("Replenishment System", '%1|%2',
            Lines."Replenishment System"::Purchase, Lines."Replenishment System"::Transfer);
    end;

    local procedure CheckSource(Source: Record "Sales Line"; LockSource: Boolean)
    var
        Current: Record "Sales Line";
    begin
        if LockSource then
            Current.LockTable();
        if not Current.GetBySystemId(Source.SystemId) then
            Error(SourceChangedErr);
        if Current.SystemModifiedAt <> Source.SystemModifiedAt then
            Error(SourceChangedErr);
    end;

    var
        NoShortagesMsg: Label 'No purchase/transfer material shortages were found for the net new production demand under the material receipt policy.';
        SelectShortageErr: Label 'Select at least one material shortage.';
        SameLocationErr: Label 'The transfer source and destination must differ for item %1.', Comment = '%1 = item number';
        DependencyErr: Label 'The configured material dependencies cannot be netted. Check for circular item dependencies across configured branches.';
        UnsupportedSupplyErr: Label 'Item %1 has an unsupported replenishment system: %2.', Comment = '%1 = item number, %2 = replenishment system';
        ChangedReviewErr: Label 'Material demand, availability or setup changed while the review was open. Reopen Create Material Supply to review current shortages. No orders were created.';
        SourceChangedErr: Label 'The source sales line changed or no longer exists. Reopen Product Configurator before creating material supply.';
        InvalidUOMErr: Label 'Item %1 unit %2 must have a positive quantity per unit of measure.', Comment = '%1 = item number, %2 = unit of measure';
        QuantityRoundingErr: Label 'Native unit rounding leaves item %1 below the reviewed shortage. Check its unit-of-measure precision before creating supply.', Comment = '%1 = item number';
        CreatedMsg: Label 'Purchase orders created: %1\Transfer orders created: %2\Orders are open and have not been released or posted. The configuration has not been applied.', Comment = '%1 = purchase order numbers, %2 = transfer order numbers';
}
