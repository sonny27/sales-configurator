namespace CloudFactory.SalesConfigurator;

using Microsoft.Foundation.Company;
using Microsoft.Foundation.Enums;
using Microsoft.Foundation.UOM;
using Microsoft.Inventory.Availability;
using Microsoft.Inventory.Costing;
using Microsoft.Inventory.BOM;
using Microsoft.Inventory.BOM.Tree;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Planning;
using Microsoft.Inventory.Requisition;
using Microsoft.Manufacturing.ProductionBOM;
using Microsoft.Sales.Document;

codeunit 91013 CF_ConfigAvailabilityMgt
{
    EventSubscriberInstance = Manual;

    procedure ShowStandard(SalesLine: Record "Sales Line"; AvailabilityType: Enum "Item Availability Type")
    var
        Item: Record Item;
        FormsMgt: Codeunit "Item Availability Forms Mgt";
        NewDate: Date;
        NewCode: Code[10];
    begin
        Item.Get(SalesLine."No.");
        FormsMgt.FilterItem(Item, SalesLine."Location Code", SalesLine."Variant Code", SalesLine."Shipment Date");
        case AvailabilityType of
            AvailabilityType::"Event":
                FormsMgt.ShowItemAvailabilityByEvent(Item, '', SalesLine."Shipment Date", NewDate, false);
            AvailabilityType::Period:
                FormsMgt.ShowItemAvailabilityByPeriod(Item, '', SalesLine."Shipment Date", NewDate);
            AvailabilityType::Variant:
                FormsMgt.ShowItemAvailabilityByVariant(Item, '', SalesLine."Variant Code", NewCode);
            AvailabilityType::Location:
                FormsMgt.ShowItemAvailabilityByLocation(Item, '', SalesLine."Location Code", NewCode);
            AvailabilityType::UOM:
                FormsMgt.ShowItemAvailabilityByUOM(Item, '', SalesLine."Unit of Measure Code", NewCode);
            else
                Error('This availability view is not supported by the standard item viewer.');
        end;
    end;

    procedure ShowLot(SalesLine: Record "Sales Line")
    var
        Item: Record Item;
        FormsMgt: Codeunit "Item Availability Forms Mgt";
    begin
        Item.Get(SalesLine."No.");
        FormsMgt.FilterItem(Item, SalesLine."Location Code", SalesLine."Variant Code", SalesLine."Shipment Date");
        Item.SetRecFilter();
        Page.RunModal(Page::"Item Availability by Lot No.", Item);
    end;

    procedure ShowBOM(SalesLine: Record "Sales Line"; var Choices: Record CF_DocumentLineProductConfig temporary)
    var
        Item: Record Item;
        Availability: Page "Item Availability by BOM Level";
        FormsMgt: Codeunit "Item Availability Forms Mgt";
    begin
        Prepare(SalesLine, Choices);
        Item.Get(Source."No.");
        FormsMgt.FilterItem(Item, Source."Location Code", Source."Variant Code", Source."Shipment Date");
        Availability.InitItem(Item);
        Availability.InitSource(Rows, "BOM Structure Show By"::CF_Configuration);
        Availability.InitDate(Source."Shipment Date");
        BindSubscription(this);
        Availability.RunModal();
        UnbindSubscription(this);
    end;

    procedure ShowPromising(SalesLine: Record "Sales Line"; var Choices: Record CF_DocumentLineProductConfig temporary)
    var
        Header: Record "Sales Header";
        PromisingLine: Record "Order Promising Line" temporary;
        Availability: Page "Order Promising Lines";
    begin
        SalesLine.TestField("Document Type", SalesLine."Document Type"::Order);
        SalesLine.TestField("Drop Shipment", false);
        SalesLine.TestField("Outstanding Quantity");
        Prepare(SalesLine, Choices);
        Header.Get(Source."Document Type", Source."Document No.");
        ContextId := CreateGuid();
        PromisingId := CopyStr(DelChr(Format(ContextId), '=', '{}-'), 1, MaxStrLen(PromisingId));
        PromisingLine.SetRange("Source Type", PromisingLine."Source Type"::Sales);
        PromisingLine.SetRange("Source ID", Source."Document No.");
        PromisingLine.SetRange("Source Line No.", Source."Line No.");
        Availability.SetSource(PromisingLine."Source Type"::Sales);
        Availability.SetTableView(PromisingLine);
        Promising := true;
        BindSubscription(this);
        Availability.RunModal();
        UnbindSubscription(this);
        Promising := false;
    end;

    local procedure Prepare(SalesLine: Record "Sales Line"; var Choices: Record CF_DocumentLineProductConfig temporary)
    var
        DraftMgt: Codeunit CF_BOMDraftMgt;
    begin
        Source := SalesLine;
        CheckSource(false);
        DraftMgt.GetPreview(Source, Choices, Rows);
        Rows.Reset();
        Rows.SetCurrentKey("Source Line ID", "Sort Order");
        Rows.FindFirst();
        RootId := Rows."Node ID";
        Clear(DemandNodes);
        Clear(DemandLocations);
        Clear(CurrentDemand);
        TransferDemand := false;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::CF_PromisePlanMgt, 'OnBeforeConfiguredAccept', '', false, false)]
    local procedure CheckAccept(var PromisingLine: Record "Order Promising Line")
    begin
        if not Promising then
            exit;
        PromisingLine.TestField("Source Type", PromisingLine."Source Type"::Sales);
        PromisingLine.TestField("Source ID", Source."Document No.");
        PromisingLine.TestField("Source Line No.", Source."Line No.");
        CheckSource(true);
    end;

    local procedure CheckSource(LockSource: Boolean)
    var
        Current: Record "Sales Line";
    begin
        if LockSource then
            Current.LockTable();
        if not Current.GetBySystemId(Source.SystemId) then
            Error('The source sales line no longer exists.');
        if (Current."No." <> Source."No.") or (Current."Variant Code" <> Source."Variant Code") or
           (Current."Location Code" <> Source."Location Code") or (Current."Unit of Measure Code" <> Source."Unit of Measure Code") or
           (Current.Quantity <> Source.Quantity) or (Current."Outstanding Qty. (Base)" <> Source."Outstanding Qty. (Base)") or
           (Current."Shipment Date" <> Source."Shipment Date")
        then
            Error('The source sales line changed. Reopen Product Configurator and calculate availability again.');
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales Availability Mgt.", 'OnOpenPageOnSetSourceOnAfterSetShouldExit', '', false, false)]
    local procedure SkipHeaderWidePromising(CrntSourceType: Enum "Order Promising Line Source Type"; var ShouldExit: Boolean)
    begin
        if Promising then
            ShouldExit := true;
    end;

    [EventSubscriber(ObjectType::Page, Page::"Order Promising Lines", 'OnOpenPageOnSetSource', '', false, false)]
    local procedure InitializePromising(var OrderPromisingLine: Record "Order Promising Line"; var CrntSourceType: Enum "Order Promising Line Source Type"; var CrntSourceID: Code[20]; var AvailabilityMgt: Codeunit AvailabilityManagement; var AcceptButtonEnable: Boolean)
    var
        Header: Record "Sales Header";
    begin
        if not Promising then
            exit;
        Header.Get(Source."Document Type", Source."Document No.");
        AvailabilityMgt.SetSourceRecord(OrderPromisingLine, Header);
        if OrderPromisingLine.IsEmpty() then
            Error('The selected sales line has no quantity available for order promising.');
        CrntSourceType := CrntSourceType::Sales;
        CrntSourceID := PromisingId;
        AcceptButtonEnable := Header.Status = Header.Status::Open;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales Availability Mgt.", 'OnSetSalesHeaderOnAfterFilterSalesLine', '', false, false)]
    local procedure FilterSelectedLine(var SalesLine: Record "Sales Line"; SalesHeader: Record "Sales Header")
    begin
        if not Promising then
            exit;
        if (SalesHeader."Document Type" <> Source."Document Type") or (SalesHeader."No." <> Source."Document No.") then
            Error('A different sales document was requested during configured order promising.');
        SalesLine.SetRange("Line No.", Source."Line No.");
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::AvailabilityManagement, 'OnBeforeCalcCapableToPromise', '', false, false)]
    local procedure CheckManufacturing(var OrderPromisingLine: Record "Order Promising Line"; var CompanyInformation: Record "Company Information"; var OrderPromisingID: Code[20]; var LastValidLine: Integer; var IsHandled: Boolean)
    var
        SKU: Record "Stockkeeping Unit";
        Planning: Codeunit "Planning-Get Parameters";
    begin
        if not Promising then
            exit;
        Planning.AtSKU(SKU, Source."No.", Source."Variant Code", Source."Location Code");
        SKU.TestField("Replenishment System", SKU."Replenishment System"::"Prod. Order");
        OrderPromisingID := PromisingId;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Capable to Promise", 'OnBeforeValidateCapableToPromise', '', false, false)]
    local procedure IdentifyDemand(var RequisitionLine: Record "Requisition Line"; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; NeededDate: Date; NeededQty: Decimal; UnitOfMeasure: Code[10]; PeriodType: Enum "Analysis Period Type"; var DueDateOfReqLine: Date; var Result: Boolean; var IsHandled: Boolean)
    var
        Node: Record CF_BOMBuffer temporary;
        ExpectedLocation: Code[10];
    begin
        if not Promising then
            exit;
        if TransferDemand then begin
            CurrentDemand := TransferNode;
            TransferDemand := false;
            exit;
        end;
        if (ItemNo = Source."No.") and (VariantCode = Source."Variant Code") and (LocationCode = Source."Location Code") then begin
            Clear(DemandNodes);
            Clear(DemandLocations);
            CurrentDemand := RootId;
            exit;
        end;
        if DemandNodes.Count() = 0 then
            Error('The native CTP demand for %1 at %2 does not match the configured BOM.', ItemNo, LocationCode);
        CurrentDemand := DemandNodes.Get(1);
        DemandNodes.RemoveAt(1);
        if IsNullGuid(CurrentDemand) then
            exit;
        Node.Copy(Rows, true);
        Node.Get(Source.SystemId, CurrentDemand);
        DemandLocations.Get(CurrentDemand, ExpectedLocation);
        if (Node."No." <> ItemNo) or (Node."Variant Code" <> VariantCode) or (ExpectedLocation <> LocationCode) then
            Error('The native CTP demand for %1 at %2 does not match the configured component %3 at %4.',
                ItemNo, LocationCode, Node."No.", ExpectedLocation);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Capable to Promise", 'OnBeforeReqLineInsert', '', false, false)]
    local procedure FreezePlanningContext(var RequisitionLine: Record "Requisition Line")
    var
        PlanMgt: Codeunit CF_PromisePlanMgt;
    begin
        if not Promising then
            exit;
        if RequisitionLine."Order Promising ID" <> PromisingId then
            exit;
        if IsNullGuid(CurrentDemand) then
            exit;
        PlanMgt.StoreContext(ContextId, Source, Rows);
        RequisitionLine.CF_PromiseContextId := ContextId;
        RequisitionLine.CF_BOMNodeId := CurrentDemand;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Capable to Promise", 'OnBeforeCheckCompsCapableToPromise', '', false, false)]
    local procedure QueueComponentDemands(RequisitionLine: Record "Requisition Line"; PeriodType: Enum "Analysis Period Type"; var Result: Boolean; var IsHandled: Boolean)
    var
        Component: Record "Planning Component";
        Children: List of [Guid];
        Index: Integer;
    begin
        if not Promising then
            exit;
        if RequisitionLine."Order Promising ID" <> PromisingId then
            exit;
        Component.SetRange("Worksheet Template Name", RequisitionLine."Worksheet Template Name");
        Component.SetRange("Worksheet Batch Name", RequisitionLine."Journal Batch Name");
        Component.SetRange("Worksheet Line No.", RequisitionLine."Line No.");
        Component.SetFilter(Quantity, '<>%1', 0);
        Component.SetRange(Critical, true);
        Component.SetRange("Supplied-by Line No.", 0);
        if Component.FindSet() then
            repeat
                if IsNullGuid(Component.CF_BOMNodeId) then
                    if RequisitionLine.CF_PromiseContextId = ContextId then
                        Error('Planning component %1 has lost its configured BOM identity.', Component."Item No.");
                Children.Add(Component.CF_BOMNodeId);
                if not IsNullGuid(Component.CF_BOMNodeId) then
                    DemandLocations.Set(Component.CF_BOMNodeId, Component."Location Code");
            until Component.Next() = 0;
        for Index := Children.Count() downto 1 do
            DemandNodes.Insert(1, Children.Get(Index));
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Capable to Promise", 'OnBeforeCheckTransferShptCTP', '', false, false)]
    local procedure IdentifyTransfer(RequisitionLine: Record "Requisition Line"; PeriodType: Enum "Analysis Period Type"; var Result: Boolean; var IsHandled: Boolean)
    var
        Item: Record Item;
    begin
        if not Promising or (RequisitionLine."Order Promising ID" <> PromisingId) then
            exit;
        Item.Get(RequisitionLine."No.");
        if Item.Critical then begin
            TransferDemand := true;
            TransferNode := RequisitionLine.CF_BOMNodeId;
        end;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Calculate BOM Tree", 'OnGenerateTreeForSource', '', false, false)]
    local procedure GenerateAvailability(SourceRecordVar: Variant; var BOMBuffer: Record "BOM Buffer"; BOMTreeType: Enum "BOM Tree Type"; ShowBy: Enum "BOM Structure Show By"; DemandDate: Date; var ItemFilter: Record Item; var EntryNo: Integer; sender: Codeunit "Calculate BOM Tree")
    var
        Root: Record CF_BOMBuffer temporary;
    begin
        if ShowBy <> ShowBy::CF_Configuration then
            exit;
        Root.Copy(Rows, true);
        Root.Get(Source.SystemId, RootId);
        BOMBuffer.Reset();
        BOMBuffer.DeleteAll();
        EntryNo := 0;
        AddAvailabilityNode(Root, BOMBuffer, EntryNo, 0, 1, 1, DemandDate, Source."Location Code", Source."Variant Code");
        BOMBuffer.Reset();
        BOMBuffer.FindFirst();
        sender.InitVars();
        sender.SetLocationSpecific(true);
        PrepareAvailabilityLocations(BOMBuffer);
        sender.CalculateTreeType(BOMBuffer, sender.GetShowTotalAvailability(), BOMTreeType);
        CalculatingBOM := false;
        BOMBuffer.Reset();
        BOMBuffer.FindFirst();
    end;

    local procedure PrepareAvailabilityLocations(var Buffer: Record "BOM Buffer" temporary)
    var
        Reader: Record "BOM Buffer" temporary;
        Keys: Record "Item Availability by Date" temporary;
    begin
        AvailabilityQueue.Reset();
        AvailabilityQueue.DeleteAll();
        Reader.Copy(Buffer, true);
        Reader.Reset();
        Reader.SetRange(Inventoriable, true);
        if Reader.FindSet() then
            repeat
                Keys.Init();
                Keys."Item No." := Reader."No.";
                Keys.Date := Reader."Needed by Date";
                Keys."Variant Code" := Reader."Variant Code";
                Keys."Location Code" := Reader."Location Code";
                if Keys.Insert(false) then begin
                    AvailabilityQueue := Reader;
                    AvailabilityQueue.Insert(false);
                end;
            until Reader.Next() = 0;
        CalculatingBOM := true;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Calculate BOM Tree", 'OnInitItemAvailDatesOnBeforeCalcAvailableQty', '', false, false)]
    local procedure UseComponentLocation(var BOMItem: Record Item)
    begin
        if not CalculatingBOM then
            exit;
        AvailabilityQueue.FindFirst();
        AvailabilityQueue.TestField("No.", BOMItem."No.");
        BOMItem.SetRange("Location Filter", AvailabilityQueue."Location Code");
        AvailabilityQueue.Delete(false);
    end;

    local procedure AddAvailabilityNode(Node: Record CF_BOMBuffer; var Native: Record "BOM Buffer" temporary; var EntryNo: Integer; Depth: Integer; QtyPerParent: Decimal; QtyPerTop: Decimal; NeededDate: Date; LocationCode: Code[10]; VariantCode: Code[10])
    var
        Item: Record Item;
        Components: Record CF_BOMBuffer temporary;
        Formula: Record "Production BOM Line" temporary;
        Tree: Codeunit CF_BOMTreeMgt;
        Planning: Codeunit "Planning-Get Parameters";
        SKU: Record "Stockkeeping Unit";
        UOMMgt: Codeunit "Unit of Measure Management";
        NativeTree: Codeunit "Calculate BOM Tree";
        CostMgt: Codeunit "Mfg. Cost Calculation Mgt.";
        ParentUOM: Decimal;
        ChildQty: Decimal;
        ChildDate: Date;
        OwnEntry: Integer;
        LotSize: Decimal;
        RoutingNo: Code[20];
    begin
        Item.Get(Node."No.");
        Planning.AtSKU(SKU, Node."No.", VariantCode, LocationCode);
        Tree.GetComponents(Rows, Node."Node ID", Components);
        Native.Init();
        Native.InitFromItem(Item);
        EntryNo += 1;
        OwnEntry := EntryNo;
        Native."Entry No." := EntryNo;
        Native."Variant Code" := VariantCode;
        Native."Location Code" := LocationCode;
        Native."Replenishment System" := SKU."Replenishment System";
        Native.Description := Node.Description;
        Native."Unit of Measure Code" := Node."Unit of Measure Code";
        Native.Indentation := Depth;
        Native."Is Leaf" := Components.IsEmpty();
        Native."Qty. per Parent" := QtyPerParent;
        Native."Qty. per Top Item" := QtyPerTop;
        Native."Needed by Date" := NeededDate;
        Native."Lead-Time Offset" := Node."Lead-Time Offset";
        Native."Calculation Formula" := Node."Calculation Formula";
        Native."Qty. per BOM Line" := Node."Quantity per";
        Native.Insert(false);
        ParentUOM := UOMMgt.GetQtyPerUnitOfMeasure(Item, Node."Unit of Measure Code");
        LotSize := Item."Lot Size";
        if LotSize = 0 then
            LotSize := 1;
        RoutingNo := SKU."Routing No.";
        if Node."Base Selection Set" then
            RoutingNo := Node."Base Routing";
        Components.SetCurrentKey("Source Line ID", "Sort Order");
        if Components.FindSet() then
            repeat
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
                ChildQty := CostMgt.CalcCompItemQtyBase(Formula, NeededDate,
                    CostMgt.CalcQtyAdjdForBOMScrap(LotSize, Item."Scrap %"), RoutingNo, true);
                Item.Get(Components."No.");
                ChildQty := ChildQty / UOMMgt.GetQtyPerUnitOfMeasure(Item, Components."Unit of Measure Code") / LotSize * ParentUOM;
                Item.Get(Node."No.");
                ChildDate := NativeTree.CalcCompDueDate(NeededDate, Item, Components."Lead-Time Offset");
                AddAvailabilityNode(Components, Native, EntryNo, Depth + 1, ChildQty, QtyPerTop * ChildQty,
                    ChildDate, SKU."Components at Location", Components."Variant Code");
            until Components.Next() = 0;
        Native.Get(OwnEntry);
    end;

    var
        Source: Record "Sales Line";
        Rows: Record CF_BOMBuffer temporary;
        Promising: Boolean;
        ContextId: Guid;
        PromisingId: Code[20];
        RootId: Guid;
        CurrentDemand: Guid;
        DemandNodes: List of [Guid];
        DemandLocations: Dictionary of [Guid, Code[10]];
        TransferDemand: Boolean;
        TransferNode: Guid;
        AvailabilityQueue: Record "BOM Buffer" temporary;
        CalculatingBOM: Boolean;
}
