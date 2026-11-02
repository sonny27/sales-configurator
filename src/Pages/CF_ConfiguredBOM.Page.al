namespace CloudFactory.SalesConfigurator;

using Microsoft.Sales.Document;
using Microsoft.Inventory.Item;
using Microsoft.Manufacturing.ProductionBOM;

page 91010 CF_ConfiguredBOM
{
    Caption = 'New Configured BOM';
    PageType = Worksheet;
    SourceTable = CF_ConfiguredBOMLine;
    SourceTableTemporary = true;
    ApplicationArea = All;
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            group(Source)
            {
                Caption = 'Sales Document BOM Preview';
                field(DocumentType; SalesLine."Document Type") { ApplicationArea = All; Caption = 'Document Type'; ToolTip = 'Specifies the source sales document type.'; }
                field(DocumentNo; SalesLine."Document No.") { ApplicationArea = All; Caption = 'Document No.'; ToolTip = 'Specifies the source sales document number.'; }
                field(DocumentLineNo; SalesLine."Line No.") { ApplicationArea = All; Caption = 'Line No.'; ToolTip = 'Specifies the source sales line.'; }
                field(ParentItemNo; SalesLine."No.") { ApplicationArea = All; Caption = 'Parent Item No.'; ToolTip = 'Specifies the finished item whose BOM is previewed.'; }
                field(ParentVariantCode; SalesLine."Variant Code") { ApplicationArea = All; Caption = 'Parent Variant Code'; ToolTip = 'Specifies the variant used to resolve the parent stockkeeping unit.'; }
                field(LocationCode; SalesLine."Location Code") { ApplicationArea = All; Caption = 'Location Code'; ToolTip = 'Specifies the location used to resolve the parent stockkeeping unit.'; }
                field(ShipmentDate; SalesLine."Shipment Date") { ApplicationArea = All; Caption = 'Shipment Date'; ToolTip = 'Specifies the date used to select the certified BOM version and effective BOM lines.'; }
                field(ProductionBOMNo; ProductionBOMNo) { ApplicationArea = All; Caption = 'Production BOM No.'; ToolTip = 'Specifies the effective production BOM from the parent item or stockkeeping unit.'; }
                field(VersionCode; VersionCode) { ApplicationArea = All; Caption = 'Version Code'; ToolTip = 'Specifies the certified BOM version for the shipment date. Blank means the certified base BOM.'; }
                field(ParentUOMCode; ParentUOMCode) { ApplicationArea = All; Caption = 'Parent BOM Unit of Measure'; ToolTip = 'Specifies the root BOM unit used for top-level quantities. Child rows use their immediate parent BOM unit shown on the line.'; }
                field(PreviewMessage; PreviewMessage) { ApplicationArea = All; ShowCaption = false; ToolTip = 'Explains the preview scope. It never writes a master BOM or creates a production order.'; }
            }
            repeater(Lines)
            {
                IndentationColumn = Rec.Indentation;
                IndentationControls = No;
                ShowAsTree = true;
                TreeInitialState = ExpandAll;
                field(Configured; Rec.Configured) { ApplicationArea = All; ToolTip = 'Specifies whether this line is an added configuration component rather than an existing master BOM line.'; }
                field(Type; Rec.Type) { ApplicationArea = All; ToolTip = 'Specifies the standard BOM line type. Expand Production BOM rows to view their nested components.'; }
                field(No; Rec."No.")
                {
                    ApplicationArea = All;
                    DrillDown = true;
                    ToolTip = 'Specifies the item or nested production BOM number. Select the number to open its Item Card or Production BOM card.';
                    trigger OnDrillDown()
                    var
                        Item: Record Item;
                        BOMHeader: Record "Production BOM Header";
                    begin
                        if Rec."No." = '' then
                            exit;
                        case Rec.Type of
                            Rec.Type::Item:
                                begin
                                    Item.Get(Rec."No.");
                                    Page.RunModal(Page::"Item Card", Item);
                                end;
                            Rec.Type::"Production BOM":
                                begin
                                    BOMHeader.Get(Rec."No.");
                                    Page.RunModal(Page::"Production BOM", BOMHeader);
                                end;
                        end;
                    end;
                }
                field(Description; Rec.Description) { ApplicationArea = All; ToolTip = 'Specifies the BOM line or configured component description.'; }
                field(VariantCode; Rec."Variant Code") { ApplicationArea = All; ToolTip = 'Specifies the component variant.'; }
                field(QuantityPer; Rec."Quantity per") { ApplicationArea = All; Caption = 'Quantity per Parent'; ToolTip = 'Specifies quantity in the component UOM per immediate parent BOM unit, not cumulative demand. Master BOM formulas and fixed quantities retain their standard meaning.'; }
                field(UOMCode; Rec."Unit of Measure Code") { ApplicationArea = All; ToolTip = 'Specifies the component unit of measure.'; }
                field(LineParentUOM; Rec."Parent BOM Unit of Measure") { ApplicationArea = All; ToolTip = 'Specifies the immediate parent BOM unit for this row''s Quantity per Parent. It can differ from the root BOM unit.'; }
                field(Level; Rec.Indentation) { ApplicationArea = All; Visible = false; ToolTip = 'Specifies the nesting level, starting at zero for root BOM lines and configured additions.'; }
                field(ScrapPercent; Rec."Scrap %") { ApplicationArea = All; ToolTip = 'Specifies scrap from the source BOM line. Direct configured additions have no extra scrap; their nested BOM components retain native scrap values.'; }
                field(RoutingLinkCode; Rec."Routing Link Code") { ApplicationArea = All; ToolTip = 'Specifies the base BOM or selected configuration routing link.'; }
                field(ConfigurationOption; Rec."Configuration Option") { ApplicationArea = All; ToolTip = 'Specifies the option that added this configured component.'; }
                field(ChoiceCode; Rec."Choice Code") { ApplicationArea = All; ToolTip = 'Specifies the selected choice that added this configured component.'; }
                field(CalculationFormula; Rec."Calculation Formula") { ApplicationArea = All; Visible = false; ToolTip = 'Specifies the unchanged calculation formula from the master BOM.'; }
                field(Length; Rec.Length) { ApplicationArea = All; Visible = false; ToolTip = 'Specifies the BOM formula length.'; }
                field(Width; Rec.Width) { ApplicationArea = All; Visible = false; ToolTip = 'Specifies the BOM formula width.'; }
                field(Depth; Rec.Depth) { ApplicationArea = All; Visible = false; ToolTip = 'Specifies the BOM formula depth.'; }
                field(Weight; Rec.Weight) { ApplicationArea = All; Visible = false; ToolTip = 'Specifies the BOM formula weight.'; }
                field(StartingDate; Rec."Starting Date") { ApplicationArea = All; Visible = false; ToolTip = 'Specifies the original BOM line starting date.'; }
                field(EndingDate; Rec."Ending Date") { ApplicationArea = All; Visible = false; ToolTip = 'Specifies the original BOM line ending date.'; }
                field(Position; Rec.Position) { ApplicationArea = All; Visible = false; ToolTip = 'Specifies the original BOM component position.'; }
                field(LeadTimeOffset; Rec."Lead-Time Offset") { ApplicationArea = All; Visible = false; ToolTip = 'Specifies the original BOM lead-time offset.'; }
            }
        }
    }

    procedure SetPreview(var TempBOMLine: Record CF_ConfiguredBOMLine temporary; SourceSalesLine: Record "Sales Line"; BOMNo: Code[20]; BOMVersion: Code[20]; BOMUOM: Code[10]; IncludesUnsavedChoices: Boolean)
    begin
        Rec.Copy(TempBOMLine, true);
        SalesLine := SourceSalesLine;
        ProductionBOMNo := BOMNo;
        VersionCode := BOMVersion;
        ParentUOMCode := BOMUOM;
        if IncludesUnsavedChoices then
            PreviewMessage := UnsavedPreviewLbl
        else
            PreviewMessage := SavedPreviewLbl;
    end;

    var
        SalesLine: Record "Sales Line";
        ProductionBOMNo: Code[20];
        VersionCode: Code[20];
        ParentUOMCode: Code[10];
        PreviewMessage: Text[500];
        UnsavedPreviewLbl: Label 'Read-only multilevel BOM preview using current window choices, including unsaved edits. Expand Production BOM rows to view components. Apply Configuration is still required. Quantities are per immediate parent, not scheduled production demand.';
        SavedPreviewLbl: Label 'Read-only multilevel BOM preview using saved choices only. Expand Production BOM rows to view components. Quantities are per immediate parent, not scheduled production demand or the linked production snapshot.';
}
