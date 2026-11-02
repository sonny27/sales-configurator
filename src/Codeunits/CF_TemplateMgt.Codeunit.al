namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;
using Microsoft.Sales.Document;

codeunit 91012 CF_TemplateMgt
{
    Permissions = tabledata CF_ConfigTemplate = rimd,
                  tabledata CF_ProductConfigHeader = rm;

    procedure Resolve(SalesLine: Record "Sales Line"): Code[20]
    var
        Header: Record CF_ProductConfigHeader;
        Template: Record CF_ConfigTemplate;
        Setup: Record CF_SalesConfiguratorSetup;
        Item: Record Item;
        AssignmentNo: Code[20];
    begin
        Header.SetRange("Source Table ID", Database::"Sales Line");
        Header.SetRange("Source Line SystemId", SalesLine.SystemId);
        if Header.FindFirst() then
            exit(Header."Template Code");
        Setup.Get();
        Item.Get(SalesLine."No.");
        if Setup."Config. Template Assign By" = Setup."Config. Template Assign By"::SalesLineItem then
            AssignmentNo := Item."No."
        else
            AssignmentNo := Item."Item Category Code";
        if AssignmentNo = '' then
            exit('');
        Template.SetRange("Template Type", Setup."Config. Template Assign By");
        if Setup."Config. Template Assign By" = Setup."Config. Template Assign By"::SalesLineItem then
            Template.SetRange("Item No.", AssignmentNo)
        else
            Template.SetRange("Item Category Code", AssignmentNo);
        if Template.FindFirst() then
            exit(Template.Code);
        exit('');
    end;

    procedure AssignmentType(SalesLine: Record "Sales Line"): Enum CF_TemplateAssignment
    var
        Header: Record CF_ProductConfigHeader;
        Setup: Record CF_SalesConfiguratorSetup;
    begin
        Header.SetRange("Source Table ID", Database::"Sales Line");
        Header.SetRange("Source Line SystemId", SalesLine.SystemId);
        if Header.FindFirst() then
            exit(Header."Template Assignment");
        Setup.Get();
        exit(Setup."Config. Template Assign By");
    end;

    procedure Stamp(SalesLine: Record "Sales Line"; var Config: Record CF_DocumentLineProductConfig)
    begin
        Config."Template Code" := Resolve(SalesLine);
        Config."Template Assignment" := AssignmentType(SalesLine);
        Config."Template Context Set" := true;
    end;

    procedure EnsureLegacyHeader(CategoryCode: Code[20])
    var
        Template: Record CF_ConfigTemplate;
    begin
        if CategoryCode = '' then
            exit;
        if Template.Get(CategoryCode) then
            exit;
        Template.Init();
        Template.Code := CategoryCode;
        Template."Template Type" := Template."Template Type"::ItemCategory;
        Template."Item Category Code" := CategoryCode;
        Template.Insert(true);
    end;

    procedure Migrate()
    var
        Options: Record CF_ConfiguratorBOM;
        Choices: Record CF_OptionChoiceLookup;
        Header: Record CF_ProductConfigHeader;
        Config: Record CF_DocumentLineProductConfig;
    begin
        if Options.FindSet() then
            repeat
                EnsureLegacyHeader(Options."Item Category Code");
            until Options.Next() = 0;
        if Choices.FindSet() then
            repeat
                EnsureLegacyHeader(Choices."Item Category Code");
            until Choices.Next() = 0;
        if Config.FindSet() then
            repeat
                EnsureLegacyHeader(Config."Item Category Code");
            until Config.Next() = 0;
        if Header.FindSet(true) then
            repeat
                EnsureLegacyHeader(Header."Item Category Code");
                Header."Template Code" := Header."Item Category Code";
                Header."Template Assignment" := CF_TemplateAssignment::ItemCategory;
                Header.Modify(false);
            until Header.Next() = 0;
    end;

    procedure CheckReference(TemplateCode: Code[20]; ItemNo: Code[20])
    var
        Template: Record CF_ConfigTemplate;
        Item: Record Item;
    begin
        Template.Get(TemplateCode);
        Item.Get(ItemNo);
        Item.TestField(Type, Item.Type::Inventory);
        if Template."Template Type" = Template."Template Type"::SalesLineItem then
            Item.TestField("No.", Template."Item No.")
        else
            Item.TestField("Item Category Code", Template."Item Category Code");
    end;

    procedure Create(var Target: Record CF_ConfigTemplate; AllowEmptyExisting: Boolean)
    var
        Existing: Record CF_ConfigTemplate;
        Options: Record CF_ConfiguratorBOM;
        Choices: Record CF_OptionChoiceLookup;
    begin
        Existing.LockTable();
        Target.CheckAssignment();
        Existing.SetRange("Template Type", Target."Template Type");
        Existing.SetRange("Item No.", Target."Item No.");
        Existing.SetRange("Item Category Code", Target."Item Category Code");
        if Existing.FindFirst() then begin
            if not AllowEmptyExisting then
                Error('A template already exists for %1 %2.', Target."Template Type", Target.GetAssignmentNo());
            Options.SetRange("Item Category Code", Existing.Code);
            Choices.SetRange("Item Category Code", Existing.Code);
            if not Options.IsEmpty() or not Choices.IsEmpty() then
                Error('Destination template %1 is not empty. Copy cannot overwrite or merge templates.', Existing.Code);
            if (Target.Code <> '') and (Target.Code <> Existing.Code) then
                Error('The assignment already belongs to template %1. Use that empty template code or a new assignment.', Existing.Code);
            Target := Existing;
            exit;
        end;
        if Target.Code = '' then
            Target.Code := Target.GetAssignmentNo();
        if Existing.Get(Target.Code) then
            Error('Template code %1 is already used. Enter a different Template Code.', Target.Code);
        Target.Insert(true);
    end;

    procedure CopyTemplate(SourceCode: Code[20]; var Target: Record CF_ConfigTemplate)
    var
        Source: Record CF_ConfigTemplate;
        Options: Record CF_ConfiguratorBOM;
        TargetOption: Record CF_ConfiguratorBOM;
        Choices: Record CF_OptionChoiceLookup;
        TargetChoice: Record CF_OptionChoiceLookup;
        DefaultChoice: Code[20];
    begin
        Source.Get(SourceCode);
        if Target.Code = SourceCode then
            Error('Source and destination templates must differ.');
        Create(Target, true);
        if Target.Code = SourceCode then
            Error('Source and destination templates must differ.');
        Options.SetRange("Item Category Code", SourceCode);
        if Options.FindSet() then
            repeat
                TargetOption := Options;
                TargetOption."Item Category Code" := Target.Code;
                DefaultChoice := TargetOption."Default Choice Code";
                TargetOption."Default Choice Code" := '';
                TargetOption.Insert(true);
                Choices.SetRange("Item Category Code", SourceCode);
                Choices.SetRange("Configuration Option", Options."Configuration Option");
                if Choices.FindSet() then
                    repeat
                        TargetChoice := Choices;
                        TargetChoice."Item Category Code" := Target.Code;
                        TargetChoice.Insert(true);
                    until Choices.Next() = 0;
                TargetOption.Validate("Default Choice Code", DefaultChoice);
                TargetOption.Modify(true);
            until Options.Next() = 0;
    end;

    procedure OpenForSalesLine(SalesLine: Record "Sales Line")
    var
        Template: Record CF_ConfigTemplate;
        Item: Record Item;
        Wizard: Page CF_NewConfigTemplate;
        Designer: Page CF_CategoryTemplateDesigner;
        Header: Record CF_ProductConfigHeader;
        Code: Code[20];
    begin
        Code := Resolve(SalesLine);
        if Code = '' then begin
            Header.SetRange("Source Table ID", Database::"Sales Line");
            Header.SetRange("Source Line SystemId", SalesLine.SystemId);
            if not Header.IsEmpty() then
                Error('This saved configuration originally had no template. Delete and recreate its configuration to use a newly assigned template.');
            Item.Get(SalesLine."No.");
            if AssignmentType(SalesLine) = CF_TemplateAssignment::ItemCategory then
                Item.TestField("Item Category Code");
            Wizard.SetAssignment(AssignmentType(SalesLine), Item."No.", Item."Item Category Code");
            if Wizard.RunModal() <> Action::OK then
                exit;
            Wizard.GetTemplate(Template);
            Commit();
        end else
            Template.Get(Code);
        Designer.SetRecord(Template);
        Designer.SetSalesLineContext(SalesLine);
        Designer.RunModal();
    end;
}
