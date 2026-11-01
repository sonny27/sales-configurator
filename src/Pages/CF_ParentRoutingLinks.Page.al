namespace CloudFactory.SalesConfigurator;

using Microsoft.Manufacturing.Routing;

page 91006 CF_ParentRoutingLinks
{
    Caption = 'Parent Routing Links';
    PageType = List;
    SourceTable = "Routing Link";
    SourceTableTemporary = true;
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            repeater(Links)
            {
                field(Code; Rec.Code) { ApplicationArea = All; ToolTip = 'Specifies a link assigned to the effective parent routing version. This is a routing link code, not an operation number.'; }
                field(Description; Rec.Description) { ApplicationArea = All; ToolTip = 'Specifies the routing link description.'; }
            }
        }
    }

    procedure SetLinks(var TempLink: Record "Routing Link" temporary)
    begin
        Rec.Copy(TempLink, true);
    end;
}
