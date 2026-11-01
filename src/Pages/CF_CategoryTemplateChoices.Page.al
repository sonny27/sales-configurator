namespace CloudFactory.SalesConfigurator;

page 91005 CF_CategoryTemplateChoices
{
    Caption = 'Category Template Choices';
    PageType = ListPart;
    SourceTable = CF_OptionChoiceLookup;
    SourceTableView = sorting("Item Category Code", "Configuration Option", "Display Order", Code);
    PopulateAllFields = true;
    DelayedInsert = true;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            repeater(Choices)
            {
                field(ChoiceCode; Rec.Code) { ApplicationArea = All; ToolTip = 'Specifies a choice code for the highlighted category option.'; }
                field(MandatoryValues; Rec."Mandatory Values")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies None, Choice Code, or Choice Code and Quantity. Any selectable mandatory choice requires one selection for the parent option. A positive default quantity satisfies the quantity requirement.';
                }
                field(ItemNo; Rec."Item No.") { ApplicationArea = All; ToolTip = 'Specifies the existing inventory item added as a production component.'; }
                field(Description; Rec.Description) { ApplicationArea = All; ToolTip = 'Specifies the choice description.'; }
                field(VariantCode; Rec."Variant Code") { ApplicationArea = All; ToolTip = 'Specifies the mapped component variant.'; }
                field(UnitOfMeasureCode; Rec."Unit of Measure Code") { ApplicationArea = All; ToolTip = 'Specifies the mapped component unit of measure.'; }
                field(Selectable; Rec.Selectable) { ApplicationArea = All; ToolTip = 'Specifies whether sales users and template defaults can select this choice.'; }
                field(DisplayOrder; Rec."Display Order") { ApplicationArea = All; ToolTip = 'Specifies the order in which choices are offered.'; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(SaveChoice)
            {
                Caption = 'Save Choice';
                ApplicationArea = All;
                Image = Save;
                ToolTip = 'Save the current choice mapping before selecting it as an option default.';
                trigger OnAction()
                begin
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
}
