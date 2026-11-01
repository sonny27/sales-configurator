namespace CloudFactory.SalesConfigurator;

using Microsoft.Manufacturing.Document;
using Microsoft.Manufacturing.ProductionBOM;
using Microsoft.Manufacturing.Routing;
using Microsoft.Sales.Document;

permissionset 91000 CF_Configurator
{
    Assignable = true;
    Caption = 'Sales Product Configurator';
    Permissions =
        tabledata CF_ConfiguratorBOM = R,
        tabledata CF_OptionChoiceLookup = R,
        tabledata CF_DocumentLineProductConfig = RIMD,
        tabledata CF_ProductConfigHeader = Rimd,
        tabledata CF_SalesConfiguratorSetup = R,
        tabledata "Routing Link" = R,
        tabledata "Routing Header" = R,
        tabledata "Routing Version" = R,
        tabledata "Routing Line" = R,
        tabledata "Production BOM Header" = R,
        tabledata "Production BOM Version" = R,
        tabledata "Production BOM Line" = R,
        table CF_ConfiguratorBOM = X,
        table CF_OptionChoiceLookup = X,
        table CF_DocumentLineProductConfig = X,
        table CF_ProductConfigHeader = X,
        table CF_SalesConfiguratorSetup = X,
        table CF_ConfiguredBOMLine = X,
        table "Sales Line" = X,
        table "Routing Link" = X,
        table "Production Order" = X,
        table "Prod. Order Component" = X,
        page CF_ConfiguratorBOMSetup = X,
        page CF_OptionChoiceLookup = X,
        page CF_ProductConfigurator = X,
        page CF_ProductConfigurations = X,
        page CF_PreviousSalesConfigs = X,
        page CF_SalesConfiguratorSetup = X,
        page CF_ParentRoutingLinks = X,
        page CF_ConfiguredBOM = X,
        page "Sales Order Subform" = X,
        page "Sales Order" = X,
        page "Sales Quote" = X,
        page "Sales Quote Subform" = X,
        page "Create Order From Sales" = X,
        page "Production Order List" = X,
        page "Simulated Production Order" = X,
        page "Planned Production Order" = X,
        page "Firm Planned Prod. Order" = X,
        page "Released Production Order" = X,
        page "Finished Production Order" = X,
        page "Prod. Order Components" = X,
        report "Replan Production Order" = X,
        codeunit CF_ConfiguratorMgt = X,
        codeunit CF_DocumentConfigMgt = X,
        codeunit CF_ConfigHeaderMgt = X,
        codeunit "Create Prod. Order from Sale" = X;
}
