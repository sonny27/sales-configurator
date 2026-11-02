namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Planning;
using Microsoft.Manufacturing.Document;
using Microsoft.Manufacturing.ProductionBOM;
using Microsoft.Manufacturing.Routing;
using Microsoft.Sales.Document;

codeunit 91001 CF_DocumentConfigMgt
{
    Permissions = tabledata CF_DocumentLineProductConfig = rimd,
                  tabledata "Sales Line" = rm;

    procedure InitializeBase(var SalesLine: Record "Sales Line")
    begin
        if not SalesLine.CF_BaseSetupSet then
            GetItemManufacturingSetup(SalesLine."No.", SalesLine."Location Code", SalesLine."Variant Code",
                SalesLine.CF_BaseBOMNo, SalesLine.CF_BaseRoutingNo);
    end;

    procedure CopyBase(Source: Record "Sales Line"; var Target: Record "Sales Line")
    begin
        Target.CF_BaseBOMNo := Source.CF_BaseBOMNo;
        Target.CF_BaseRoutingNo := Source.CF_BaseRoutingNo;
        Target.CF_BaseSetupSet := Source.CF_BaseSetupSet;
    end;

    procedure StampBase(SalesLine: Record "Sales Line"; var Config: Record CF_DocumentLineProductConfig temporary)
    var
        OriginalView: Text;
    begin
        OriginalView := Config.GetView(false);
        Config.Reset();
        if Config.FindSet() then
            repeat
                Config."Base BOM" := SalesLine.CF_BaseBOMNo;
                Config."Base Routing" := SalesLine.CF_BaseRoutingNo;
                Config."Base Selection Set" := SalesLine.CF_BaseSetupSet;
                Config.Modify(false);
            until Config.Next() = 0;
        Config.SetView(OriginalView);
    end;

    procedure ValidateBase(SalesLine: Record "Sales Line")
    var
        BOM: Record "Production BOM Header";
        Routing: Record "Routing Header";
        VersionMgt: Codeunit VersionManagement;
    begin
        if SalesLine.CF_BaseBOMNo <> '' then begin
            BOM.Get(SalesLine.CF_BaseBOMNo);
            if VersionMgt.GetBOMVersion(BOM."No.", WorkDate(), true) = '' then
                BOM.TestField(Status, BOM.Status::Certified);
        end;
        if SalesLine.CF_BaseRoutingNo <> '' then begin
            Routing.Get(SalesLine.CF_BaseRoutingNo);
            if VersionMgt.GetRtngVersion(Routing."No.", WorkDate(), true) = '' then
                Routing.TestField(Status, Routing.Status::Certified);
        end;
    end;

    procedure FilterSalesLine(SalesLine: Record "Sales Line"; var Config: Record CF_DocumentLineProductConfig)
    begin
        Config.Reset();
        Config.SetRange("Document Type", GetConfigDocumentType(SalesLine));
        Config.SetRange("Source Table ID", Database::"Sales Line");
        Config.SetRange("Source Line SystemId", SalesLine.SystemId);
    end;

    procedure ValidateForProduction(SalesLine: Record "Sales Line")
    var
        Config: Record CF_DocumentLineProductConfig;
        DraftMgt: Codeunit CF_BOMDraftMgt;
    begin
        SalesLine.TestField("Document Type", SalesLine."Document Type"::Order);
        ValidateSalesLine(SalesLine);
        FilterSalesLine(SalesLine, Config);
        if Config.FindSet() then
            repeat
                ValidateStoredRow(Config);
            until Config.Next() = 0;
        ValidateMandatory(SalesLine, Config);
        DraftMgt.CheckChoices(SalesLine, Config);
    end;

    procedure ValidatePreview(SalesLine: Record "Sales Line"; var Choices: Record CF_DocumentLineProductConfig temporary)
    var
        Reader: Record CF_DocumentLineProductConfig temporary;
    begin
        ValidateSalesLine(SalesLine);
        ValidateBase(SalesLine);
        Reader.Copy(Choices, true);
        Reader.Reset();
        if Reader.FindSet() then
            repeat
                ValidateStoredRow(Reader);
            until Reader.Next() = 0;
        ValidateMandatory(SalesLine, Reader);
    end;

    procedure ValidateItem(ItemNo: Code[20]; VariantCode: Code[10]; UOM: Code[10])
    var
        Item: Record Item;
        Variant: Record "Item Variant";
        ItemUOM: Record "Item Unit of Measure";
    begin
        if (ItemNo = '') or not Item.Get(ItemNo) then
            Error('Configured component item %1 does not exist.', ItemNo);
        if not (Item.Type in [Item.Type::Inventory, Item.Type::"Non-Inventory"]) then
            Error('Configured component item %1 must be an inventory or non-inventory item.', ItemNo);
        if Item.Blocked then
            Error('Configured component item %1 is blocked.', ItemNo);
        // Output-only blocking does not prohibit consumption. Unknown blocking values fail closed.
        if not (Item."Production Blocked" in [Item."Production Blocked"::" ", Item."Production Blocked"::Output]) then
            Error('Configured component item %1 is blocked for production consumption.', ItemNo);
        if VariantCode <> '' then begin
            if not Variant.Get(ItemNo, VariantCode) then
                Error('Variant %1 does not exist for configured component item %2.', VariantCode, ItemNo);
            if Variant.Blocked then
                Error('Variant %1 of configured component item %2 is blocked.', VariantCode, ItemNo);
            if not (Variant."Production Blocked" in [Variant."Production Blocked"::" ", Variant."Production Blocked"::Output]) then
                Error('Variant %1 of configured component item %2 is blocked for production consumption.', VariantCode, ItemNo);
        end;
        if (UOM = '') or not ItemUOM.Get(ItemNo, UOM) then
            Error('Unit of measure %1 is not valid for configured component item %2.', UOM, ItemNo);
        ItemUOM.TestField("Qty. per Unit of Measure");
        if ItemUOM."Qty. per Unit of Measure" <= 0 then
            Error('Unit of measure %1 for item %2 must have a positive conversion factor.', UOM, ItemNo);
    end;

    procedure EnsureEditable(SalesLine: Record "Sales Line")
    var
        ProductionOrder: Record "Production Order";
    begin
        if GetLinkedProductionOrders(SalesLine, ProductionOrder) then
            Error('Sales order %1, line %2 is linked to production order %3 (%4). Its configuration and parent item context cannot be changed.',
                SalesLine."Document No.", SalesLine."Line No.", ProductionOrder."No.", ProductionOrder.Status);
    end;

    procedure FilterLinkedProductionOrders(SourceTableId: Integer; SourceLineId: Guid; var ProductionOrder: Record "Production Order")
    begin
        ProductionOrder.Reset();
        ProductionOrder.SetCurrentKey(CF_SourceTableId, CF_SourceLineId, CF_ConfigVersion);
        ProductionOrder.SetRange(CF_SourceTableId, SourceTableId);
        ProductionOrder.SetRange(CF_SourceLineId, SourceLineId);
        ProductionOrder.SetFilter(CF_ConfigVersion, '>0');
    end;

    procedure GetLinkedProductionOrders(SalesLine: Record "Sales Line"; var ProductionOrder: Record "Production Order"): Boolean
    begin
        FilterLinkedProductionOrders(Database::"Sales Line", SalesLine.SystemId, ProductionOrder);
        exit(ProductionOrder.FindFirst());
    end;

    procedure OpenLinkedProductionOrders(SalesLine: Record "Sales Line")
    var
        ProductionOrder: Record "Production Order";
    begin
        if not GetLinkedProductionOrders(SalesLine, ProductionOrder) then
            Error(NoLinkedOrderErr, SalesLine."Document No.", SalesLine."Line No.");
        if ProductionOrder.Count() > 1 then begin
            Page.RunModal(Page::"Production Order List", ProductionOrder);
            exit;
        end;
        ProductionOrder.SetCurrentKey(Status, "No.");
        ProductionOrder.SetRecFilter();
        case ProductionOrder.Status of
            ProductionOrder.Status::Simulated:
                Page.RunModal(Page::"Simulated Production Order", ProductionOrder);
            ProductionOrder.Status::Planned:
                Page.RunModal(Page::"Planned Production Order", ProductionOrder);
            ProductionOrder.Status::"Firm Planned":
                Page.RunModal(Page::"Firm Planned Prod. Order", ProductionOrder);
            ProductionOrder.Status::Released:
                Page.RunModal(Page::"Released Production Order", ProductionOrder);
            ProductionOrder.Status::Finished:
                Page.RunModal(Page::"Finished Production Order", ProductionOrder);
            else
                Error(UnsupportedOrderStatusErr, ProductionOrder.Status);
        end;
    end;

    procedure CreateProductionOrder(SalesLine: Record "Sales Line")
    var
        Setup: Record CF_SalesConfiguratorSetup;
        CreateOrderFromSales: Page "Create Order From Sales";
        CreateProdOrderFromSale: Codeunit "Create Prod. Order from Sale";
        NewStatus: Enum "Production Order Status";
        NewOrderType: Enum "Create Production Order Type";
        SourceLineId: Guid;
    begin
        SalesLine.TestField("Document Type", SalesLine."Document Type"::Order);
        ValidateSalesLine(SalesLine);
        CheckProductionDemand(SalesLine);
        SourceLineId := SalesLine.SystemId;
        Setup.Get();
        Setup.CheckProductionOrderStatus();
        CreateOrderFromSales.SetParameters(Setup."Default Prod. Order Status", NewOrderType::ItemOrder);
        if CreateOrderFromSales.RunModal() <> Action::Yes then
            exit;
        CreateOrderFromSales.GetParameters(NewStatus, NewOrderType);
        if not SalesLine.GetBySystemId(SourceLineId) then
            Error(SourceMissingErr);
        ValidateSalesLine(SalesLine);
        CheckProductionDemand(SalesLine);
        CreateProdOrderFromSale.CreateProductionOrder(SalesLine, NewStatus, NewOrderType);
    end;

    procedure ShowConfiguredBOM(SalesLine: Record "Sales Line")
    var
        Config: Record CF_DocumentLineProductConfig;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
    begin
        ValidateSalesLine(SalesLine);
        FilterSalesLine(SalesLine, Config);
        if Config.FindSet() then
            repeat
                TempConfig := Config;
                TempConfig.Insert(false, true);
            until Config.Next() = 0;
        OpenEditableBOM(SalesLine, TempConfig);
    end;

    procedure ShowConfiguredBOM(SalesLine: Record "Sales Line"; var TempConfig: Record CF_DocumentLineProductConfig temporary): Boolean
    begin
        exit(OpenEditableBOM(SalesLine, TempConfig));
    end;

    local procedure OpenEditableBOM(SalesLine: Record "Sales Line"; var TempConfig: Record CF_DocumentLineProductConfig temporary): Boolean
    var
        DraftMgt: Codeunit CF_BOMDraftMgt;
    begin
        ValidateSalesLine(SalesLine);
        exit(DraftMgt.Open(SalesLine, TempConfig));
    end;

    local procedure OpenConfiguredBOM(SalesLine: Record "Sales Line"; var TempConfig: Record CF_DocumentLineProductConfig temporary; IncludesUnsavedChoices: Boolean)
    var
        CurrentSalesLine: Record "Sales Line";
        ItemUOM: Record "Item Unit of Measure";
        TempBOMLine: Record CF_ConfiguredBOMLine temporary;
        RootPreviewLine: Record CF_ConfiguredBOMLine temporary;
        Reader: Record CF_DocumentLineProductConfig temporary;
        ComponentItem: Record Item;
        ComponentVariant: Record "Item Variant";
        ComponentBOM: Record "Production BOM Header";
        VersionMgt: Codeunit VersionManagement;
        Preview: Page CF_ConfiguredBOM;
        BOMNo: Code[20];
        RoutingNo: Code[20];
        VersionCode: Code[20];
        BOMUOM: Code[10];
        NextLineNo: Integer;
        BOMPath: List of [Code[20]];
    begin
        ValidateSalesLine(SalesLine);
        CurrentSalesLine.GetBySystemId(SalesLine.SystemId);
        CurrentSalesLine.TestField("Shipment Date");
        GetItemManufacturingSetup(CurrentSalesLine."No.", CurrentSalesLine."Location Code", CurrentSalesLine."Variant Code", BOMNo, RoutingNo);
        if BOMNo = '' then
            Error(NoParentBOMErr, CurrentSalesLine."Document No.", CurrentSalesLine."Line No.", CurrentSalesLine."No.");
        VersionCode := GetCertifiedBOMVersion(BOMNo, CurrentSalesLine."Shipment Date");
        BOMUOM := VersionMgt.GetBOMUnitOfMeasure(BOMNo, VersionCode);
        ItemUOM.Get(CurrentSalesLine."No.", BOMUOM);
        if ItemUOM."Qty. per Unit of Measure" <= 0 then
            ItemUOM.FieldError("Qty. per Unit of Measure", PositiveBOMUOMErr);

        RootPreviewLine.Indentation := -1;
        AppendPreviewBOMLines(BOMNo, CurrentSalesLine."Shipment Date", RootPreviewLine, TempBOMLine, NextLineNo, BOMPath);

        Reader.Copy(TempConfig, true);
        Reader.Reset();
        Reader.SetCurrentKey("Document Type", "Source Table ID", "Source Line SystemId", "Display Order", "Configuration Option");
        if Reader.FindSet() then
            repeat
                ValidateContext(CurrentSalesLine, Reader);
                if Reader."Choice Code" <> '' then begin
                    ValidateConfiguredComponent(CurrentSalesLine, Reader);
                    ValidateConfigQuantity(Reader);
                    ValidateRoutingLink(CurrentSalesLine, Reader."Routing Link Code", Reader."Configuration Option");
                    NextLineNo += 10000;
                    TempBOMLine.Init();
                    TempBOMLine."Line No." := NextLineNo;
                    TempBOMLine."Production BOM No." := BOMNo;
                    TempBOMLine."Version Code" := VersionCode;
                    TempBOMLine."Parent BOM Unit of Measure" := BOMUOM;
                    TempBOMLine.Type := Reader."Component Type";
                    TempBOMLine."No." := Reader."Component Item No.";
                    if Reader."Component Type" = Reader."Component Type"::"Production BOM" then begin
                        ComponentBOM.Get(Reader."Component Item No.");
                        TempBOMLine.Description := ComponentBOM.Description;
                        TempBOMLine."Description 2" := ComponentBOM."Description 2";
                    end else begin
                        ComponentItem.Get(Reader."Component Item No.");
                        TempBOMLine.Description := ComponentItem.Description;
                        TempBOMLine."Description 2" := ComponentItem."Description 2";
                        if Reader."Component Variant Code" <> '' then begin
                            ComponentVariant.Get(Reader."Component Item No.", Reader."Component Variant Code");
                            TempBOMLine.Description := ComponentVariant.Description;
                            TempBOMLine."Description 2" := ComponentVariant."Description 2";
                        end;
                    end;
                    TempBOMLine."Variant Code" := Reader."Component Variant Code";
                    TempBOMLine."Unit of Measure Code" := Reader."Component UOM Code";
                    TempBOMLine."Quantity per" := Reader."Quantity per Unit" * ItemUOM."Qty. per Unit of Measure";
                    TempBOMLine."Routing Link Code" := Reader."Routing Link Code";
                    TempBOMLine.Configured := true;
                    TempBOMLine."Configuration Option" := Reader."Configuration Option";
                    TempBOMLine."Choice Code" := Reader."Choice Code";
                    TempBOMLine.Insert();
                    if TempBOMLine.Type = TempBOMLine.Type::"Production BOM" then
                        AppendPreviewBOMLines(TempBOMLine."No.", CurrentSalesLine."Shipment Date", TempBOMLine, TempBOMLine, NextLineNo, BOMPath);
                end;
            until Reader.Next() = 0;
        TempBOMLine.Reset();
        Preview.SetPreview(TempBOMLine, CurrentSalesLine, BOMNo, VersionCode, BOMUOM, IncludesUnsavedChoices);
        Preview.RunModal();
    end;

    local procedure GetCertifiedBOMVersion(BOMNo: Code[20]; EffectiveDate: Date): Code[20]
    var
        BOMHeader: Record "Production BOM Header";
        BOMVersion: Record "Production BOM Version";
        VersionMgt: Codeunit VersionManagement;
        VersionCode: Code[20];
    begin
        BOMHeader.Get(BOMNo);
        VersionCode := VersionMgt.GetBOMVersion(BOMNo, EffectiveDate, true);
        if VersionCode = '' then
            BOMHeader.TestField(Status, BOMHeader.Status::Certified)
        else begin
            BOMVersion.Get(BOMNo, VersionCode);
            BOMVersion.TestField(Status, BOMVersion.Status::Certified);
        end;
        exit(VersionCode);
    end;

    local procedure AppendPreviewBOMLines(BOMNo: Code[20]; EffectiveDate: Date; ParentLine: Record CF_ConfiguredBOMLine; var TempBOMLine: Record CF_ConfiguredBOMLine temporary; var NextLineNo: Integer; var BOMPath: List of [Code[20]])
    var
        BOMLine: Record "Production BOM Line";
        ChildLine: Record CF_ConfiguredBOMLine temporary;
        VersionMgt: Codeunit VersionManagement;
        VersionCode: Code[20];
        ParentUOM: Code[10];
    begin
        if BOMPath.Contains(BOMNo) then
            Error('Circular Production BOM reference %1 prevents building the configured BOM preview.', BOMNo);
        if BOMPath.Count() >= 50 then
            Error('Production BOM %1 exceeds the maximum preview depth of 50 BOM levels.', BOMNo);
        BOMPath.Add(BOMNo);
        VersionCode := GetCertifiedBOMVersion(BOMNo, EffectiveDate);
        ParentUOM := VersionMgt.GetBOMUnitOfMeasure(BOMNo, VersionCode);
        BOMLine.SetRange("Production BOM No.", BOMNo);
        BOMLine.SetRange("Version Code", VersionCode);
        BOMLine.SetFilter("Starting Date", '%1|..%2', 0D, EffectiveDate);
        BOMLine.SetFilter("Ending Date", '%1|%2..', 0D, EffectiveDate);
        if BOMLine.FindSet() then
            repeat
                ChildLine.Init();
                ChildLine.TransferFields(BOMLine, false);
                NextLineNo += 10000;
                ChildLine."Line No." := NextLineNo;
                ChildLine.Indentation := ParentLine.Indentation + 1;
                ChildLine."Parent BOM Unit of Measure" := ParentUOM;
                ChildLine.Configured := ParentLine.Configured;
                ChildLine."Configuration Option" := ParentLine."Configuration Option";
                ChildLine."Choice Code" := ParentLine."Choice Code";
                TempBOMLine := ChildLine;
                TempBOMLine.Insert();
                if ChildLine.Type = ChildLine.Type::"Production BOM" then
                    AppendPreviewBOMLines(ChildLine."No.", EffectiveDate, ChildLine, TempBOMLine, NextLineNo, BOMPath);
            until BOMLine.Next() = 0;
        BOMPath.Remove(BOMNo);
    end;

    local procedure CheckProductionDemand(var SalesLine: Record "Sales Line")
    begin
        SalesLine.TestField("Shipment Date");
        SalesLine.CalcFields("Reserved Qty. (Base)");
        if SalesLine."Outstanding Qty. (Base)" <= SalesLine."Reserved Qty. (Base)" then
            Error(NoProductionDemandErr, SalesLine."Document No.", SalesLine."Line No.");
        if not IsProductionEligible(SalesLine) then
            Error(ProductionEligibilityErr, SalesLine."No.", SalesLine."Variant Code", SalesLine."Location Code");
    end;

    local procedure IsProductionEligible(SalesLine: Record "Sales Line"): Boolean
    var
        Item: Record Item;
        ItemVariant: Record "Item Variant";
        StockkeepingUnit: Record "Stockkeeping Unit";
        ProductionReplenishment: Boolean;
    begin
        Item.Get(SalesLine."No.");
        if StockkeepingUnit.Get(SalesLine."Location Code", SalesLine."No.", SalesLine."Variant Code") then
            ProductionReplenishment := StockkeepingUnit."Replenishment System" = StockkeepingUnit."Replenishment System"::"Prod. Order";
        ProductionReplenishment := ProductionReplenishment or (Item."Replenishment System" = Item."Replenishment System"::"Prod. Order");
        if not ProductionReplenishment or Item.Blocked or (Item."Production Blocked" = Item."Production Blocked"::Output) then
            exit(false);
        if SalesLine."Variant Code" <> '' then begin
            ItemVariant.Get(SalesLine."No.", SalesLine."Variant Code");
            if ItemVariant.Blocked or (ItemVariant."Production Blocked" = ItemVariant."Production Blocked"::Output) then
                exit(false);
        end;
        exit(true);
    end;

    procedure DeleteConfiguration(SalesLine: Record "Sales Line"): Boolean
    var
        Config: Record CF_DocumentLineProductConfig;
        ProductionOrder: Record "Production Order";
        CurrentSalesLine: Record "Sales Line";
        DraftMgt: Codeunit CF_BOMDraftMgt;
        Header: Record CF_ProductConfigHeader;
    begin
        ValidateSalesLine(SalesLine);
        if GetLinkedProductionOrders(SalesLine, ProductionOrder) then begin
            if Confirm(OpenLinkedOrderQst, false, SalesLine."Document No.", SalesLine."Line No.",
                ProductionOrder."No.", ProductionOrder.Status)
            then
                OpenLinkedProductionOrders(SalesLine);
            exit(false);
        end;
        FilterSalesLine(SalesLine, Config);
        if Config.IsEmpty() and not DraftMgt.HasSaved(SalesLine.SystemId) then begin
            Message(NoSavedConfigMsg);
            exit(false);
        end;
        if not Confirm(DeleteConfigurationQst, false, SalesLine."Document No.", SalesLine."Line No.") then
            exit(false);
        CurrentSalesLine.LockTable();
        if not CurrentSalesLine.GetBySystemId(SalesLine.SystemId) then
            Error(SourceMissingErr);
        ValidateSalesLine(CurrentSalesLine);
        EnsureEditable(CurrentSalesLine);
        Config.LockTable();
        FilterSalesLine(CurrentSalesLine, Config);
        Config.DeleteAll(true);
        DraftMgt.DeleteSaved(SalesLine.SystemId);
        Header.SetRange("Source Table ID", Database::"Sales Line");
        Header.SetRange("Source Line SystemId", SalesLine.SystemId);
        if Header.FindFirst() then begin
            Header.Delete(true);
            CurrentSalesLine.CF_ProductConfigurationNo := '';
            CurrentSalesLine.Modify(false);
        end;
        CurrentSalesLine.GetBySystemId(SalesLine.SystemId);
        Clear(CurrentSalesLine.CF_BaseBOMNo);
        Clear(CurrentSalesLine.CF_BaseRoutingNo);
        CurrentSalesLine.CF_BaseSetupSet := false;
        CurrentSalesLine.Modify(false);
        exit(true);
    end;

    procedure ConfirmProductionOrderDeletion(ProductionOrder: Record "Production Order"): Boolean
    var
        Config: Record CF_DocumentLineProductConfig;
    begin
        if not GuiAllowed() or ProductionOrder.IsTemporary() or (ProductionOrder.CF_ConfigVersion = 0) then
            exit(true);
        Config.SetRange("Document Type", ProductionOrder.CF_DocumentType);
        Config.SetRange("Source Table ID", ProductionOrder.CF_SourceTableId);
        Config.SetRange("Source Line SystemId", ProductionOrder.CF_SourceLineId);
        if Config.IsEmpty() then
            exit(true);
        if Confirm(DeleteProductionOrderQst, false, ProductionOrder.CF_DocumentNo,
            ProductionOrder.CF_DocumentLineNo, ProductionOrder."No.", ProductionOrder.Status)
        then
            exit(true);
        if Confirm(OpenProductionConfigurationQst, false) then
            OpenConfigurationSummary(ProductionOrder.CF_DocumentType, ProductionOrder.CF_SourceTableId, ProductionOrder.CF_SourceLineId, false);
        exit(false);
    end;

    procedure OpenConfigurationSummary(DocumentType: Enum CF_ConfigDocumentType; SourceTableId: Integer; SourceLineId: Guid; Modal: Boolean)
    var
        Header: Record CF_ProductConfigHeader;
    begin
        Header.SetRange("Document Type", DocumentType);
        Header.SetRange("Source Table ID", SourceTableId);
        Header.SetRange("Source Line SystemId", SourceLineId);
        if Header.IsEmpty() then
            Error('The selected document line no longer has a saved configuration header.');
        if Modal then
            Page.RunModal(Page::CF_ProductConfigurations, Header)
        else
            Page.Run(Page::CF_ProductConfigurations, Header);
    end;

    procedure OpenSalesOrder(Config: Record CF_DocumentLineProductConfig)
    var
        SalesLine: Record "Sales Line";
        SalesHeader: Record "Sales Header";
    begin
        GetSource(Config, SalesLine);
        SalesHeader.Get(SalesLine."Document Type", SalesLine."Document No.");
        SalesHeader.SetRecFilter();
        case SalesLine."Document Type" of
            SalesLine."Document Type"::Order:
                Page.RunModal(Page::"Sales Order", SalesHeader);
            SalesLine."Document Type"::Quote:
                Page.RunModal(Page::"Sales Quote", SalesHeader);
        end;
    end;

    procedure EnsureConfigEditable(Config: Record CF_DocumentLineProductConfig)
    var
        SalesLine: Record "Sales Line";
    begin
        GetSource(Config, SalesLine);
        EnsureEditable(SalesLine);
    end;

    procedure ValidateStoredRow(Config: Record CF_DocumentLineProductConfig)
    var
        SalesLine: Record "Sales Line";
        OptionSetup: Record CF_ConfiguratorBOM;
        Choice: Record CF_OptionChoiceLookup;
    begin
        GetSource(Config, SalesLine);
        ValidateContext(SalesLine, Config);
        Config.TestField("Configuration Option");
        if not OptionSetup.Get(Config.GetTemplateCode(), Config."Configuration Option") then
            Error('Sales document %1, line %2: option %3 no longer exists. Clear this obsolete option explicitly in Product Configurator.',
                Config."Document No.", Config."Document Line No.", Config."Configuration Option");
        if not OptionSetup.Enabled then
            Error('Sales document %1, line %2: option %3 is disabled. Clear this obsolete option explicitly in Product Configurator.',
                Config."Document No.", Config."Document Line No.", Config."Configuration Option");
        if Config."Choice Code" = '' then begin
            if (Config."Component Item No." <> '') or (Config."Component Variant Code" <> '') or (Config."Component UOM Code" <> '') then
                Error('Unselected option %1 must not contain a component mapping.', Config."Configuration Option");
            exit;
        end;
        GetChoice(Config, Choice);
        if (Config."Component Type" <> Choice.Type) or (Config."Component Item No." <> Choice."Item No.") or
           (Config."Component Variant Code" <> Choice."Variant Code") or
           (Config."Component UOM Code" <> Choice."Unit of Measure Code")
        then
            Error('Sales document %1, line %2, option %3, choice %4: the setup item/variant/UOM mapping changed. Explicitly reselect the choice and apply the configuration.',
                Config."Document No.", Config."Document Line No.", Config."Configuration Option", Config."Choice Code");
        ValidateConfiguredComponent(SalesLine, Config);
        ValidateConfigQuantity(Config);
        ValidateRoutingLink(SalesLine, Config."Routing Link Code", Config."Configuration Option");
    end;

    procedure ValidateConfigQuantity(Config: Record CF_DocumentLineProductConfig)
    var
        Choice: Record CF_OptionChoiceLookup;
    begin
        if Config."Quantity per Unit" <= 0 then
            Error('Quantity per unit must be positive for option %1.', Config."Configuration Option");
        if Config."Choice Code" = '' then
            exit;
        GetChoice(Config, Choice);
        Choice.CheckQuantity(Config."Quantity per Unit");
    end;

    procedure ValidateChoice(var Config: Record CF_DocumentLineProductConfig)
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
    begin
        GetSource(Config, SalesLine);
        ValidateContext(SalesLine, Config);
        EnsureEditable(SalesLine);
        if Config."Choice Code" = '' then begin
            Config."Component Type" := Config."Component Type"::Item;
            Clear(Config."Component Item No.");
            Clear(Config."Component Variant Code");
            Clear(Config."Component UOM Code");
            Config."Quantity per Unit" := 1;
            Clear(Config."Routing Link Code");
            exit;
        end;
        GetChoice(Config, Choice);
        Config."Component Type" := Choice.Type;
        Config."Component Item No." := Choice."Item No.";
        Config."Component Variant Code" := Choice."Variant Code";
        Config."Component UOM Code" := Choice."Unit of Measure Code";
        Choice.Validate("Quantity per Unit");
        // Zero is an incomplete worksheet default, never a valid applied component quantity.
        Config."Quantity per Unit" := Choice."Quantity per Unit";
        ValidateConfiguredComponent(SalesLine, Config);
    end;

    procedure ValidateConfiguredComponent(SalesLine: Record "Sales Line"; Config: Record CF_DocumentLineProductConfig)
    var
        VersionMgt: Codeunit VersionManagement;
        VersionCode: Code[20];
    begin
        if not (Config."Component Type" in [Config."Component Type"::Item, Config."Component Type"::"Production BOM"]) then
            Config.FieldError("Component Type", 'must be Item or Production BOM');
        if Config."Component Type" = Config."Component Type"::Item then begin
            ValidateItem(Config."Component Item No.", Config."Component Variant Code", Config."Component UOM Code");
            exit;
        end;
        Config.TestField("Component Variant Code", '');
        SalesLine.TestField("Shipment Date");
        VersionCode := GetCertifiedBOMVersion(Config."Component Item No.", SalesLine."Shipment Date");
        Config.TestField("Component UOM Code", VersionMgt.GetBOMUnitOfMeasure(Config."Component Item No.", VersionCode));
    end;

    procedure LookupChoice(var Config: Record CF_DocumentLineProductConfig): Boolean
    var
        Choice: Record CF_OptionChoiceLookup;
        Choices: Page CF_OptionChoiceLookup;
    begin
        Choice.SetRange("Item Category Code", Config.GetTemplateCode());
        Choice.SetRange("Configuration Option", Config."Configuration Option");
        Choice.SetRange(Selectable, true);
        Choices.SetTableView(Choice);
        Choices.LookupMode(true);
        if Choices.RunModal() <> Action::LookupOK then
            exit(false);
        Choices.GetRecord(Choice);
        Config.Validate("Choice Code", Choice.Code);
        exit(true);
    end;

    procedure GetAvailableRoutingLinks(SalesLine: Record "Sales Line"; var TempLink: Record "Routing Link" temporary)
    var
        RoutingLine: Record "Routing Line";
    begin
        FilterParentRoutingLines(SalesLine, RoutingLine);
        CollectRoutingLinks(RoutingLine, TempLink);
    end;

    procedure GetAvailableItemRoutingLinks(ItemNo: Code[20]; LocationCode: Code[10]; VariantCode: Code[10]; RoutingDate: Date; var TempLink: Record "Routing Link" temporary)
    var
        RoutingLine: Record "Routing Line";
    begin
        FilterItemRoutingLines(ItemNo, LocationCode, VariantCode, RoutingDate, RoutingLine);
        CollectRoutingLinks(RoutingLine, TempLink);
    end;

    local procedure CollectRoutingLinks(var RoutingLine: Record "Routing Line"; var TempLink: Record "Routing Link" temporary)
    var
        Link: Record "Routing Link";
    begin
        TempLink.Reset();
        TempLink.DeleteAll();
        if RoutingLine.GetRangeMin("Routing No.") = '' then
            exit;
        RoutingLine.SetFilter("Routing Link Code", '<>%1', '');
        if RoutingLine.FindSet() then
            repeat
                if not TempLink.Get(RoutingLine."Routing Link Code") then begin
                    Link.Get(RoutingLine."Routing Link Code");
                    TempLink := Link;
                    TempLink.Insert(false);
                end;
            until RoutingLine.Next() = 0;
        TempLink.Reset();
    end;

    procedure LookupRoutingLink(var Config: Record CF_DocumentLineProductConfig): Boolean
    var
        SalesLine: Record "Sales Line";
        TempLink: Record "Routing Link" temporary;
        LinkCode: Code[10];
    begin
        GetSource(Config, SalesLine);
        ValidateContext(SalesLine, Config);
        EnsureEditable(SalesLine);
        LinkCode := Config."Routing Link Code";
        GetAvailableRoutingLinks(SalesLine, TempLink);
        if TempLink.IsEmpty() then
            Error('No routing link codes are available on the selected base routing for item %1. Leave Routing Link Code blank, or select a routing with assigned links.', SalesLine."No.");
        if not LookupRoutingLinks(TempLink, LinkCode) then
            exit(false);
        Config.Validate("Routing Link Code", LinkCode);
        exit(true);
    end;

    procedure LookupItemRoutingLink(ItemNo: Code[20]; LocationCode: Code[10]; VariantCode: Code[10]; RoutingDate: Date; var LinkCode: Code[10]): Boolean
    var
        TempLink: Record "Routing Link" temporary;
    begin
        GetAvailableItemRoutingLinks(ItemNo, LocationCode, VariantCode, RoutingDate, TempLink);
        if TempLink.IsEmpty() then
            Error('No routing link codes are available on the effective parent item/SKU routing for item %1, location %2, variant %3, date %4. Leave Routing Link Code blank, or maintain links on that routing.',
                ItemNo, LocationCode, VariantCode, RoutingDate);
        exit(LookupRoutingLinks(TempLink, LinkCode));
    end;

    local procedure LookupRoutingLinks(var TempLink: Record "Routing Link" temporary; var LinkCode: Code[10]): Boolean
    var
        Links: Page CF_ParentRoutingLinks;
    begin
        Links.SetLinks(TempLink);
        if TempLink.Get(LinkCode) then
            Links.SetRecord(TempLink);
        Links.LookupMode(true);
        if Links.RunModal() <> Action::LookupOK then
            exit(false);
        Links.GetRecord(TempLink);
        LinkCode := TempLink.Code;
        exit(true);
    end;

    procedure ValidateItemRoutingLink(ItemNo: Code[20]; LocationCode: Code[10]; VariantCode: Code[10]; RoutingDate: Date; LinkCode: Code[10])
    var
        TempLink: Record "Routing Link" temporary;
    begin
        if LinkCode = '' then
            exit;
        GetAvailableItemRoutingLinks(ItemNo, LocationCode, VariantCode, RoutingDate, TempLink);
        if not TempLink.Get(LinkCode) then
            Error('Routing link %1 is not assigned to the effective parent item/SKU routing for item %2, location %3, variant %4, date %5.',
                LinkCode, ItemNo, LocationCode, VariantCode, RoutingDate);
    end;

    procedure ValidateConfigRoutingLink(Config: Record CF_DocumentLineProductConfig)
    var
        SalesLine: Record "Sales Line";
    begin
        GetSource(Config, SalesLine);
        ValidateContext(SalesLine, Config);
        EnsureEditable(SalesLine);
        ValidateRoutingLink(SalesLine, Config."Routing Link Code", Config."Configuration Option");
    end;

    procedure GetPreviousSalesConfigurations(TargetSalesLine: Record "Sales Line"; var TempSalesLine: Record "Sales Line" temporary)
    var
        Config: Record CF_DocumentLineProductConfig;
        PreviousSalesLine: Record "Sales Line";
        SeenSources: Dictionary of [Guid, Boolean];
    begin
        ValidateSalesLine(TargetSalesLine);
        TempSalesLine.Reset();
        TempSalesLine.DeleteAll();
        Config.SetRange("Document Type", CF_ConfigDocumentType::SalesOrder);
        Config.SetRange("Source Table ID", Database::"Sales Line");
        Config.SetRange("Parent Item No.", TargetSalesLine."No.");
        Config.SetFilter("Source Line SystemId", '<>%1', TargetSalesLine.SystemId);
        if Config.FindSet() then
            repeat
                if not SeenSources.ContainsKey(Config."Source Line SystemId") then begin
                    SeenSources.Add(Config."Source Line SystemId", true);
                    if PreviousSalesLine.GetBySystemId(Config."Source Line SystemId") then
                        if (PreviousSalesLine."Document Type" = PreviousSalesLine."Document Type"::Order) and
                           (PreviousSalesLine.Type = PreviousSalesLine.Type::Item) and
                           (PreviousSalesLine."No." = TargetSalesLine."No.")
                        then begin
                            TempSalesLine := PreviousSalesLine;
                            TempSalesLine.Insert(false, true);
                        end;
                end;
            until Config.Next() = 0;
    end;

    procedure LookupPreviousConfiguration(TargetSalesLine: Record "Sales Line"; var TempConfig: Record CF_DocumentLineProductConfig temporary): Boolean
    var
        PreviousSalesLine: Record "Sales Line";
        CurrentSalesLine: Record "Sales Line";
        TempLoadedConfig: Record CF_DocumentLineProductConfig temporary;
        PreviousConfigurations: Page CF_PreviousSalesConfigs;
    begin
        ValidateSalesLine(TargetSalesLine);
        EnsureEditable(TargetSalesLine);
        if not CurrentSalesLine.GetBySystemId(TargetSalesLine.SystemId) then
            Error(SourceMissingErr);
        PreviousConfigurations.SetSalesLine(CurrentSalesLine);
        PreviousConfigurations.LookupMode(true);
        if PreviousConfigurations.RunModal() <> Action::LookupOK then
            exit(false);
        PreviousConfigurations.GetRecord(PreviousSalesLine);
        if not CurrentSalesLine.GetBySystemId(TargetSalesLine.SystemId) then
            Error(SourceMissingErr);
        ValidateSalesLine(TargetSalesLine);
        BuildPreviousConfiguration(CurrentSalesLine, PreviousSalesLine.SystemId, TempConfig, TempLoadedConfig);
        if not Confirm(LoadPreviousConfigurationQst, false, PreviousSalesLine."Document No.",
            PreviousSalesLine."Line No.", CurrentSalesLine."Document No.", CurrentSalesLine."Line No.")
        then
            exit(false);
        EnsureEditable(CurrentSalesLine);
        CopyTemporaryConfiguration(TempLoadedConfig, TempConfig);
        FilterSalesLine(CurrentSalesLine, TempConfig);
        TempConfig.SetCurrentKey("Document Type", "Source Table ID", "Source Line SystemId", "Display Order", "Configuration Option");
        TempConfig.FindFirst();
        exit(true);
    end;

    local procedure BuildPreviousConfiguration(TargetSalesLine: Record "Sales Line"; PreviousLineId: Guid; var TempCurrentConfig: Record CF_DocumentLineProductConfig temporary; var TempLoadedConfig: Record CF_DocumentLineProductConfig temporary)
    var
        PreviousSalesLine: Record "Sales Line";
        PreviousConfig: Record CF_DocumentLineProductConfig;
        OptionSetup: Record CF_ConfiguratorBOM;
    begin
        ValidateSalesLine(TargetSalesLine);
        EnsureEditable(TargetSalesLine);
        if not PreviousSalesLine.GetBySystemId(PreviousLineId) then
            Error(PreviousSourceMissingErr);
        ValidateSalesLine(PreviousSalesLine);
        if (PreviousLineId = TargetSalesLine.SystemId) or (PreviousSalesLine."No." <> TargetSalesLine."No.") then
            Error(PreviousItemMismatchErr, TargetSalesLine."No.");
        FilterSalesLine(PreviousSalesLine, PreviousConfig);
        if not PreviousConfig.FindSet() then
            Error(PreviousConfigurationMissingErr, PreviousSalesLine."Document No.", PreviousSalesLine."Line No.");

        CopyTemporaryConfiguration(TempCurrentConfig, TempLoadedConfig);
        if TempLoadedConfig.FindSet() then
            repeat
                TempLoadedConfig.Validate("Choice Code", '');
                if IsCurrentOption(TempLoadedConfig, OptionSetup) then begin
                    TempLoadedConfig."Option Description" := OptionSetup."Option Description";
                    TempLoadedConfig."Display Order" := OptionSetup."Display Order";
                    TempLoadedConfig."Routing Link Code" := OptionSetup."Routing Link Code";
                end;
                TempLoadedConfig.Modify();
            until TempLoadedConfig.Next() = 0;
        AddTemplateOptions(TargetSalesLine, TempLoadedConfig, false);
        repeat
            ValidateContext(PreviousSalesLine, PreviousConfig);
            if not TempLoadedConfig.Get(GetConfigDocumentType(TargetSalesLine), Database::"Sales Line",
                TargetSalesLine.SystemId, PreviousConfig."Configuration Option")
            then
                Error(PreviousOptionUnavailableErr, PreviousConfig."Configuration Option", TargetSalesLine."No.");
            if not IsCurrentOption(TempLoadedConfig, OptionSetup) then
                Error(PreviousOptionUnavailableErr, PreviousConfig."Configuration Option", TargetSalesLine."No.");
            TempLoadedConfig."Option Description" := OptionSetup."Option Description";
            TempLoadedConfig."Display Order" := OptionSetup."Display Order";
            TempLoadedConfig.Validate("Choice Code", PreviousConfig."Choice Code");
            if (TempLoadedConfig."Component Type" <> PreviousConfig."Component Type") or
               (TempLoadedConfig."Component Item No." <> PreviousConfig."Component Item No.") or
               (TempLoadedConfig."Component Variant Code" <> PreviousConfig."Component Variant Code") or
               (TempLoadedConfig."Component UOM Code" <> PreviousConfig."Component UOM Code")
            then
                Error(PreviousMappingChangedErr, PreviousConfig."Configuration Option", PreviousConfig."Choice Code");
            TempLoadedConfig.Validate("Quantity per Unit", PreviousConfig."Quantity per Unit");
            TempLoadedConfig.Validate("Routing Link Code", PreviousConfig."Routing Link Code");
            ValidateStoredRow(TempLoadedConfig);
            TempLoadedConfig.Modify();
        until PreviousConfig.Next() = 0;
    end;

    local procedure CopyTemporaryConfiguration(var TempSource: Record CF_DocumentLineProductConfig temporary; var TempTarget: Record CF_DocumentLineProductConfig temporary)
    var
        TempReader: Record CF_DocumentLineProductConfig temporary;
    begin
        TempReader.Copy(TempSource, true);
        TempReader.Reset();
        TempTarget.Reset();
        TempTarget.DeleteAll();
        if TempReader.FindSet() then
            repeat
                TempTarget := TempReader;
                TempTarget.Insert(false, true);
            until TempReader.Next() = 0;
    end;

    procedure Load(SalesLine: Record "Sales Line"; var TempConfig: Record CF_DocumentLineProductConfig temporary)
    var
        Config: Record CF_DocumentLineProductConfig;
        StoredSalesLine: Record "Sales Line";
        ApplyDefaults: Boolean;
    begin
        ValidateSalesLine(SalesLine);
        TempConfig.Reset();
        TempConfig.DeleteAll();
        FilterSalesLine(SalesLine, Config);
        ApplyDefaults := Config.IsEmpty();
        if Config.FindSet() then
            repeat
                GetSource(Config, StoredSalesLine);
                ValidateContext(StoredSalesLine, Config);
                TempConfig := Config;
                TempConfig.Insert(false, true);
            until Config.Next() = 0;
        AddTemplateOptions(SalesLine, TempConfig, ApplyDefaults);
        InitializeBase(SalesLine);
        StampBase(SalesLine, TempConfig);
    end;

    procedure RefreshTemplate(SalesLine: Record "Sales Line"; var TempConfig: Record CF_DocumentLineProductConfig temporary)
    var
        Config: Record CF_DocumentLineProductConfig;
    begin
        ValidateSalesLine(SalesLine);
        FilterSalesLine(SalesLine, Config);
        AddTemplateOptions(SalesLine, TempConfig, Config.IsEmpty());
        InitializeBase(SalesLine);
        StampBase(SalesLine, TempConfig);
    end;

    procedure CanMaintainTemplates(): Boolean
    var
        OptionSetup: Record CF_ConfiguratorBOM;
        Choice: Record CF_OptionChoiceLookup;
    begin
        exit(OptionSetup.WritePermission() and Choice.WritePermission());
    end;

    procedure OpenCategoryTemplate(CategoryCode: Code[20])
    var
        Template: Record CF_ConfigTemplate;
        Wizard: Page CF_NewConfigTemplate;
        Designer: Page CF_CategoryTemplateDesigner;
    begin
        if not CanMaintainTemplates() then
            Error('You need Product Configurator Setup permissions to maintain templates.');
        Template.SetRange("Template Type", Template."Template Type"::ItemCategory);
        Template.SetRange("Item Category Code", CategoryCode);
        if not Template.FindFirst() then begin
            Wizard.SetAssignment(CF_TemplateAssignment::ItemCategory, '', CategoryCode);
            if Wizard.RunModal() <> Action::OK then
                exit;
            Wizard.GetTemplate(Template);
            Commit();
        end;
        Designer.SetRecord(Template);
        Designer.RunModal();
    end;

    procedure OpenCategoryTemplate(CategoryCode: Code[20]; SalesLine: Record "Sales Line")
    var
        TemplateMgt: Codeunit CF_TemplateMgt;
    begin
        if not CanMaintainTemplates() then
            Error('You need Product Configurator Setup permissions to maintain templates.');
        ValidateSalesLine(SalesLine);
        TemplateMgt.OpenForSalesLine(SalesLine);
    end;

    local procedure AddTemplateOptions(SalesLine: Record "Sales Line"; var TempConfig: Record CF_DocumentLineProductConfig temporary; ApplyDefaults: Boolean)
    var
        OptionSetup: Record CF_ConfiguratorBOM;
        Item: Record Item;
        TemplateMgt: Codeunit CF_TemplateMgt;
        TemplateCode: Code[20];
    begin
        Item.Get(SalesLine."No.");
        TempConfig.Reset();
        TemplateCode := TemplateMgt.Resolve(SalesLine);
        if TemplateCode = '' then
            exit;
        OptionSetup.SetRange("Item Category Code", TemplateCode);
        OptionSetup.SetRange(Enabled, true);
        if OptionSetup.FindSet() then
            repeat
                if not TempConfig.Get(GetConfigDocumentType(SalesLine), Database::"Sales Line", SalesLine.SystemId, OptionSetup."Configuration Option") then begin
                    TempConfig.Init();
                    SetSource(SalesLine, TempConfig);
                    TempConfig."Item Category Code" := Item."Item Category Code";
                    TemplateMgt.Stamp(SalesLine, TempConfig);
                    TempConfig."Parent Item No." := SalesLine."No.";
                    TempConfig."Parent Variant Code" := SalesLine."Variant Code";
                    TempConfig."Configuration Option" := OptionSetup."Configuration Option";
                    TempConfig."Option Description" := OptionSetup."Option Description";
                    TempConfig."Routing Link Code" := OptionSetup."Routing Link Code";
                    TempConfig."Display Order" := OptionSetup."Display Order";
                    if ApplyDefaults and (OptionSetup."Default Choice Code" <> '') then
                        TempConfig.Validate("Choice Code", OptionSetup."Default Choice Code");
                    Clear(TempConfig.SystemId);
                    TempConfig.Insert();
                end;
            until OptionSetup.Next() = 0;
        FilterSalesLine(SalesLine, TempConfig);
        TempConfig.SetCurrentKey("Document Type", "Source Table ID", "Source Line SystemId", "Display Order", "Configuration Option");
    end;

    procedure Save(SalesLine: Record "Sales Line"; var TempConfig: Record CF_DocumentLineProductConfig temporary)
    var
        CurrentSalesLine: Record "Sales Line";
        Config: Record CF_DocumentLineProductConfig;
        Existing: Record CF_DocumentLineProductConfig;
        OptionSetup: Record CF_ConfiguratorBOM;
        DraftMgt: Codeunit CF_BOMDraftMgt;
        SelectionId: Guid;
    begin
        CurrentSalesLine.LockTable();
        if not CurrentSalesLine.GetBySystemId(SalesLine.SystemId) then
            Error('The source sales line no longer exists.');
        ValidateSalesLine(CurrentSalesLine);
        EnsureEditable(CurrentSalesLine);
        if SalesLine.CF_BaseSetupSet then begin
            CopyBase(SalesLine, CurrentSalesLine);
            ValidateBase(CurrentSalesLine);
            CurrentSalesLine.Modify(false);
            StampBase(CurrentSalesLine, TempConfig);
        end;
        DraftMgt.CheckChoices(CurrentSalesLine, TempConfig);
        Config.LockTable();
        TempConfig.Reset();
        if TempConfig.FindSet() then
            repeat
                ValidateContext(CurrentSalesLine, TempConfig);
                GetSource(TempConfig, SalesLine);
                if IsCurrentOption(TempConfig, OptionSetup) then
                    ValidateStoredRow(TempConfig)
                else
                    if TempConfig."Choice Code" <> '' then
                        Error('Option %1 is obsolete or disabled. Explicitly clear its choice before applying.', TempConfig."Configuration Option");
            until TempConfig.Next() = 0;
        ValidateMandatory(CurrentSalesLine, TempConfig);

        // Missing saved rows are an error, not an implicit deletion.
        FilterSalesLine(CurrentSalesLine, Config);
        if Config.FindSet() then
            repeat
                if not TempConfig.Get(Config."Document Type", Config."Source Table ID", Config."Source Line SystemId", Config."Configuration Option") then
                    Error('Saved option %1 is missing from the worksheet. Reopen Product Configurator.', Config."Configuration Option");
            until Config.Next() = 0;
        TempConfig.Reset();
        if TempConfig.FindSet() then
            repeat
                if Existing.Get(TempConfig."Document Type", TempConfig."Source Table ID", TempConfig."Source Line SystemId", TempConfig."Configuration Option") then begin
                    if IsCurrentOption(TempConfig, OptionSetup) then begin
                        SelectionId := Existing.SystemId;
                        Existing.TransferFields(TempConfig, false);
                        Existing.SystemId := SelectionId;
                        Existing.Modify(true);
                    end;
                end else
                    if IsCurrentOption(TempConfig, OptionSetup) then begin
                        Config := TempConfig;
                        Config.Insert(true, true);
                    end;
            until TempConfig.Next() = 0;
        // Save replacement options before removing obsolete rows so their header number survives.
        FilterSalesLine(CurrentSalesLine, Config);
        if Config.FindSet(true) then
            repeat
                if not IsCurrentOption(Config, OptionSetup) then
                    Config.Delete(true);
            until Config.Next() = 0;
    end;

    procedure OpenConfigurator(SalesLine: Record "Sales Line")
    var
        Configurator: Page CF_ProductConfigurator;
    begin
        ValidateSalesLine(SalesLine);
        Configurator.SetSalesLine(SalesLine);
        Configurator.RunModal();
    end;

    local procedure ValidateSalesLine(SalesLine: Record "Sales Line")
    var
        Persisted: Record "Sales Line";
    begin
        if not (SalesLine."Document Type" in [SalesLine."Document Type"::Order, SalesLine."Document Type"::Quote]) then
            Error('Product Configurator supports Sales Order and Sales Quote lines only.');
        if SalesLine.Type <> SalesLine.Type::Item then
            Error('Sales document %1, line %2 must be an Item line.', SalesLine."Document No.", SalesLine."Line No.");
        SalesLine.TestField("No.");
        if IsNullGuid(SalesLine.SystemId) or not Persisted.GetBySystemId(SalesLine.SystemId) then
            Error('Save the sales document item line before opening Product Configurator.');
        if (Persisted."Document Type" <> SalesLine."Document Type") or
           (Persisted."Document No." <> SalesLine."Document No.") or (Persisted."Line No." <> SalesLine."Line No.") or
           (Persisted.Type <> SalesLine.Type) or (Persisted."No." <> SalesLine."No.") or
           (Persisted."Variant Code" <> SalesLine."Variant Code")
        then
            Error('Sales document %1, line %2 changed. Save and reopen Product Configurator.', SalesLine."Document No.", SalesLine."Line No.");
    end;

    procedure GetConfigDocumentType(SalesLine: Record "Sales Line"): Enum CF_ConfigDocumentType
    begin
        case SalesLine."Document Type" of
            SalesLine."Document Type"::Order:
                exit(CF_ConfigDocumentType::SalesOrder);
            SalesLine."Document Type"::Quote:
                exit(CF_ConfigDocumentType::SalesQuote);
            else
                Error('Product Configurator supports Sales Order and Sales Quote lines only.');
        end;
    end;

    procedure GetSource(Config: Record CF_DocumentLineProductConfig; var SalesLine: Record "Sales Line")
    begin
        if not (Config."Document Type" in [CF_ConfigDocumentType::SalesOrder, CF_ConfigDocumentType::SalesQuote]) or (Config."Source Table ID" <> Database::"Sales Line") then
            Error('Only Sales Order and Sales Quote configuration with Sales Line as the source table is supported.');
        if IsNullGuid(Config."Source Line SystemId") or not SalesLine.GetBySystemId(Config."Source Line SystemId") then
            Error('The source sales line for document %1, line %2 no longer exists.', Config."Document No.", Config."Document Line No.");
        ValidateSalesLine(SalesLine);
        if Config."Document Type" <> GetConfigDocumentType(SalesLine) then
            Error('The configuration document type does not match its source sales line.');
        if (Config."Document No." <> SalesLine."Document No.") or (Config."Document Line No." <> SalesLine."Line No.") then
            Error('Configuration source identifiers do not match sales document %1, line %2.', SalesLine."Document No.", SalesLine."Line No.");
        if Config."Base Selection Set" and Config.IsTemporary() then begin
            SalesLine.CF_BaseBOMNo := Config."Base BOM";
            SalesLine.CF_BaseRoutingNo := Config."Base Routing";
            SalesLine.CF_BaseSetupSet := true;
        end;
    end;

    local procedure SetSource(SalesLine: Record "Sales Line"; var Config: Record CF_DocumentLineProductConfig)
    var
        Item: Record Item;
    begin
        Config."Document Type" := GetConfigDocumentType(SalesLine);
        Config."Source Table ID" := Database::"Sales Line";
        Config."Source Line SystemId" := SalesLine.SystemId;
        Config."Document No." := SalesLine."Document No.";
        Config."Document Line No." := SalesLine."Line No.";
        Item.Get(SalesLine."No.");
        Config."Parent Item No." := SalesLine."No.";
        Config."Parent Variant Code" := SalesLine."Variant Code";
        Config."Item Category Code" := Item."Item Category Code";
        Config."Base BOM" := SalesLine.CF_BaseBOMNo;
        Config."Base Routing" := SalesLine.CF_BaseRoutingNo;
        Config."Base Selection Set" := SalesLine.CF_BaseSetupSet;
    end;

    local procedure ValidateContext(SalesLine: Record "Sales Line"; Config: Record CF_DocumentLineProductConfig)
    var
        Item: Record Item;
        TemplateMgt: Codeunit CF_TemplateMgt;
    begin
        Item.Get(SalesLine."No.");
        if (Config."Document Type" <> GetConfigDocumentType(SalesLine)) or
           (Config."Source Table ID" <> Database::"Sales Line") or (Config."Source Line SystemId" <> SalesLine.SystemId) or
           (Config."Document No." <> SalesLine."Document No.") or (Config."Document Line No." <> SalesLine."Line No.") or
           (Config."Parent Item No." <> SalesLine."No.") or (Config."Parent Variant Code" <> SalesLine."Variant Code") or
           (Config."Item Category Code" <> Item."Item Category Code") or
           (Config.GetTemplateCode() <> TemplateMgt.Resolve(SalesLine)) or
           (Config."Template Assignment" <> TemplateMgt.AssignmentType(SalesLine))
        then
            Error('Sales document %1, line %2, option %3 has stale source, parent item, variant, or category context. Configuration must not be silently reused.',
                SalesLine."Document No.", SalesLine."Line No.", Config."Configuration Option");
    end;

    local procedure GetChoice(Config: Record CF_DocumentLineProductConfig; var Choice: Record CF_OptionChoiceLookup)
    var
        OptionSetup: Record CF_ConfiguratorBOM;
    begin
        if not IsCurrentOption(Config, OptionSetup) then
            Error('Option %1 in template %2 is missing or disabled.', Config."Configuration Option", Config.GetTemplateCode());
        if not Choice.Get(Config.GetTemplateCode(), Config."Configuration Option", Config."Choice Code") then
            Error('Sales document %1, line %2: choice %3 does not exist for template %4, option %5.',
                Config."Document No.", Config."Document Line No.", Config."Choice Code", Config.GetTemplateCode(), Config."Configuration Option");
        if not Choice.Selectable then
            Error('Sales document %1, line %2: choice %3 for option %4 is not selectable.',
                Config."Document No.", Config."Document Line No.", Config."Choice Code", Config."Configuration Option");
    end;

    local procedure IsCurrentOption(Config: Record CF_DocumentLineProductConfig; var OptionSetup: Record CF_ConfiguratorBOM): Boolean
    begin
        if not OptionSetup.Get(Config.GetTemplateCode(), Config."Configuration Option") then
            exit(false);
        exit(OptionSetup.Enabled);
    end;

    local procedure ValidateMandatory(SalesLine: Record "Sales Line"; var Config: Record CF_DocumentLineProductConfig)
    var
        Item: Record Item;
        OptionSetup: Record CF_ConfiguratorBOM;
        TemplateMgt: Codeunit CF_TemplateMgt;
        TemplateCode: Code[20];
    begin
        Item.Get(SalesLine."No.");
        TemplateCode := TemplateMgt.Resolve(SalesLine);
        if TemplateCode = '' then
            exit;
        OptionSetup.SetRange("Item Category Code", TemplateCode);
        OptionSetup.SetRange(Enabled, true);
        if OptionSetup.FindSet() then
            repeat
                if OptionSetup.RequiresChoice() then begin
                    if not Config.Get(GetConfigDocumentType(SalesLine), Database::"Sales Line", SalesLine.SystemId, OptionSetup."Configuration Option") then
                        Error('Sales document %1, line %2: mandatory option %3 requires a choice.', SalesLine."Document No.", SalesLine."Line No.", OptionSetup."Configuration Option");
                    if Config."Choice Code" = '' then
                        Error('Sales document %1, line %2: mandatory option %3 requires a choice.', SalesLine."Document No.", SalesLine."Line No.", OptionSetup."Configuration Option");
                    ValidateStoredRow(Config);
                end;
            until OptionSetup.Next() = 0;
    end;

    local procedure ValidateRoutingLink(SalesLine: Record "Sales Line"; LinkCode: Code[10]; OptionCode: Code[10])
    var
        RoutingLine: Record "Routing Line";
        Link: Record "Routing Link";
        RoutingNo: Code[20];
    begin
        if LinkCode = '' then
            exit;
        Link.Get(LinkCode);
        FilterParentRoutingLines(SalesLine, RoutingLine);
        RoutingNo := RoutingLine.GetRangeMin("Routing No.");
        if RoutingNo = '' then
            Error('Sales document %1, line %2, option %3: the parent item/SKU has no routing for link %4.',
                SalesLine."Document No.", SalesLine."Line No.", OptionCode, LinkCode);
        RoutingLine.SetRange("Routing Link Code", LinkCode);
        if RoutingLine.IsEmpty() then
            Error('Sales document %1, line %2, option %3: routing link %4 does not exist on the parent item/SKU routing %5, version %6. Select a link from Parent Routing Links, or clear it.',
                SalesLine."Document No.", SalesLine."Line No.", OptionCode, LinkCode, RoutingNo, RoutingLine.GetRangeMin("Version Code"));
    end;

    procedure GetRoutingOperations(SalesLine: Record "Sales Line"; LinkCode: Code[10]): Text
    var
        RoutingLine: Record "Routing Line";
        Operations: Text;
    begin
        if LinkCode = '' then
            exit('');
        FilterParentRoutingLines(SalesLine, RoutingLine);
        if RoutingLine.GetRangeMin("Routing No.") = '' then
            exit('');
        RoutingLine.SetCurrentKey("Routing No.", "Version Code", "Operation No.");
        RoutingLine.SetRange("Routing Link Code", LinkCode);
        if RoutingLine.FindSet() then
            repeat
                if Operations <> '' then
                    Operations += '; ';
                Operations += RoutingLine."Operation No.";
                if RoutingLine.Description <> '' then
                    Operations += ' - ' + RoutingLine.Description;
            until RoutingLine.Next() = 0;
        exit(Operations);
    end;

    procedure FilterParentRoutingLines(SalesLine: Record "Sales Line"; var RoutingLine: Record "Routing Line")
    var
        RoutingNo: Code[20];
    begin
        ValidateSalesLine(SalesLine);
        if SalesLine.CF_BaseSetupSet then begin
            RoutingNo := SalesLine.CF_BaseRoutingNo;
            FilterRoutingLines(RoutingNo, SalesLine."Shipment Date", RoutingLine);
        end else
            FilterItemRoutingLines(SalesLine."No.", SalesLine."Location Code", SalesLine."Variant Code", SalesLine."Shipment Date", RoutingLine);
    end;

    local procedure FilterItemRoutingLines(ItemNo: Code[20]; LocationCode: Code[10]; VariantCode: Code[10]; RoutingDate: Date; var RoutingLine: Record "Routing Line")
    var
        BOMNo: Code[20];
        RoutingNo: Code[20];
    begin
        GetItemManufacturingSetup(ItemNo, LocationCode, VariantCode, BOMNo, RoutingNo);
        FilterRoutingLines(RoutingNo, RoutingDate, RoutingLine);
    end;

    local procedure FilterRoutingLines(RoutingNo: Code[20]; RoutingDate: Date; var RoutingLine: Record "Routing Line")
    var
        RoutingHeader: Record "Routing Header";
        VersionMgt: Codeunit VersionManagement;
        VersionCode: Code[20];
    begin
        if RoutingNo <> '' then begin
            VersionCode := VersionMgt.GetRtngVersion(RoutingNo, RoutingDate, true);
            if VersionCode = '' then begin
                RoutingHeader.Get(RoutingNo);
                RoutingHeader.TestField(Status, RoutingHeader.Status::Certified);
            end;
        end;
        RoutingLine.Reset();
        RoutingLine.SetRange("Routing No.", RoutingNo);
        RoutingLine.SetRange("Version Code", VersionCode);
    end;

    local procedure GetItemManufacturingSetup(ItemNo: Code[20]; LocationCode: Code[10]; VariantCode: Code[10]; var BOMNo: Code[20]; var RoutingNo: Code[20])
    var
        Item: Record Item;
        SKU: Record "Stockkeeping Unit";
        Variant: Record "Item Variant";
    begin
        Item.Get(ItemNo);
        if VariantCode <> '' then
            Variant.Get(ItemNo, VariantCode);
        BOMNo := Item."Production BOM No.";
        RoutingNo := Item."Routing No.";
        // Standard line initialization applies the blank-variant SKU before validating the final variant.
        if SKU.Get(LocationCode, ItemNo, '') then begin
            if SKU."Production BOM No." <> '' then
                BOMNo := SKU."Production BOM No.";
            if SKU."Routing No." <> '' then
                RoutingNo := SKU."Routing No.";
        end;
        if VariantCode <> '' then
            if SKU.Get(LocationCode, ItemNo, VariantCode) then begin
                if SKU."Production BOM No." <> '' then
                    BOMNo := SKU."Production BOM No.";
                if SKU."Routing No." <> '' then
                    RoutingNo := SKU."Routing No.";
            end else begin
                BOMNo := Item."Production BOM No.";
                RoutingNo := Item."Routing No.";
            end;
    end;

    var
        NoParentBOMErr: Label 'Sales document %1, line %2: parent item/SKU %3 has no production BOM to preview.', Comment = '%1 = document number, %2 = line number, %3 = parent item number';
        PositiveBOMUOMErr: Label 'must be positive';
        NoLinkedOrderErr: Label 'Sales order %1, line %2 has no linked production order.', Comment = '%1 = sales order number, %2 = line number';
        UnsupportedOrderStatusErr: Label 'Production order status %1 has no supported navigation page.', Comment = '%1 = production order status';
        SourceMissingErr: Label 'The source sales line no longer exists.';
        NoProductionDemandErr: Label 'Sales order %1, line %2 has no outstanding unreserved quantity to produce.', Comment = '%1 = sales order number, %2 = line number';
        ProductionEligibilityErr: Label 'Item %1, variant %2, location %3 is not eligible for production-order replenishment or is blocked for production. Check the item and stockkeeping unit setup.', Comment = '%1 = item, %2 = variant, %3 = location';
        OpenLinkedOrderQst: Label 'Sales order %1, line %2 is linked to production order %3 (%4). Delete its linked production orders before deleting the configuration. Do you want to open the linked production orders?', Comment = '%1 = sales order number, %2 = line number, %3 = production order number, %4 = status';
        NoSavedConfigMsg: Label 'There is no saved configuration to delete. Use Cancel to discard unsaved choices.';
        DeleteConfigurationQst: Label 'Delete all saved product configuration choices for sales document %1, line %2? This does not delete the sales line.', Comment = '%1 = sales document number, %2 = line number';
        DeleteProductionOrderQst: Label 'Linked sales order line product configuration exists for sales order %1, line %2. Do you still want to delete production order %3 (%4)? Standard Business Central deletion validations still apply.', Comment = '%1 = sales order number, %2 = line number, %3 = production order number, %4 = status';
        OpenProductionConfigurationQst: Label 'Deletion was canceled. Do you want to open the linked product configuration?';
        LoadPreviousConfigurationQst: Label 'Replace the current temporary selections with the saved configuration from sales order %1, line %2, for sales document %3, line %4? Nothing is saved until Apply Configuration.', Comment = '%1 = previous order, %2 = previous line, %3 = current document, %4 = current line';
        PreviousSourceMissingErr: Label 'The selected previous sales line no longer exists. Reopen Load Previous Sales Configuration.';
        PreviousItemMismatchErr: Label 'Select another saved sales configuration for the same parent item %1.', Comment = '%1 = current parent item';
        PreviousConfigurationMissingErr: Label 'Sales order %1, line %2 no longer has a saved configuration.', Comment = '%1 = previous order, %2 = previous line';
        PreviousOptionUnavailableErr: Label 'Previous option %1 is not enabled in the current template for item %2. The previous configuration cannot be loaded.', Comment = '%1 = option, %2 = current parent item';
        PreviousMappingChangedErr: Label 'The saved component item, variant, or UOM mapping for option %1, choice %2 has changed. The previous configuration cannot be loaded without explicitly correcting its choices.', Comment = '%1 = option, %2 = choice';

    [EventSubscriber(ObjectType::Table, Database::CF_DocumentLineProductConfig, 'OnBeforeInsertEvent', '', false, false)]
    local procedure GuardConfigInsert(var Rec: Record CF_DocumentLineProductConfig; RunTrigger: Boolean)
    var
        HeaderMgt: Codeunit CF_ConfigHeaderMgt;
    begin
        if Rec.IsTemporary() then
            exit;
        EnsureConfigEditable(Rec);
        ValidateStoredRow(Rec);
        HeaderMgt.EnsureHeader(Rec);
    end;

    [EventSubscriber(ObjectType::Table, Database::CF_DocumentLineProductConfig, 'OnBeforeModifyEvent', '', false, false)]
    local procedure GuardConfigModify(var Rec: Record CF_DocumentLineProductConfig; var xRec: Record CF_DocumentLineProductConfig; RunTrigger: Boolean)
    var
        SalesLine: Record "Sales Line";
        HeaderMgt: Codeunit CF_ConfigHeaderMgt;
    begin
        if Rec.IsTemporary() then
            exit;
        if not (xRec."Document Type" in [CF_ConfigDocumentType::SalesOrder, CF_ConfigDocumentType::SalesQuote]) or (xRec."Source Table ID" <> Database::"Sales Line") then
            Error('Only Sales Order and Sales Quote configuration with Sales Line as the source table is supported.');
        if not SalesLine.GetBySystemId(xRec."Source Line SystemId") then
            Error('The original configuration source sales line no longer exists.');
        EnsureEditable(SalesLine);
        EnsureConfigEditable(Rec);
        ValidateStoredRow(Rec);
        HeaderMgt.EnsureHeader(Rec);
    end;

    [EventSubscriber(ObjectType::Table, Database::CF_DocumentLineProductConfig, 'OnAfterDeleteEvent', '', false, false)]
    local procedure CleanupConfigHeader(var Rec: Record CF_DocumentLineProductConfig; RunTrigger: Boolean)
    var
        HeaderMgt: Codeunit CF_ConfigHeaderMgt;
        DraftMgt: Codeunit CF_BOMDraftMgt;
    begin
        if not Rec.IsTemporary() and not DraftMgt.HasSaved(Rec."Source Line SystemId") then
            HeaderMgt.RemoveEmptyHeader(Rec);
    end;

    [EventSubscriber(ObjectType::Table, Database::CF_DocumentLineProductConfig, 'OnBeforeDeleteEvent', '', false, false)]
    local procedure GuardConfigDelete(var Rec: Record CF_DocumentLineProductConfig; RunTrigger: Boolean)
    var
        SalesLine: Record "Sales Line";
    begin
        if Rec.IsTemporary() then
            exit;
        if not (Rec."Document Type" in [CF_ConfigDocumentType::SalesOrder, CF_ConfigDocumentType::SalesQuote]) or (Rec."Source Table ID" <> Database::"Sales Line") then
            Error('Only Sales Order and Sales Quote configuration with Sales Line as the source table is supported.');
        if SalesLine.GetBySystemId(Rec."Source Line SystemId") then
            EnsureEditable(SalesLine);
    end;

    [EventSubscriber(ObjectType::Table, Database::CF_DocumentLineProductConfig, 'OnBeforeRenameEvent', '', false, false)]
    local procedure GuardConfigRename(var Rec: Record CF_DocumentLineProductConfig; var xRec: Record CF_DocumentLineProductConfig; RunTrigger: Boolean)
    begin
        if not Rec.IsTemporary() then
            Error('Configuration identity cannot be renamed.');
    end;

    [EventSubscriber(ObjectType::Table, Database::"Sales Line", 'OnBeforeModifyEvent', '', false, false)]
    local procedure GuardSalesLineChange(var Rec: Record "Sales Line"; var xRec: Record "Sales Line"; RunTrigger: Boolean)
    var
        Config: Record CF_DocumentLineProductConfig;
        DraftMgt: Codeunit CF_BOMDraftMgt;
    begin
        if Rec.IsTemporary() then
            exit;
        if Rec.CF_ProductConfigurationNo <> xRec.CF_ProductConfigurationNo then
            ValidateSalesLineNumber(Rec);
        if not (xRec."Document Type" in [xRec."Document Type"::Order, xRec."Document Type"::Quote]) then
            exit;
        if (Rec.CF_BaseBOMNo <> xRec.CF_BaseBOMNo) or (Rec.CF_BaseRoutingNo <> xRec.CF_BaseRoutingNo) or
           (Rec.CF_BaseSetupSet <> xRec.CF_BaseSetupSet)
        then
            EnsureEditable(xRec);
        if (Rec.Type = xRec.Type) and (Rec."No." = xRec."No.") and
           (Rec."Variant Code" = xRec."Variant Code") and (Rec."Item Category Code" = xRec."Item Category Code") and
           (Rec."Location Code" = xRec."Location Code") and (Rec."Unit of Measure Code" = xRec."Unit of Measure Code") and
           (Rec."Document Type" = xRec."Document Type")
        then
            exit;
        EnsureEditable(xRec);
        FilterSalesLine(xRec, Config);
        if not Config.IsEmpty() or DraftMgt.HasSaved(xRec.SystemId) then
            Error('Sales document %1, line %2 has saved configuration. Its item, type, variant, category, location, UOM, and document type cannot be changed. Delete its saved configuration first to configure a different parent.',
                xRec."Document No.", xRec."Line No.");
    end;

    [EventSubscriber(ObjectType::Table, Database::"Sales Line", 'OnAfterDeleteEvent', '', false, false)]
    local procedure CleanupSalesLine(var Rec: Record "Sales Line"; RunTrigger: Boolean)
    var
        Config: Record CF_DocumentLineProductConfig;
        DraftMgt: Codeunit CF_BOMDraftMgt;
    begin
        if Rec.IsTemporary() then
            exit;
        if not (Rec."Document Type" in [Rec."Document Type"::Order, Rec."Document Type"::Quote]) then
            exit;
        FilterSalesLine(Rec, Config);
        // Posting deletes source lines; the production snapshot is independent.
        Config.DeleteAll(false);
        DraftMgt.DeleteSaved(Rec.SystemId);
    end;

    [EventSubscriber(ObjectType::Table, Database::"Sales Line", 'OnBeforeRenameEvent', '', false, false)]
    local procedure GuardSalesLineRename(var Rec: Record "Sales Line"; var xRec: Record "Sales Line"; RunTrigger: Boolean)
    begin
        if Rec.IsTemporary() then
            exit;
        if Rec."Document Type" <> xRec."Document Type" then
            Error('A configured sales line cannot be renamed to a different document type.');
        EnsureEditable(xRec);
    end;

    [EventSubscriber(ObjectType::Table, Database::"Sales Line", 'OnAfterRenameEvent', '', false, false)]
    local procedure SyncSalesLineRename(var Rec: Record "Sales Line"; var xRec: Record "Sales Line"; RunTrigger: Boolean)
    var
        Config: Record CF_DocumentLineProductConfig;
        DraftMgt: Codeunit CF_BOMDraftMgt;
        HeaderMgt: Codeunit CF_ConfigHeaderMgt;
        TemplateMgt: Codeunit CF_TemplateMgt;
    begin
        if Rec.IsTemporary() then
            exit;
        if not (Rec."Document Type" in [Rec."Document Type"::Order, Rec."Document Type"::Quote]) then
            exit;
        FilterSalesLine(Rec, Config);
        if Config.FindSet(true) then
            repeat
                SetSource(Rec, Config);
                Config.Modify(false);
            until Config.Next() = 0;
        if DraftMgt.HasSaved(Rec.SystemId) then begin
            SetSource(Rec, Config);
            TemplateMgt.Stamp(Rec, Config);
            HeaderMgt.EnsureHeader(Config);
        end;
    end;

    [EventSubscriber(ObjectType::Table, Database::Item, 'OnBeforeModifyEvent', '', false, false)]
    local procedure GuardItemCategory(var Rec: Record Item; var xRec: Record Item; RunTrigger: Boolean)
    var
        Config: Record CF_DocumentLineProductConfig;
        ProductionOrder: Record "Production Order";
        Header: Record CF_ProductConfigHeader;
        DraftMgt: Codeunit CF_BOMDraftMgt;
    begin
        if Rec.IsTemporary() or (Rec."Item Category Code" = xRec."Item Category Code") then
            exit;
        ProductionOrder.SetRange(CF_SourceTableId, Database::"Sales Line");
        ProductionOrder.SetRange(CF_ParentItemNo, Rec."No.");
        ProductionOrder.SetFilter(CF_ConfigVersion, '>0');
        if ProductionOrder.FindFirst() then
            Error('Item %1 has linked configured production order %2. Its category cannot be changed.', Rec."No.", ProductionOrder."No.");
        Config.SetFilter("Document Type", '%1|%2', CF_ConfigDocumentType::SalesOrder, CF_ConfigDocumentType::SalesQuote);
        Config.SetRange("Source Table ID", Database::"Sales Line");
        Config.SetRange("Parent Item No.", Rec."No.");
        if Config.FindFirst() then
            Error('Item %1 has saved configuration on sales order %2, line %3. Its category cannot be changed while these selections exist.',
                Rec."No.", Config."Document No.", Config."Document Line No.");
        Header.SetRange("Parent Item No.", Rec."No.");
        if Header.FindSet() then
            repeat
                if DraftMgt.HasSaved(Header."Source Line SystemId") then
                    Error('Item %1 has a saved BOM structure on configuration %2. Delete its configuration before changing the item category.', Rec."No.", Header."No.");
            until Header.Next() = 0;
    end;

    [EventSubscriber(ObjectType::Table, Database::"Sales Line", 'OnBeforeInsertEvent', '', false, false)]
    local procedure ClearCopiedSalesLineNumber(var Rec: Record "Sales Line"; RunTrigger: Boolean)
    begin
        if not Rec.IsTemporary() then begin
            Clear(Rec.CF_ProductConfigurationNo);
            Clear(Rec.CF_BaseBOMNo);
            Clear(Rec.CF_BaseRoutingNo);
            Rec.CF_BaseSetupSet := false;
        end;
    end;

    local procedure ValidateSalesLineNumber(SalesLine: Record "Sales Line")
    var
        Header: Record CF_ProductConfigHeader;
        ExpectedNumber: Code[100];
    begin
        if SalesLine."Document Type" in [SalesLine."Document Type"::Order, SalesLine."Document Type"::Quote] then begin
            Header.SetRange("Document Type", GetConfigDocumentType(SalesLine));
            Header.SetRange("Source Table ID", Database::"Sales Line");
            Header.SetRange("Source Line SystemId", SalesLine.SystemId);
            if Header.FindFirst() then
                ExpectedNumber := Header."No.";
        end;
        if SalesLine.CF_ProductConfigurationNo <> ExpectedNumber then
            Error('Product Configuration No. must match the saved configuration header for this sales line. Apply or delete configuration through Product Configurator.');
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Quote to Order", 'OnAfterInsertSalesOrderLine', '', false, false)]
    local procedure TransferQuoteConfiguration(var SalesOrderLine: Record "Sales Line"; SalesOrderHeader: Record "Sales Header"; SalesQuoteLine: Record "Sales Line"; SalesQuoteHeader: Record "Sales Header")
    var
        QuoteConfig: Record CF_DocumentLineProductConfig;
        TempOrderConfig: Record CF_DocumentLineProductConfig temporary;
        ExistingOrderConfig: Record CF_DocumentLineProductConfig;
        HeaderMgt: Codeunit CF_ConfigHeaderMgt;
        DraftMgt: Codeunit CF_BOMDraftMgt;
        TemplateMgt: Codeunit CF_TemplateMgt;
    begin
        if SalesQuoteLine.IsTemporary() or SalesOrderLine.IsTemporary() then
            exit;
        FilterSalesLine(SalesQuoteLine, QuoteConfig);
        if not QuoteConfig.FindSet(true) then begin
            if DraftMgt.HasSaved(SalesQuoteLine.SystemId) then begin
                ValidateSalesLine(SalesQuoteLine);
                ValidateSalesLine(SalesOrderLine);
                CopyBase(SalesQuoteLine, SalesOrderLine);
                SalesOrderLine.Modify(false);
                SetSource(SalesOrderLine, TempOrderConfig);
                TemplateMgt.Stamp(SalesQuoteLine, TempOrderConfig);
                HeaderMgt.MoveQuoteHeader(SalesQuoteLine, SalesOrderLine, TempOrderConfig);
                ValidateMandatory(SalesOrderLine, TempOrderConfig);
                DraftMgt.MoveSaved(SalesQuoteLine.SystemId, SalesOrderLine.SystemId);
                SalesOrderLine.GetBySystemId(SalesOrderLine.SystemId);
                exit;
            end;
            if SalesQuoteLine.CF_ProductConfigurationNo <> '' then
                Error('The quote line has a configuration number but no saved choices. Correct its configuration before Make Order.');
            exit;
        end;
        ValidateSalesLine(SalesQuoteLine);
        ValidateSalesLine(SalesOrderLine);
        FilterSalesLine(SalesOrderLine, ExistingOrderConfig);
        if not ExistingOrderConfig.IsEmpty() then
            Error('The new sales order line already has configuration. Quote configuration cannot overwrite it.');
        CopyBase(SalesQuoteLine, SalesOrderLine);
        SalesOrderLine.Modify(false);
        repeat
            ValidateStoredRow(QuoteConfig);
            TempOrderConfig := QuoteConfig;
            SetSource(SalesOrderLine, TempOrderConfig);
            TempOrderConfig.Insert(false, true);
        until QuoteConfig.Next() = 0;
        TempOrderConfig.FindFirst();
        HeaderMgt.MoveQuoteHeader(SalesQuoteLine, SalesOrderLine, TempOrderConfig);
        ValidateMandatory(SalesOrderLine, TempOrderConfig);
        // Remove old rows before inserting their preserved selection SystemIds on the order.
        QuoteConfig.DeleteAll(true);
        Save(SalesOrderLine, TempOrderConfig);
        DraftMgt.MoveSaved(SalesQuoteLine.SystemId, SalesOrderLine.SystemId);
        SalesOrderLine.GetBySystemId(SalesOrderLine.SystemId);
    end;
}
