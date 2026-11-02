namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;
using Microsoft.Manufacturing.Document;
using Microsoft.Manufacturing.ProductionBOM;
using Microsoft.Sales.Document;

page 91011 CF_BOMDraftEditor
{
    Caption = 'New Configured BOM';
    PageType = Worksheet;
    SourceTable = CF_BOMBuffer;
    SourceTableTemporary = true;
    SourceTableView = sorting("Source Line ID", "Sort Order");
    ApplicationArea = All;
    InsertAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            group(Source)
            {
                Caption = 'Sales Line Configuration Draft';
                Editable = false;
                field(DocumentNo; SalesLine."Document No.") { ApplicationArea = All; Caption = 'Document No.'; ToolTip = 'Specifies the source sales document.'; }
                field(LineNo; SalesLine."Line No.") { ApplicationArea = All; Caption = 'Line No.'; ToolTip = 'Specifies the source sales line.'; }
                field(ParentItem; SalesLine."No.") { ApplicationArea = All; Caption = 'Parent Item No.'; ToolTip = 'Specifies the finished item being configured.'; }
                field(EffectiveDate; EffectiveDate) { ApplicationArea = All; Caption = 'Structure Date'; ToolTip = 'Specifies Work Date, matching the native BOM Structure version and effective-line selection when a new draft is generated.'; }
                field(DraftMessage; DraftMessage)
                {
                    ApplicationArea = All;
                    ShowCaption = false;
                    ToolTip = 'Explains draft isolation, quantity units, read-only routing operations and Favorable (green) styling for directly added rows. Inherited BOM descendants retain normal styling.';
                }
            }
            repeater(Lines)
            {
                IndentationColumn = Rec.Indentation;
                IndentationControls = No;
                ShowAsTree = true;
                TreeInitialState = ExpandAll;
                field(Type; Rec.Type) { ApplicationArea = All; Editable = false; StyleExpr = LineStyle; ToolTip = 'Specifies the component or read-only native routing-operation type.'; }
                field(No; Rec."No.")
                {
                    ApplicationArea = All;
                    Editable = false;
                    DrillDown = true;
                    StyleExpr = NoStyle;
                    ToolTip = 'Opens the item, Production BOM, Work Center or Machine Center card. To replace a component identity, delete its branch and insert a new component.';
                    trigger OnDrillDown()
                    begin
                        Rec.OpenCard();
                    end;
                }
                field(Description; Rec.Description) { ApplicationArea = All; Editable = ComponentEditable; StyleExpr = LineStyle; ToolTip = 'Specifies the description used for this component in production.'; }
                field(Variant; Rec."Variant Code") { ApplicationArea = All; Editable = MappingEditable; StyleExpr = LineStyle; ToolTip = 'Specifies the component variant. Choice-root mappings remain controlled by the option choice.'; }
                field(Quantity; Rec."Quantity per")
                {
                    ApplicationArea = All;
                    Editable = ComponentEditable;
                    StyleExpr = LineStyle;
                    ToolTip = 'Specifies component quantity before formula and scrap per immediate parent item base unit, or per phantom BOM unit. Routing rows show native calculated time and cannot be edited.';
                    trigger OnValidate()
                    begin
                        if Rec."Choice Root" and (Rec."Quantity per" <= 0) then
                            Error('Enter a positive component quantity.');
                        if Rec."Choice Root" then begin
                            Choices.Get(DocumentMgt.GetConfigDocumentType(SalesLine), Database::"Sales Line", SalesLine.SystemId, Rec."Configuration Option");
                            Choices.Validate("Quantity per Unit", Rec."Quantity per");
                            Choices.Modify();
                        end;
                    end;
                }
                field(UOM; Rec."Unit of Measure Code") { ApplicationArea = All; Editable = MappingEditable; StyleExpr = LineStyle; ToolTip = 'Specifies the component unit. Production BOM rows retain their BOM header unit.'; }
                field(Scrap; Rec."Scrap %") { ApplicationArea = All; Editable = ComponentEditable; StyleExpr = LineStyle; ToolTip = 'Specifies the component scrap percentage used by native production quantity calculation.'; }
                field(RoutingLink; Rec."Routing Link Code")
                {
                    ApplicationArea = All;
                    Editable = ComponentEditable;
                    StyleExpr = LineStyle;
                    ToolTip = 'Specifies an existing native routing-operation link. This does not edit the routing.';
                    trigger OnValidate()
                    begin
                        if Rec."Choice Root" then begin
                            Choices.Get(DocumentMgt.GetConfigDocumentType(SalesLine), Database::"Sales Line", SalesLine.SystemId, Rec."Configuration Option");
                            Choices.Validate("Routing Link Code", Rec."Routing Link Code");
                            Choices.Modify();
                        end;
                    end;
                }
                field(Formula; Rec."Calculation Formula") { ApplicationArea = All; Editable = MappingEditable; StyleExpr = LineStyle; Visible = false; ToolTip = 'Specifies the native quantity calculation formula retained from the source BOM.'; }
                field(Length; Rec.Length) { ApplicationArea = All; Editable = MappingEditable; StyleExpr = LineStyle; Visible = false; ToolTip = 'Specifies formula length.'; }
                field(Width; Rec.Width) { ApplicationArea = All; Editable = MappingEditable; StyleExpr = LineStyle; Visible = false; ToolTip = 'Specifies formula width.'; }
                field(Depth; Rec.Depth) { ApplicationArea = All; Editable = MappingEditable; StyleExpr = LineStyle; Visible = false; ToolTip = 'Specifies formula depth.'; }
                field(Weight; Rec.Weight) { ApplicationArea = All; Editable = MappingEditable; StyleExpr = LineStyle; Visible = false; ToolTip = 'Specifies formula weight.'; }
                field(OptionCode; Rec."Configuration Option") { ApplicationArea = All; Editable = false; StyleExpr = LineStyle; ToolTip = 'Specifies the selected option that owns this choice root.'; }
                field(ChoiceCode; Rec."Choice Code") { ApplicationArea = All; Editable = false; StyleExpr = LineStyle; ToolTip = 'Specifies the selected choice that owns this component branch.'; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(Diagram)
            {
                Caption = 'Diagram';
                ApplicationArea = All;
                Image = BOM;
                ToolTip = 'Show a read-only visual tree of the current draft, including unsaved edits. Switch between components only and components with operations, zoom and pan. This does not apply the configuration.';
                trigger OnAction()
                var
                    DiagramPage: Page CF_BOMDiagram;
                begin
                    CurrPage.SaveRecord();
                    DiagramPage.SetRows(Rec);
                    DiagramPage.RunModal();
                end;
            }
            action(InsertItem)
            {
                Caption = 'Insert Item';
                ApplicationArea = All;
                Image = New;
                Enabled = CanEdit;
                ToolTip = 'Insert an item and its native component/routing subtree beneath the selected item or Production BOM.';
                trigger OnAction()
                var
                    Item: Record Item;
                    Items: Page "Item List";
                begin
                    CurrPage.SaveRecord();
                    Item.SetFilter(Type, '%1|%2', Item.Type::Inventory, Item.Type::"Non-Inventory");
                    Items.SetTableView(Item);
                    Items.LookupMode(true);
                    if Items.RunModal() = Action::LookupOK then begin
                        Items.GetRecord(Item);
                        DraftMgt.AddComponent(SalesLine, Rec, Item."No.", false, Rec);
                        CurrPage.Update(false);
                    end;
                end;
            }
            action(InsertProductionBOM)
            {
                Caption = 'Insert Production BOM';
                ApplicationArea = All;
                Image = BOM;
                Enabled = CanEdit;
                ToolTip = 'Insert a phantom Production BOM and its components beneath the selected parent. No master BOM is changed.';
                trigger OnAction()
                var
                    BOM: Record "Production BOM Header";
                    BOMs: Page "Production BOM List";
                begin
                    CurrPage.SaveRecord();
                    BOMs.LookupMode(true);
                    if BOMs.RunModal() = Action::LookupOK then begin
                        BOMs.GetRecord(BOM);
                        DraftMgt.AddComponent(SalesLine, Rec, BOM."No.", true, Rec);
                        CurrPage.Update(false);
                    end;
                end;
            }
            action(DeleteComponent)
            {
                Caption = 'Delete Component Branch';
                ApplicationArea = All;
                Image = Delete;
                Enabled = CanEdit;
                ToolTip = 'Delete the selected component and all descendants in this draft. A choice root also clears its option choice; mandatory rules are checked on Apply.';
                trigger OnAction()
                begin
                    CurrPage.SaveRecord();
                    if Confirm('Delete component %1 and its entire branch from this draft?', false, Rec."No.") then begin
                        DraftMgt.DeleteBranch(Rec, Rec, Choices);
                        CurrPage.Update(false);
                    end;
                end;
            }
            action(Apply)
            {
                Caption = 'Apply BOM and Configuration';
                ApplicationArea = All;
                Image = Approve;
                Enabled = CanEdit;
                ToolTip = 'Validate and save this BOM structure and all current option choices together against the sales line. Master BOMs and routings remain unchanged.';
                trigger OnAction()
                begin
                    CurrPage.SaveRecord();
                    DraftMgt.Save(SalesLine, Choices, Rec, Revision, SavedId, CommittedChoicesSignature);
                    Applied := true;
                    CurrPage.Close();
                end;
            }
            action(CancelDraft)
            {
                Caption = 'Cancel';
                ApplicationArea = All;
                Image = Cancel;
                ToolTip = 'Close without saving this temporary BOM draft or its option-quantity changes.';
                trigger OnAction()
                begin
                    CurrPage.Close();
                end;
            }
        }
        area(Promoted)
        {
            actionref(DiagramPromoted; Diagram) { }
            actionref(ApplyPromoted; Apply) { }
            actionref(InsertItemPromoted; InsertItem) { }
            actionref(InsertBOMPromoted; InsertProductionBOM) { }
            actionref(DeletePromoted; DeleteComponent) { }
            actionref(CancelPromoted; CancelDraft) { }
        }
    }

    trigger OnAfterGetRecord()
    var
        Child: Record CF_BOMBuffer temporary;
    begin
        ComponentEditable := CanEdit and Rec.IsComponent() and (Rec.Indentation > 0);
        MappingEditable := ComponentEditable and not Rec."Choice Root" and (Rec.Type = Rec.Type::Item);
        Child.Copy(Rec, true);
        Child.Reset();
        Child.SetRange("Parent Node ID", Rec."Node ID");
        HasChildren := not Child.IsEmpty();
        LineStyle := 'Standard';
        NoStyle := 'Standard';
        if HasChildren then
            NoStyle := 'Strong';
        if IsDirectAddition() then begin
            LineStyle := 'Favorable';
            NoStyle := 'Favorable';
        end;
    end;

    local procedure IsDirectAddition(): Boolean
    var
        Parent: Record CF_BOMBuffer temporary;
    begin
        if Rec."Choice Root" or Rec."Direct Addition" then
            exit(true);
        if not Rec."Configurator Added" or IsNullGuid(Rec."Parent Node ID") then
            exit(false);
        // Earlier drafts tracked branch origin but not direct manual additions.
        Parent.Copy(Rec, true);
        Parent.Reset();
        Parent.Get(Rec."Source Line ID", Rec."Parent Node ID");
        exit(not Parent."Configurator Added");
    end;

    procedure SetDraft(Source: Record "Sales Line"; var SourceChoices: Record CF_DocumentLineProductConfig temporary; var Rows: Record CF_BOMBuffer temporary; SourceRevision: Integer; SourceSavedId: Guid; SourceChoicesSignature: Text)
    var
        Reader: Record CF_DocumentLineProductConfig temporary;
        Order: Record "Production Order";
    begin
        SalesLine := Source;
        Revision := SourceRevision;
        SavedId := SourceSavedId;
        CommittedChoicesSignature := SourceChoicesSignature;
        CanEdit := not DocumentMgt.GetLinkedProductionOrders(SalesLine, Order);
        DraftMessage := 'Direct additions use Favorable (green) style; inherited BOM descendants keep normal styling. Drafts are private until Apply. Operations are read-only; production routing remains native. Item quantities are per parent base unit.';
        Rec.Copy(Rows, true);
        Rec.FindFirst();
        EffectiveDate := Rec."Generated Date";
        Reader.Copy(SourceChoices, true);
        Reader.Reset();
        if Reader.FindSet() then
            repeat
                Choices := Reader;
                Choices.Insert(false, true);
            until Reader.Next() = 0;
    end;

    procedure GetAppliedChoices(var Target: Record CF_DocumentLineProductConfig temporary)
    var
        OriginalView: Text;
    begin
        if not Applied then
            exit;
        OriginalView := Target.GetView(false);
        Target.Reset();
        Target.DeleteAll();
        Choices.Reset();
        if Choices.FindSet() then
            repeat
                Target := Choices;
                Target.Insert(false, true);
            until Choices.Next() = 0;
        Target.SetView(OriginalView);
    end;

    procedure WasApplied(): Boolean
    begin
        exit(Applied);
    end;

    var
        SalesLine: Record "Sales Line";
        Choices: Record CF_DocumentLineProductConfig temporary;
        DraftMgt: Codeunit CF_BOMDraftMgt;
        DocumentMgt: Codeunit CF_DocumentConfigMgt;
        Revision: Integer;
        SavedId: Guid;
        CommittedChoicesSignature: Text;
        EffectiveDate: Date;
        CanEdit: Boolean;
        ComponentEditable: Boolean;
        MappingEditable: Boolean;
        Applied: Boolean;
        HasChildren: Boolean;
        LineStyle: Text;
        NoStyle: Text;
        DraftMessage: Text;
}
