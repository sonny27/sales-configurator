namespace CloudFactory.SalesConfigurator;

using Microsoft.Manufacturing.Document;

pageextension 91001 CF_ProdOrderComponents extends "Prod. Order Components"
{
    layout
    {
        addafter("Item No.")
        {
            field(CF_ConfiguredComponent; Rec.CF_ConfiguredComponent)
            {
                ApplicationArea = Manufacturing;
                ToolTip = 'Specifies whether this component was added from the document line product configuration.';
            }
            field(CF_ConfigOption; Rec.CF_ConfigOption)
            {
                ApplicationArea = Manufacturing;
                ToolTip = 'Specifies the product configuration option that added this component.';
            }
        }
    }
}
