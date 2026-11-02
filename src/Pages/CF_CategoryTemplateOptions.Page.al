namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;

page 91004 CF_CategoryTemplateOptions
{
    Caption = 'Template Options';
    PageType = ListPart;
    SourceTable = CF_ConfiguratorBOM;
    SourceTableView = sorting("Item Category Code", "Display Order", "Configuration Option");
    AutoSplitKey = false;
    PopulateAllFields = true;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            repeater(Options)
            {
                field(ConfigurationOption; Rec."Configuration Option") { ApplicationArea = All; ToolTip = 'Specifies the stable option code within the selected template.'; }
                field(OptionDescription; Rec."Option Description") { ApplicationArea = All; ToolTip = 'Specifies the option description displayed to sales users.'; }
                field(MandatoryValues; Rec."Mandatory Values") { ApplicationArea = All; ToolTip = 'Specifies the mandatory rule shared by every choice under this option: None, Choice Code, or Choice Code and Quantity.'; }
                field(Enabled; Rec.Enabled) { ApplicationArea = All; ToolTip = 'Specifies whether new configurations offer this option.'; }
                field(DefaultChoiceCode; Rec."Default Choice Code") { ApplicationArea = All; ToolTip = 'Specifies the selectable choice preselected for a first configuration. Create its choice mapping in the lower grid first.'; }
                field(DisplayOrder; Rec."Display Order") { ApplicationArea = All; ToolTip = 'Specifies the order in which options are displayed.'; }
                field(RoutingLinkCode; Rec."Routing Link Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Select a link assigned to the reference parent item/SKU routing and effective certified version. Standalone setup requires a reference item and date.';
                    trigger OnLookup(var Text: Text): Boolean
                    var
                        LinkCode: Code[10];
                        Mgt: Codeunit CF_DocumentConfigMgt;
                    begin
                        EnsureRoutingContext();
                        LinkCode := Rec."Routing Link Code";
                        if Mgt.LookupItemRoutingLink(ReferenceItemNo, ReferenceLocationCode, ReferenceVariantCode, ReferenceDate, LinkCode) then begin
                            Rec.Validate("Routing Link Code", LinkCode);
                            Text := Rec."Routing Link Code";
                            CurrPage.SaveRecord();
                            CurrPage.Update(false);
                        end;
                        exit(true);
                    end;
                    trigger OnValidate()
                    begin
                        CheckRoutingLink();
                    end;
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(SaveOption)
            {
                Caption = 'Save Option';
                ApplicationArea = All;
                Image = Save;
                ToolTip = 'Save the current option before defining its choices in the lower grid.';
                trigger OnAction()
                begin
                    CheckRoutingLink();
                    CurrPage.SaveRecord();
                    CurrPage.Update(false);
                end;
            }
        }
    }

    trigger OnOpenPage()
    begin
        CurrPage.Editable(Rec.WritePermission());
    end;

    trigger OnInsertRecord(BelowxRec: Boolean): Boolean
    begin
        CheckRoutingLink();
        exit(true);
    end;

    trigger OnModifyRecord(): Boolean
    begin
        if RoutingContextReady or (Rec."Routing Link Code" <> xRec."Routing Link Code") then
            CheckRoutingLink();
        exit(true);
    end;

    procedure SetRoutingContext(ItemNo: Code[20]; LocationCode: Code[10]; VariantCode: Code[10]; RoutingDate: Date; ContextReady: Boolean)
    begin
        ReferenceItemNo := ItemNo;
        ReferenceLocationCode := LocationCode;
        ReferenceVariantCode := VariantCode;
        ReferenceDate := RoutingDate;
        RoutingContextReady := ContextReady;
    end;

    local procedure EnsureRoutingContext()
    var
        Item: Record Item;
        TemplateMgt: Codeunit CF_TemplateMgt;
    begin
        if not RoutingContextReady then
            Error('Select a reference parent item and routing reference date before selecting a routing link. Location and variant are optional.');
        Item.Get(ReferenceItemNo);
        TemplateMgt.CheckReference(Rec."Item Category Code", Item."No.");
    end;

    local procedure CheckRoutingLink()
    var
        Mgt: Codeunit CF_DocumentConfigMgt;
    begin
        if Rec."Routing Link Code" = '' then
            exit;
        EnsureRoutingContext();
        Mgt.ValidateItemRoutingLink(ReferenceItemNo, ReferenceLocationCode, ReferenceVariantCode, ReferenceDate, Rec."Routing Link Code");
    end;

    var
        ReferenceItemNo: Code[20];
        ReferenceLocationCode: Code[10];
        ReferenceVariantCode: Code[10];
        ReferenceDate: Date;
        RoutingContextReady: Boolean;
}
