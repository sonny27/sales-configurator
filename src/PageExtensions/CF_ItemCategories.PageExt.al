namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;

pageextension 91002 CF_ItemCategories extends "Item Categories"
{
    actions
    {
        addlast(Creation)
        {
            action(CF_CategoryTemplateSetup)
            {
                Caption = 'BOM Template Setup';
                ApplicationArea = All;
                AccessByPermission = tabledata CF_ConfiguratorBOM = M;
                Image = Setup;
                ToolTip = 'Maintain the shared configurator options, choices, and defaults for the selected item category.';
                trigger OnAction()
                var
                    Mgt: Codeunit CF_DocumentConfigMgt;
                begin
                    CurrPage.SaveRecord();
                    Mgt.OpenCategoryTemplate(Rec.Code);
                end;
            }
        }
        addlast(Category_Process)
        {
            actionref(CF_CategoryTemplatePromoted; CF_CategoryTemplateSetup) { }
        }
    }
}
