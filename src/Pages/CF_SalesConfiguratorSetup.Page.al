namespace CloudFactory.SalesConfigurator;

page 91009 CF_SalesConfiguratorSetup
{
    Caption = 'Sales Configurator Setup';
    ApplicationArea = All;
    UsageCategory = Administration;
    PageType = Card;
    SourceTable = CF_SalesConfiguratorSetup;
    InsertAllowed = false;
    DeleteAllowed = false;
    layout
    {
        area(Content)
        {
            group(Numbering)
            {
                Caption = 'Numbering';
                field(ConfigurationNumberFormat; ConfigurationNumberFormatLbl)
                {
                    ApplicationArea = All;
                    Caption = 'Configuration Number Format';
                    Editable = false;
                    ToolTip = 'Configuration numbers use the originating document number and line number, separated by a hyphen, in a 100-character field. Make Order retains the quote configuration number.';
                }
                group(Production)
                {
                    Caption = 'Production';
                    field(DefaultProductionOrderStatus; Rec."Default Prod. Order Status")
                    {
                        ApplicationArea = Manufacturing;
                        ToolTip = 'Specifies the status preselected when Create Production Order is run from the sales-line Product Configurator menu. You can change it in the creation dialog.';
                    }
                }
            }
            group(General)
            {
                Caption = 'General';
                field(Enable; Rec.Enable)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies whether the Product Configurator menu and Product Configuration No. column are available on sales order and sales quote lines. Reopen the sales document after changing this setting.';
                }
            }
        }
    }
    trigger OnOpenPage()
    begin
        Rec.Reset();
        if not Rec.Get() then begin
            Rec.Init();
            Rec.Insert(true);
        end;
    end;

    var
        ConfigurationNumberFormatLbl: Label 'Document No.-Line No. (100 characters)';
}
