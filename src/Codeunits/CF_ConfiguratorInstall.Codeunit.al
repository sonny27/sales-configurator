namespace CloudFactory.SalesConfigurator;

codeunit 91006 CF_ConfiguratorInstall
{
    Subtype = Install;

    trigger OnInstallAppPerCompany()
    var
        HeaderMgt: Codeunit CF_ConfigHeaderMgt;
    begin
        HeaderMgt.InitializeSetup();
        HeaderMgt.BackfillHeaders();
        HeaderMgt.UpgradeDocumentNumbers();
    end;
}
