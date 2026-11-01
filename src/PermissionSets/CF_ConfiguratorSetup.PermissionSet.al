namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;

permissionset 91001 CF_ConfiguratorSetup
{
    Assignable = true;
    Caption = 'Product Configurator Setup';
    IncludedPermissionSets = CF_Configurator;
    Permissions =
        tabledata CF_ConfiguratorBOM = RIMD,
        tabledata CF_OptionChoiceLookup = RIMD,
        tabledata CF_SalesConfiguratorSetup = RIM,
        tabledata "Item Category" = R,
        table "Item Category" = X,
        page CF_CategoryTemplateDesigner = X,
        page CF_CategoryTemplateOptions = X,
        page CF_CategoryTemplateChoices = X;
}
