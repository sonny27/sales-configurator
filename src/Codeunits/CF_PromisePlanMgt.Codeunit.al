namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Availability;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Planning;
using Microsoft.Inventory.Requisition;
using Microsoft.Manufacturing.Document;
using Microsoft.Manufacturing.ProductionBOM;
using Microsoft.Manufacturing.Routing;
using Microsoft.Sales.Document;

codeunit 91014 CF_PromisePlanMgt
{
    SingleInstance = true;
    Permissions = tabledata CF_PromiseContext = rimd;

    procedure CheckAccept(var PromisingLine: Record "Order Promising Line")
    begin
        OnBeforeConfiguredAccept(PromisingLine);
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeConfiguredAccept(var PromisingLine: Record "Order Promising Line")
    begin
    end;

    procedure StoreContext(ID: Guid; SalesLine: Record "Sales Line"; var Rows: Record CF_BOMBuffer temporary)
    var
        Context: Record CF_PromiseContext;
        Order: Record "Production Order" temporary;
        Input: InStream;
        Output: OutStream;
        Snapshot: JsonObject;
        Supply: JsonObject;
        Reader: Record CF_BOMBuffer temporary;
        SKU: Record "Stockkeeping Unit";
        Planning: Codeunit "Planning-Get Parameters";
    begin
        if Context.Get(ID) then
            exit;
        Rows.Reset();
        Rows.SetCurrentKey("Source Line ID", "Sort Order");
        Rows.FindFirst();
        Context.ID := ID;
        Context."Source Line ID" := SalesLine.SystemId;
        Context."Document No." := SalesLine."Document No.";
        Context."Document Line No." := SalesLine."Line No.";
        Context."Parent Item No." := SalesLine."No.";
        Context."Parent Variant Code" := SalesLine."Variant Code";
        WriteOrderSnapshot(Context, Rows, Rows."Node ID", Order);
        Order.CF_ConfigSnapshot.CreateInStream(Input);
        Snapshot.ReadFrom(Input);
        Reader.Copy(Rows, true);
        Reader.Reset();
        Reader.SetRange(Type, Reader.Type::Item);
        if Reader.FindSet() then
            repeat
                Planning.AtSKU(SKU, Reader."No.", Reader."Variant Code", Reader."Location Code");
                Supply.Add(Format(Reader."Node ID"), SKU."Replenishment System".AsInteger());
            until Reader.Next() = 0;
        Snapshot.Add('nativeSupply', Supply);
        Context.Snapshot.CreateOutStream(Output, TextEncoding::UTF8);
        Snapshot.WriteTo(Output);
        Context.Insert(true);
    end;

    procedure ReadContext(ID: Guid; var Rows: Record CF_BOMBuffer temporary)
    var
        Context: Record CF_PromiseContext;
        Order: Record "Production Order" temporary;
        DraftMgt: Codeunit CF_BOMDraftMgt;
        Input: InStream;
        Output: OutStream;
    begin
        Context.Get(ID);
        Context.CalcFields(Snapshot);
        Order."No." := CopyStr(DelChr(Format(ID), '=', '{}-'), 1, MaxStrLen(Order."No."));
        SetSource(Context, Order);
        Context.Snapshot.CreateInStream(Input);
        Order.CF_ConfigSnapshot.CreateOutStream(Output);
        CopyStream(Output, Input);
        Order.Insert(false);
        DraftMgt.ReadSnapshot(Order, Rows);
    end;

    local procedure SetSource(Context: Record CF_PromiseContext; var Order: Record "Production Order")
    begin
        Order.CF_DocumentType := CF_ConfigDocumentType::SalesOrder;
        Order.CF_SourceTableId := Database::"Sales Line";
        Order.CF_SourceLineId := Context."Source Line ID";
        Order.CF_DocumentNo := Context."Document No.";
        Order.CF_DocumentLineNo := Context."Document Line No.";
        Order.CF_ParentItemNo := Context."Parent Item No.";
        Order.CF_ParentVariantCode := Context."Parent Variant Code";
        Order.CF_ConfigVersion := 3;
    end;

    local procedure WriteOrderSnapshot(Context: Record CF_PromiseContext; var Rows: Record CF_BOMBuffer temporary; NodeId: Guid; var Order: Record "Production Order")
    var
        Reader: Record CF_BOMBuffer temporary;
        Subtree: Record CF_BOMBuffer temporary;
        DraftMgt: Codeunit CF_BOMDraftMgt;
        Snapshot: JsonObject;
        Entries: JsonArray;
        Entry: JsonObject;
        Output: OutStream;
        RootIndent: Integer;
        SortOrder: Integer;
    begin
        Reader.Copy(Rows, true);
        Reader.Reset();
        Reader.SetCurrentKey("Source Line ID", "Sort Order");
        Reader.Get(Context."Source Line ID", NodeId);
        RootIndent := Reader.Indentation;
        SetSource(Context, Order);
        Order.CF_ParentItemNo := Reader."No.";
        Order.CF_ParentVariantCode := Reader."Variant Code";
        repeat
            Subtree := Reader;
            Subtree.Indentation -= RootIndent;
            SortOrder += 10000;
            Subtree."Sort Order" := SortOrder;
            if Subtree.Indentation = 0 then begin
                Clear(Subtree."Parent Node ID");
                Subtree."Choice Root" := false;
                Subtree."Quantity per" := 1;
            end;
            Subtree.Insert(false);
            if Subtree."Choice Root" then begin
                Clear(Entry);
                Entry.Add('selectionId', Format(Subtree."Selection ID"));
                Entry.Add('option', Subtree."Configuration Option");
                Entry.Add('choice', Subtree."Choice Code");
                Entry.Add('item', Subtree."No.");
                Entry.Add('variant', Subtree."Variant Code");
                Entry.Add('uom', Subtree."Unit of Measure Code");
                Entry.Add('quantityPer', Subtree."Quantity per");
                Entry.Add('routingLink', Subtree."Routing Link Code");
                if Subtree.Type = Subtree.Type::CF_ProductionBOM then
                    Entry.Add('componentType', 2)
                else
                    Entry.Add('componentType', 1);
                Entries.Add(Entry);
            end;
            if Reader.Next() = 0 then
                break;
        until Reader.Indentation <= RootIndent;
        Snapshot.Add('version', 3);
        Snapshot.Add('sourceLineId', Format(Context."Source Line ID"));
        Snapshot.Add('parentItem', Order.CF_ParentItemNo);
        Snapshot.Add('parentVariant', Order.CF_ParentVariantCode);
        Snapshot.Add('entries', Entries);
        DraftMgt.WriteSnapshot(Subtree, Snapshot);
        Clear(Order.CF_ConfigSnapshot);
        Order.CF_ConfigSnapshot.CreateOutStream(Output, TextEncoding::UTF8);
        Snapshot.WriteTo(Output);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Planning Line Management", 'OnBeforeCalculate', '', false, false)]
    local procedure CalculateConfiguration(var ReqLine2: Record "Requisition Line"; Direction: Option Forward,Backward; CalcRouting: Boolean; CalcComponents: Boolean; PlanningLevel: Integer; var IsHandled: Boolean)
    var
        Rows: Record CF_BOMBuffer temporary;
        Node: Record CF_BOMBuffer temporary;
        Component: Record "Planning Component";
        SKU: Record "Stockkeeping Unit";
        Planning: Codeunit "Planning-Get Parameters";
    begin
        if IsNullGuid(ReqLine2.CF_PromiseContextId) or not CalcComponents then
            exit;
        if not (ReqLine2."Replenishment System" in [ReqLine2."Replenishment System"::"Prod. Order", ReqLine2."Replenishment System"::Assembly]) then
            exit;
        if not HasConfiguredSupply(ReqLine2) then begin
            Clear(ReqLine2.CF_PromiseContextId);
            Clear(ReqLine2.CF_BOMNodeId);
            exit;
        end;
        if IsHandled then
            Error('Another extension has handled configured planning line %1.', ReqLine2."Line No.");
        ReadContext(ReqLine2.CF_PromiseContextId, Rows);
        Node.Copy(Rows, true);
        Node.Get(Rows."Source Line ID", ReqLine2.CF_BOMNodeId);
        Node.TestField("No.", ReqLine2."No.");
        Node.TestField("Variant Code", ReqLine2."Variant Code");
        if Node."Base Selection Set" then begin
            ReqLine2.Validate("Production BOM No.", Node."Base BOM");
            ReqLine2.Validate("Routing No.", Node."Base Routing");
        end;
        Component.SetRange("Worksheet Template Name", ReqLine2."Worksheet Template Name");
        Component.SetRange("Worksheet Batch Name", ReqLine2."Journal Batch Name");
        Component.SetRange("Worksheet Line No.", ReqLine2."Line No.");
        Component.DeleteAll(true);
        if ReqLine2."Planning Level" = 0 then
            ReqLine2.DeleteMultiLevel();
        // Use native routing/date calculation without re-exploding the master BOM.
        Planner.Calculate(ReqLine2, Direction, CalcRouting, false, PlanningLevel);
        InsertComponents(ReqLine2, Rows, Node."Node ID");
        Planner.Recalculate(ReqLine2, Direction);
        Planning.AtSKU(SKU, ReqLine2."No.", ReqLine2."Variant Code", ReqLine2."Location Code");
        if SKU."Manufacturing Policy" = SKU."Manufacturing Policy"::"Make-to-Order" then
            Planner.CheckMultiLevelStructure(ReqLine2, CalcRouting, true, PlanningLevel);
        ReqLine2.Get(ReqLine2."Worksheet Template Name", ReqLine2."Journal Batch Name", ReqLine2."Line No.");
        IsHandled := true;
    end;

    local procedure HasConfiguredSupply(ReqLine: Record "Requisition Line"): Boolean
    var
        Context: Record CF_PromiseContext;
        Snapshot: JsonObject;
        Supply: JsonToken;
        Value: JsonToken;
        Input: InStream;
    begin
        Context.Get(ReqLine.CF_PromiseContextId);
        Context.CalcFields(Snapshot);
        Context.Snapshot.CreateInStream(Input, TextEncoding::UTF8);
        Snapshot.ReadFrom(Input);
        if not Snapshot.Get('nativeSupply', Supply) then
            Error('The configured planning snapshot has no native supply context.');
        if not Supply.AsObject().Get(Format(ReqLine.CF_BOMNodeId), Value) then
            Error('The configured planning node has no native supply context.');
        exit(Value.AsValue().AsInteger() in [
            ReqLine."Replenishment System"::"Prod. Order".AsInteger(), ReqLine."Replenishment System"::Assembly.AsInteger()]);
    end;

    local procedure InsertComponents(ReqLine: Record "Requisition Line"; var Rows: Record CF_BOMBuffer temporary; NodeId: Guid)
    var
        Components: Record CF_BOMBuffer temporary;
        Component: Record "Planning Component";
        ParentSKU: Record "Stockkeeping Unit";
        ChildSKU: Record "Stockkeeping Unit";
        Item: Record Item;
        Routing: Record "Planning Routing Line";
        Tree: Codeunit CF_BOMTreeMgt;
        DocumentMgt: Codeunit CF_DocumentConfigMgt;
        Planning: Codeunit "Planning-Get Parameters";
        LineNo: Integer;
    begin
        Planning.AtSKU(ParentSKU, ReqLine."No.", ReqLine."Variant Code", ReqLine."Location Code");
        Tree.GetComponents(Rows, NodeId, Components);
        Components.SetCurrentKey("Source Line ID", "Sort Order");
        if Components.FindSet() then
            repeat
                DocumentMgt.ValidateItem(Components."No.", Components."Variant Code", Components."Unit of Measure Code");
                Clear(Component);
                LineNo += 10000;
                Component.SetRequisitionLine(ReqLine);
                Component."Worksheet Template Name" := ReqLine."Worksheet Template Name";
                Component."Worksheet Batch Name" := ReqLine."Journal Batch Name";
                Component."Worksheet Line No." := ReqLine."Line No.";
                Component."Line No." := LineNo;
                Component."Location Code" := ParentSKU."Components at Location";
                Component.Validate("Item No.", Components."No.");
                Component.Validate("Variant Code", Components."Variant Code");
                Component.Validate("Unit of Measure Code", Components."Unit of Measure Code");
                Component.Description := Components.Description;
                Component."Description 2" := Components."Description 2";
                Component."Planning Line Origin" := ReqLine."Planning Line Origin";
                Component."Quantity per" := Tree.GetComponentQuantityPer(Components, ReqLine."Qty. per Unit of Measure");
                if Components."Routing Link Code" <> '' then begin
                    Routing.SetRange("Worksheet Template Name", ReqLine."Worksheet Template Name");
                    Routing.SetRange("Worksheet Batch Name", ReqLine."Journal Batch Name");
                    Routing.SetRange("Worksheet Line No.", ReqLine."Line No.");
                    Routing.SetRange("Routing Link Code", Components."Routing Link Code");
                    if Routing.IsEmpty() then
                        Error('Routing link %1 for configured component %2 is missing from the planning routing.', Components."Routing Link Code", Components."No.");
                end;
                Component.Validate("Routing Link Code", Components."Routing Link Code");
                Component.Length := Components.Length;
                Component.Width := Components.Width;
                Component.Depth := Components.Depth;
                Component.Weight := Components.Weight;
                Component.Position := Components.Position;
                Component."Position 2" := Components."Position 2";
                Component."Position 3" := Components."Position 3";
                Component."Lead-Time Offset" := Components."Lead-Time Offset";
                Component.Validate("Scrap %", Components."Scrap %");
                Component.Validate("Calculation Formula", Components."Calculation Formula");
                Item.Get(Component."Item No.");
                Component.Critical := Item.Critical;
                Planning.AtSKU(ChildSKU, Component."Item No.", Component."Variant Code", Component."Location Code");
                Component."Flushing Method" := ChildSKU."Flushing Method";
                if (ParentSKU."Manufacturing Policy" = ParentSKU."Manufacturing Policy"::"Make-to-Order") and
                   (ChildSKU."Manufacturing Policy" = ChildSKU."Manufacturing Policy"::"Make-to-Order") and
                   (ChildSKU."Replenishment System" = ChildSKU."Replenishment System"::"Prod. Order")
                then
                    Component."Planning Level Code" := ReqLine."Planning Level" + 1;
                Component."Ref. Order Type" := ReqLine."Ref. Order Type";
                Component."Ref. Order Status" := ReqLine."Ref. Order Status";
                Component."Ref. Order No." := ReqLine."Ref. Order No.";
                Component.CF_BOMNodeId := Components."Node ID";
                Component.GetDefaultBin();
                Component.Insert(true);
            until Components.Next() = 0;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Planning Line Management", 'OnCheckMultiLevelStructureOnBeforeInsertPlanningLine', '', false, false)]
    local procedure IdentifyChild(var ReqLine: Record "Requisition Line"; var PlanningComponent: Record "Planning Component")
    var
        Parent: Record "Requisition Line";
    begin
        if IsNullGuid(PlanningComponent.CF_BOMNodeId) then
            exit;
        Parent.Get(PlanningComponent."Worksheet Template Name", PlanningComponent."Worksheet Batch Name", PlanningComponent."Worksheet Line No.");
        ReqLine.CF_PromiseContextId := Parent.CF_PromiseContextId;
        ReqLine.CF_BOMNodeId := PlanningComponent.CF_BOMNodeId;
    end;

    [EventSubscriber(ObjectType::Table, Database::"Requisition Line", 'OnAfterDeleteEvent', '', false, false)]
    local procedure CleanContext(var Rec: Record "Requisition Line"; RunTrigger: Boolean)
    var
        Other: Record "Requisition Line";
        Context: Record CF_PromiseContext;
    begin
        if Rec.IsTemporary() or IsNullGuid(Rec.CF_PromiseContextId) then
            exit;
        Other.SetRange(CF_PromiseContextId, Rec.CF_PromiseContextId);
        if Other.IsEmpty() then
            if Context.Get(Rec.CF_PromiseContextId) then
                Context.Delete(true);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Mfg. Carry Out Action", 'OnInsertProdOrderOnBeforeProdOrderInsert', '', false, false)]
    local procedure PreserveSnapshot(var ProdOrder: Record "Production Order"; ReqLine: Record "Requisition Line")
    var
        Context: Record CF_PromiseContext;
        Rows: Record CF_BOMBuffer temporary;
    begin
        if IsNullGuid(ReqLine.CF_PromiseContextId) then
            exit;
        Context.Get(ReqLine.CF_PromiseContextId);
        ReadContext(Context.ID, Rows);
        WriteOrderSnapshot(Context, Rows, ReqLine.CF_BOMNodeId, ProdOrder);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Mfg. Carry Out Action", 'OnInsertProdOrderLineOnBeforeValidateUnitCost', '', false, false)]
    local procedure IdentifyOutput(var RequisitionLine: Record "Requisition Line"; ProductionOrder: Record "Production Order"; var ProdOrderLine: Record "Prod. Order Line"; Item: Record Item)
    begin
        if not IsNullGuid(RequisitionLine.CF_PromiseContextId) then
            ProdOrderLine.CF_BOMNodeId := RequisitionLine.CF_BOMNodeId;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Mfg. Carry Out Action", 'OnAfterTransferPlanningComp', '', false, false)]
    local procedure IdentifyComponent(var PlanningComponent: Record "Planning Component"; var ProdOrderComponent: Record "Prod. Order Component")
    begin
        if IsNullGuid(PlanningComponent.CF_BOMNodeId) then
            exit;
        ProdOrderComponent.CF_BOMNodeId := PlanningComponent.CF_BOMNodeId;
        ProdOrderComponent.CF_ConfiguredComponent := true;
        ProdOrderComponent.CF_ProductionBOMChoice := true;
    end;

    var
        // Native make-to-order recursion must share its line-spacing state.
        Planner: Codeunit "Planning Line Management";
}
