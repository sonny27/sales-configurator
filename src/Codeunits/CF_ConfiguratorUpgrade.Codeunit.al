namespace CloudFactory.SalesConfigurator;

using Microsoft.Manufacturing.Document;

codeunit 91004 CF_ConfiguratorUpgrade
{
    Subtype = Upgrade;
    Permissions = tabledata CF_ConfiguratorBOM = r,
                  tabledata CF_OptionChoiceLookup = rm,
                  tabledata CF_SalesConfiguratorSetup = rm;

    trigger OnUpgradePerCompany()
    var
        Module: ModuleInfo;
        HeaderMgt: Codeunit CF_ConfigHeaderMgt;
        Setup: Record CF_SalesConfiguratorSetup;
    begin
        if not NavApp.GetCurrentModuleInfo(Module) then
            Error(ModuleInfoUnavailableErr);
        if Module.DataVersion() < Version.Create(1, 0, 0, 1) then
            UpgradeMandatoryValues();
        if Module.DataVersion() < Version.Create(1, 0, 0, 2) then begin
            HeaderMgt.InitializeSetup();
            HeaderMgt.BackfillHeaders();
        end;
        if Module.DataVersion() < Version.Create(1, 0, 0, 4) then
            HeaderMgt.UpgradeDocumentNumbers();
        if Module.DataVersion() < Version.Create(1, 0, 0, 6) then begin
            HeaderMgt.InitializeSetup();
            Setup.Get();
            Setup."Default Prod. Order Status" := Setup."Default Prod. Order Status"::"Firm Planned";
            Setup.Modify(true);
        end;
    end;

    local procedure UpgradeMandatoryValues()
    var
        OptionSetup: Record CF_ConfiguratorBOM;
        Choice: Record CF_OptionChoiceLookup;
    begin
        Choice.LockTable();
        if Choice.FindSet(true) then
            repeat
                OptionSetup.Get(Choice."Item Category Code", Choice."Configuration Option");
                if OptionSetup.Mandatory then
                    Choice."Mandatory Values" := CF_MandatoryValues::ChoiceCode
                else
                    Choice."Mandatory Values" := CF_MandatoryValues::None;
                // Only the new rule changes; existing mappings may legitimately need later review.
                Choice.Modify(false);
            until Choice.Next() = 0;
    end;

    var
        ModuleInfoUnavailableErr: Label 'The configuration app data version could not be read. Mandatory Values migration cannot continue.';
}
