namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Planning;
using Microsoft.Inventory.Tracking;
using Microsoft.Manufacturing.Capacity;
using Microsoft.Manufacturing.Document;
using Microsoft.Sales.Document;

codeunit 91000 CF_ConfiguratorMgt
{
    Permissions = tabledata "Production Order" = rm,
                  tabledata "Prod. Order Component" = rimd;

    var
        SnapshotErr: Label 'Production order %1 has an invalid configuration snapshot: %2.', Comment = '%1 = production order number, %2 = error detail';
        UnsupportedErr: Label '%1 is not supported for configured production order %2. Use Refresh Production Order.', Comment = '%1 = operation, %2 = order';
        ProtectedErr: Label 'Configured component %1 on production order %2 has consumption, reservations, or warehouse picks. It cannot be rebuilt or changed.', Comment = '%1 = component line, %2 = order';
        RootErr: Label 'Production order %1 must contain exactly one root line for configured item %2, variant %3.', Comment = '%1 = order, %2 = item, %3 = variant';
        CalculationErr: Label 'Production order %1 could not be calculated. Configured components have not been applied.', Comment = '%1 = order';
        ProjectErr: Label 'Sales order %1 contains product configurations. Create Item Orders instead of a Project Order.', Comment = '%1 = sales order';
        DuplicateErr: Label 'Production order %1 has duplicate configured components for option %2.', Comment = '%1 = order, %2 = option';
        RoutingErr: Label 'Routing link %1 for option %2 must match an operation on production order %3.', Comment = '%1 = routing link, %2 = option, %3 = order';
        ParentErr: Label 'The source item or variant of configured production order %1 cannot be changed.', Comment = '%1 = order';
        TraceErr: Label 'The identity of a configured component on production order %1 cannot be changed.', Comment = '%1 = order';

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Prod. Order from Sale", 'OnAfterCreateProdOrderFromSalesLine', '', false, false)]
    local procedure OnHeaderCreated(var ProdOrder: Record "Production Order"; var SalesLine: Record "Sales Line")
    var
        DocumentConfigMgt: Codeunit CF_DocumentConfigMgt;
    begin
        if ProdOrder."Source Type" <> ProdOrder."Source Type"::Item then
            exit;
        DocumentConfigMgt.ValidateForProduction(SalesLine);
        CaptureSnapshot(ProdOrder, SalesLine);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Prod. Order from Sale", 'OnBeforeCreateProdOrderLines', '', false, false)]
    local procedure BeforeCreateLines(var ProdOrder: Record "Production Order"; var SalesLine: Record "Sales Line"; var IsHandled: Boolean; OrderType: Enum "Create Production Order Type")
    var
        OrderLine: Record "Sales Line";
        Config: Record CF_DocumentLineProductConfig;
        DocumentConfigMgt: Codeunit CF_DocumentConfigMgt;
    begin
        if OrderType = OrderType::ItemOrder then
            exit;
        OrderLine.SetRange("Document Type", OrderLine."Document Type"::Order);
        OrderLine.SetRange("Document No.", SalesLine."Document No.");
        OrderLine.SetRange(Type, OrderLine.Type::Item);
        if OrderLine.FindSet() then
            repeat
                DocumentConfigMgt.FilterSalesLine(OrderLine, Config);
                Config.SetFilter("Choice Code", '<>%1', '');
                if not Config.IsEmpty() then
                    Error(ProjectErr, SalesLine."Document No.");
            until OrderLine.Next() = 0;
    end;

    procedure CaptureSnapshot(var ProdOrder: Record "Production Order"; SalesLine: Record "Sales Line")
    var
        Config: Record CF_DocumentLineProductConfig;
        DocumentConfigMgt: Codeunit CF_DocumentConfigMgt;
        Snapshot: JsonObject;
        Entry: JsonObject;
        Entries: JsonArray;
        Output: OutStream;
    begin
        ProdOrder.TestField(CF_ConfigVersion, 0);
        DocumentConfigMgt.FilterSalesLine(SalesLine, Config);
        Config.SetFilter("Choice Code", '<>%1', '');
        if not Config.FindSet() then
            exit;
        repeat
            Clear(Entry);
            Entry.Add('selectionId', Format(Config.SystemId));
            Entry.Add('option', Config."Configuration Option");
            Entry.Add('choice', Config."Choice Code");
            Entry.Add('item', Config."Component Item No.");
            Entry.Add('variant', Config."Component Variant Code");
            Entry.Add('uom', Config."Component UOM Code");
            Entry.Add('quantityPer', Config."Quantity per Unit");
            Entry.Add('routingLink', Config."Routing Link Code");
            Entries.Add(Entry);
        until Config.Next() = 0;
        ProdOrder.CF_DocumentType := ProdOrder.CF_DocumentType::SalesOrder;
        ProdOrder.CF_SourceTableId := Database::"Sales Line";
        ProdOrder.CF_SourceLineId := SalesLine.SystemId;
        ProdOrder.CF_DocumentNo := SalesLine."Document No.";
        ProdOrder.CF_DocumentLineNo := SalesLine."Line No.";
        ProdOrder.CF_ParentItemNo := SalesLine."No.";
        ProdOrder.CF_ParentVariantCode := SalesLine."Variant Code";
        Snapshot.Add('version', 1);
        Snapshot.Add('sourceLineId', Format(SalesLine.SystemId));
        Snapshot.Add('parentItem', SalesLine."No.");
        Snapshot.Add('parentVariant', SalesLine."Variant Code");
        Snapshot.Add('entries', Entries);
        Clear(ProdOrder.CF_ConfigSnapshot);
        ProdOrder.CF_ConfigSnapshot.CreateOutStream(Output, TextEncoding::UTF8);
        Snapshot.WriteTo(Output);
        ProdOrder.CF_ConfigVersion := 1;
        // This transaction-scoped flag is cleared after Copy; a failed creation rolls it back.
        ProdOrder.CF_RebuildAllowed := true;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Prod. Order Lines", 'OnBeforeCopy', '', false, false)]
    local procedure BeforeCopy(var ProductionOrder: Record "Production Order"; Direction: Option; VariantCode: Code[10]; LetDueDateDecrease: Boolean; var ErrorOccured: Boolean; var IsHandled: Boolean)
    begin
        if ProductionOrder.CF_ConfigVersion = 0 then
            exit;
        if not ProductionOrder.CF_RebuildAllowed then
            Error(UnsupportedErr, 'Direct production line recreation', ProductionOrder."No.");
        CheckUnprocessedComponents(ProductionOrder);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Prod. Order Lines", 'OnAfterCopy', '', false, false)]
    local procedure AfterCopy(var ProdOrder: Record "Production Order"; var ErrorOccured: Boolean)
    begin
        if ProdOrder.CF_ConfigVersion = 0 then
            exit;
        if ErrorOccured then
            Error(CalculationErr, ProdOrder."No.");
        ApplyConfiguredComponents(ProdOrder);
        ProdOrder.CF_RebuildAllowed := false;
        ProdOrder.Modify();
    end;

    [EventSubscriber(ObjectType::Report, Report::"Refresh Production Order", 'OnBeforeCalcProdOrder', '', false, false)]
    local procedure BeforeRefresh(var ProductionOrder: Record "Production Order"; Direction: Option)
    var
        TempConfig: Record CF_DocumentLineProductConfig temporary;
    begin
        if ProductionOrder.CF_ConfigVersion = 0 then
            exit;
        ReadSnapshot(ProductionOrder, TempConfig);
        CheckUnprocessedComponents(ProductionOrder);
        ProductionOrder.CF_RebuildAllowed := true;
        ProductionOrder.Modify();
    end;

    [EventSubscriber(ObjectType::Report, Report::"Refresh Production Order", 'OnProductionOrderOnAfterGetRecordOnAfterCalcRoutingsOrComponents', '', false, false)]
    local procedure AfterRefreshCalculation(var ProductionOrder: Record "Production Order"; CalcLines: Boolean; CalcRoutings: Boolean; CalcComponents: Boolean; var ErrorOccured: Boolean)
    begin
        if ProductionOrder.CF_ConfigVersion = 0 then
            exit;
        if ErrorOccured then
            Error(CalculationErr, ProductionOrder."No.");
        ApplyConfiguredComponents(ProductionOrder);
        ProductionOrder.CF_RebuildAllowed := false;
        ProductionOrder.Modify();
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Calculate Prod. Order", 'OnBeforeCalculate', '', false, false)]
    local procedure BeforeCalculate(var ItemLedgerEntry: Record "Item Ledger Entry"; var CapacityLedgerEntry: Record "Capacity Ledger Entry"; Direction: Option; CalcRouting: Boolean; CalcComponents: Boolean; var DeleteRelations: Boolean; LetDueDateDecrease: Boolean; var IsHandled: Boolean; var ProdOrderLine: Record "Prod. Order Line"; var ErrorOccured: Boolean)
    var
        ProductionOrder: Record "Production Order";
    begin
        ProductionOrder.Get(ProdOrderLine.Status, ProdOrderLine."Prod. Order No.");
        if (ProductionOrder.CF_ConfigVersion <> 0) and not ProductionOrder.CF_RebuildAllowed then
            Error(UnsupportedErr, 'Direct production calculation', ProductionOrder."No.");
    end;

    [EventSubscriber(ObjectType::Table, Database::"Prod. Order Component", 'OnAfterProdOrderNeeds', '', false, false)]
    local procedure ConfiguredNeeds(ProdOrderComponent: Record "Prod. Order Component"; ProdOrderLine: Record "Prod. Order Line"; ProdOrderRoutingLine: Record "Prod. Order Routing Line"; var NeededQty: Decimal)
    begin
        if ProdOrderComponent.CF_ConfiguredComponent then
            NeededQty := ProdOrderLine.Quantity;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Prod. Order Status Management", 'OnBeforeFlushProdOrder', '', false, false)]
    local procedure BeforeFlushing(var ProductionOrder: Record "Production Order"; NewStatus: Enum "Production Order Status"; PostingDate: Date; var IsHandled: Boolean)
    begin
        if (ProductionOrder.CF_ConfigVersion = 0) or (NewStatus = NewStatus::Finished) then
            exit;
        ApplyConfiguredComponents(ProductionOrder);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Prod. Order Status Management", 'OnTransProdOrderOnBeforeToProdOrderInsert', '', false, false)]
    local procedure TransferSnapshot(var ToProdOrder: Record "Production Order"; FromProdOrder: Record "Production Order"; NewPostingDate: Date)
    begin
        CopySnapshot(FromProdOrder, ToProdOrder);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Prod. Order Status Management", 'OnAfterTransferReopenProdOrder', '', false, false)]
    local procedure ReopenSnapshot(ProductionOrder: Record "Production Order"; FromProductionOrder: Record "Production Order")
    begin
        if FromProductionOrder.CF_ConfigVersion = 0 then
            exit;
        CopySnapshot(FromProductionOrder, ProductionOrder);
        ProductionOrder.Modify(false);
    end;

    local procedure CopySnapshot(var FromOrder: Record "Production Order"; var ToOrder: Record "Production Order")
    var
        TempConfig: Record CF_DocumentLineProductConfig temporary;
        Input: InStream;
        Output: OutStream;
    begin
        if FromOrder.CF_ConfigVersion = 0 then
            exit;
        ReadSnapshot(FromOrder, TempConfig);
        ToOrder.CF_DocumentType := FromOrder.CF_DocumentType;
        ToOrder.CF_SourceTableId := FromOrder.CF_SourceTableId;
        ToOrder.CF_SourceLineId := FromOrder.CF_SourceLineId;
        ToOrder.CF_DocumentNo := FromOrder.CF_DocumentNo;
        ToOrder.CF_DocumentLineNo := FromOrder.CF_DocumentLineNo;
        ToOrder.CF_ParentItemNo := FromOrder.CF_ParentItemNo;
        ToOrder.CF_ParentVariantCode := FromOrder.CF_ParentVariantCode;
        ToOrder.CF_ConfigVersion := FromOrder.CF_ConfigVersion;
        ToOrder.CF_RebuildAllowed := false;
        FromOrder.CF_ConfigSnapshot.CreateInStream(Input);
        Clear(ToOrder.CF_ConfigSnapshot);
        ToOrder.CF_ConfigSnapshot.CreateOutStream(Output);
        CopyStream(Output, Input);
    end;

    procedure ReadSnapshot(var ProdOrder: Record "Production Order"; var TempConfig: Record CF_DocumentLineProductConfig temporary)
    var
        Snapshot: JsonObject;
        Entry: JsonObject;
        Entries: JsonArray;
        Token: JsonToken;
        Input: InStream;
        Index: Integer;
        Version: Integer;
        SelectionId: Guid;
        SourceId: Guid;
        SeenIds: List of [Guid];
    begin
        TempConfig.Reset();
        TempConfig.DeleteAll();
        ProdOrder.TestField(CF_ConfigVersion, 1);
        ProdOrder.TestField(CF_SourceTableId, Database::"Sales Line");
        ProdOrder.TestField(CF_DocumentType, ProdOrder.CF_DocumentType::SalesOrder);
        if IsNullGuid(ProdOrder.CF_SourceLineId) then
            Error(SnapshotErr, ProdOrder."No.", 'Missing source line identity');
        ProdOrder.CalcFields(CF_ConfigSnapshot);
        if not ProdOrder.CF_ConfigSnapshot.HasValue() then
            Error(SnapshotErr, ProdOrder."No.", 'Missing payload');
        ProdOrder.CF_ConfigSnapshot.CreateInStream(Input, TextEncoding::UTF8);
        if not Snapshot.ReadFrom(Input) then
            Error(SnapshotErr, ProdOrder."No.", 'Invalid JSON');
        RequireValue(Snapshot, 'version', Token, ProdOrder."No.");
        Version := Token.AsValue().AsInteger();
        if Version <> 1 then
            Error(SnapshotErr, ProdOrder."No.", 'Unsupported schema version');
        if not Evaluate(SourceId, ReadText(Snapshot, 'sourceLineId', 50, ProdOrder."No.")) then
            Error(SnapshotErr, ProdOrder."No.", 'Invalid source line identity');
        if SourceId <> ProdOrder.CF_SourceLineId then
            Error(SnapshotErr, ProdOrder."No.", 'Source line identity mismatch');
        if ReadText(Snapshot, 'parentItem', 20, ProdOrder."No.") <> ProdOrder.CF_ParentItemNo then
            Error(SnapshotErr, ProdOrder."No.", 'Parent item mismatch');
        if ReadText(Snapshot, 'parentVariant', 10, ProdOrder."No.") <> ProdOrder.CF_ParentVariantCode then
            Error(SnapshotErr, ProdOrder."No.", 'Parent variant mismatch');
        if not Snapshot.Get('entries', Token) then
            Error(SnapshotErr, ProdOrder."No.", 'Missing entries');
        if not Token.IsArray() then
            Error(SnapshotErr, ProdOrder."No.", 'Entries must be an array');
        Entries := Token.AsArray();
        if Entries.Count() = 0 then
            Error(SnapshotErr, ProdOrder."No.", 'Empty configured snapshot');
        for Index := 0 to Entries.Count() - 1 do begin
            Entries.Get(Index, Token);
            if not Token.IsObject() then
                Error(SnapshotErr, ProdOrder."No.", 'Entry must be an object');
            Entry := Token.AsObject();
            TempConfig.Init();
            TempConfig."Document Type" := TempConfig."Document Type"::SalesOrder;
            TempConfig."Source Table ID" := ProdOrder.CF_SourceTableId;
            TempConfig."Source Line SystemId" := ProdOrder.CF_SourceLineId;
            TempConfig."Document No." := ProdOrder.CF_DocumentNo;
            TempConfig."Document Line No." := ProdOrder.CF_DocumentLineNo;
            TempConfig."Parent Item No." := ProdOrder.CF_ParentItemNo;
            TempConfig."Parent Variant Code" := ProdOrder.CF_ParentVariantCode;
            TempConfig."Configuration Option" := ReadText(Entry, 'option', 10, ProdOrder."No.");
            TempConfig."Choice Code" := ReadText(Entry, 'choice', 20, ProdOrder."No.");
            TempConfig."Component Item No." := ReadText(Entry, 'item', 20, ProdOrder."No.");
            TempConfig."Component Variant Code" := ReadText(Entry, 'variant', 10, ProdOrder."No.");
            TempConfig."Component UOM Code" := ReadText(Entry, 'uom', 10, ProdOrder."No.");
            TempConfig."Routing Link Code" := ReadText(Entry, 'routingLink', 10, ProdOrder."No.");
            RequireValue(Entry, 'quantityPer', Token, ProdOrder."No.");
            TempConfig."Quantity per Unit" := Token.AsValue().AsDecimal();
            if (TempConfig."Configuration Option" = '') or (TempConfig."Choice Code" = '') or
               (TempConfig."Component Item No." = '') or (TempConfig."Component UOM Code" = '') or
               (TempConfig."Quantity per Unit" <= 0)
            then
                Error(SnapshotErr, ProdOrder."No.", 'Entry has missing or invalid required values');
            if not Evaluate(SelectionId, ReadText(Entry, 'selectionId', 50, ProdOrder."No.")) then
                Error(SnapshotErr, ProdOrder."No.", 'Invalid selection identity');
            if IsNullGuid(SelectionId) or SeenIds.Contains(SelectionId) then
                Error(SnapshotErr, ProdOrder."No.", 'Missing or duplicate selection identity');
            SeenIds.Add(SelectionId);
            if TempConfig.Get(TempConfig."Document Type", TempConfig."Source Table ID", TempConfig."Source Line SystemId", TempConfig."Configuration Option") then
                Error(SnapshotErr, ProdOrder."No.", 'Duplicate configuration option');
            TempConfig.SystemId := SelectionId;
            TempConfig.Insert(false, true);
        end;
    end;

    local procedure RequireValue(Object: JsonObject; Name: Text; var Token: JsonToken; OrderNo: Code[20])
    begin
        if not Object.Get(Name, Token) then
            Error(SnapshotErr, OrderNo, StrSubstNo('Missing %1', Name));
        if not Token.IsValue() then
            Error(SnapshotErr, OrderNo, StrSubstNo('%1 must be a scalar value', Name));
        if Token.AsValue().IsNull() then
            Error(SnapshotErr, OrderNo, StrSubstNo('%1 cannot be null', Name));
    end;

    local procedure ReadText(Object: JsonObject; Name: Text; MaximumLength: Integer; OrderNo: Code[20]): Text
    var
        Token: JsonToken;
        Value: Text;
    begin
        RequireValue(Object, Name, Token, OrderNo);
        Value := Token.AsValue().AsText();
        if StrLen(Value) > MaximumLength then
            Error(SnapshotErr, OrderNo, StrSubstNo('%1 exceeds its maximum length', Name));
        exit(Value);
    end;

    procedure ApplyConfiguredComponents(var ProdOrder: Record "Production Order")
    var
        TempConfig: Record CF_DocumentLineProductConfig temporary;
        RootLine: Record "Prod. Order Line";
        Component: Record "Prod. Order Component";
        Desired: Record "Prod. Order Component";
    begin
        if ProdOrder.CF_ConfigVersion = 0 then
            exit;
        ProdOrder.TestField("Source Type", ProdOrder."Source Type"::Item);
        ProdOrder.TestField("Source No.", ProdOrder.CF_ParentItemNo);
        ProdOrder.TestField("Variant Code", ProdOrder.CF_ParentVariantCode);
        if ProdOrder.Status = ProdOrder.Status::Finished then
            Error(UnsupportedErr, 'Component synchronization', ProdOrder."No.");
        ReadSnapshot(ProdOrder, TempConfig);
        RootLine.SetRange(Status, ProdOrder.Status);
        RootLine.SetRange("Prod. Order No.", ProdOrder."No.");
        RootLine.SetRange("Planning Level Code", 0);
        RootLine.SetRange("Item No.", ProdOrder.CF_ParentItemNo);
        RootLine.SetRange("Variant Code", ProdOrder.CF_ParentVariantCode);
        if RootLine.Count() <> 1 then
            Error(RootErr, ProdOrder."No.", ProdOrder.CF_ParentItemNo, ProdOrder.CF_ParentVariantCode);
        RootLine.FindFirst();
        Component.LockTable();
        if TempConfig.FindSet() then
            repeat
                BuildComponent(RootLine, TempConfig, Desired);
                Component.Reset();
                Component.SetRange(Status, RootLine.Status);
                Component.SetRange("Prod. Order No.", RootLine."Prod. Order No.");
                Component.SetRange("Prod. Order Line No.", RootLine."Line No.");
                Component.SetRange(CF_ConfigSelectionId, TempConfig.SystemId);
                if Component.Count() > 1 then
                    Error(DuplicateErr, ProdOrder."No.", TempConfig."Configuration Option");
                if Component.FindFirst() then begin
                    Component.TestField(CF_ConfiguredComponent, true);
                    if not SameComponent(Component, Desired) then begin
                        CheckUnprocessedComponent(Component);
                        UpdateComponent(Component, Desired);
                    end;
                end else
                    Desired.Insert(true);
            until TempConfig.Next() = 0;
    end;

    local procedure BuildComponent(RootLine: Record "Prod. Order Line"; Config: Record CF_DocumentLineProductConfig; var Component: Record "Prod. Order Component")
    var
        LastComponent: Record "Prod. Order Component";
        ParentSKU: Record "Stockkeeping Unit";
        ComponentSKU: Record "Stockkeeping Unit";
        RoutingLine: Record "Prod. Order Routing Line";
        PlanningParameters: Codeunit "Planning-Get Parameters";
        DocumentConfigMgt: Codeunit CF_DocumentConfigMgt;
    begin
        DocumentConfigMgt.ValidateItem(Config."Component Item No.", Config."Component Variant Code", Config."Component UOM Code");
        Clear(Component);
        Component.Status := RootLine.Status;
        Component."Prod. Order No." := RootLine."Prod. Order No.";
        Component."Prod. Order Line No." := RootLine."Line No.";
        Component.InitNewLine(LastComponent);
        Component."Line No." := LastComponent."Line No." + 10000;
        Component.CF_ConfiguredComponent := true;
        Component.CF_ConfigSelectionId := Config.SystemId;
        Component.CF_ConfigOption := Config."Configuration Option";
        PlanningParameters.AtSKU(ParentSKU, RootLine."Item No.", RootLine."Variant Code", RootLine."Location Code");
        Component."Location Code" := ParentSKU."Components at Location";
        Component.Validate("Item No.", Config."Component Item No.");
        Component.Validate("Variant Code", Config."Component Variant Code");
        Component.Validate("Unit of Measure Code", Config."Component UOM Code");
        PlanningParameters.AtSKU(ComponentSKU, Component."Item No.", Component."Variant Code", Component."Location Code");
        Component.Validate("Flushing Method", ComponentSKU."Flushing Method");
        Component."Due Date" := RootLine."Starting Date";
        Component."Due Time" := RootLine."Starting Time";
        if Config."Routing Link Code" <> '' then begin
            RoutingLine.SetRange(Status, RootLine.Status);
            RoutingLine.SetRange("Prod. Order No.", RootLine."Prod. Order No.");
            RoutingLine.SetRange("Routing No.", RootLine."Routing No.");
            RoutingLine.SetRange("Routing Reference No.", RootLine."Routing Reference No.");
            RoutingLine.SetRange("Routing Link Code", Config."Routing Link Code");
            if RoutingLine.IsEmpty() then
                Error(RoutingErr, Config."Routing Link Code", Config."Configuration Option", RootLine."Prod. Order No.");
        end;
        Component.Validate("Routing Link Code", Config."Routing Link Code");
        Component.Validate("Quantity per", Config."Quantity per Unit" * RootLine."Qty. per Unit of Measure");
        Component.GetDefaultBin();
        Component.UpdateDatetime();
    end;

    local procedure SameComponent(Component: Record "Prod. Order Component"; Desired: Record "Prod. Order Component"): Boolean
    begin
        exit((Component."Item No." = Desired."Item No.") and
             (Component."Variant Code" = Desired."Variant Code") and
             (Component."Unit of Measure Code" = Desired."Unit of Measure Code") and
             (Component."Quantity per" = Desired."Quantity per") and
             (Component."Expected Quantity" = Desired."Expected Quantity") and
             (Component."Calculation Formula" = Desired."Calculation Formula") and
             (Component."Scrap %" = Desired."Scrap %") and
             (Component."Location Code" = Desired."Location Code") and
             (Component."Routing Link Code" = Desired."Routing Link Code") and
             (Component."Due Date" = Desired."Due Date") and
             (Component."Due Time" = Desired."Due Time") and
             (Component.CF_ConfigOption = Desired.CF_ConfigOption));
    end;

    local procedure UpdateComponent(var Component: Record "Prod. Order Component"; Desired: Record "Prod. Order Component")
    begin
        Component.Validate("Item No.", Desired."Item No.");
        Component."Bin Code" := '';
        Component.Validate("Location Code", Desired."Location Code");
        Component.Validate("Variant Code", Desired."Variant Code");
        Component.Validate("Unit of Measure Code", Desired."Unit of Measure Code");
        Component.Validate("Routing Link Code", Desired."Routing Link Code");
        Component.Validate("Calculation Formula", Desired."Calculation Formula");
        Component.Validate("Scrap %", Desired."Scrap %");
        Component.Validate("Quantity per", Desired."Quantity per");
        Component."Due Date" := Desired."Due Date";
        Component."Due Time" := Desired."Due Time";
        Component.CF_ConfigOption := Desired.CF_ConfigOption;
        Component.GetDefaultBin();
        Component.UpdateDatetime();
        Component.Modify(true);
    end;

    local procedure CheckUnprocessedComponents(ProdOrder: Record "Production Order")
    var
        Component: Record "Prod. Order Component";
    begin
        Component.SetRange(Status, ProdOrder.Status);
        Component.SetRange("Prod. Order No.", ProdOrder."No.");
        Component.SetRange(CF_ConfiguredComponent, true);
        if Component.FindSet() then
            repeat
                CheckUnprocessedComponent(Component);
            until Component.Next() = 0;
    end;

    local procedure CheckUnprocessedComponent(var Component: Record "Prod. Order Component")
    begin
        Component.CalcFields("Act. Consumption (Qty)", "Reserved Qty. (Base)");
        if (Component."Act. Consumption (Qty)" <> 0) or (Component."Reserved Qty. (Base)" <> 0) or
           (Component."Qty. Picked" <> 0)
        then
            Error(ProtectedErr, Component."Line No.", Component."Prod. Order No.");
    end;

    procedure CheckUnsupportedOperation(ProdOrder: Record "Production Order"; Operation: Text)
    begin
        if ProdOrder.CF_ConfigVersion <> 0 then
            Error(UnsupportedErr, Operation, ProdOrder."No.");
    end;

    [EventSubscriber(ObjectType::Report, Report::"Copy Production Order Document", 'OnBeforeToProdOrderModify', '', false, false)]
    local procedure BeforeCopyHeader(var ToProdOrder: Record "Production Order"; FromProdOrder: Record "Production Order")
    begin
        CheckUnsupportedOperation(ToProdOrder, 'Copy Production Order');
        CheckUnsupportedOperation(FromProdOrder, 'Copy Production Order');
    end;

    [EventSubscriber(ObjectType::Report, Report::"Copy Production Order Document", 'OnBeforeToProdOrderLineInsert', '', false, false)]
    local procedure BeforeCopyLine(var ToProdOrderLine: Record "Prod. Order Line"; FromProdOrderLine: Record "Prod. Order Line")
    var
        ProdOrder: Record "Production Order";
    begin
        ProdOrder.Get(ToProdOrderLine.Status, ToProdOrderLine."Prod. Order No.");
        CheckUnsupportedOperation(ProdOrder, 'Copy Production Order');
        ProdOrder.Get(FromProdOrderLine.Status, FromProdOrderLine."Prod. Order No.");
        CheckUnsupportedOperation(ProdOrder, 'Copy Production Order');
    end;

    [EventSubscriber(ObjectType::Page, Page::"Prod. Order Components", 'OnDeleteRecordEvent', '', false, false)]
    local procedure BeforeDeleteComponentOnPage(var Rec: Record "Prod. Order Component"; var AllowDelete: Boolean)
    begin
        if not AllowDelete or Rec.IsTemporary() or not Rec.CF_ConfiguredComponent then
            exit;
        Error(UnsupportedErr, 'Deleting a configured component', Rec."Prod. Order No.");
    end;

    [EventSubscriber(ObjectType::Page, Page::"Simulated Production Order", 'OnDeleteRecordEvent', '', false, false)]
    local procedure DeleteSimulatedOrder(var Rec: Record "Production Order"; var AllowDelete: Boolean)
    begin
        ConfirmPageDeletion(Rec, AllowDelete);
    end;

    [EventSubscriber(ObjectType::Page, Page::"Simulated Production Orders", 'OnDeleteRecordEvent', '', false, false)]
    local procedure DeleteSimulatedOrders(var Rec: Record "Production Order"; var AllowDelete: Boolean)
    begin
        ConfirmPageDeletion(Rec, AllowDelete);
    end;

    [EventSubscriber(ObjectType::Page, Page::"Planned Production Order", 'OnDeleteRecordEvent', '', false, false)]
    local procedure DeletePlannedOrder(var Rec: Record "Production Order"; var AllowDelete: Boolean)
    begin
        ConfirmPageDeletion(Rec, AllowDelete);
    end;

    [EventSubscriber(ObjectType::Page, Page::"Planned Production Orders", 'OnDeleteRecordEvent', '', false, false)]
    local procedure DeletePlannedOrders(var Rec: Record "Production Order"; var AllowDelete: Boolean)
    begin
        ConfirmPageDeletion(Rec, AllowDelete);
    end;

    [EventSubscriber(ObjectType::Page, Page::"Firm Planned Prod. Order", 'OnDeleteRecordEvent', '', false, false)]
    local procedure DeleteFirmPlannedOrder(var Rec: Record "Production Order"; var AllowDelete: Boolean)
    begin
        ConfirmPageDeletion(Rec, AllowDelete);
    end;

    [EventSubscriber(ObjectType::Page, Page::"Firm Planned Prod. Orders", 'OnDeleteRecordEvent', '', false, false)]
    local procedure DeleteFirmPlannedOrders(var Rec: Record "Production Order"; var AllowDelete: Boolean)
    begin
        ConfirmPageDeletion(Rec, AllowDelete);
    end;

    [EventSubscriber(ObjectType::Page, Page::"Released Production Order", 'OnDeleteRecordEvent', '', false, false)]
    local procedure DeleteReleasedOrder(var Rec: Record "Production Order"; var AllowDelete: Boolean)
    begin
        ConfirmPageDeletion(Rec, AllowDelete);
    end;

    [EventSubscriber(ObjectType::Page, Page::"Released Production Orders", 'OnDeleteRecordEvent', '', false, false)]
    local procedure DeleteReleasedOrders(var Rec: Record "Production Order"; var AllowDelete: Boolean)
    begin
        ConfirmPageDeletion(Rec, AllowDelete);
    end;

    [EventSubscriber(ObjectType::Page, Page::"Finished Production Order", 'OnDeleteRecordEvent', '', false, false)]
    local procedure DeleteFinishedOrder(var Rec: Record "Production Order"; var AllowDelete: Boolean)
    begin
        ConfirmPageDeletion(Rec, AllowDelete);
    end;

    [EventSubscriber(ObjectType::Page, Page::"Finished Production Orders", 'OnDeleteRecordEvent', '', false, false)]
    local procedure DeleteFinishedOrders(var Rec: Record "Production Order"; var AllowDelete: Boolean)
    begin
        ConfirmPageDeletion(Rec, AllowDelete);
    end;

    [EventSubscriber(ObjectType::Page, Page::"Production Order List", 'OnDeleteRecordEvent', '', false, false)]
    local procedure DeleteProductionOrderList(var Rec: Record "Production Order"; var AllowDelete: Boolean)
    begin
        ConfirmPageDeletion(Rec, AllowDelete);
    end;

    local procedure ConfirmPageDeletion(ProductionOrder: Record "Production Order"; var AllowDelete: Boolean)
    var
        DocumentConfigMgt: Codeunit CF_DocumentConfigMgt;
    begin
        if AllowDelete then
            AllowDelete := DocumentConfigMgt.ConfirmProductionOrderDeletion(ProductionOrder);
    end;

    [EventSubscriber(ObjectType::Table, Database::"Prod. Order Component", 'OnBeforeModifyEvent', '', false, false)]
    local procedure ProtectComponentIdentity(var Rec: Record "Prod. Order Component"; var xRec: Record "Prod. Order Component"; RunTrigger: Boolean)
    begin
        if Rec.IsTemporary() or not xRec.CF_ConfiguredComponent then
            exit;
        if not Rec.CF_ConfiguredComponent or (Rec.CF_ConfigSelectionId <> xRec.CF_ConfigSelectionId) then
            Error(TraceErr, Rec."Prod. Order No.");
    end;

    [EventSubscriber(ObjectType::Table, Database::"Production Order", 'OnBeforeModifyEvent', '', false, false)]
    local procedure ProtectProductionSource(var Rec: Record "Production Order"; var xRec: Record "Production Order"; RunTrigger: Boolean)
    begin
        if Rec.IsTemporary() or (xRec.CF_ConfigVersion = 0) then
            exit;
        if (Rec."Source Type" <> Rec."Source Type"::Item) or (Rec."Source No." <> Rec.CF_ParentItemNo) or
           (Rec."Variant Code" <> Rec.CF_ParentVariantCode) or (Rec.CF_ConfigVersion <> xRec.CF_ConfigVersion) or
           (Rec.CF_SourceLineId <> xRec.CF_SourceLineId)
        then
            Error(ParentErr, Rec."No.");
    end;

    [EventSubscriber(ObjectType::Table, Database::"Prod. Order Line", 'OnBeforeModifyEvent', '', false, false)]
    local procedure ProtectProductionLine(var Rec: Record "Prod. Order Line"; var xRec: Record "Prod. Order Line"; RunTrigger: Boolean)
    var
        ProdOrder: Record "Production Order";
    begin
        if Rec.IsTemporary() or (xRec."Planning Level Code" <> 0) then
            exit;
        if not ProdOrder.Get(Rec.Status, Rec."Prod. Order No.") then
            exit;
        if ProdOrder.CF_ConfigVersion = 0 then
            exit;
        if (Rec."Item No." <> ProdOrder.CF_ParentItemNo) or (Rec."Variant Code" <> ProdOrder.CF_ParentVariantCode) or
           (Rec."Planning Level Code" <> 0)
        then
            Error(ParentErr, ProdOrder."No.");
    end;
}
