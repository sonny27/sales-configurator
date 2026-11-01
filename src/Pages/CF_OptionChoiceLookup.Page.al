namespace CloudFactory.SalesConfigurator;

page 91001 CF_OptionChoiceLookup
{
    Caption = 'Configurator Choices';
    PageType = List;
    SourceTable = CF_OptionChoiceLookup;
    SourceTableView = sorting("Item Category Code", "Configuration Option", "Display Order", Code);
    DelayedInsert = true;
    PopulateAllFields = true;
    ApplicationArea = All;
    UsageCategory = Administration;
    layout
    {
        area(Content)
        {
            repeater(Choices)
            {
                field(ItemCategoryCode; Rec."Item Category Code") { ApplicationArea = All; ToolTip = 'Specifies the category of the parent configuration option.'; }
                field(ConfigurationOption; Rec."Configuration Option") { ApplicationArea = All; ToolTip = 'Specifies the configuration option to which this choice belongs.'; }
                field(ChoiceCode; Rec.Code) { ApplicationArea = All; ToolTip = 'Specifies the choice identifier, which need not equal the component item number.'; }
                field(MandatoryValues; Rec."Mandatory Values")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies None, Choice Code, or Choice Code and Quantity. Any selectable mandatory choice requires one selection for the parent option. New choices default to Choice Code.';
                }
                field(ItemNo; Rec."Item No.") { ApplicationArea = All; ToolTip = 'Specifies the existing inventory item consumed by this choice.'; }
                field(Description; Rec.Description) { ApplicationArea = All; ToolTip = 'Specifies the choice description.'; }
                field(VariantCode; Rec."Variant Code") { ApplicationArea = All; ToolTip = 'Specifies the component item variant.'; }
                field(UnitOfMeasureCode; Rec."Unit of Measure Code") { ApplicationArea = All; ToolTip = 'Specifies the component item UOM. Defaults to the mapped item base UOM.'; }
                field(DisplayOrder; Rec."Display Order") { ApplicationArea = All; ToolTip = 'Specifies the choice presentation order.'; }
                field(Selectable; Rec.Selectable) { ApplicationArea = All; ToolTip = 'Specifies whether this choice can currently be selected.'; }
            }
        }
    }
    trigger OnOpenPage()
    begin
        CanMaintain := Rec.WritePermission() and not CurrPage.LookupMode();
        CurrPage.Editable(CanMaintain);
    end;

    var
        CanMaintain: Boolean;
}
