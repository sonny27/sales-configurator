namespace CloudFactory.SalesConfigurator;

page 91014 CF_BOMDiagram
{
    Caption = 'Configured BOM Structure Diagram';
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = None;
    InsertAllowed = false;
    DeleteAllowed = false;
    LinksAllowed = false;

    layout
    {
        area(Content)
        {
            usercontrol(Diagram; CF_BOMDiagram)
            {
                ApplicationArea = All;
                trigger ControlReady()
                begin
                    Ready := true;
                    SendDiagram();
                end;

                trigger RenderFailed(Details: Text)
                begin
                    Message(RenderFailedMsg, Details);
                end;

                trigger OpenNode(NodeId: Text)
                var
                    Node: Record CF_BOMBuffer temporary;
                    Id: Guid;
                begin
                    if not Evaluate(Id, NodeId) then
                        Error(InvalidNodeErr);
                    Node.Copy(Rows, true);
                    Node.Reset();
                    Node.SetRange("Node ID", Id);
                    if not Node.FindFirst() then
                        Error(InvalidNodeErr);
                    Node.OpenCard();
                end;
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(ComponentsOnly)
            {
                Caption = 'Show Components Only';
                ApplicationArea = All;
                Image = BOM;
                ToolTip = 'Show the finished item, items and Production BOM groups from the current draft.';
                trigger OnAction()
                begin
                    IncludeOperations := false;
                    SendDiagram();
                end;
            }
            action(ComponentsAndOperations)
            {
                Caption = 'Show Components and Operations';
                ApplicationArea = All;
                Image = BOM;
                ToolTip = 'Also show the draft''s read-only Work Center and Machine Center operation rows.';
                trigger OnAction()
                begin
                    IncludeOperations := true;
                    SendDiagram();
                end;
            }
        }
        area(Promoted)
        {
            actionref(ComponentsPromoted; ComponentsOnly) { }
            actionref(OperationsPromoted; ComponentsAndOperations) { }
        }
    }

    procedure SetRows(var SourceRows: Record CF_BOMBuffer temporary)
    var
        Reader: Record CF_BOMBuffer temporary;
    begin
        DiagramSessionId := CreateGuid();
        Rows.Reset();
        Rows.DeleteAll();
        Reader.Copy(SourceRows, true);
        Reader.Reset();
        if Reader.Count() > 10000 then
            Error(TooLargeErr);
        if not Reader.FindSet() then
            Error(EmptyErr);
        repeat
            Rows := Reader;
            Rows.Insert(false);
        until Reader.Next() = 0;
    end;

    local procedure SendDiagram()
    var
        Payload: JsonObject;
        Nodes: JsonArray;
        Node: JsonObject;
        Labels: JsonObject;
        Kind: Text;
    begin
        if not Ready then
            exit;
        Rows.Reset();
        Rows.SetCurrentKey("Source Line ID", "Sort Order");
        if Rows.FindSet() then
            repeat
                if not IncludeOperations and not Rows.IsComponent() then
                    continue;
                case Rows.Type of
                    Rows.Type::Item:
                        Kind := 'item';
                    Rows.Type::CF_ProductionBOM:
                        Kind := 'bom';
                    Rows.Type::"Work Center":
                        Kind := 'work';
                    Rows.Type::"Machine Center":
                        Kind := 'machine';
                    else
                        Error(UnsupportedTypeErr, Rows.Type);
                end;
                Clear(Node);
                Node.Add('id', Format(Rows."Node ID"));
                if IsNullGuid(Rows."Parent Node ID") then
                    Node.Add('parent', '')
                else
                    Node.Add('parent', Format(Rows."Parent Node ID"));
                Node.Add('kind', Kind);
                Node.Add('type', Format(Rows.Type));
                Node.Add('no', Rows."No.");
                Node.Add('description', Rows.Description);
                Node.Add('quantity', Format(Rows."Quantity per"));
                Node.Add('unit', Rows."Unit of Measure Code");
                Node.Add('variant', Rows."Variant Code");
                Node.Add('option', Rows."Configuration Option");
                Node.Add('choice', Rows."Choice Code");
                Node.Add('choiceRoot', Rows."Choice Root");
                Nodes.Add(Node);
            until Rows.Next() = 0;
        Labels.Add('title', TitleLbl);
        Labels.Add('fit', FitLbl);
        Labels.Add('zoomIn', ZoomInLbl);
        Labels.Add('zoomOut', ZoomOutLbl);
        Labels.Add('collapse', CollapseLbl);
        Labels.Add('expand', ExpandLbl);
        Labels.Add('help', HelpLbl);
        Labels.Add('components', ComponentsLbl);
        Labels.Add('operations', OperationsLbl);
        Labels.Add('variant', VariantLbl);
        Labels.Add('option', OptionLbl);
        Labels.Add('choice', ChoiceLbl);
        Labels.Add('quantity', QuantityLbl);
        Labels.Add('openCard', OpenCardLbl);
        Labels.Add('reset', ResetLayoutLbl);
        Payload.Add('session', Format(DiagramSessionId));
        Payload.Add('nodes', Nodes);
        Payload.Add('labels', Labels);
        Payload.Add('includeOperations', IncludeOperations);
        CurrPage.Diagram.Load(Payload);
    end;

    var
        Rows: Record CF_BOMBuffer temporary;
        Ready: Boolean;
        IncludeOperations: Boolean;
        DiagramSessionId: Guid;
        TitleLbl: Label 'Configured BOM structure';
        FitLbl: Label 'Fit to window';
        ZoomInLbl: Label 'Zoom in';
        ZoomOutLbl: Label 'Zoom out';
        CollapseLbl: Label 'Collapse one hierarchy level';
        ExpandLbl: Label 'Expand one hierarchy level';
        HelpLbl: Label 'Drag a box to move its whole branch; drag the background to pan. Double-click a box or select Open card to drill down. Up/down buttons collapse/expand levels. Scroll or + / - zoom; 0 fits. Keyboard: arrow keys pan; Shift+arrow moves a focused branch; Enter opens its card; Space selects it. Positions are temporary.';
        ComponentsLbl: Label 'Components only';
        OperationsLbl: Label 'Components and operations';
        VariantLbl: Label 'Variant';
        OptionLbl: Label 'Option';
        ChoiceLbl: Label 'Choice';
        QuantityLbl: Label 'Qty. per parent';
        OpenCardLbl: Label 'Open card';
        ResetLayoutLbl: Label 'Reset layout';
        InvalidNodeErr: Label 'The selected node does not belong to this BOM diagram.';
        EmptyErr: Label 'There is no BOM draft to display.';
        TooLargeErr: Label 'The BOM diagram cannot exceed 10000 rows.';
        UnsupportedTypeErr: Label 'BOM row type %1 cannot be displayed.', Comment = '%1 = BOM type';
        RenderFailedMsg: Label 'The configured BOM diagram could not be displayed: %1', Comment = '%1 = renderer error details';
}
