namespace CloudFactory.SalesConfigurator;

using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Setup;
using Microsoft.Manufacturing.Document;
using Microsoft.Manufacturing.ProductionBOM;
using Microsoft.Manufacturing.Setup;
using Microsoft.Sales.Document;
using Microsoft.Foundation.NoSeries;
using Microsoft.Foundation.UOM;

codeunit 91002 CF_ConfiguratorTests
{
    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure AddsBlueWithoutChangingAB()
    var
        ProductionOrder: Record "Production Order";
        RootLine: Record "Prod. Order Line";
        ComponentItem: Record Item;
        Component: Record "Prod. Order Component";
        ItemA: Record Item;
        ItemB: Record Item;
        ConfiguratorMgt: Codeunit CF_ConfiguratorMgt;
    begin
        CreateFixture(ProductionOrder, RootLine, ComponentItem, 10, 1, 1);
        CreateItem(ItemA, 'PCS', 1);
        CreateItem(ItemB, 'PCS', 1);
        InsertStandardComponent(RootLine, ItemA."No.", 10000);
        InsertStandardComponent(RootLine, ItemB."No.", 20000);
        ConfiguratorMgt.ApplyConfiguredComponents(ProductionOrder);
        Component.SetRange(Status, ProductionOrder.Status);
        Component.SetRange("Prod. Order No.", ProductionOrder."No.");
        AssertEqual(3, Component.Count(), 'A, B and configured BLUE must all remain.');
        Component.SetRange(CF_ConfiguredComponent, true);
        Component.FindFirst();
        Component.TestField("Item No.", ComponentItem."No.");
        AssertEqual(10, Component."Expected Quantity", 'BLUE quantity must scale to finished base quantity.');
    end;

    [Test]
    procedure ReapplyingDoesNotDuplicate()
    var
        ProductionOrder: Record "Production Order";
        RootLine: Record "Prod. Order Line";
        ComponentItem: Record Item;
        Component: Record "Prod. Order Component";
        ConfiguratorMgt: Codeunit CF_ConfiguratorMgt;
    begin
        CreateFixture(ProductionOrder, RootLine, ComponentItem, 10, 1, 1);
        ConfiguratorMgt.ApplyConfiguredComponents(ProductionOrder);
        ConfiguratorMgt.ApplyConfiguredComponents(ProductionOrder);
        Component.SetRange(Status, ProductionOrder.Status);
        Component.SetRange("Prod. Order No.", ProductionOrder."No.");
        Component.SetRange(CF_ConfiguredComponent, true);
        AssertEqual(1, Component.Count(), 'Applying twice must create only one configured component.');
    end;

    [Test]
    procedure SameItemInStandardBOMStaysSeparate()
    var
        ProductionOrder: Record "Production Order";
        RootLine: Record "Prod. Order Line";
        ComponentItem: Record Item;
        Component: Record "Prod. Order Component";
        ConfiguratorMgt: Codeunit CF_ConfiguratorMgt;
    begin
        CreateFixture(ProductionOrder, RootLine, ComponentItem, 10, 1, 1);
        InsertStandardComponent(RootLine, ComponentItem."No.", 10000);
        ConfiguratorMgt.ApplyConfiguredComponents(ProductionOrder);
        Component.SetRange(Status, ProductionOrder.Status);
        Component.SetRange("Prod. Order No.", ProductionOrder."No.");
        Component.SetRange("Item No.", ComponentItem."No.");
        AssertEqual(2, Component.Count(), 'The standard component must not be merged with configured demand.');
        Component.SetRange(CF_ConfiguredComponent, false);
        AssertEqual(1, Component.Count(), 'The original standard component must remain unmarked.');
    end;

    [Test]
    procedure ConvertsFinishedAndComponentUOM()
    var
        ProductionOrder: Record "Production Order";
        RootLine: Record "Prod. Order Line";
        ComponentItem: Record Item;
        Component: Record "Prod. Order Component";
        ConfiguratorMgt: Codeunit CF_ConfiguratorMgt;
    begin
        CreateFixture(ProductionOrder, RootLine, ComponentItem, 2, 5, 2);
        ConfiguratorMgt.ApplyConfiguredComponents(ProductionOrder);
        Component.SetRange(Status, ProductionOrder.Status);
        Component.SetRange("Prod. Order No.", ProductionOrder."No.");
        Component.FindFirst();
        AssertEqual(10, Component."Expected Quantity", '2 finished BOX of 5 requires 10 component BOX.');
        AssertEqual(20, Component."Expected Qty. (Base)", '10 component BOX of 2 requires 20 base units.');
    end;

    [Test]
    procedure ConfiguredDemandDoesNotAddScrap()
    var
        ProductionOrder: Record "Production Order";
        RootLine: Record "Prod. Order Line";
        ComponentItem: Record Item;
        Component: Record "Prod. Order Component";
        ConfiguratorMgt: Codeunit CF_ConfiguratorMgt;
    begin
        CreateFixture(ProductionOrder, RootLine, ComponentItem, 10, 1, 1);
        RootLine."Scrap %" := 10;
        RootLine.Modify(false);
        ConfiguratorMgt.ApplyConfiguredComponents(ProductionOrder);
        Component.SetRange(Status, ProductionOrder.Status);
        Component.SetRange("Prod. Order No.", ProductionOrder."No.");
        Component.FindFirst();
        AssertEqual(10, Component."Expected Quantity", 'Configured demand is linear without parent scrap.');
    end;

    [Test]
    procedure MissingSnapshotFailsExplicitly()
    var
        ProductionOrder: Record "Production Order";
        RootLine: Record "Prod. Order Line";
        ComponentItem: Record Item;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
        ConfiguratorMgt: Codeunit CF_ConfiguratorMgt;
    begin
        CreateFixture(ProductionOrder, RootLine, ComponentItem, 10, 1, 1);
        Clear(ProductionOrder.CF_ConfigSnapshot);
        ProductionOrder.Modify(false);
        asserterror ConfiguratorMgt.ReadSnapshot(ProductionOrder, TempConfig);
        AssertContains(GetLastErrorText(), 'Missing payload');
    end;

    [Test]
    procedure SnapshotSurvivesSalesLineDeletion()
    var
        ProductionOrder: Record "Production Order";
        RootLine: Record "Prod. Order Line";
        ComponentItem: Record Item;
        SalesLine: Record "Sales Line";
        Component: Record "Prod. Order Component";
        ConfiguratorMgt: Codeunit CF_ConfiguratorMgt;
    begin
        CreateFixture(ProductionOrder, RootLine, ComponentItem, 10, 1, 1);
        SalesLine.GetBySystemId(ProductionOrder.CF_SourceLineId);
        SalesLine.Delete(false);
        ConfiguratorMgt.ApplyConfiguredComponents(ProductionOrder);
        Component.SetRange(Status, ProductionOrder.Status);
        Component.SetRange("Prod. Order No.", ProductionOrder."No.");
        AssertEqual(1, Component.Count(), 'Production snapshot must not need a live sales line.');
    end;

    [Test]
    procedure PickedComponentCannotBeResized()
    var
        ProductionOrder: Record "Production Order";
        RootLine: Record "Prod. Order Line";
        ComponentItem: Record Item;
        Component: Record "Prod. Order Component";
        ConfiguratorMgt: Codeunit CF_ConfiguratorMgt;
    begin
        CreateFixture(ProductionOrder, RootLine, ComponentItem, 10, 1, 1);
        ConfiguratorMgt.ApplyConfiguredComponents(ProductionOrder);
        Component.SetRange(Status, ProductionOrder.Status);
        Component.SetRange("Prod. Order No.", ProductionOrder."No.");
        Component.FindFirst();
        Component."Qty. Picked" := 1;
        Component.Modify(false);
        RootLine.Quantity := 20;
        RootLine."Quantity (Base)" := 20;
        RootLine.Modify(false);
        asserterror ConfiguratorMgt.ApplyConfiguredComponents(ProductionOrder);
        AssertContains(GetLastErrorText(), 'warehouse picks');
    end;

    [Test]
    procedure StandardCreationAddsConfiguredComponent()
    var
        ProductionOrder: Record "Production Order";
        RootLine: Record "Prod. Order Line";
        ComponentItem: Record Item;
        SalesLine: Record "Sales Line";
        SalesHeader: Record "Sales Header";
        Component: Record "Prod. Order Component";
        CreateFromSales: Codeunit "Create Prod. Order from Sale";
    begin
        CreateFixture(ProductionOrder, RootLine, ComponentItem, 10, 1, 1);
        AttachStandardBOM(RootLine);
        SetupProductionNumberSeries();
        SalesLine.GetBySystemId(ProductionOrder.CF_SourceLineId);
        SalesHeader.Init();
        SalesHeader."Document Type" := SalesHeader."Document Type"::Order;
        SalesHeader."No." := SalesLine."Document No.";
        SalesHeader.Insert(false);
        SalesLine."Shipment Date" := WorkDate() + 10;
        SalesLine.Quantity := 10;
        SalesLine."Quantity (Base)" := 10;
        SalesLine."Outstanding Quantity" := 10;
        SalesLine."Outstanding Qty. (Base)" := 10;
        SalesLine."Qty. per Unit of Measure" := 1;
        SalesLine."Unit of Measure Code" := 'PCS';
        SalesLine.Modify(false);
        RootLine.Delete(false);
        ProductionOrder.Delete(false);
        CreateFromSales.SetHideValidationDialog(true);
        CreateFromSales.CreateProductionOrder(SalesLine, ProductionOrder.Status::"Firm Planned", "Create Production Order Type"::ItemOrder);
        ProductionOrder.SetRange(CF_SourceLineId, SalesLine.SystemId);
        ProductionOrder.FindFirst();
        ProductionOrder.TestField(CF_ConfigVersion, 1);
        ProductionOrder.TestField(CF_RebuildAllowed, false);
        Component.SetRange(Status, ProductionOrder.Status);
        Component.SetRange("Prod. Order No.", ProductionOrder."No.");
        AssertEqual(3, Component.Count(), 'Standard sales creation must preserve two BOM components and add BLUE.');
        Component.SetRange(CF_ConfiguredComponent, true);
        Component.FindFirst();
        Component.TestField("Item No.", ComponentItem."No.");
        AssertEqual(10, Component."Expected Quantity", 'Standard creation must calculate BLUE from production output.');
    end;

    [Test]
    procedure FullAndComponentRefreshPreserveSelections()
    var
        ProductionOrder: Record "Production Order";
        RootLine: Record "Prod. Order Line";
        ComponentItem: Record Item;
        Component: Record "Prod. Order Component";
        Refresh: Report "Refresh Production Order";
        ConfiguratorMgt: Codeunit CF_ConfiguratorMgt;
    begin
        // The standard refresh report uses Update; select it before fixture writes without committing test data.
        CurrentTransactionType(TransactionType::Update);
        CreateFixture(ProductionOrder, RootLine, ComponentItem, 10, 1, 1);
        AttachStandardBOM(RootLine);
        ConfiguratorMgt.ApplyConfiguredComponents(ProductionOrder);
        ProductionOrder.CF_RebuildAllowed := false;
        ProductionOrder.Modify(false);
        ProductionOrder.SetRecFilter();
        Refresh.SetTableView(ProductionOrder);
        Refresh.InitializeRequest(1, true, true, true, false);
        Refresh.SetHideValidationDialog(true);
        Refresh.UseRequestPage(false);
        Refresh.Run();
        Clear(Refresh);
        Refresh.SetTableView(ProductionOrder);
        Refresh.InitializeRequest(1, false, false, true, false);
        Refresh.SetHideValidationDialog(true);
        Refresh.UseRequestPage(false);
        Refresh.Run();
        ProductionOrder.Get(ProductionOrder.Status, ProductionOrder."No.");
        ProductionOrder.TestField(CF_RebuildAllowed, false);
        Component.SetRange(Status, ProductionOrder.Status);
        Component.SetRange("Prod. Order No.", ProductionOrder."No.");
        AssertEqual(3, Component.Count(), 'Both refresh paths must retain A, B and one BLUE.');
        Component.SetRange(CF_ConfiguredComponent, true);
        AssertEqual(1, Component.Count(), 'Repeated refresh must not duplicate BLUE.');
        Component.FindFirst();
        Component.TestField("Item No.", ComponentItem."No.");
        AssertEqual(10, Component."Expected Quantity", 'Refresh must preserve configured quantities.');
    end;

    [Test]
    procedure DirectLineRecreationIsBlocked()
    var
        ProductionOrder: Record "Production Order";
        RootLine: Record "Prod. Order Line";
        ComponentItem: Record Item;
        CreateLines: Codeunit "Create Prod. Order Lines";
    begin
        CreateFixture(ProductionOrder, RootLine, ComponentItem, 10, 1, 1);
        ProductionOrder.CF_RebuildAllowed := false;
        ProductionOrder.Modify(false);
        asserterror CreateLines.Copy(ProductionOrder, 1, '', false);
        AssertContains(GetLastErrorText(), 'Direct production line recreation');
    end;

    [Test]
    [CommitBehavior(CommitBehavior::Ignore)]
    procedure StatusChangePreservesSnapshotAndMarkers()
    var
        ProductionOrder: Record "Production Order";
        ReleasedOrder: Record "Production Order";
        RootLine: Record "Prod. Order Line";
        ComponentItem: Record Item;
        Component: Record "Prod. Order Component";
        TempConfig: Record CF_DocumentLineProductConfig temporary;
        ConfiguratorMgt: Codeunit CF_ConfiguratorMgt;
        StatusMgt: Codeunit "Prod. Order Status Management";
    begin
        CreateFixture(ProductionOrder, RootLine, ComponentItem, 10, 1, 1);
        AttachStandardBOM(RootLine);
        SetupProductionNumberSeries();
        ConfiguratorMgt.ApplyConfiguredComponents(ProductionOrder);
        ProductionOrder.CF_RebuildAllowed := false;
        ProductionOrder.Modify(false);
        StatusMgt.ChangeProdOrderStatus(ProductionOrder, ReleasedOrder, ProductionOrder.Status::Released, WorkDate(), false);
        ReleasedOrder.TestField(Status, ReleasedOrder.Status::Released);
        ConfiguratorMgt.ReadSnapshot(ReleasedOrder, TempConfig);
        AssertEqual(1, TempConfig.Count(), 'Status changes must preserve the immutable snapshot.');
        Component.SetRange(Status, ReleasedOrder.Status);
        Component.SetRange("Prod. Order No.", ReleasedOrder."No.");
        Component.SetRange(CF_ConfiguredComponent, true);
        AssertEqual(1, Component.Count(), 'Status changes must preserve component markers.');
    end;

    [Test]
    procedure ProjectOrderWithSelectionsIsRejected()
    var
        ProductionOrder: Record "Production Order";
        RootLine: Record "Prod. Order Line";
        ComponentItem: Record Item;
        SalesLine: Record "Sales Line";
        SalesHeader: Record "Sales Header";
        CreateFromSales: Codeunit "Create Prod. Order from Sale";
    begin
        CreateFixture(ProductionOrder, RootLine, ComponentItem, 10, 1, 1);
        AttachStandardBOM(RootLine);
        SetupProductionNumberSeries();
        SalesLine.GetBySystemId(ProductionOrder.CF_SourceLineId);
        SalesHeader.Init();
        SalesHeader."Document Type" := SalesHeader."Document Type"::Order;
        SalesHeader."No." := SalesLine."Document No.";
        SalesHeader.Insert(false);
        SalesLine."Shipment Date" := WorkDate() + 10;
        SalesLine.Modify(false);
        CreateFromSales.SetHideValidationDialog(true);
        asserterror CreateFromSales.CreateProductionOrder(SalesLine, ProductionOrder.Status::"Firm Planned", "Create Production Order Type"::ProjectOrder);
        AssertContains(GetLastErrorText(), 'Create Item Orders instead');
    end;

    local procedure AttachStandardBOM(RootLine: Record "Prod. Order Line")
    var
        ParentItem: Record Item;
        ItemA: Record Item;
        ItemB: Record Item;
        BOM: Record "Production BOM Header";
        BOMLine: Record "Production BOM Line";
        ManufacturingSetup: Record "Manufacturing Setup";
    begin
        if not ManufacturingSetup.Get() then begin
            ManufacturingSetup.Init();
            ManufacturingSetup."Normal Starting Time" := 080000T;
            ManufacturingSetup."Normal Ending Time" := 160000T;
            ManufacturingSetup.Insert();
        end;
        CreateItem(ItemA, 'PCS', 1);
        CreateItem(ItemB, 'PCS', 1);
        BOM.Init();
        BOM."No." := NewCode();
        BOM."Unit of Measure Code" := 'PCS';
        BOM.Status := BOM.Status::Certified;
        BOM.Insert(false);
        BOMLine.Init();
        BOMLine."Production BOM No." := BOM."No.";
        BOMLine."Line No." := 10000;
        BOMLine.Type := BOMLine.Type::Item;
        BOMLine."No." := ItemA."No.";
        BOMLine."Unit of Measure Code" := 'PCS';
        BOMLine.Quantity := 1;
        BOMLine."Quantity per" := 1;
        BOMLine.Insert(false);
        BOMLine."Line No." := 20000;
        BOMLine."No." := ItemB."No.";
        BOMLine.Insert(false);
        ParentItem.Get(RootLine."Item No.");
        ParentItem."Production BOM No." := BOM."No.";
        ParentItem."Replenishment System" := ParentItem."Replenishment System"::"Prod. Order";
        ParentItem.Modify(false);
    end;

    local procedure SetupProductionNumberSeries()
    var
        Series: Record "No. Series";
        SeriesLine: Record "No. Series Line";
        ManufacturingSetup: Record "Manufacturing Setup";
    begin
        ManufacturingSetup.Get();
        Series.Init();
        Series.Code := NewCode();
        Series."Default Nos." := true;
        Series.Insert();
        SeriesLine.Init();
        SeriesLine."Series Code" := Series.Code;
        SeriesLine."Line No." := 10000;
        SeriesLine."Starting Date" := WorkDate();
        SeriesLine."Starting No." := CopyStr(NewCode(), 1, 8) + '000001';
        SeriesLine."Ending No." := CopyStr(SeriesLine."Starting No.", 1, 8) + '999999';
        SeriesLine."Increment-by No." := 1;
        SeriesLine.Open := true;
        SeriesLine.Insert();
        ManufacturingSetup."Firm Planned Order Nos." := Series.Code;
        ManufacturingSetup."Released Order Nos." := Series.Code;
        ManufacturingSetup.Modify();
    end;

    local procedure CreateFixture(var ProductionOrder: Record "Production Order"; var RootLine: Record "Prod. Order Line"; var ComponentItem: Record Item; FinishedQuantity: Decimal; FinishedFactor: Decimal; ComponentFactor: Decimal)
    var
        ParentItem: Record Item;
        ItemCategory: Record "Item Category";
        SalesLine: Record "Sales Line";
        Config: Record CF_DocumentLineProductConfig;
        ConfigOption: Record CF_ConfiguratorBOM;
        Choice: Record CF_OptionChoiceLookup;
        InventorySetup: Record "Inventory Setup";
        GLSetup: Record "General Ledger Setup";
        ConfiguratorMgt: Codeunit CF_ConfiguratorMgt;
    begin
        if not InventorySetup.Get() then begin
            InventorySetup.Init();
            InventorySetup.Insert();
        end;
        if not GLSetup.Get() then begin
            GLSetup.Init();
            GLSetup."Amount Rounding Precision" := 0.01;
            GLSetup.Insert();
        end;
        CreateItem(ParentItem, 'BOX', FinishedFactor);
        CreateItem(ComponentItem, 'BOX', ComponentFactor);
        ItemCategory.Init();
        ItemCategory.Code := NewCode();
        ItemCategory.Insert();
        ParentItem."Item Category Code" := ItemCategory.Code;
        ParentItem.Modify(false);
        ConfigOption.Init();
        ConfigOption."Item Category Code" := ItemCategory.Code;
        ConfigOption."Configuration Option" := 'WOOD';
        ConfigOption."Option Description" := 'Wood finish';
        ConfigOption."Quantity per Unit" := 1;
        ConfigOption.Enabled := true;
        ConfigOption.Insert(true);
        Choice.Init();
        Choice."Item Category Code" := ItemCategory.Code;
        Choice."Configuration Option" := 'WOOD';
        Choice.Code := 'BLUE';
        Choice."Item No." := ComponentItem."No.";
        Choice."Unit of Measure Code" := 'BOX';
        Choice.Selectable := true;
        Choice.Insert(true);
        ProductionOrder.Init();
        ProductionOrder.Status := ProductionOrder.Status::"Firm Planned";
        ProductionOrder."No." := NewCode();
        ProductionOrder."Source Type" := ProductionOrder."Source Type"::Item;
        ProductionOrder."Source No." := ParentItem."No.";
        ProductionOrder."Starting Date" := WorkDate();
        ProductionOrder."Starting Time" := 080000T;
        ProductionOrder."Ending Date" := WorkDate() + 1;
        ProductionOrder."Ending Time" := 160000T;
        ProductionOrder."Due Date" := WorkDate() + 1;
        ProductionOrder.Quantity := FinishedQuantity * FinishedFactor;
        ProductionOrder.Insert(false);
        RootLine.Init();
        RootLine.Status := ProductionOrder.Status;
        RootLine."Prod. Order No." := ProductionOrder."No.";
        RootLine."Line No." := 10000;
        RootLine."Item No." := ParentItem."No.";
        RootLine."Unit of Measure Code" := 'BOX';
        RootLine."Qty. per Unit of Measure" := FinishedFactor;
        RootLine.Quantity := FinishedQuantity;
        RootLine."Quantity (Base)" := FinishedQuantity * FinishedFactor;
        RootLine."Starting Date" := ProductionOrder."Starting Date";
        RootLine."Starting Time" := ProductionOrder."Starting Time";
        RootLine."Ending Date" := ProductionOrder."Ending Date";
        RootLine."Ending Time" := ProductionOrder."Ending Time";
        RootLine."Due Date" := ProductionOrder."Due Date";
        RootLine.Insert(false);
        SalesLine.Init();
        SalesLine."Document Type" := SalesLine."Document Type"::Order;
        SalesLine."Document No." := NewCode();
        SalesLine."Line No." := 10000;
        SalesLine.Type := SalesLine.Type::Item;
        SalesLine."No." := ParentItem."No.";
        SalesLine.Insert(false);
        Config.Init();
        Config."Document Type" := Config."Document Type"::SalesOrder;
        Config."Source Table ID" := Database::"Sales Line";
        Config."Source Line SystemId" := SalesLine.SystemId;
        Config."Document No." := SalesLine."Document No.";
        Config."Document Line No." := SalesLine."Line No.";
        Config."Parent Item No." := ParentItem."No.";
        Config."Item Category Code" := ItemCategory.Code;
        Config."Configuration Option" := 'WOOD';
        Config."Choice Code" := 'BLUE';
        Config."Component Item No." := ComponentItem."No.";
        Config."Component UOM Code" := 'BOX';
        Config."Quantity per Unit" := 1;
        Config.Insert(false);
        ConfiguratorMgt.CaptureSnapshot(ProductionOrder, SalesLine);
        ProductionOrder.Modify(false);
    end;

    local procedure CreateItem(var Item: Record Item; UOMCode: Code[10]; Factor: Decimal)
    var
        UOM: Record "Unit of Measure";
        ItemUOM: Record "Item Unit of Measure";
        PostingGroup: Record "Inventory Posting Group";
    begin
        if not UOM.Get('PCS') then begin
            UOM.Init();
            UOM.Code := 'PCS';
            UOM.Insert();
        end;
        if not UOM.Get(UOMCode) then begin
            UOM.Init();
            UOM.Code := UOMCode;
            UOM.Insert();
        end;
        Item.Init();
        if not PostingGroup.Get('CFTEST') then begin
            PostingGroup.Init();
            PostingGroup.Code := 'CFTEST';
            PostingGroup.Insert();
        end;
        Item."No." := NewCode();
        Item.Type := Item.Type::Inventory;
        Item."Base Unit of Measure" := 'PCS';
        Item."Inventory Posting Group" := PostingGroup.Code;
        Item.Insert(false);
        ItemUOM.Init();
        ItemUOM."Item No." := Item."No.";
        ItemUOM.Code := 'PCS';
        ItemUOM."Qty. per Unit of Measure" := 1;
        ItemUOM.Insert(false);
        if UOMCode <> 'PCS' then begin
            ItemUOM.Init();
            ItemUOM."Item No." := Item."No.";
            ItemUOM.Code := UOMCode;
            ItemUOM."Qty. per Unit of Measure" := Factor;
            ItemUOM.Insert(false);
        end;
    end;

    local procedure InsertStandardComponent(RootLine: Record "Prod. Order Line"; ItemNo: Code[20]; LineNo: Integer)
    var
        Component: Record "Prod. Order Component";
    begin
        Component.Init();
        Component.Status := RootLine.Status;
        Component."Prod. Order No." := RootLine."Prod. Order No.";
        Component."Prod. Order Line No." := RootLine."Line No.";
        Component."Line No." := LineNo;
        Component."Item No." := ItemNo;
        Component.Insert(false);
    end;

    local procedure NewCode(): Code[20]
    begin
        exit(CopyStr(DelChr(Format(CreateGuid()), '=', '{}-'), 1, 20));
    end;

    local procedure AssertEqual(Expected: Decimal; Actual: Decimal; Message: Text)
    begin
        if Expected <> Actual then
            Error('%1 Expected %2, actual %3.', Message, Expected, Actual);
    end;

    local procedure AssertContains(Value: Text; Expected: Text)
    begin
        if StrPos(Value, Expected) = 0 then
            Error('Expected error containing "%1", actual "%2".', Expected, Value);
    end;
}
