namespace CloudFactory.SalesConfigurator;

using Microsoft.Manufacturing.Document;
using Microsoft.Manufacturing.ProductionBOM;

codeunit 91008 CF_ConfigBOMMgt
{
    EventSubscriberInstance = Manual;

    procedure SetSelection(Config: Record CF_DocumentLineProductConfig)
    begin
        Selection := Config;
    end;

    procedure Explode(RootLine: Record "Prod. Order Line")
    begin
        SourceRoot := RootLine;
        SourceRoot.TestField("Production BOM No.");
        Active := true;
        // Initialize the native engine with the real parent context, replacing only its BOM transfer.
        if not NativeCalculation.Calculate(RootLine, 1, false, true, false, false) then
            Error(CalculationErr, RootLine."Prod. Order No.", Selection."Configuration Option");
        Active := false;
    end;

    local procedure IsSource(ProdOrderLine: Record "Prod. Order Line"): Boolean
    begin
        exit(Active and (ProdOrderLine.Status = SourceRoot.Status) and
            (ProdOrderLine."Prod. Order No." = SourceRoot."Prod. Order No.") and
            (ProdOrderLine."Line No." = SourceRoot."Line No."));
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Calculate Prod. Order", 'OnBeforeTransferBOM', '', false, false)]
    local procedure TransferSelectedBOM(var ProdOrder: Record "Production Order"; var ProdOrderLine: Record "Prod. Order Line"; ProdBOMNo: Code[20]; Level: Integer; LineQtyPerUOM: Decimal; ItemQtyPerUOM: Decimal; Blocked: Boolean; var ErrorOccured: Boolean; var IsHandled: Boolean)
    var
        VersionMgt: Codeunit VersionManagement;
        VersionCode: Code[20];
    begin
        if not IsSource(ProdOrderLine) or (Level <> 1) then
            exit;
        if IsHandled then
            Error(TransferHandledErr);
        SourceRoot := ProdOrderLine;
        VersionCode := VersionMgt.GetBOMVersion(Selection."Component Item No.", SourceRoot."Starting Date", true);
        Selection.TestField("Component UOM Code", VersionMgt.GetBOMUnitOfMeasure(Selection."Component Item No.", VersionCode));
        IsHandled := true;
        // Level 2 uses native phantom-BOM date/version, formula, scrap, and recursion handling.
        if not NativeCalculation.TransferBOM(Selection."Component Item No.", 2,
            Selection."Quantity per Unit" * SourceRoot."Qty. per Unit of Measure", 1)
        then
            ErrorOccured := true;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Calculate Prod. Order", 'OnAfterProdOrderCompFilter', '', false, false)]
    local procedure KeepSelectionSeparate(var ProdOrderComp: Record "Prod. Order Component"; ProdBOMLine: Record "Production BOM Line")
    begin
        if not Active or (ProdOrderComp.Status <> SourceRoot.Status) or
           (ProdOrderComp."Prod. Order No." <> SourceRoot."Prod. Order No.")
        then
            exit;
        ProdOrderComp.SetRange(CF_ConfigSelectionId, Selection.SystemId);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Calculate Prod. Order", 'OnBeforeTransferBOMComponent', '', false, false)]
    local procedure ApplySelectedRouting(ProdOrder: Record "Production Order"; ProdOrderLine: Record "Prod. Order Line"; var ProdBOMLine: Record "Production BOM Line"; var ErrorOccured: Boolean; var IsHandled: Boolean; Level: Integer)
    begin
        if IsSource(ProdOrderLine) and (ProdBOMLine.Type = ProdBOMLine.Type::Item) and
           (ProdBOMLine."Routing Link Code" = '')
        then
            ProdBOMLine."Routing Link Code" := Selection."Routing Link Code";
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Calculate Prod. Order", 'OnAfterTransferBOMComponent', '', false, false)]
    local procedure MarkConfiguredLeaf(var ProdOrderLine: Record "Prod. Order Line"; var ProductionBOMLine: Record "Production BOM Line"; var ProdOrderComponent: Record "Prod. Order Component"; LineQtyPerUOM: Decimal; ItemQtyPerUOM: Decimal)
    begin
        if not IsSource(ProdOrderLine) then
            exit;
        ProdOrderComponent.CF_ConfiguredComponent := true;
        ProdOrderComponent.CF_ConfigSelectionId := Selection.SystemId;
        ProdOrderComponent.CF_ConfigOption := Selection."Configuration Option";
        ProdOrderComponent.CF_ProductionBOMChoice := true;
    end;

    var
        Selection: Record CF_DocumentLineProductConfig;
        SourceRoot: Record "Prod. Order Line";
        NativeCalculation: Codeunit "Calculate Prod. Order";
        Active: Boolean;
        CalculationErr: Label 'Production order %1, option %2: native BOM calculation failed.', Comment = '%1 = production order number, %2 = configuration option';
        TransferHandledErr: Label 'Another extension has handled BOM transfer during configured BOM calculation. The configured BOM cannot be calculated safely.';
}
