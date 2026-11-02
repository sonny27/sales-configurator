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
                field(ItemCategoryCode; Rec."Item Category Code") { ApplicationArea = All; ToolTip = 'Specifies the template of the parent configuration option.'; }
                field(ConfigurationOption; Rec."Configuration Option") { ApplicationArea = All; ToolTip = 'Specifies the configuration option to which this choice belongs.'; }
                field(ChoiceCode; Rec.Code) { ApplicationArea = All; ToolTip = 'Specifies the choice identifier, which need not equal the component item number.'; }
                field(Type; Rec.Type) { ApplicationArea = All; ToolTip = 'Specifies Item for a component or Production BOM for native nested-BOM explosion. Manufactured Item components use standard make-to-order rules.'; }
                field(ItemNo; Rec."Item No.") { ApplicationArea = All; ToolTip = 'Specifies an existing inventory or non-inventory item, or a production BOM. Production BOM choices do not require a same-numbered item.'; }
                field(Description; Rec.Description) { ApplicationArea = All; ToolTip = 'Specifies the choice description.'; }
                field(QuantityPerUnit; Rec."Quantity per Unit") { ApplicationArea = All; ToolTip = 'Specifies the default quantity in the selected UOM per finished item base unit. Set zero to require users to enter a positive quantity in Product Configurator before Apply. Positive quantities must satisfy enabled min/max limits.'; }
                field(MinMaxQuantityBehavior; Rec."Min. Max. Quantity Behavior") { ApplicationArea = All; ToolTip = 'Specifies whether to check neither, both, only the minimum, or only the maximum quantity for this choice. Enabled limits reject quantities outside the range.'; }
                field(MinimumQuantity; Rec."Minimum Quantity") { ApplicationArea = All; ToolTip = 'Specifies the inclusive minimum quantity in the selected UOM per finished item base unit, when minimum checking is enabled.'; }
                field(MaximumQuantity; Rec."Maximum Quantity") { ApplicationArea = All; ToolTip = 'Specifies the inclusive maximum quantity in the selected UOM per finished item base unit, when maximum checking is enabled. An enabled maximum must be positive.'; }
                field(VariantCode; Rec."Variant Code") { ApplicationArea = All; Editable = Rec.Type = Rec.Type::Item; ToolTip = 'Specifies the component item variant. Production BOM references have no variant.'; }
                field(UnitOfMeasureCode; Rec."Unit of Measure Code") { ApplicationArea = All; ToolTip = 'Specifies the item UOM or the selected production BOM version UOM. Production BOM choices default to the BOM header UOM.'; }
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
