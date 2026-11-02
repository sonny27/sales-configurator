namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Planning;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Ledger;
using Microsoft.Manufacturing.Capacity;
using Microsoft.Foundation.UOM;
using Microsoft.Manufacturing.Document;

codeunit 91011 CF_BOMProductionMgt
{
    Permissions = tabledata "Prod. Order Component" = rimd,
                  tabledata "Prod. Order Line" = rm;

    [EventSubscriber(ObjectType::Table, Database::"Prod. Order Line", 'OnAfterGetItem', '', false, false)]
    local procedure UseBaseItem(var Item: Record Item; var ProdOrderLine: Record "Prod. Order Line")
    var
        Root: Record CF_BOMBuffer;
    begin
        if not GetBaseRoot(ProdOrderLine, Root) then
            exit;
        Item."Production BOM No." := Root."Base BOM";
        Item."Routing No." := Root."Base Routing";
    end;

    [EventSubscriber(ObjectType::Table, Database::"Prod. Order Line", 'OnBeforeGetUpdateFromSKU', '', false, false)]
    local procedure UseBaseSKU(var ProdOrderLine: Record "Prod. Order Line"; var SKU: Record "Stockkeeping Unit"; var Item: Record Item; var IsHandled: Boolean)
    var
        Root: Record CF_BOMBuffer;
    begin
        if not GetBaseRoot(ProdOrderLine, Root) then
            exit;
        if IsHandled then
            Error('Another extension has handled SKU initialization for the configured production output.');
        Item."Production BOM No." := Root."Base BOM";
        Item."Routing No." := Root."Base Routing";
        // Supply the native SKU cache without changing its cost or replenishment settings.
        if SKU.Get(ProdOrderLine."Location Code", ProdOrderLine."Item No.", ProdOrderLine."Variant Code") then begin
            SKU."Production BOM No." := Root."Base BOM";
            SKU."Routing No." := Root."Base Routing";
        end else
            Clear(SKU);
    end;

    local procedure GetBaseRoot(Line: Record "Prod. Order Line"; var Root: Record CF_BOMBuffer): Boolean
    var
        Order: Record "Production Order";
        Rows: Record CF_BOMBuffer temporary;
        DraftMgt: Codeunit CF_BOMDraftMgt;
    begin
        if Line.IsTemporary() or not Order.Get(Line.Status, Line."Prod. Order No.") then
            exit(false);
        if (Order.CF_ConfigVersion <> 3) or (Line."Item No." <> Order.CF_ParentItemNo) or
           ((Line."Variant Code" <> '') and (Line."Variant Code" <> Order.CF_ParentVariantCode))
        then
            exit(false);
        DraftMgt.ReadSnapshot(Order, Rows);
        Rows.SetRange(Indentation, 0);
        Rows.FindFirst();
        Root := Rows;
        exit(Root."Base Selection Set");
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Calculate Prod. Order", 'OnBeforeCalculate', '', false, false)]
    local procedure IdentifyRoot(var ItemLedgerEntry: Record "Item Ledger Entry"; var CapacityLedgerEntry: Record "Capacity Ledger Entry"; Direction: Option; CalcRouting: Boolean; CalcComponents: Boolean; var DeleteRelations: Boolean; LetDueDateDecrease: Boolean; var IsHandled: Boolean; var ProdOrderLine: Record "Prod. Order Line"; var ErrorOccured: Boolean)
    var
        Order: Record "Production Order";
        Rows: Record CF_BOMBuffer temporary;
        DraftMgt: Codeunit CF_BOMDraftMgt;
    begin
        Order.Get(ProdOrderLine.Status, ProdOrderLine."Prod. Order No.");
        if Order.CF_ConfigVersion <> 3 then
            exit;
        DraftMgt.ReadSnapshot(Order, Rows);
        if IsNullGuid(ProdOrderLine.CF_BOMNodeId) then begin
            ProdOrderLine.TestField("Planning Level Code", 0);
            Rows.SetRange(Indentation, 0);
            Rows.FindFirst();
            ProdOrderLine.CF_BOMNodeId := Rows."Node ID";
        end else
            Rows.Get(Order.CF_SourceLineId, ProdOrderLine.CF_BOMNodeId);
        if (Rows.Indentation = 0) and Rows."Base Selection Set" then begin
            if Order."Routing No." <> Rows."Base Routing" then begin
                Order."Routing No." := Rows."Base Routing";
                Order.Modify(false);
            end;
            if ProdOrderLine."Production BOM No." <> Rows."Base BOM" then
                ProdOrderLine.Validate("Production BOM No.", Rows."Base BOM");
            if ProdOrderLine."Routing No." <> Rows."Base Routing" then
                ProdOrderLine.Validate("Routing No.", Rows."Base Routing");
        end;
        ProdOrderLine.Modify(false);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Calculate Prod. Order", 'OnCalculateOnBeforeCalcComponents', '', false, false)]
    local procedure TransferDraft(ProdOrderLine: Record "Prod. Order Line"; CalcComponents: Boolean; var SkipCalcComponents: Boolean)
    var
        Order: Record "Production Order";
        Component: Record "Prod. Order Component";
        Rows: Record CF_BOMBuffer temporary;
        Parent: Record CF_BOMBuffer temporary;
        DraftMgt: Codeunit CF_BOMDraftMgt;
    begin
        if not CalcComponents then
            exit;
        Order.Get(ProdOrderLine.Status, ProdOrderLine."Prod. Order No.");
        if Order.CF_ConfigVersion <> 3 then
            exit;
        Order.TestField(CF_RebuildAllowed, true);
        if SkipCalcComponents then
            Error('Another extension has handled component generation for configured production order %1.', Order."No.");
        DraftMgt.ReadSnapshot(Order, Rows);
        Parent.Copy(Rows, true);
        ProdOrderLine.TestField(CF_BOMNodeId);
        Parent.Get(Order.CF_SourceLineId, ProdOrderLine.CF_BOMNodeId);
        Parent.TestField(Type, Parent.Type::Item);
        Parent.TestField("No.", ProdOrderLine."Item No.");
        Parent.TestField("Variant Code", ProdOrderLine."Variant Code");
        Component.SetRange(Status, ProdOrderLine.Status);
        Component.SetRange("Prod. Order No.", ProdOrderLine."Prod. Order No.");
        Component.SetRange("Prod. Order Line No.", ProdOrderLine."Line No.");
        if not Component.IsEmpty() then
            Error('Production order %1 line %2 still has components. Use a full component refresh to rebuild its saved BOM structure.',
                ProdOrderLine."Prod. Order No.", ProdOrderLine."Line No.");
        AppendChildren(ProdOrderLine, Parent."Node ID", Rows);
        // Native Recalculate follows this event, retaining scheduling and component demand calculation.
        SkipCalcComponents := true;
    end;

    local procedure AppendChildren(Line: Record "Prod. Order Line"; ParentId: Guid; var Rows: Record CF_BOMBuffer temporary)
    var
        Children: Record CF_BOMBuffer temporary;
        Tree: Codeunit CF_BOMTreeMgt;
    begin
        Tree.GetComponents(Rows, ParentId, Children);
        Children.SetCurrentKey("Source Line ID", "Sort Order");
        if Children.FindSet() then
            repeat
                InsertComponent(Line, Children, Children."Scrap %", Children."Routing Link Code");
            until Children.Next() = 0;
    end;

    local procedure InsertComponent(Line: Record "Prod. Order Line"; Row: Record CF_BOMBuffer; Scrap: Decimal; Link: Code[10])
    var
        Component: Record "Prod. Order Component";
        Last: Record "Prod. Order Component";
        ParentSKU: Record "Stockkeeping Unit";
        ComponentSKU: Record "Stockkeeping Unit";
        Item: Record Item;
        Routing: Record "Prod. Order Routing Line";
        Planning: Codeunit "Planning-Get Parameters";
        DocumentMgt: Codeunit CF_DocumentConfigMgt;
        Tree: Codeunit CF_BOMTreeMgt;
    begin
        DocumentMgt.ValidateItem(Row."No.", Row."Variant Code", Row."Unit of Measure Code");
        Component.Status := Line.Status;
        Component."Prod. Order No." := Line."Prod. Order No.";
        Component."Prod. Order Line No." := Line."Line No.";
        Component.InitNewLine(Last);
        Component."Line No." := Last."Line No." + 10000;
        Planning.AtSKU(ParentSKU, Line."Item No.", Line."Variant Code", Line."Location Code");
        Component."Location Code" := ParentSKU."Components at Location";
        Component.Validate("Item No.", Row."No.");
        Component.Validate("Variant Code", Row."Variant Code");
        Component.Validate("Unit of Measure Code", Row."Unit of Measure Code");
        Component.Description := Row.Description;
        Component."Description 2" := Row."Description 2";
        Component.Length := Row.Length;
        Component.Width := Row.Width;
        Component.Depth := Row.Depth;
        Component.Weight := Row.Weight;
        Component.Position := Row.Position;
        Component."Position 2" := Row."Position 2";
        Component."Position 3" := Row."Position 3";
        Component."Lead-Time Offset" := Row."Lead-Time Offset";
        if Link <> '' then begin
            Routing.SetRange(Status, Line.Status);
            Routing.SetRange("Prod. Order No.", Line."Prod. Order No.");
            Routing.SetRange("Routing Reference No.", Line."Routing Reference No.");
            Routing.SetRange("Routing No.", Line."Routing No.");
            Routing.SetRange("Routing Link Code", Link);
            if Routing.IsEmpty() then
                Error('Routing link %1 for component %2 is missing on production order %3 line %4.', Link, Row."No.", Line."Prod. Order No.", Line."Line No.");
        end;
        Component.Validate("Routing Link Code", Link);
        Component.Validate("Scrap %", Scrap);
        Component."Quantity per" := Tree.GetComponentQuantityPer(Row, Line."Qty. per Unit of Measure");
        Item.Get(Component."Item No.");
        Component.Validate("Calculation Formula", Row."Calculation Formula");
        Planning.AtSKU(ComponentSKU, Component."Item No.", Component."Variant Code", Component."Location Code");
        Component."Flushing Method" := ComponentSKU."Flushing Method";
        Component."Item Low-Level Code" := Item."Low-Level Code";
        if (ParentSKU."Manufacturing Policy" = ParentSKU."Manufacturing Policy"::"Make-to-Order") and
           (ComponentSKU."Manufacturing Policy" = ComponentSKU."Manufacturing Policy"::"Make-to-Order") and
           (ComponentSKU."Replenishment System" = ComponentSKU."Replenishment System"::"Prod. Order")
        then
            Component."Planning Level Code" := Line."Planning Level Code" + 1;
        Component.CF_ConfiguredComponent := true;
        Component.CF_ProductionBOMChoice := true;
        Component.CF_ConfigSelectionId := Row."Selection ID";
        Component.CF_ConfigOption := Row."Configuration Option";
        Component.CF_BOMNodeId := Row."Node ID";
        Component."Due Date" := Line."Starting Date";
        Component."Due Time" := Line."Starting Time";
        Component.GetDefaultBin();
        Component.UpdateDatetime();
        Component.Insert(true);
        Component.AutoReserve();
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Create Prod. Order Lines", 'OnCheckMakeOrderLineBeforeInsert', '', false, false)]
    local procedure IdentifyChild(var ProdOrderLine: Record "Prod. Order Line"; var ProdOrderComponent: Record "Prod. Order Component"; var InsertNew: Boolean)
    var
        Order: Record "Production Order";
    begin
        Order.Get(ProdOrderLine.Status, ProdOrderLine."Prod. Order No.");
        if Order.CF_ConfigVersion <> 3 then
            exit;
        ProdOrderComponent.TestField(CF_BOMNodeId);
        ProdOrderLine.CF_BOMNodeId := ProdOrderComponent.CF_BOMNodeId;
        // Different edited occurrences of the same item must not share one manufactured output.
        InsertNew := true;
    end;

    [EventSubscriber(ObjectType::Table, Database::"Prod. Order Component", 'OnBeforeModifyEvent', '', false, false)]
    local procedure ProtectComponentNode(var Rec: Record "Prod. Order Component"; var xRec: Record "Prod. Order Component"; RunTrigger: Boolean)
    begin
        if not Rec.IsTemporary() and (Rec.CF_BOMNodeId <> xRec.CF_BOMNodeId) then
            Error('The saved BOM identity of a production component cannot be changed.');
    end;

    [EventSubscriber(ObjectType::Table, Database::"Prod. Order Line", 'OnBeforeModifyEvent', '', false, false)]
    local procedure ProtectOutputNode(var Rec: Record "Prod. Order Line"; var xRec: Record "Prod. Order Line"; RunTrigger: Boolean)
    begin
        if Rec.IsTemporary() or IsNullGuid(xRec.CF_BOMNodeId) then
            exit;
        if (Rec.CF_BOMNodeId <> xRec.CF_BOMNodeId) or (Rec."Item No." <> xRec."Item No.") or
           (Rec."Variant Code" <> xRec."Variant Code")
        then
            Error('The saved BOM identity, item and variant of a configured production output cannot be changed.');
    end;
}
