namespace CloudFactory.SalesConfigurator;

using Microsoft.Sales.Document;

pageextension 91003 CF_SalesQuoteSubform extends "Sales Quote Subform"
{
    layout
    {
        addafter("No.")
        {
            field(CF_ProductConfigurationNo; Rec.CF_ProductConfigurationNo)
            {
                ApplicationArea = All;
                Visible = ConfiguratorEnabled;
                ToolTip = 'Specifies the saved product configuration number. Make Order moves this configuration to the sales order and retains its original number.';
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
                    ToolTip = 'Configure this saved sales quote item line. Apply saves its number and choices for Make Order.';
                    trigger OnAction()
                    var
                        Mgt: Codeunit CF_DocumentConfigMgt;
                    begin
                        CurrPage.SaveRecord();
                        Mgt.OpenConfigurator(Rec);
                        CurrPage.Update(false);
                    end;
                }
                action(CF_ShowNewConfiguredBOM)
                {
                    Caption = 'Show New Configured BOM';
                    ApplicationArea = Manufacturing;
                    Image = BOM;
                    Ellipsis = true;
                    ToolTip = 'Open a private editable component draft with multilevel items and read-only routing operations. Apply saves it against this sales configuration without changing master BOMs or routings.';
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
                    ToolTip = 'View numbered configurations for sales quotes and sales orders.';
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
