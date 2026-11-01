namespace CloudFactory.SalesConfigurator;

using Microsoft.Manufacturing.Document;
using Microsoft.Sales.Document;

pageextension 91000 CF_SalesOrderSubform extends "Sales Order Subform"
{
    layout
    {
        addafter("No.")
        {
            field(CF_ProductConfigurationNo; Rec.CF_ProductConfigurationNo)
            {
                ApplicationArea = All;
                Visible = ConfiguratorEnabled;
                ToolTip = 'Specifies the saved configuration number. A configuration transferred by Make Order retains the original quote document/line number.';
                trigger OnDrillDown()
                var
                    Mgt: Codeunit CF_DocumentConfigMgt;
                begin
                    Mgt.OpenConfigurationSummary(Mgt.GetConfigDocumentType(Rec), Database::"Sales Line", Rec.SystemId, true);
                end;
            }
        }
    }
    actions
    {
        addafter(SelectMultiItems)
        {
            group(CF_ConfiguratorActions)
            {
                Caption = 'Product Configurator';
                Image = Setup;
                ShowAs = SplitButton;
                Visible = ConfiguratorEnabled;
                Enabled = ConfiguratorEnabled;

                action(CF_ProductConfigurator)
                {
                    Caption = 'Product Configurator';
                    ApplicationArea = All;
                    Image = Setup;
                    ToolTip = 'Configure component choices for this persisted sales order item line.';
                    trigger OnAction()
                    var
                        Mgt: Codeunit CF_DocumentConfigMgt;
                    begin
                        CurrPage.SaveRecord();
                        Mgt.OpenConfigurator(Rec);
                        CurrPage.Update(false);
                    end;
                }
                action(CF_CreateProductionOrder)
                {
                    Caption = 'Create Production Order';
                    ApplicationArea = Manufacturing;
                    AccessByPermission = tabledata "Production Order" = I;
                    Image = CreateDocument;
                    Ellipsis = true;
                    ToolTip = 'Use the standard Create Order From Sales dialog and production creation flow for this sales line, including its saved configuration.';
                    trigger OnAction()
                    var
                        Mgt: Codeunit CF_DocumentConfigMgt;
                    begin
                        CurrPage.SaveRecord();
                        Mgt.CreateProductionOrder(Rec);
                        CurrPage.Update(false);
                    end;
                }
                action(CF_ViewProductionOrder)
                {
                    Caption = 'View Production Order';
                    ApplicationArea = Manufacturing;
                    AccessByPermission = tabledata "Production Order" = R;
                    Image = Production;
                    Ellipsis = true;
                    ToolTip = 'Open the production order linked to this configured sales line. If several orders are linked, show a filtered list of those orders.';
                    trigger OnAction()
                    var
                        Mgt: Codeunit CF_DocumentConfigMgt;
                    begin
                        CurrPage.SaveRecord();
                        Mgt.OpenLinkedProductionOrders(Rec);
                        CurrPage.Update(false);
                    end;
                }
                action(CF_ShowNewConfiguredBOM)
                {
                    Caption = 'Show New Configured BOM';
                    ApplicationArea = Manufacturing;
                    Image = BOM;
                    Ellipsis = true;
                    ToolTip = 'Preview the effective parent item/SKU BOM plus saved configuration components without changing any master BOM.';
                    trigger OnAction()
                    var
                        Mgt: Codeunit CF_DocumentConfigMgt;
                    begin
                        CurrPage.SaveRecord();
                        Mgt.ShowConfiguredBOM(Rec);
                    end;
                }
                action(CF_ProductConfigurations)
                {
                    Caption = 'Product Configurations';
                    ApplicationArea = All;
                    Image = List;
                    RunObject = page CF_ProductConfigurations;
                    ToolTip = 'View one numbered configuration summary per document line, with sales order and linked production order details.';
                }
            }
        }
    }

    trigger OnOpenPage()
    var
        Setup: Record CF_SalesConfiguratorSetup;
    begin
        ConfiguratorEnabled := false;
        if Setup.Get() then
            ConfiguratorEnabled := Setup.Enable;
    end;

    var
        ConfiguratorEnabled: Boolean;
}
