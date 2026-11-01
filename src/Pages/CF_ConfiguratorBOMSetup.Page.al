namespace CloudFactory.SalesConfigurator;

page 91000 CF_ConfiguratorBOMSetup
{
    Caption = 'Configurator Options';
    PageType = List;
    SourceTable = CF_ConfiguratorBOM;
    SourceTableView = sorting("Item Category Code", "Display Order", "Configuration Option");
    ApplicationArea = All;
    UsageCategory = Administration;
    layout
    {
        area(Content)
        {
            repeater(Options)
            {
                field(ItemCategoryCode; Rec."Item Category Code") { ApplicationArea = All; ToolTip = 'Specifies the parent item category that offers this option.'; }
                field(ConfigurationOption; Rec."Configuration Option") { ApplicationArea = All; ToolTip = 'Specifies the stable option identifier.'; }
                field(OptionDescription; Rec."Option Description") { ApplicationArea = All; ToolTip = 'Specifies the description shown in Product Configurator.'; }
                field(QuantityPerUnit; Rec."Quantity per Unit") { ApplicationArea = All; ToolTip = 'Specifies the default component quantity in its selected UOM per finished item base unit.'; }
                field(DisplayOrder; Rec."Display Order") { ApplicationArea = All; ToolTip = 'Specifies the option presentation order.'; }
                field(DefaultChoiceCode; Rec."Default Choice Code") { ApplicationArea = All; ToolTip = 'Specifies a selectable choice preselected for a first configuration. Nothing is saved to the sales line until Apply.'; }
                field(Enabled; Rec.Enabled) { ApplicationArea = All; ToolTip = 'Specifies whether this option is available for current configurations.'; }
                field(RoutingLinkCode; Rec."Routing Link Code") { ApplicationArea = All; ToolTip = 'Specifies the default routing link, which must exist on the parent routing when selected.'; }
            }
        }
    }
    actions
    {
        area(Navigation)
        {
            action(Choices)
            {
                Caption = 'Choices';
                ApplicationArea = All;
                Image = List;
                ToolTip = 'View or maintain choice-to-item mappings for this category and option.';
                RunObject = page CF_OptionChoiceLookup;
                RunPageLink = "Item Category Code" = field("Item Category Code"), "Configuration Option" = field("Configuration Option");
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
