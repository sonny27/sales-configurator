namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Planning;
using Microsoft.Inventory.Requisition;
using Microsoft.Inventory.Tracking;
using Microsoft.Manufacturing.Document;
using Microsoft.Manufacturing.Routing;
using Microsoft.Purchases.Document;
using Microsoft.Sales.Document;
using Microsoft.Foundation.UOM;

codeunit 91003 CF_DocumentConfigTests
{
    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MandatoryChoiceRequiredWithoutSavedRows()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
    begin
        CreateFixture(SalesLine, Choice);
        SetMandatoryValues(Choice, CF_MandatoryValues::ChoiceCode);

        asserterror Mgt.ValidateForProduction(SalesLine);
        AssertErrorContains('mandatory option WOOD requires a choice');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure TypedChoiceRequiresExactCategoryAndOption()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        WrongChoice: Record CF_OptionChoiceLookup;
        OptionSetup: Record CF_ConfiguratorBOM;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
        Category: Record "Item Category";
    begin
        CreateFixture(SalesLine, Choice);
        OptionSetup.Init();
        OptionSetup."Item Category Code" := Choice."Item Category Code";
        OptionSetup."Configuration Option" := 'OTHER';
        OptionSetup."Quantity per Unit" := 1;
        OptionSetup.Enabled := true;
        OptionSetup.Insert(true);
        WrongChoice := Choice;
        WrongChoice."Configuration Option" := 'OTHER';
        WrongChoice.Code := 'WRONGOPTION';
        Clear(WrongChoice.SystemId);
        WrongChoice.Insert(true);

        Category.Code := NewCode('CAT');
        Category.Insert(false);
        OptionSetup."Item Category Code" := Category.Code;
        OptionSetup."Configuration Option" := 'WOOD';
        Clear(OptionSetup.SystemId);
        OptionSetup.Insert(true);
        WrongChoice."Item Category Code" := Category.Code;
        WrongChoice."Configuration Option" := 'WOOD';
        WrongChoice.Code := 'WRONGCATEGORY';
        Clear(WrongChoice.SystemId);
        WrongChoice.Insert(true);

        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        TempConfig.Validate("Choice Code", 'BLUE');
        AssertTrue(TempConfig."Component Item No." = Choice."Item No.", 'A valid typed choice must resolve its authoritative item mapping.');
        AssertTrue(TempConfig."Component UOM Code" = Choice."Unit of Measure Code", 'A typed choice must resolve its item UOM.');
        asserterror TempConfig.Validate("Choice Code", 'WRONGOPTION');
        AssertErrorContains('does not exist for category');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure TypedChoiceRejectsOtherCategory()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        WrongChoice: Record CF_OptionChoiceLookup;
        OptionSetup: Record CF_ConfiguratorBOM;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
        Category: Record "Item Category";
    begin
        CreateFixture(SalesLine, Choice);
        Category.Code := NewCode('CAT');
        Category.Insert(false);
        OptionSetup."Item Category Code" := Category.Code;
        OptionSetup."Configuration Option" := 'WOOD';
        OptionSetup."Quantity per Unit" := 1;
        OptionSetup.Enabled := true;
        OptionSetup.Insert(true);
        WrongChoice := Choice;
        WrongChoice."Item Category Code" := Category.Code;
        WrongChoice.Code := 'WRONGCATEGORY';
        Clear(WrongChoice.SystemId);
        WrongChoice.Insert(true);

        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        asserterror TempConfig.Validate("Choice Code", 'WRONGCATEGORY');
        AssertErrorContains('does not exist for category');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure TwoSalesLinesHaveIndependentSelections()
    var
        FirstLine: Record "Sales Line";
        SecondLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        RedChoice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig;
    begin
        CreateFixture(FirstLine, Choice);
        AddRedChoice(Choice, RedChoice);
        CopyLine(FirstLine, SecondLine);
        SaveChoice(FirstLine, 'BLUE');
        SaveChoice(SecondLine, 'RED');

        Mgt.FilterSalesLine(FirstLine, Config);
        AssertTrue(Config.Count() = 1, 'The first line must have exactly one saved option.');
        Config.FindFirst();
        AssertTrue(Config."Choice Code" = 'BLUE', 'The first line must retain BLUE.');
        AssertTrue(Config."Source Line SystemId" = FirstLine.SystemId, 'The first selection must use its own source identity.');
        Mgt.FilterSalesLine(SecondLine, Config);
        AssertTrue(Config.Count() = 1, 'The second line must have exactly one saved option.');
        Config.FindFirst();
        AssertTrue(Config."Choice Code" = 'RED', 'The second line must retain RED.');
        AssertTrue(Config."Component Item No." = RedChoice."Item No.", 'The second line must resolve RED independently.');
        AssertTrue(Config."Source Line SystemId" = SecondLine.SystemId, 'The second selection must use its own source identity.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure UpdatingSelectionPreservesSystemId()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
        SelectionId: Guid;
    begin
        CreateFixture(SalesLine, Choice);
        SaveChoice(SalesLine, 'BLUE');
        Mgt.FilterSalesLine(SalesLine, Config);
        Config.FindFirst();
        SelectionId := Config.SystemId;
        AssertTrue(not IsNullGuid(SelectionId), 'A saved selection must have a SystemId.');

        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        TempConfig.Validate("Quantity per Unit", 2);
        TempConfig.Modify();
        Mgt.Save(SalesLine, TempConfig);

        Mgt.FilterSalesLine(SalesLine, Config);
        Config.FindFirst();
        AssertTrue(Config.SystemId = SelectionId, 'Updating a selection must preserve its SystemId.');
        AssertTrue(Config."Quantity per Unit" = 2, 'The updated quantity must be saved.');
    end;

    [Test]
    [HandlerFunctions('CancelPopup')]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure CancelPopupDoesNotPersistTemporaryEdits()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        RedChoice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig;
        SelectionId: Guid;
    begin
        CreateFixture(SalesLine, Choice);
        AddRedChoice(Choice, RedChoice);
        SaveChoice(SalesLine, 'BLUE');
        Mgt.FilterSalesLine(SalesLine, Config);
        Config.FindFirst();
        SelectionId := Config.SystemId;

        Mgt.OpenConfigurator(SalesLine);

        Mgt.FilterSalesLine(SalesLine, Config);
        AssertTrue(Config.Count() = 1, 'Cancel must not insert extra saved selections.');
        Config.FindFirst();
        AssertTrue(Config."Choice Code" = 'BLUE', 'Cancel must discard the temporary RED choice.');
        AssertTrue(Config."Quantity per Unit" = 1, 'Cancel must discard the temporary quantity.');
        AssertTrue(Config.SystemId = SelectionId, 'Cancel must leave the saved identity unchanged.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MappingDriftRequiresExplicitReselection()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
        ReplacementItem: Record Item;
        OriginalItemNo: Code[20];
    begin
        CreateFixture(SalesLine, Choice);
        SaveChoice(SalesLine, 'BLUE');
        OriginalItemNo := Choice."Item No.";
        CreateItem(ReplacementItem, '', Choice."Unit of Measure Code");
        Choice.Validate("Item No.", ReplacementItem."No.");
        Choice.Modify(true);

        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        AssertTrue(TempConfig."Component Item No." = OriginalItemNo, 'Reopening must not silently remap the saved component.');
        TempConfig.Validate("Choice Code", 'BLUE');
        TempConfig.Modify();
        Mgt.Save(SalesLine, TempConfig);
        Mgt.ValidateForProduction(SalesLine);
        Mgt.FilterSalesLine(SalesLine, Config);
        Config.FindFirst();
        AssertTrue(Config."Component Item No." = ReplacementItem."No.", 'Explicit reselection must accept the new mapping.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MappingDriftBlocksProduction()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        ReplacementItem: Record Item;
    begin
        CreateFixture(SalesLine, Choice);
        SaveChoice(SalesLine, 'BLUE');
        CreateItem(ReplacementItem, '', Choice."Unit of Measure Code");
        Choice.Validate("Item No.", ReplacementItem."No.");
        Choice.Modify(true);

        asserterror Mgt.ValidateForProduction(SalesLine);
        AssertErrorContains('mapping changed');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MappingDriftBlocksApply()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        ReplacementItem: Record Item;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
    begin
        CreateFixture(SalesLine, Choice);
        SaveChoice(SalesLine, 'BLUE');
        CreateItem(ReplacementItem, '', Choice."Unit of Measure Code");
        Choice.Validate("Item No.", ReplacementItem."No.");
        Choice.Modify(true);
        Mgt.Load(SalesLine, TempConfig);

        asserterror Mgt.Save(SalesLine, TempConfig);
        AssertErrorContains('mapping changed');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure LinkedProductionBlocksSave()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
    begin
        CreateFixture(SalesLine, Choice);
        SaveChoice(SalesLine, 'BLUE');
        Mgt.Load(SalesLine, TempConfig);
        CreateLinkedOrder(SalesLine);

        asserterror Mgt.Save(SalesLine, TempConfig);
        AssertErrorContains('linked to production order');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure LinkedProductionBlocksTriggerlessTableEdit()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig;
    begin
        CreateFixture(SalesLine, Choice);
        SaveChoice(SalesLine, 'BLUE');
        CreateLinkedOrder(SalesLine);
        Mgt.FilterSalesLine(SalesLine, Config);
        Config.FindFirst();
        Config."Quantity per Unit" := 2;
        asserterror Config.Modify(false);
        AssertErrorContains('linked to production order');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure CopiedLineDoesNotInheritAndDeleteCleansSource()
    var
        SourceLine: Record "Sales Line";
        DestinationLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig;
    begin
        CreateFixture(SourceLine, Choice);
        SaveChoice(SourceLine, 'BLUE');
        CopyLine(SourceLine, DestinationLine);
        AssertTrue(DestinationLine.SystemId <> SourceLine.SystemId, 'A copied line must have a new SystemId.');
        Mgt.FilterSalesLine(DestinationLine, Config);
        AssertTrue(Config.IsEmpty(), 'A copied sales line must not inherit the original selections.');

        SourceLine.Delete(false);

        Mgt.FilterSalesLine(SourceLine, Config);
        AssertTrue(Config.IsEmpty(), 'Deleting the source line must clean its saved selections, even without table triggers.');
        AssertTrue(DestinationLine.GetBySystemId(DestinationLine.SystemId), 'Cleanup must not delete the copied line.');
        Mgt.FilterSalesLine(DestinationLine, Config);
        AssertTrue(Config.IsEmpty(), 'Cleanup must not create selections on the copied line.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DefaultChoiceLoadsTemporarilyAndApplySaves()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
    begin
        CreateFixture(SalesLine, Choice);
        SetDefault(Choice, 'BLUE');
        SetMandatoryValues(Choice, CF_MandatoryValues::ChoiceCode);

        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        AssertTrue(TempConfig."Choice Code" = 'BLUE', 'The category default must be preselected.');
        AssertTrue(TempConfig."Component Item No." = Choice."Item No.", 'The default must resolve the component item.');
        AssertTrue(TempConfig."Component UOM Code" = Choice."Unit of Measure Code", 'The default must resolve the component UOM.');
        Mgt.FilterSalesLine(SalesLine, Config);
        AssertTrue(Config.IsEmpty(), 'Loading defaults must not save a document selection.');

        Mgt.Save(SalesLine, TempConfig);
        Mgt.FilterSalesLine(SalesLine, Config);
        Config.FindFirst();
        AssertTrue(Config."Choice Code" = 'BLUE', 'Apply must save the preselected default.');
        Mgt.ValidateForProduction(SalesLine);
    end;

    [Test]
    [HandlerFunctions('CancelDefaultPopup')]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure CancelFirstDefaultDoesNotSave()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig;
    begin
        CreateFixture(SalesLine, Choice);
        SetDefault(Choice, 'BLUE');
        Mgt.OpenConfigurator(SalesLine);
        Mgt.FilterSalesLine(SalesLine, Config);
        AssertTrue(Config.IsEmpty(), 'Cancel must discard a first preselected default without saving.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DefaultDoesNotReplaceSavedChoiceOrIdentity()
    var
        SalesLine: Record "Sales Line";
        BlueChoice: Record CF_OptionChoiceLookup;
        RedChoice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
        SelectionId: Guid;
    begin
        CreateFixture(SalesLine, BlueChoice);
        AddRedChoice(BlueChoice, RedChoice);
        SaveChoice(SalesLine, 'RED');
        Mgt.FilterSalesLine(SalesLine, Config);
        Config.FindFirst();
        SelectionId := Config.SystemId;
        SetDefault(BlueChoice, 'BLUE');

        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        AssertTrue(TempConfig."Choice Code" = 'RED', 'A new default must not replace a saved choice.');
        AssertTrue(TempConfig.SystemId = SelectionId, 'Loading a template must preserve selection identity.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DefaultDoesNotRestoreDeliberatelyClearedChoice()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
    begin
        CreateFixture(SalesLine, Choice);
        SetDefault(Choice, 'BLUE');
        SaveChoice(SalesLine, '');
        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        AssertTrue(TempConfig."Choice Code" = '', 'A saved cleared choice must remain cleared on reopening.');
        AssertTrue(TempConfig."Component Item No." = '', 'A cleared choice must not regain a component mapping.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure NewOptionsOnSavedConfigurationDoNotAutoSelect()
    var
        SalesLine: Record "Sales Line";
        BlueChoice: Record CF_OptionChoiceLookup;
        NewChoice: Record CF_OptionChoiceLookup;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
    begin
        CreateFixture(SalesLine, BlueChoice);
        SaveChoice(SalesLine, 'BLUE');
        AddOptionWithDefault(BlueChoice, 'NUTS', NewChoice);
        Mgt.Load(SalesLine, TempConfig);
        TempConfig.Get(CF_ConfigDocumentType::SalesOrder, Database::"Sales Line", SalesLine.SystemId, 'NUTS');
        AssertTrue(TempConfig."Choice Code" = '', 'Adding a template option must not silently select more demand on a saved configuration.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RefreshTemplatePreservesUnsavedEditsAndAddsOptions()
    var
        SalesLine: Record "Sales Line";
        BlueChoice: Record CF_OptionChoiceLookup;
        RedChoice: Record CF_OptionChoiceLookup;
        NewChoice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
    begin
        CreateFixture(SalesLine, BlueChoice);
        AddRedChoice(BlueChoice, RedChoice);
        SetDefault(BlueChoice, 'BLUE');
        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        TempConfig.Validate("Choice Code", 'RED');
        TempConfig.Validate("Quantity per Unit", 3);
        TempConfig.Modify();
        AddOptionWithDefault(BlueChoice, 'NUTS', NewChoice);

        Mgt.RefreshTemplate(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        AssertTrue(TempConfig."Choice Code" = 'RED', 'Returning from setup must preserve unsaved choices.');
        AssertTrue(TempConfig."Quantity per Unit" = 3, 'Returning from setup must preserve unsaved quantities.');
        TempConfig.Get(CF_ConfigDocumentType::SalesOrder, Database::"Sales Line", SalesLine.SystemId, 'NUTS');
        AssertTrue(TempConfig."Choice Code" = NewChoice.Code, 'A newly created option can load its default on a first configuration.');
        Mgt.FilterSalesLine(SalesLine, Config);
        AssertTrue(Config.IsEmpty(), 'Returning from setup must not apply the temporary selections.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DefaultMustBelongToSameOption()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        OtherChoice: Record CF_OptionChoiceLookup;
        OptionSetup: Record CF_ConfiguratorBOM;
    begin
        CreateFixture(SalesLine, Choice);
        AddOptionWithDefault(Choice, 'NUTS', OtherChoice);
        OptionSetup.Get(Choice."Item Category Code", 'WOOD');
        OptionSetup."Default Choice Code" := OtherChoice.Code;
        asserterror OptionSetup.Modify(true);
        AssertErrorContains('does not exist for category');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DefaultRejectsNonSelectableChoice()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        OptionSetup: Record CF_ConfiguratorBOM;
    begin
        CreateFixture(SalesLine, Choice);
        Choice.Selectable := false;
        Choice.Modify(true);
        OptionSetup.Get(Choice."Item Category Code", Choice."Configuration Option");
        OptionSetup."Default Choice Code" := Choice.Code;
        asserterror OptionSetup.Modify(true);
        AssertErrorContains('Selectable');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DefaultRejectsBlockedComponent()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        OptionSetup: Record CF_ConfiguratorBOM;
        Component: Record Item;
    begin
        CreateFixture(SalesLine, Choice);
        Component.Get(Choice."Item No.");
        Component.Blocked := true;
        Component.Modify(false);
        OptionSetup.Get(Choice."Item Category Code", Choice."Configuration Option");
        OptionSetup."Default Choice Code" := Choice.Code;
        asserterror OptionSetup.Modify(true);
        AssertErrorContains('is blocked');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DefaultChoiceCannotBeDeleted()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
    begin
        CreateFixture(SalesLine, Choice);
        SetDefault(Choice, 'BLUE');
        asserterror Choice.Delete(true);
        AssertErrorContains('Clear or change the default');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DefaultChoiceCannotBeDisabled()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
    begin
        CreateFixture(SalesLine, Choice);
        SetDefault(Choice, 'BLUE');
        Choice.Selectable := false;
        asserterror Choice.Modify(true);
        AssertErrorContains('Clear or change the default');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DesignerFiltersByCategoryAndHighlightedOption()
    var
        FirstLine: Record "Sales Line";
        SecondLine: Record "Sales Line";
        FirstChoice: Record CF_OptionChoiceLookup;
        SecondChoice: Record CF_OptionChoiceLookup;
        NewChoice: Record CF_OptionChoiceLookup;
        Designer: TestPage CF_CategoryTemplateDesigner;
    begin
        CreateFixture(FirstLine, FirstChoice);
        CreateFixture(SecondLine, SecondChoice);
        AddOptionWithDefault(FirstChoice, 'NUTS', NewChoice);
        Designer.OpenEdit();
        Designer.ItemCategoryCode.SetValue(FirstChoice."Item Category Code");
        AssertTrue(Designer.Options.First(), 'The designer must show options for the selected category.');
        Designer.Options.ConfigurationOption.AssertEquals('NUTS');
        AssertTrue(Designer.Choices.First(), 'The designer must show choices for the highlighted option.');
        Designer.Choices.ChoiceCode.AssertEquals(NewChoice.Code);
        if Designer.Choices.Next() then
            Designer.Choices.ChoiceCode.AssertEquals('');
        AssertTrue(Designer.Options.Next(), 'The selected category must also show WOOD.');
        Designer.Options.ConfigurationOption.AssertEquals('WOOD');
        AssertTrue(Designer.Choices.First(), 'Changing the highlighted option must refresh choices.');
        Designer.Choices.ChoiceCode.AssertEquals('BLUE');
        Designer.Choices.ItemNo.AssertEquals(FirstChoice."Item No.");
        if Designer.Options.Next() then
            Designer.Options.ConfigurationOption.AssertEquals('');

        Designer.ItemCategoryCode.SetValue(SecondChoice."Item Category Code");
        AssertTrue(Designer.Options.First(), 'Changing category must refresh the option grid.');
        Designer.Options.ConfigurationOption.AssertEquals('WOOD');
        AssertTrue(Designer.Choices.First(), 'Changing category must refresh the choice grid.');
        Designer.Choices.ItemNo.AssertEquals(SecondChoice."Item No.");
        if Designer.Options.Next() then
            Designer.Options.ConfigurationOption.AssertEquals('');
        Designer.Close();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DesignerCreatesOptionChoiceAndDefaultInCategory()
    var
        SalesLine: Record "Sales Line";
        ExistingChoice: Record CF_OptionChoiceLookup;
        OptionSetup: Record CF_ConfiguratorBOM;
        NewChoice: Record CF_OptionChoiceLookup;
        Designer: TestPage CF_CategoryTemplateDesigner;
    begin
        CreateFixture(SalesLine, ExistingChoice);
        Designer.OpenEdit();
        Designer.ItemCategoryCode.SetValue(ExistingChoice."Item Category Code");
        Designer.Options.New();
        Designer.Options.ConfigurationOption.SetValue('LEGS');
        Designer.Options.OptionDescription.SetValue('Leg style');
        Designer.Options.MandatoryValues.SetValue(CF_MandatoryValues::ChoiceCodeAndQuantity);
        Designer.Options.SaveOption.Invoke();
        OptionSetup.Get(ExistingChoice."Item Category Code", 'LEGS');
        Designer.Options.GoToRecord(OptionSetup);
        Designer.Options.ConfigurationOption.AssertEquals('LEGS');
        Designer.Choices.First();
        AssertTrue(Designer.ValidationErrorCount() = 0, Designer.GetValidationError());
        AssertTrue(Designer.Options.ValidationErrorCount() = 0, Designer.Options.GetValidationError());
        AssertTrue(Designer.Choices.ValidationErrorCount() = 0, Designer.Choices.GetValidationError());
        Designer.Choices.New();
        Designer.Choices.ChoiceCode.SetValue('STANDARD');
        Designer.Choices.ItemNo.SetValue(ExistingChoice."Item No.");
        Designer.Choices.QuantityPerUnit.SetValue(4);
        Designer.Choices.SaveChoice.Invoke();
        Designer.Options.DefaultChoiceCode.SetValue('STANDARD');
        Designer.Close();

        OptionSetup.Get(ExistingChoice."Item Category Code", 'LEGS');
        AssertTrue(OptionSetup."Mandatory Values" = CF_MandatoryValues::ChoiceCodeAndQuantity, 'The designer must persist the option mandatory rule.');
        AssertTrue(OptionSetup."Default Choice Code" = 'STANDARD', 'The designer must persist the default.');
        NewChoice.Get(ExistingChoice."Item Category Code", 'LEGS', 'STANDARD');
        AssertTrue(NewChoice."Quantity per Unit" = 4, 'The designer must persist the choice quantity.');
        AssertTrue(NewChoice."Item No." = ExistingChoice."Item No.", 'Choice creation must inherit the selected category and option.');
    end;

    [ModalPageHandler]
    procedure CancelDefaultPopup(var Configurator: TestPage CF_ProductConfigurator)
    begin
        Configurator.ChoiceCode.AssertEquals('BLUE');
        Configurator.CancelConfiguration.Invoke();
    end;

    [Test]
    [HandlerFunctions('SetupFromPopup,CreateTemplateOption')]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PopupSetupPersistsTemplateButCancelDiscardsSelections()
    var
        SalesLine: Record "Sales Line";
        BlueChoice: Record CF_OptionChoiceLookup;
        RedChoice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig;
        OptionSetup: Record CF_ConfiguratorBOM;
        Item: Record Item;
    begin
        CreateFixture(SalesLine, BlueChoice);
        AddRedChoice(BlueChoice, RedChoice);
        ExpectedCategory := BlueChoice."Item Category Code";
        ExpectedComponent := BlueChoice."Item No.";
        Mgt.OpenConfigurator(SalesLine);
        OptionSetup.Get(ExpectedCategory, 'NUTS');
        AssertTrue(OptionSetup."Default Choice Code" = 'STANDARD', 'Setup opened from the popup must persist its shared template.');
        Mgt.FilterSalesLine(SalesLine, Config);
        AssertTrue(Config.IsEmpty(), 'Cancel must discard document edits, not the separately saved template.');
        Item.Get(SalesLine."No.");
        AssertTrue(Item."Item Category Code" = ExpectedCategory, 'The designer must not change the parent item category.');
    end;

    [Test]
    [HandlerFunctions('EmptyTemplatePopup')]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PopupExplainsCategoryWithoutEnabledOptions()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        OptionSetup: Record CF_ConfiguratorBOM;
    begin
        CreateFixture(SalesLine, Choice);
        ExpectedCategory := Choice."Item Category Code";
        OptionSetup.Get(ExpectedCategory, Choice."Configuration Option");
        OptionSetup.Enabled := false;
        OptionSetup.Modify(true);
        Mgt.OpenConfigurator(SalesLine);
    end;

    [Test]
    [HandlerFunctions('MissingCategoryPopup')]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PopupExplainsParentWithoutCategory()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Item: Record Item;
    begin
        CreateFixture(SalesLine, Choice);
        Item.Get(SalesLine."No.");
        Item."Item Category Code" := '';
        Item.Modify(false);
        Mgt.OpenConfigurator(SalesLine);
    end;

    [ModalPageHandler]
    procedure SetupFromPopup(var Configurator: TestPage CF_ProductConfigurator)
    begin
        Configurator.ItemCategoryCode.AssertEquals(ExpectedCategory);
        Configurator.ChoiceCode.SetValue('RED');
        Configurator.QuantityPerUnit.SetValue(3);
        Configurator.ChoiceCode.AssertEquals('RED');
        Configurator.QuantityPerUnit.AssertEquals(3);
        Configurator.CategoryTemplateSetup.Invoke();
        AssertTrue(Configurator.First(), 'Returning from setup must refresh newly added template options.');
        Configurator.ConfigurationOption.AssertEquals('NUTS');
        Configurator.ChoiceCode.AssertEquals('STANDARD');
        AssertTrue(Configurator.Next(), 'Returning from setup must preserve the original option.');
        Configurator.ConfigurationOption.AssertEquals('WOOD');
        Configurator.ChoiceCode.AssertEquals('RED');
        Configurator.QuantityPerUnit.AssertEquals(3);
        Configurator.CancelConfiguration.Invoke();
    end;

    [Test]
    [HandlerFunctions('ApplyEditedPopup')]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PopupApplySavesEditedDefaultAndQuantity()
    var
        SalesLine: Record "Sales Line";
        BlueChoice: Record CF_OptionChoiceLookup;
        RedChoice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig;
    begin
        CreateFixture(SalesLine, BlueChoice);
        AddRedChoice(BlueChoice, RedChoice);
        SetDefault(BlueChoice, 'BLUE');
        Mgt.OpenConfigurator(SalesLine);
        Mgt.FilterSalesLine(SalesLine, Config);
        Config.FindFirst();
        AssertTrue(Config."Choice Code" = 'RED', 'Apply must save the edited choice, not restore the default.');
        AssertTrue(Config."Component Item No." = RedChoice."Item No.", 'Apply must save the edited component mapping.');
        AssertTrue(Config."Quantity per Unit" = 3, 'Apply must save the edited quantity.');
    end;

    [ModalPageHandler]
    procedure ApplyEditedPopup(var Configurator: TestPage CF_ProductConfigurator)
    begin
        Configurator.ChoiceCode.AssertEquals('BLUE');
        Configurator.ChoiceCode.SetValue('RED');
        Configurator.QuantityPerUnit.SetValue(3);
        Configurator.ApplyConfiguration.Invoke();
    end;

    [Test]
    [HandlerFunctions('ApplyLookupPopup,SelectRedChoice')]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PopupLookupUpdatesMappingAndApplyPersists()
    var
        SalesLine: Record "Sales Line";
        BlueChoice: Record CF_OptionChoiceLookup;
        RedChoice: Record CF_OptionChoiceLookup;
        OtherChoice: Record CF_OptionChoiceLookup;
        HiddenChoice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
    begin
        CreateFixture(SalesLine, BlueChoice);
        AddRedChoice(BlueChoice, RedChoice);
        AddOptionWithDefault(BlueChoice, 'OTHER', OtherChoice);
        HiddenChoice := BlueChoice;
        HiddenChoice.Code := 'HIDDEN';
        HiddenChoice.Selectable := false;
        Clear(HiddenChoice.SystemId);
        HiddenChoice.Insert(true);
        ExpectedComponent := RedChoice."Item No.";
        Mgt.OpenConfigurator(SalesLine);

        Mgt.FilterSalesLine(SalesLine, Config);
        Config.SetRange("Configuration Option", 'WOOD');
        Config.FindFirst();
        AssertTrue(Config."Choice Code" = 'RED', 'Apply must save the choice selected from the lookup list.');
        AssertTrue(Config."Component Item No." = ExpectedComponent, 'Apply must save its resolved component item.');
        AssertTrue(Config."Component UOM Code" = RedChoice."Unit of Measure Code", 'Apply must save its resolved UOM.');
        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        AssertTrue(TempConfig."Choice Code" = 'RED', 'The lookup selection must survive reopening.');
        AssertTrue(TempConfig.SystemId = Config.SystemId, 'Reopening must preserve selection identity.');
    end;

    [Test]
    [HandlerFunctions('CancelLookupPopup,CancelChoiceLookup')]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure CancelChoiceLookupPreservesSavedSelection()
    var
        SalesLine: Record "Sales Line";
        BlueChoice: Record CF_OptionChoiceLookup;
        RedChoice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig;
        SelectionId: Guid;
    begin
        CreateFixture(SalesLine, BlueChoice);
        AddRedChoice(BlueChoice, RedChoice);
        SaveChoice(SalesLine, 'BLUE');
        Mgt.FilterSalesLine(SalesLine, Config);
        Config.FindFirst();
        SelectionId := Config.SystemId;
        ExpectedComponent := BlueChoice."Item No.";
        Mgt.OpenConfigurator(SalesLine);
        Mgt.FilterSalesLine(SalesLine, Config);
        Config.FindFirst();
        AssertTrue(Config."Choice Code" = 'BLUE', 'Canceling the lookup must retain the previous choice.');
        AssertTrue(Config."Component Item No." = ExpectedComponent, 'Canceling the lookup must retain the previous mapping.');
        AssertTrue(Config.SystemId = SelectionId, 'Canceling the lookup must preserve the saved identity.');
    end;

    [Test]
    [HandlerFunctions('CancelSelectedLookupPopup,SelectRedChoice')]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure CancelConfiguratorDoesNotSaveLookupSelection()
    var
        SalesLine: Record "Sales Line";
        BlueChoice: Record CF_OptionChoiceLookup;
        RedChoice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig;
    begin
        CreateFixture(SalesLine, BlueChoice);
        AddRedChoice(BlueChoice, RedChoice);
        ExpectedComponent := RedChoice."Item No.";
        Mgt.OpenConfigurator(SalesLine);
        Mgt.FilterSalesLine(SalesLine, Config);
        AssertTrue(Config.IsEmpty(), 'A lookup selection must remain temporary until Apply.');
    end;

    [ModalPageHandler]
    procedure ApplyLookupPopup(var Configurator: TestPage CF_ProductConfigurator)
    begin
        Configurator.First();
        Configurator.Next();
        Configurator.ConfigurationOption.AssertEquals('WOOD');
        Configurator.ChoiceCode.AssertEquals('');
        Configurator.ChoiceCode.Lookup();
        Configurator.ChoiceCode.AssertEquals('RED');
        Configurator.ComponentItemNo.AssertEquals(ExpectedComponent);
        Configurator.ApplyConfiguration.Invoke();
    end;

    [ModalPageHandler]
    procedure SelectRedChoice(var Choices: TestPage CF_OptionChoiceLookup)
    begin
        AssertTrue(Choices.First(), 'The choice lookup must contain BLUE.');
        Choices.ChoiceCode.AssertEquals('BLUE');
        AssertTrue(Choices.Next(), 'The choice lookup must contain RED.');
        Choices.ChoiceCode.AssertEquals('RED');
        AssertTrue(not Choices.Next(), 'The lookup must exclude nonselectable choices and other options.');
        Choices.Last();
        Choices.OK().Invoke();
    end;

    [ModalPageHandler]
    procedure CancelLookupPopup(var Configurator: TestPage CF_ProductConfigurator)
    begin
        Configurator.ChoiceCode.Lookup();
        Configurator.ChoiceCode.AssertEquals('BLUE');
        Configurator.ComponentItemNo.AssertEquals(ExpectedComponent);
        Configurator.ApplyConfiguration.Invoke();
    end;

    [ModalPageHandler]
    procedure CancelChoiceLookup(var Choices: TestPage CF_OptionChoiceLookup)
    begin
        Choices.Cancel().Invoke();
    end;

    [ModalPageHandler]
    procedure CancelSelectedLookupPopup(var Configurator: TestPage CF_ProductConfigurator)
    begin
        Configurator.ChoiceCode.Lookup();
        Configurator.ChoiceCode.AssertEquals('RED');
        Configurator.ComponentItemNo.AssertEquals(ExpectedComponent);
        Configurator.CancelConfiguration.Invoke();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RoutingLinksExcludeUnassignedAndDeduplicate()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Link: Record "Routing Link";
        OtherLink: Record "Routing Link";
        TempLink: Record "Routing Link" temporary;
        RoutingNo: Code[20];
        OtherRoutingNo: Code[20];
    begin
        CreateRoutingFixture(SalesLine, Choice, RoutingNo, Link);
        AddRoutingOperation(RoutingNo, '', '20', Link.Code);
        AddRoutingOperation(RoutingNo, '', '100', '');
        CreateRouting(OtherRoutingNo, OtherLink);
        Mgt.GetAvailableRoutingLinks(SalesLine, TempLink);
        AssertTrue(TempLink.Count() = 1, 'Only distinct assigned links on the parent routing may be offered.');
        AssertTrue(TempLink.Get(Link.Code), 'The assigned parent link must be available.');
        AssertTrue(not TempLink.Get(OtherLink.Code), 'A global link on a different routing must be excluded.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RoutingLinksUseLocationVariantSKU()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        ItemLink: Record "Routing Link";
        SKULink: Record "Routing Link";
        TempLink: Record "Routing Link" temporary;
        RoutingNo: Code[20];
        SKURoutingNo: Code[20];
    begin
        CreateRoutingFixture(SalesLine, Choice, RoutingNo, ItemLink);
        SetSalesContext(SalesLine, CopyStr(NewCode('LOC'), 1, 10), 'VAR');
        CreateRouting(SKURoutingNo, SKULink);
        CreateSKU(SalesLine, SalesLine."Variant Code", SKURoutingNo);
        Mgt.GetAvailableRoutingLinks(SalesLine, TempLink);
        AssertTrue(TempLink.Count() = 1, 'The exact location/variant SKU must determine available links.');
        AssertTrue(TempLink.Get(SKULink.Code), 'The SKU link must be available.');
        AssertTrue(not TempLink.Get(ItemLink.Code), 'The overridden item link must not be offered.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure BlankSKURoutingFallsBackToItem()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Link: Record "Routing Link";
        TempLink: Record "Routing Link" temporary;
        RoutingNo: Code[20];
    begin
        CreateRoutingFixture(SalesLine, Choice, RoutingNo, Link);
        CreateSKU(SalesLine, '', '');
        Mgt.GetAvailableRoutingLinks(SalesLine, TempLink);
        AssertTrue(TempLink.Get(Link.Code), 'An empty SKU routing must not suppress the item routing.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure VariantBlankSKURoutingMatchesStandardInitialization()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        ItemLink: Record "Routing Link";
        SKULink: Record "Routing Link";
        VersionLink: Record "Routing Link";
        RoutingLine: Record "Routing Line";
        BaseLine: Record "Prod. Order Line";
        ProductionOrder: Record "Production Order";
        RoutingNo: Code[20];
        SKURoutingNo: Code[20];
    begin
        CreateRoutingFixture(SalesLine, Choice, RoutingNo, ItemLink);
        SetSalesContext(SalesLine, '', 'VAR');
        CreateRouting(SKURoutingNo, SKULink);
        CreateRoutingVersion(SKURoutingNo, 'ACTIVE', WorkDate() + 5, true, VersionLink);
        CreateSKU(SalesLine, '', SKURoutingNo);
        CreateSKU(SalesLine, 'VAR', '');

        ProductionOrder.Status := ProductionOrder.Status::"Firm Planned";
        ProductionOrder."No." := NewCode('PROD');
        ProductionOrder."Source Type" := ProductionOrder."Source Type"::Item;
        ProductionOrder."Source No." := SalesLine."No.";
        ProductionOrder.Insert(false);
        BaseLine.Status := ProductionOrder.Status;
        BaseLine."Prod. Order No." := ProductionOrder."No.";
        BaseLine."Line No." := 10000;
        BaseLine."Routing Reference No." := 10000;
        BaseLine."Item No." := SalesLine."No.";
        BaseLine."Due Date" := SalesLine."Shipment Date";
        BaseLine.Validate("Routing No.", RoutingNo);
        BaseLine.GetUpdateFromSKU();
        BaseLine."Variant Code" := SalesLine."Variant Code";
        BaseLine.GetUpdateFromSKU();

        Mgt.FilterParentRoutingLines(SalesLine, RoutingLine);
        AssertTrue(BaseLine."Routing No." = SKURoutingNo, 'Standard initialization must retain the blank-variant SKU route when the exact SKU route is blank.');
        AssertTrue(RoutingLine.GetRangeMin("Routing No.") = BaseLine."Routing No.", 'Configurator routing resolution must match the standard production line.');
        AssertTrue(RoutingLine.GetRangeMin("Version Code") = BaseLine."Routing Version Code", 'Configurator routing version must match the standard production line.');
        AssertTrue(BaseLine."Routing Version Code" = 'ACTIVE', 'Standard version selection must use the shipment/due date.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MissingVariantSKUResetsToItemRouting()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        ItemLink: Record "Routing Link";
        SKULink: Record "Routing Link";
        TempLink: Record "Routing Link" temporary;
        RoutingNo: Code[20];
        SKURoutingNo: Code[20];
    begin
        CreateRoutingFixture(SalesLine, Choice, RoutingNo, ItemLink);
        SetSalesContext(SalesLine, '', 'VAR');
        CreateRouting(SKURoutingNo, SKULink);
        CreateSKU(SalesLine, '', SKURoutingNo);
        Mgt.GetAvailableRoutingLinks(SalesLine, TempLink);
        AssertTrue(TempLink.Get(ItemLink.Code), 'Without an exact variant SKU, standard initialization resets to the item routing.');
        AssertTrue(not TempLink.Get(SKULink.Code), 'The blank-variant SKU route must not leak into a missing exact variant SKU.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RoutingLinksUseCertifiedVersionAtShipmentDate()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        BaseLink: Record "Routing Link";
        OldLink: Record "Routing Link";
        CurrentLink: Record "Routing Link";
        FutureLink: Record "Routing Link";
        UncertifiedLink: Record "Routing Link";
        TempLink: Record "Routing Link" temporary;
        RoutingNo: Code[20];
    begin
        CreateRoutingFixture(SalesLine, Choice, RoutingNo, BaseLink);
        CreateRoutingVersion(RoutingNo, 'OLD', WorkDate() - 10, true, OldLink);
        CreateRoutingVersion(RoutingNo, 'CURRENT', WorkDate() + 5, true, CurrentLink);
        CreateRoutingVersion(RoutingNo, 'FUTURE', WorkDate() + 20, true, FutureLink);
        CreateRoutingVersion(RoutingNo, 'UNCERTIFIED', WorkDate() + 8, false, UncertifiedLink);
        Mgt.GetAvailableRoutingLinks(SalesLine, TempLink);
        AssertTrue(TempLink.Count() = 1, 'Only the effective certified version may supply links.');
        AssertTrue(TempLink.Get(CurrentLink.Code), 'Use the shipment/due date, not WorkDate, to select the version.');
        AssertTrue(not TempLink.Get(BaseLink.Code), 'Base routing links must not leak into the selected version.');
        AssertTrue(not TempLink.Get(OldLink.Code), 'Older version links must not be offered.');
        AssertTrue(not TempLink.Get(FutureLink.Code), 'Future version links must not be offered.');
        AssertTrue(not TempLink.Get(UncertifiedLink.Code), 'Uncertified version links must not be offered.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure BlankShipmentDateDoesNotSubstituteWorkDate()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        BaseLink: Record "Routing Link";
        VersionLink: Record "Routing Link";
        TempLink: Record "Routing Link" temporary;
        RoutingNo: Code[20];
    begin
        CreateRoutingFixture(SalesLine, Choice, RoutingNo, BaseLink);
        CreateRoutingVersion(RoutingNo, 'DATED', WorkDate() - 1, true, VersionLink);
        SalesLine."Shipment Date" := 0D;
        SalesLine.Modify(false);
        Mgt.GetAvailableRoutingLinks(SalesLine, TempLink);
        AssertTrue(TempLink.Get(BaseLink.Code), 'A zero due date must use the same version semantics as standard version management.');
        AssertTrue(not TempLink.Get(VersionLink.Code), 'WorkDate must not silently replace the source due date.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure TypedRoutingLinkRejectsOtherRoutingImmediately()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Link: Record "Routing Link";
        OtherLink: Record "Routing Link";
        TempConfig: Record CF_DocumentLineProductConfig temporary;
        RoutingNo: Code[20];
        OtherRoutingNo: Code[20];
    begin
        CreateRoutingFixture(SalesLine, Choice, RoutingNo, Link);
        CreateRouting(OtherRoutingNo, OtherLink);
        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        TempConfig.Validate("Choice Code", 'BLUE');
        asserterror TempConfig.Validate("Routing Link Code", OtherLink.Code);
        AssertErrorContains('does not exist on the parent item/SKU routing');
    end;

    [Test]
    [HandlerFunctions('ApplyRoutingLookupPopup,SelectParentRoutingLink')]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure RoutingLookupUpdatesAndApplyPersists()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Link: Record "Routing Link";
        OtherLink: Record "Routing Link";
        Config: Record CF_DocumentLineProductConfig;
        RoutingNo: Code[20];
        OtherRoutingNo: Code[20];
    begin
        CreateRoutingFixture(SalesLine, Choice, RoutingNo, Link);
        CreateRouting(OtherRoutingNo, OtherLink);
        ExpectedRoutingLink := Link.Code;
        Mgt.OpenConfigurator(SalesLine);
        Mgt.FilterSalesLine(SalesLine, Config);
        Config.FindFirst();
        AssertTrue(Config."Routing Link Code" = ExpectedRoutingLink, 'Apply must persist the valid parent routing link selected from the list.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure NoParentRoutingAllowsOnlyBlankLink()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
        TempLink: Record "Routing Link" temporary;
    begin
        CreateFixture(SalesLine, Choice);
        Mgt.GetAvailableRoutingLinks(SalesLine, TempLink);
        AssertTrue(TempLink.IsEmpty(), 'A parent without routing must not offer global links.');
        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        TempConfig.Validate("Routing Link Code", '');
        asserterror Mgt.LookupRoutingLink(TempConfig);
        AssertErrorContains('No routing link codes are available');
    end;

    [Test]
    [HandlerFunctions('CancelRoutingLookupPopup,CancelParentRoutingLink')]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure CancelRoutingLookupPreservesSelection()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Link: Record "Routing Link";
        TempConfig: Record CF_DocumentLineProductConfig temporary;
        Config: Record CF_DocumentLineProductConfig;
        RoutingNo: Code[20];
        SelectionId: Guid;
    begin
        CreateRoutingFixture(SalesLine, Choice, RoutingNo, Link);
        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        TempConfig.Validate("Choice Code", 'BLUE');
        TempConfig.Validate("Routing Link Code", Link.Code);
        TempConfig.Modify();
        Mgt.Save(SalesLine, TempConfig);
        Mgt.FilterSalesLine(SalesLine, Config);
        Config.FindFirst();
        SelectionId := Config.SystemId;
        ExpectedRoutingLink := Link.Code;
        Mgt.OpenConfigurator(SalesLine);
        Mgt.FilterSalesLine(SalesLine, Config);
        Config.FindFirst();
        AssertTrue(Config."Routing Link Code" = ExpectedRoutingLink, 'Canceling the routing lookup must not clear the selected link.');
        AssertTrue(Config.SystemId = SelectionId, 'Canceling the routing lookup must retain selection identity.');
    end;

    [ModalPageHandler]
    procedure CancelRoutingLookupPopup(var Configurator: TestPage CF_ProductConfigurator)
    begin
        Configurator.RoutingLinkCode.Lookup();
        Configurator.RoutingLinkCode.AssertEquals(ExpectedRoutingLink);
        Configurator.ApplyConfiguration.Invoke();
    end;

    [ModalPageHandler]
    procedure CancelParentRoutingLink(var Links: TestPage CF_ParentRoutingLinks)
    begin
        Links.Cancel().Invoke();
    end;

    [ModalPageHandler]
    procedure ApplyRoutingLookupPopup(var Configurator: TestPage CF_ProductConfigurator)
    begin
        Configurator.ChoiceCode.SetValue('BLUE');
        Configurator.RoutingLinkCode.Lookup();
        Configurator.RoutingLinkCode.AssertEquals(ExpectedRoutingLink);
        Configurator.ApplyConfiguration.Invoke();
    end;

    [ModalPageHandler]
    procedure SelectParentRoutingLink(var Links: TestPage CF_ParentRoutingLinks)
    begin
        AssertTrue(Links.First(), 'The parent routing link must be offered.');
        Links.Code.AssertEquals(ExpectedRoutingLink);
        AssertTrue(not Links.Next(), 'Unassigned global routing links must not be offered.');
        Links.First();
        Links.OK().Invoke();
    end;

    [Test]
    [HandlerFunctions('OpenRoutingDesignerFromPopup,ChooseTemplateRoutingLink,SelectParentRoutingLink')]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DesignerFromSalesUsesLockedSKUAndDateContext()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        ItemLink: Record "Routing Link";
        SKULink: Record "Routing Link";
        VersionLink: Record "Routing Link";
        OptionSetup: Record CF_ConfiguratorBOM;
        Config: Record CF_DocumentLineProductConfig;
        RoutingNo: Code[20];
        SKURoutingNo: Code[20];
    begin
        CreateRoutingFixture(SalesLine, Choice, RoutingNo, ItemLink);
        SetSalesContext(SalesLine, CopyStr(NewCode('LOC'), 1, 10), 'VAR');
        CreateRouting(SKURoutingNo, SKULink);
        CreateRoutingVersion(SKURoutingNo, 'ACTIVE', WorkDate() + 5, true, VersionLink);
        CreateSKU(SalesLine, 'VAR', SKURoutingNo);
        SetExpectedReference(SalesLine);
        ExpectedRoutingLink := VersionLink.Code;
        Mgt.OpenConfigurator(SalesLine);
        OptionSetup.Get(ExpectedCategory, 'WOOD');
        AssertTrue(OptionSetup."Routing Link Code" = ExpectedRoutingLink, 'The designer must save a default link from the sales-line SKU and effective version.');
        Mgt.FilterSalesLine(SalesLine, Config);
        AssertTrue(Config.IsEmpty(), 'Canceling the configurator must not apply selections when template setup is saved.');
    end;

    [Test]
    [HandlerFunctions('SelectParentRoutingLink')]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure StandaloneDesignerUsesReferenceSKUAndDate()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        ItemLink: Record "Routing Link";
        SKULink: Record "Routing Link";
        VersionLink: Record "Routing Link";
        OptionSetup: Record CF_ConfiguratorBOM;
        Designer: TestPage CF_CategoryTemplateDesigner;
        RoutingNo: Code[20];
        SKURoutingNo: Code[20];
    begin
        CreateRoutingFixture(SalesLine, Choice, RoutingNo, ItemLink);
        SetSalesContext(SalesLine, CopyStr(NewCode('LOC'), 1, 10), 'VAR');
        CreateRouting(SKURoutingNo, SKULink);
        CreateRoutingVersion(SKURoutingNo, 'ACTIVE', WorkDate() + 5, true, VersionLink);
        CreateSKU(SalesLine, 'VAR', SKURoutingNo);
        ExpectedRoutingLink := VersionLink.Code;
        Designer.OpenEdit();
        Designer.ItemCategoryCode.SetValue(Choice."Item Category Code");
        Designer.ReferenceItemNo.SetValue(SalesLine."No.");
        Designer.ReferenceLocationCode.SetValue(SalesLine."Location Code");
        Designer.ReferenceVariantCode.SetValue(SalesLine."Variant Code");
        Designer.ReferenceDate.SetValue(SalesLine."Shipment Date");
        Designer.Options.First();
        Designer.Options.RoutingLinkCode.Lookup();
        Designer.Options.RoutingLinkCode.AssertEquals(ExpectedRoutingLink);
        Designer.Options.SaveOption.Invoke();
        Designer.Close();
        OptionSetup.Get(Choice."Item Category Code", 'WOOD');
        AssertTrue(OptionSetup."Routing Link Code" = ExpectedRoutingLink, 'Standalone reference context must filter and persist the same eligible SKU/version link.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DesignerRoutingLookupRequiresReferenceItem()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Designer: TestPage CF_CategoryTemplateDesigner;
    begin
        CreateFixture(SalesLine, Choice);
        Designer.OpenEdit();
        Designer.ItemCategoryCode.SetValue(Choice."Item Category Code");
        Designer.Options.First();
        asserterror Designer.Options.RoutingLinkCode.Lookup();
        AssertErrorContains('Select a reference parent item and routing reference date');
        Designer.Close();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DesignerRoutingLookupRequiresReferenceDate()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Link: Record "Routing Link";
        Designer: TestPage CF_CategoryTemplateDesigner;
        RoutingNo: Code[20];
    begin
        CreateRoutingFixture(SalesLine, Choice, RoutingNo, Link);
        Designer.OpenEdit();
        Designer.ItemCategoryCode.SetValue(Choice."Item Category Code");
        Designer.ReferenceItemNo.SetValue(SalesLine."No.");
        Designer.ReferenceDate.SetValue(0D);
        Designer.Options.First();
        asserterror Designer.Options.RoutingLinkCode.Lookup();
        AssertErrorContains('Select a reference parent item and routing reference date');
        Designer.Close();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DesignerCategoryChangeClearsRoutingReference()
    var
        FirstLine: Record "Sales Line";
        SecondLine: Record "Sales Line";
        FirstChoice: Record CF_OptionChoiceLookup;
        SecondChoice: Record CF_OptionChoiceLookup;
        Designer: TestPage CF_CategoryTemplateDesigner;
    begin
        CreateFixture(FirstLine, FirstChoice);
        CreateFixture(SecondLine, SecondChoice);
        Designer.OpenEdit();
        Designer.ItemCategoryCode.SetValue(FirstChoice."Item Category Code");
        Designer.ReferenceItemNo.SetValue(FirstLine."No.");
        Designer.ItemCategoryCode.SetValue(SecondChoice."Item Category Code");
        Designer.ReferenceItemNo.AssertEquals('');
        Designer.ReferenceLocationCode.AssertEquals('');
        Designer.ReferenceVariantCode.AssertEquals('');
        Designer.Close();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DesignerRejectsTypedUnassignedRoutingLink()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Link: Record "Routing Link";
        OtherLink: Record "Routing Link";
        Designer: TestPage CF_CategoryTemplateDesigner;
        RoutingNo: Code[20];
        OtherRoutingNo: Code[20];
    begin
        CreateRoutingFixture(SalesLine, Choice, RoutingNo, Link);
        CreateRouting(OtherRoutingNo, OtherLink);
        Designer.OpenEdit();
        Designer.ItemCategoryCode.SetValue(Choice."Item Category Code");
        Designer.ReferenceItemNo.SetValue(SalesLine."No.");
        Designer.Options.First();
        asserterror Designer.Options.RoutingLinkCode.SetValue(OtherLink.Code);
        AssertErrorContains('is not assigned to the effective parent item/SKU routing');
        Designer.Close();
    end;

    [Test]
    [HandlerFunctions('CancelParentRoutingLink')]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DesignerRoutingLookupCancelPreservesDefault()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Link: Record "Routing Link";
        OptionSetup: Record CF_ConfiguratorBOM;
        Designer: TestPage CF_CategoryTemplateDesigner;
        RoutingNo: Code[20];
    begin
        CreateRoutingFixture(SalesLine, Choice, RoutingNo, Link);
        OptionSetup.Get(Choice."Item Category Code", 'WOOD');
        OptionSetup."Routing Link Code" := Link.Code;
        OptionSetup.Modify(true);
        Designer.OpenEdit();
        Designer.ItemCategoryCode.SetValue(Choice."Item Category Code");
        Designer.ReferenceItemNo.SetValue(SalesLine."No.");
        Designer.Options.First();
        Designer.Options.RoutingLinkCode.Lookup();
        Designer.Options.RoutingLinkCode.AssertEquals(Link.Code);
        Designer.Options.SaveOption.Invoke();
        Designer.Close();
        OptionSetup.Get(Choice."Item Category Code", 'WOOD');
        AssertTrue(OptionSetup."Routing Link Code" = Link.Code, 'Canceling the filtered designer lookup must retain the default.');
    end;

    [ModalPageHandler]
    procedure OpenRoutingDesignerFromPopup(var Configurator: TestPage CF_ProductConfigurator)
    begin
        Configurator.CategoryTemplateSetup.Invoke();
        Configurator.CancelConfiguration.Invoke();
    end;

    [ModalPageHandler]
    procedure ChooseTemplateRoutingLink(var Designer: TestPage CF_CategoryTemplateDesigner)
    begin
        Designer.ReferenceItemNo.AssertEquals(ExpectedReferenceItem);
        Designer.ReferenceLocationCode.AssertEquals(ExpectedReferenceLocation);
        Designer.ReferenceVariantCode.AssertEquals(ExpectedReferenceVariant);
        Designer.ReferenceDate.AssertEquals(ExpectedReferenceDate);
        AssertTrue(not Designer.ReferenceItemNo.Editable(), 'The sales-line parent reference must not be overridden.');
        AssertTrue(not Designer.ReferenceLocationCode.Editable(), 'The sales-line location reference must not be overridden.');
        AssertTrue(not Designer.ReferenceVariantCode.Editable(), 'The sales-line variant reference must not be overridden.');
        AssertTrue(not Designer.ReferenceDate.Editable(), 'The sales-line date reference must not be overridden.');
        AssertTrue(not Designer.ItemCategoryCode.Editable(), 'The sales-line designer category must match its parent.');
        Designer.Options.First();
        Designer.Options.RoutingLinkCode.Lookup();
        Designer.Options.RoutingLinkCode.AssertEquals(ExpectedRoutingLink);
        Designer.Options.SaveOption.Invoke();
        Designer.OK().Invoke();
    end;

    [ModalPageHandler]
    procedure CreateTemplateOption(var Designer: TestPage CF_CategoryTemplateDesigner)
    begin
        Designer.ItemCategoryCode.AssertEquals(ExpectedCategory);
        Designer.Options.New();
        Designer.Options.ConfigurationOption.SetValue('NUTS');
        Designer.Options.SaveOption.Invoke();
        Designer.Choices.First();
        Designer.Choices.New();
        Designer.Choices.ChoiceCode.SetValue('STANDARD');
        Designer.Choices.ItemNo.SetValue(ExpectedComponent);
        Designer.Choices.SaveChoice.Invoke();
        Designer.Options.DefaultChoiceCode.SetValue('STANDARD');
        Designer.Options.SaveOption.Invoke();
        Designer.OK().Invoke();
    end;

    [ModalPageHandler]
    procedure EmptyTemplatePopup(var Configurator: TestPage CF_ProductConfigurator)
    begin
        Configurator.ItemCategoryCode.AssertEquals(ExpectedCategory);
        AssertTrue(Configurator.TemplateMessage.Visible(), 'An empty template must display setup guidance.');
        AssertTrue(StrPos(Configurator.TemplateMessage.Value(), 'No enabled options') > 0, 'The popup must explain missing enabled options.');
        Configurator.CancelConfiguration.Invoke();
    end;

    [ModalPageHandler]
    procedure MissingCategoryPopup(var Configurator: TestPage CF_ProductConfigurator)
    begin
        Configurator.ItemCategoryCode.AssertEquals('');
        AssertTrue(Configurator.TemplateMessage.Visible(), 'A missing category must display guidance.');
        AssertTrue(StrPos(Configurator.TemplateMessage.Value(), 'no Item Category Code') > 0, 'The popup must explain the missing item category.');
        AssertTrue(not Configurator.CategoryTemplateSetup.Enabled(), 'Category setup must be disabled until the item has a category.');
        Configurator.CancelConfiguration.Invoke();
    end;

    [ModalPageHandler]
    procedure CancelPopup(var Configurator: TestPage CF_ProductConfigurator)
    begin
        Configurator.ChoiceCode.SetValue('RED');
        Configurator.QuantityPerUnit.SetValue(3);
        Configurator.CancelConfiguration.Invoke();
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MandatoryLineStyleTracksChoicePopulation()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
    begin
        CreateFixture(SalesLine, Choice);
        SetMandatoryValues(Choice, CF_MandatoryValues::ChoiceCode);
        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        AssertTrue(TempConfig.GetStyleText() = 'Unfavorable', 'A blank mandatory choice must be red.');
        TempConfig.Validate("Choice Code", 'BLUE');
        AssertTrue(TempConfig.GetStyleText() = 'Favorable', 'A populated mandatory choice must be green.');
        TempConfig.Validate("Choice Code", '');
        AssertTrue(TempConfig.GetStyleText() = 'Unfavorable', 'Clearing a mandatory choice must restore red styling.');
        SetMandatoryValues(Choice, CF_MandatoryValues::None);
        AssertTrue(TempConfig.GetStyleText() = 'Standard', 'Changing the mandatory values to None must use current setup without reloading the selection.');
        SetMandatoryValues(Choice, CF_MandatoryValues::ChoiceCode);
        AssertTrue(TempConfig.GetStyleText() = 'Unfavorable', 'Restoring mandatory Choice Code must restore red styling for a blank choice.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure OptionalLineStyleRemainsStandard()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
    begin
        CreateFixture(SalesLine, Choice);
        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        AssertTrue(TempConfig.GetStyleText() = 'Standard', 'A blank optional choice must retain normal styling.');
        TempConfig.Validate("Choice Code", 'BLUE');
        AssertTrue(TempConfig.GetStyleText() = 'Standard', 'A populated optional choice must retain normal styling.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure DisabledMandatoryLineStyleRemainsStandard()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        OptionSetup: Record CF_ConfiguratorBOM;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
    begin
        CreateFixture(SalesLine, Choice);
        SaveChoice(SalesLine, 'BLUE');
        SetMandatoryValues(Choice, CF_MandatoryValues::ChoiceCode);
        OptionSetup.Get(Choice."Item Category Code", 'WOOD');
        OptionSetup.Enabled := false;
        OptionSetup.Modify(true);
        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        AssertTrue(TempConfig.GetStyleText() = 'Standard', 'An obsolete disabled option must not be marked as a current mandatory choice.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MandatoryDefaultLineStyleIsFavorable()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
    begin
        CreateFixture(SalesLine, Choice);
        SetDefault(Choice, 'BLUE');
        SetMandatoryValues(Choice, CF_MandatoryValues::ChoiceCodeAndQuantity);
        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        AssertTrue(TempConfig.GetStyleText() = 'Favorable', 'A mandatory preselected default must be green before Apply.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure LineStylesIndependentAcrossOptions()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        OtherChoice: Record CF_OptionChoiceLookup;
        TempConfig: Record CF_DocumentLineProductConfig temporary;
    begin
        CreateFixture(SalesLine, Choice);
        AddOptionWithDefault(Choice, 'OTHER', OtherChoice);
        SetMandatoryValues(OtherChoice, CF_MandatoryValues::ChoiceCode);
        Mgt.Load(SalesLine, TempConfig);
        TempConfig.Get(Enum::CF_ConfigDocumentType::SalesOrder, Database::"Sales Line", SalesLine.SystemId, 'OTHER');
        AssertTrue(TempConfig.GetStyleText() = 'Favorable', 'A populated mandatory row must be green.');
        GetWood(SalesLine, TempConfig);
        AssertTrue(TempConfig.GetStyleText() = 'Standard', 'An optional row must not inherit the preceding mandatory row style.');
        TempConfig.Get(Enum::CF_ConfigDocumentType::SalesOrder, Database::"Sales Line", SalesLine.SystemId, 'OTHER');
        TempConfig.Validate("Choice Code", '');
        AssertTrue(TempConfig.GetStyleText() = 'Unfavorable', 'A cleared mandatory row must be red.');
        GetWood(SalesLine, TempConfig);
        AssertTrue(TempConfig.GetStyleText() = 'Standard', 'An optional row must not inherit red styling either.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ComponentValidationAcceptsNonInventory()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Component: Record Item;
    begin
        CreateFixture(SalesLine, Choice);
        Component.Get(Choice."Item No.");
        Component.Type := Component.Type::"Non-Inventory";
        Component.Modify(false);

        Mgt.ValidateItem(Component."No.", '', Choice."Unit of Measure Code");
        Choice.Validate("Item No.", Component."No.");
        Choice.Modify(true);
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ComponentValidationRejectsService()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Component: Record Item;
    begin
        CreateFixture(SalesLine, Choice);
        Component.Get(Choice."Item No.");
        Component.Type := Component.Type::Service;
        Component.Modify(false);

        asserterror Mgt.ValidateItem(Component."No.", '', Choice."Unit of Measure Code");
        AssertErrorContains('must be an inventory or non-inventory item');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure BOMRootStillRequiresInventory()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        ParentItem: Record Item;
        Rows: Record CF_BOMBuffer temporary;
        DraftMgt: Codeunit CF_BOMDraftMgt;
        Tree: Codeunit CF_BOMTreeMgt;
    begin
        CreateFixture(SalesLine, Choice);
        ParentItem.Get(SalesLine."No.");
        ParentItem.Type := ParentItem.Type::"Non-Inventory";
        ParentItem.Modify(false);
        Rows."Source Line ID" := SalesLine.SystemId;
        Rows."Node ID" := CreateGuid();
        Rows.Type := Rows.Type::Item;
        Rows."No." := SalesLine."No.";
        Rows."Unit of Measure Code" := SalesLine."Unit of Measure Code";
        Rows."Quantity per" := 1;
        Rows."Sort Order" := 10000;
        Rows."Source Context" := Tree.Context(SalesLine);
        Rows.Insert(false);

        asserterror DraftMgt.ValidateTree(SalesLine, Rows);
        AssertErrorContains('Inventory');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure AvailabilityPreviewIncludesUnappliedChoices()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig temporary;
        Rows: Record CF_BOMBuffer temporary;
        Stored: Record CF_DocumentLineProductConfig;
        DraftMgt: Codeunit CF_BOMDraftMgt;
    begin
        CreateFixture(SalesLine, Choice);
        Mgt.Load(SalesLine, Config);
        GetWood(SalesLine, Config);
        Config.Validate("Choice Code", Choice.Code);
        Config.Validate("Quantity per Unit", 2);
        Config.Modify(false);

        DraftMgt.GetPreview(SalesLine, Config, Rows);
        Rows.SetRange("Choice Root", true);
        Rows.FindFirst();
        AssertTrue(Rows."No." = Choice."Item No.", 'Availability must use the current unapplied component.');
        AssertTrue(Rows."Quantity per" = 2, 'Availability must use the current unapplied quantity.');
        Mgt.FilterSalesLine(SalesLine, Stored);
        AssertTrue(Stored.IsEmpty(), 'Opening availability must not apply choices.');
        AssertTrue(not DraftMgt.HasSaved(SalesLine.SystemId), 'Opening availability must not create a saved draft.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure PromisingContextFreezesItsBOM()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Config: Record CF_DocumentLineProductConfig temporary;
        Rows: Record CF_BOMBuffer temporary;
        Frozen: Record CF_BOMBuffer temporary;
        DraftMgt: Codeunit CF_BOMDraftMgt;
        PlanMgt: Codeunit CF_PromisePlanMgt;
        ContextId: Guid;
    begin
        CreateFixture(SalesLine, Choice);
        Mgt.Load(SalesLine, Config);
        GetWood(SalesLine, Config);
        Config.Validate("Choice Code", Choice.Code);
        Config.Validate("Quantity per Unit", 2);
        Config.Modify(false);
        DraftMgt.GetPreview(SalesLine, Config, Rows);
        ContextId := CreateGuid();
        PlanMgt.StoreContext(ContextId, SalesLine, Rows);
        Rows.SetRange("Choice Root", true);
        Rows.FindFirst();
        Rows."Quantity per" := 9;
        Rows.Modify(false);

        PlanMgt.ReadContext(ContextId, Frozen);
        Frozen.SetRange("Choice Root", true);
        Frozen.FindFirst();
        AssertTrue(Frozen."Quantity per" = 2, 'Accepted planning must retain its own immutable structure.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure ConfiguredPlanningExplodesChoicesWithoutBaseBOM()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Item: Record Item;
        Config: Record CF_DocumentLineProductConfig temporary;
        Rows: Record CF_BOMBuffer temporary;
        ReqLine: Record "Requisition Line";
        Component: Record "Planning Component";
        DraftMgt: Codeunit CF_BOMDraftMgt;
        PlanMgt: Codeunit CF_PromisePlanMgt;
        LineMgt: Codeunit "Planning Line Management";
        ContextId: Guid;
    begin
        CreateFixture(SalesLine, Choice);
        Item.Get(SalesLine."No.");
        Item."Replenishment System" := Item."Replenishment System"::"Prod. Order";
        Item.Modify(false);
        Mgt.Load(SalesLine, Config);
        GetWood(SalesLine, Config);
        Config.Validate("Choice Code", Choice.Code);
        Config.Validate("Quantity per Unit", 2);
        Config.Modify(false);
        DraftMgt.GetPreview(SalesLine, Config, Rows);
        ContextId := CreateGuid();
        PlanMgt.StoreContext(ContextId, SalesLine, Rows);
        Rows.Reset();
        Rows.SetRange(Indentation, 0);
        Rows.FindFirst();
        ReqLine."Line No." := 10000;
        ReqLine.Type := ReqLine.Type::Item;
        ReqLine.Validate("No.", Item."No.");
        ReqLine.Validate("Unit of Measure Code", Choice."Unit of Measure Code");
        ReqLine."Action Message" := ReqLine."Action Message"::New;
        ReqLine.Validate(Quantity, 3);
        ReqLine."Starting Date" := WorkDate();
        ReqLine."Ending Date" := WorkDate();
        ReqLine."Due Date" := WorkDate();
        ReqLine.CF_PromiseContextId := ContextId;
        ReqLine.CF_BOMNodeId := Rows."Node ID";
        ReqLine.Insert(false);

        LineMgt.Calculate(ReqLine, 0, false, true, 0);
        Component.SetRange("Worksheet Template Name", ReqLine."Worksheet Template Name");
        Component.SetRange("Worksheet Batch Name", ReqLine."Journal Batch Name");
        Component.SetRange("Worksheet Line No.", ReqLine."Line No.");
        AssertTrue(Component.Count() = 1, 'Planning must generate the selected component even with no base BOM.');
        Component.FindFirst();
        AssertTrue(Component."Item No." = Choice."Item No.", 'Planning must not fall back to the item master BOM.');
        AssertTrue(Component."Expected Quantity" = 6, 'Two components per finished unit and three finished units must require six components.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MaterialShortageUsesUnappliedQuantityAndSelectsAll()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Rows: Record CF_BOMBuffer temporary;
        Lines: Record CF_MaterialSupplyLine temporary;
        SupplyMgt: Codeunit CF_MaterialSupplyMgt;
    begin
        CreateMaterialFixture(SalesLine, Choice, Rows);
        SupplyMgt.Calculate(SalesLine, Rows, CF_MaterialReceiptPolicy::OnTime, Lines);
        Lines.SetRange("Item No.", Choice."Item No.");
        Lines.FindFirst();
        AssertTrue(Lines."Required Quantity" = 6, 'Three outputs at two components per unit must require six base units.');
        AssertTrue(Lines."Shortage Quantity" = 6, 'Without inventory or receipts, all six units must be shortages.');
        AssertTrue(Lines.Selected, 'Every shortage must be selected by default.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MaterialReceiptPolicyControlsLatePurchaseCoverage()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Rows: Record CF_BOMBuffer temporary;
        Lines: Record CF_MaterialSupplyLine temporary;
        PurchaseLine: Record "Purchase Line";
        SupplyMgt: Codeunit CF_MaterialSupplyMgt;
    begin
        CreateMaterialFixture(SalesLine, Choice, Rows);
        Rows.SetRange("No.", Choice."Item No.");
        Rows.FindFirst();
        PurchaseLine."Document Type" := PurchaseLine."Document Type"::Order;
        PurchaseLine."Document No." := NewCode('PO');
        PurchaseLine."Line No." := 10000;
        PurchaseLine.Type := PurchaseLine.Type::Item;
        PurchaseLine."No." := Choice."Item No.";
        PurchaseLine."Location Code" := Rows."Location Code";
        PurchaseLine."Outstanding Qty. (Base)" := 5;
        PurchaseLine."Expected Receipt Date" := WorkDate() + 10;
        PurchaseLine.Insert(false);

        SupplyMgt.Calculate(SalesLine, Rows, CF_MaterialReceiptPolicy::OnTime, Lines);
        Lines.SetRange("Item No.", Choice."Item No.");
        Lines.FindFirst();
        AssertTrue(Lines."Shortage Quantity" = 6, 'Late receipts must not cover on-time demand.');
        SupplyMgt.Calculate(SalesLine, Rows, CF_MaterialReceiptPolicy::AllReceipts, Lines);
        Lines.SetRange("Item No.", Choice."Item No.");
        Lines.FindFirst();
        AssertTrue(Lines."Shortage Quantity" = 1, 'Five late purchase units must cover five of the six units under All Receipts.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MaterialSupplyDoesNotPurchaseTheConfiguredFinishedItem()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Rows: Record CF_BOMBuffer temporary;
        Lines: Record CF_MaterialSupplyLine temporary;
        Item: Record Item;
        SupplyMgt: Codeunit CF_MaterialSupplyMgt;
    begin
        CreateMaterialFixture(SalesLine, Choice, Rows);
        Item.Get(SalesLine."No.");
        Item."Replenishment System" := Item."Replenishment System"::Purchase;
        Item.Modify(false);
        SupplyMgt.Calculate(SalesLine, Rows, CF_MaterialReceiptPolicy::OnTime, Lines);
        Lines.SetRange("Item No.", SalesLine."No.");
        Lines.FindFirst();
        AssertTrue(Lines."Replenishment System" = Lines."Replenishment System"::"Prod. Order", 'The finished root is the configured production output, not a material purchase.');
        Lines.SetRange("Item No.", Choice."Item No.");
        Lines.FindFirst();
        AssertTrue(Lines."Shortage Quantity" = 6, 'Material planning must still explode the configured output when its default supply method is Purchase.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MaterialDemandNetsFinishedItemStockFirst()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Rows: Record CF_BOMBuffer temporary;
        Lines: Record CF_MaterialSupplyLine temporary;
        SupplyMgt: Codeunit CF_MaterialSupplyMgt;
    begin
        CreateMaterialFixture(SalesLine, Choice, Rows);
        AddMaterialStock(SalesLine."No.", SalesLine."Location Code", 2);
        SupplyMgt.Calculate(SalesLine, Rows, CF_MaterialReceiptPolicy::OnTime, Lines);
        Lines.SetRange("Item No.", Choice."Item No.");
        Lines.FindFirst();
        AssertTrue(Lines."Required Quantity" = 2, 'Two finished units in stock must leave only one output requiring two raw-material units.');
        AssertTrue(Lines."Shortage Quantity" = 2, 'Procurement must cover net new production rather than the full sales quantity.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MaterialSupplyUsesTransferSKUDefaults()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Rows: Record CF_BOMBuffer temporary;
        Lines: Record CF_MaterialSupplyLine temporary;
        Item: Record Item;
        SKU: Record "Stockkeeping Unit";
        Location: Record Location;
        SupplyMgt: Codeunit CF_MaterialSupplyMgt;
    begin
        CreateMaterialFixture(SalesLine, Choice, Rows);
        Rows.SetRange("No.", Choice."Item No.");
        Rows.FindFirst();
        Location.Code := CopyStr(NewCode('FROM'), 1, MaxStrLen(Location.Code));
        Location.Insert(false);
        Item.Get(Choice."Item No.");
        SKU.CopyFromItem(Item);
        SKU."Item No." := Item."No.";
        SKU."Location Code" := Rows."Location Code";
        SKU."Replenishment System" := SKU."Replenishment System"::Transfer;
        SKU."Transfer-from Code" := Location.Code;
        SKU.Insert(false);

        SupplyMgt.Calculate(SalesLine, Rows, CF_MaterialReceiptPolicy::OnTime, Lines);
        Lines.SetRange("Item No.", Choice."Item No.");
        Lines.FindFirst();
        AssertTrue(Lines."Replenishment System" = Lines."Replenishment System"::Transfer, 'The effective SKU must override Item purchase replenishment.');
        AssertTrue(Lines."Transfer-from Code" = Location.Code, 'The review must default the SKU transfer source.');
        AssertTrue(Lines."Shortage Quantity" = 6, 'Changing supply method must not change the required base quantity.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MaterialOccurrencesCannotReuseTheSameStock()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Rows: Record CF_BOMBuffer temporary;
        Lines: Record CF_MaterialSupplyLine temporary;
        SupplyMgt: Codeunit CF_MaterialSupplyMgt;
    begin
        CreateMaterialFixture(SalesLine, Choice, Rows);
        Rows.SetRange("No.", Choice."Item No.");
        Rows.FindFirst();
        AddMaterialStock(Choice."Item No.", Rows."Location Code", 7);
        Rows."Node ID" := CreateGuid();
        Rows."Sort Order" += 100000;
        Rows.Insert(false);

        SupplyMgt.Calculate(SalesLine, Rows, CF_MaterialReceiptPolicy::OnTime, Lines);
        Lines.SetRange("Item No.", Choice."Item No.");
        AssertTrue(Lines.Count() = 2, 'Repeated item occurrences must retain their own identities.');
        Lines.CalcSums("Required Quantity", "Covered Quantity", "Shortage Quantity");
        AssertTrue(Lines."Required Quantity" = 12, 'Two occurrences must require twelve base units.');
        AssertTrue(Lines."Covered Quantity" = 7, 'Seven existing units must be allocated only once.');
        AssertTrue(Lines."Shortage Quantity" = 5, 'The total purchase shortage must be exactly five.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MaterialDemandDoesNotTreatReservedProposalAsActualSupply()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Rows: Record CF_BOMBuffer temporary;
        Lines: Record CF_MaterialSupplyLine temporary;
        Reservation: Record "Reservation Entry";
        SupplyMgt: Codeunit CF_MaterialSupplyMgt;
        EntryNo: Integer;
    begin
        CreateMaterialFixture(SalesLine, Choice, Rows);
        if Reservation.FindLast() then
            EntryNo := Reservation."Entry No.";
        Reservation.Init();
        Reservation."Entry No." := EntryNo + 1;
        Reservation.Positive := false;
        Reservation."Reservation Status" := Reservation."Reservation Status"::Reservation;
        Reservation."Item No." := SalesLine."No.";
        Reservation."Location Code" := SalesLine."Location Code";
        Reservation."Source Type" := Database::"Sales Line";
        Reservation."Source Subtype" := SalesLine."Document Type".AsInteger();
        Reservation."Source ID" := SalesLine."Document No.";
        Reservation."Source Ref. No." := SalesLine."Line No.";
        Reservation."Shipment Date" := WorkDate();
        Reservation."Expected Receipt Date" := WorkDate();
        Reservation.Quantity := -3;
        Reservation."Quantity (Base)" := -3;
        Reservation."Qty. per Unit of Measure" := 1;
        Reservation.Insert(false);
        Reservation.Positive := true;
        Reservation."Source Type" := Database::"Requisition Line";
        Reservation."Source Subtype" := 0;
        Reservation."Source ID" := '';
        Reservation."Source Ref. No." := 10000;
        Reservation.Quantity := 3;
        Reservation."Quantity (Base)" := 3;
        Reservation.Insert(false);

        SupplyMgt.Calculate(SalesLine, Rows, CF_MaterialReceiptPolicy::OnTime, Lines);
        Lines.SetRange("Item No.", Choice."Item No.");
        Lines.FindFirst();
        AssertTrue(Lines."Required Quantity" = 6, 'A reservation to an unconverted requisition proposal must not suppress production/material demand.');
        AssertTrue(Lines."Shortage Quantity" = 6, 'A proposal reservation is not inventory or an actual purchase/transfer order.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MaterialReviewRequiresSelectionAndVendor()
    var
        Lines: Record CF_MaterialSupplyLine temporary;
        SupplyMgt: Codeunit CF_MaterialSupplyMgt;
    begin
        Lines."Node ID" := CreateGuid();
        Lines."Shortage Quantity" := 1;
        Lines."Required Date" := WorkDate();
        Lines.Selected := false;
        Lines.Insert();
        asserterror SupplyMgt.CheckSelected(Lines);
        AssertErrorContains('Select at least one material shortage');
        Lines.Selected := true;
        Lines.Modify();
        asserterror SupplyMgt.CheckSelected(Lines);
        AssertErrorContains('Vendor No.');
    end;

    [Test]
    [TransactionModel(TransactionModel::AutoRollback)]
    procedure MaterialDemandNetsSubassemblyStockBeforeLeafMaterials()
    var
        SalesLine: Record "Sales Line";
        Choice: Record CF_OptionChoiceLookup;
        Rows: Record CF_BOMBuffer temporary;
        Lines: Record CF_MaterialSupplyLine temporary;
        Subassembly: Record Item;
        Material: Record Item;
        SupplyMgt: Codeunit CF_MaterialSupplyMgt;
        ParentId: Guid;
    begin
        CreateMaterialFixture(SalesLine, Choice, Rows);
        Rows.SetRange("No.", Choice."Item No.");
        Rows.FindFirst();
        ParentId := Rows."Node ID";
        Subassembly.Get(Choice."Item No.");
        Subassembly."Replenishment System" := Subassembly."Replenishment System"::"Prod. Order";
        Evaluate(Subassembly."Safety Lead Time", '<0D>');
        Subassembly.Modify(false);
        AddMaterialStock(Subassembly."No.", Rows."Location Code", 4);
        CreateItem(Material, '', Choice."Unit of Measure Code");
        Rows."Node ID" := CreateGuid();
        Rows."Parent Node ID" := ParentId;
        Rows."No." := Material."No.";
        Rows."Quantity per" := 3;
        Rows.Indentation += 1;
        Rows."Sort Order" += 100000;
        Rows."Choice Root" := false;
        Rows.Insert(false);

        SupplyMgt.Calculate(SalesLine, Rows, CF_MaterialReceiptPolicy::OnTime, Lines);
        Lines.SetRange("Item No.", Subassembly."No.");
        Lines.FindFirst();
        AssertTrue(Lines."Required Quantity" = 6, 'The output requires six subassemblies.');
        AssertTrue(Lines."Shortage Quantity" = 2, 'Four stocked subassemblies must reduce new subassembly production to two.');
        Lines.SetRange("Item No.", Material."No.");
        Lines.FindFirst();
        AssertTrue(Lines."Required Quantity" = 6, 'Two new subassemblies at three components each must require six raw units, not eighteen.');
        AssertTrue(Lines."Shortage Quantity" = 6, 'Only the net manufactured subassembly demand may be purchased.');
    end;

    local procedure CreateMaterialFixture(var SalesLine: Record "Sales Line"; var Choice: Record CF_OptionChoiceLookup; var Rows: Record CF_BOMBuffer temporary)
    var
        Item: Record Item;
        Config: Record CF_DocumentLineProductConfig temporary;
        DraftMgt: Codeunit CF_BOMDraftMgt;
    begin
        CreateFixture(SalesLine, Choice);
        Item.Get(SalesLine."No.");
        Item."Replenishment System" := Item."Replenishment System"::"Prod. Order";
        Evaluate(Item."Safety Lead Time", '<0D>');
        Item.Modify(false);
        SalesLine.Quantity := 3;
        SalesLine."Quantity (Base)" := 3;
        SalesLine."Outstanding Quantity" := 3;
        SalesLine."Outstanding Qty. (Base)" := 3;
        SalesLine."Qty. per Unit of Measure" := 1;
        SalesLine."Shipment Date" := WorkDate();
        SalesLine.Modify(false);
        Mgt.Load(SalesLine, Config);
        GetWood(SalesLine, Config);
        Config.Validate("Choice Code", Choice.Code);
        Config.Validate("Quantity per Unit", 2);
        Config.Modify(false);
        DraftMgt.GetPreview(SalesLine, Config, Rows);
    end;

    local procedure AddMaterialStock(ItemNo: Code[20]; LocationCode: Code[10]; Quantity: Decimal)
    var
        Entry: Record "Item Ledger Entry";
        EntryNo: Integer;
    begin
        if Entry.FindLast() then
            EntryNo := Entry."Entry No.";
        Entry.Init();
        Entry."Entry No." := EntryNo + 1;
        Entry."Item No." := ItemNo;
        Entry."Location Code" := LocationCode;
        Entry."Posting Date" := WorkDate();
        Entry."Entry Type" := Entry."Entry Type"::"Positive Adjmt.";
        Entry.Quantity := Quantity;
        Entry."Remaining Quantity" := Quantity;
        Entry.Positive := true;
        Entry.Open := true;
        Entry.Insert(false);
    end;

    local procedure SetMandatoryValues(Choice: Record CF_OptionChoiceLookup; MandatoryValues: Enum CF_MandatoryValues)
    var
        OptionSetup: Record CF_ConfiguratorBOM;
    begin
        OptionSetup.Get(Choice."Item Category Code", Choice."Configuration Option");
        OptionSetup.Validate("Mandatory Values", MandatoryValues);
        OptionSetup.Modify(true);
    end;

    local procedure CreateFixture(var SalesLine: Record "Sales Line"; var Choice: Record CF_OptionChoiceLookup)
    var
        Category: Record "Item Category";
        ParentItem: Record Item;
        ComponentItem: Record Item;
        UOM: Record "Unit of Measure";
        SalesHeader: Record "Sales Header";
        OptionSetup: Record CF_ConfiguratorBOM;
        UOMCode: Code[10];
    begin
        Category.Code := NewCode('CAT');
        Category.Insert(false);
        UOMCode := CopyStr(NewCode('EA'), 1, MaxStrLen(UOMCode));
        UOM.Code := UOMCode;
        UOM.Insert(false);
        CreateItem(ParentItem, Category.Code, UOMCode);
        CreateItem(ComponentItem, '', UOMCode);
        SalesHeader."Document Type" := SalesHeader."Document Type"::Order;
        SalesHeader."No." := NewCode('SO');
        SalesHeader.Insert(false);
        SalesLine."Document Type" := SalesLine."Document Type"::Order;
        SalesLine."Document No." := SalesHeader."No.";
        SalesLine."Line No." := 10000;
        SalesLine.Type := SalesLine.Type::Item;
        SalesLine."No." := ParentItem."No.";
        SalesLine."Item Category Code" := Category.Code;
        SalesLine."Unit of Measure Code" := UOMCode;
        SalesLine.Insert(false);
        OptionSetup."Item Category Code" := Category.Code;
        OptionSetup."Configuration Option" := 'WOOD';
        OptionSetup."Option Description" := 'Wood finish';
        OptionSetup."Quantity per Unit" := 1;
        OptionSetup."Mandatory Values" := CF_MandatoryValues::None;
        OptionSetup.Enabled := true;
        OptionSetup.Insert(true);
        Choice."Item Category Code" := Category.Code;
        Choice."Configuration Option" := 'WOOD';
        Choice.Code := 'BLUE';
        Choice.Validate("Item No.", ComponentItem."No.");
        Choice.Selectable := true;
        Choice.Insert(true);
    end;

    local procedure CreateItem(var Item: Record Item; CategoryCode: Code[20]; UOMCode: Code[10])
    var
        ItemUOM: Record "Item Unit of Measure";
    begin
        Item.Init();
        Item."No." := NewCode('ITEM');
        Item.Type := Item.Type::Inventory;
        Item."Item Category Code" := CategoryCode;
        Item."Base Unit of Measure" := UOMCode;
        Item.Insert(false);
        ItemUOM."Item No." := Item."No.";
        ItemUOM.Code := UOMCode;
        ItemUOM."Qty. per Unit of Measure" := 1;
        ItemUOM.Insert(false);
    end;

    local procedure AddRedChoice(BlueChoice: Record CF_OptionChoiceLookup; var RedChoice: Record CF_OptionChoiceLookup)
    var
        RedItem: Record Item;
    begin
        CreateItem(RedItem, '', BlueChoice."Unit of Measure Code");
        RedChoice := BlueChoice;
        RedChoice.Code := 'RED';
        RedChoice.Validate("Item No.", RedItem."No.");
        Clear(RedChoice.SystemId);
        RedChoice.Insert(true);
    end;

    local procedure SetDefault(Choice: Record CF_OptionChoiceLookup; ChoiceCode: Code[20])
    var
        OptionSetup: Record CF_ConfiguratorBOM;
    begin
        OptionSetup.Get(Choice."Item Category Code", Choice."Configuration Option");
        OptionSetup.Validate("Default Choice Code", ChoiceCode);
        OptionSetup.Modify(true);
    end;

    local procedure CreateRoutingFixture(var SalesLine: Record "Sales Line"; var Choice: Record CF_OptionChoiceLookup; var RoutingNo: Code[20]; var Link: Record "Routing Link")
    var
        Item: Record Item;
    begin
        CreateFixture(SalesLine, Choice);
        CreateRouting(RoutingNo, Link);
        Item.Get(SalesLine."No.");
        Item."Routing No." := RoutingNo;
        Item.Modify(false);
        SalesLine."Shipment Date" := WorkDate() + 10;
        SalesLine.Modify(false);
    end;

    local procedure SetExpectedReference(SalesLine: Record "Sales Line")
    var
        Item: Record Item;
    begin
        Item.Get(SalesLine."No.");
        ExpectedCategory := Item."Item Category Code";
        ExpectedReferenceItem := SalesLine."No.";
        ExpectedReferenceLocation := SalesLine."Location Code";
        ExpectedReferenceVariant := SalesLine."Variant Code";
        ExpectedReferenceDate := SalesLine."Shipment Date";
    end;

    local procedure CreateRouting(var RoutingNo: Code[20]; var Link: Record "Routing Link")
    var
        Header: Record "Routing Header";
    begin
        RoutingNo := NewCode('RTG');
        Header."No." := RoutingNo;
        Header.Status := Header.Status::Certified;
        Header.Insert(false);
        CreateRoutingLink(Link);
        AddRoutingOperation(RoutingNo, '', '10', Link.Code);
    end;

    local procedure CreateRoutingLink(var Link: Record "Routing Link")
    begin
        Link.Init();
        Link.Code := CopyStr(NewCode('L'), 1, MaxStrLen(Link.Code));
        Link.Description := 'Test parent routing link';
        Link.Insert(false);
    end;

    local procedure AddRoutingOperation(RoutingNo: Code[20]; VersionCode: Code[20]; OperationNo: Code[10]; LinkCode: Code[10])
    var
        RoutingLine: Record "Routing Line";
    begin
        RoutingLine."Routing No." := RoutingNo;
        RoutingLine."Version Code" := VersionCode;
        RoutingLine."Operation No." := OperationNo;
        RoutingLine."Routing Link Code" := LinkCode;
        RoutingLine.Insert(false);
    end;

    local procedure CreateRoutingVersion(RoutingNo: Code[20]; VersionCode: Code[20]; StartingDate: Date; Certified: Boolean; var Link: Record "Routing Link")
    var
        Version: Record "Routing Version";
    begin
        Version."Routing No." := RoutingNo;
        Version."Version Code" := VersionCode;
        Version."Starting Date" := StartingDate;
        if Certified then
            Version.Status := Version.Status::Certified;
        Version.Insert(false);
        CreateRoutingLink(Link);
        AddRoutingOperation(RoutingNo, VersionCode, '10', Link.Code);
    end;

    local procedure SetSalesContext(var SalesLine: Record "Sales Line"; LocationCode: Code[10]; VariantCode: Code[10])
    var
        Location: Record Location;
        Variant: Record "Item Variant";
    begin
        if LocationCode <> '' then begin
            Location.Code := LocationCode;
            Location.Insert(false);
        end;
        if VariantCode <> '' then begin
            Variant."Item No." := SalesLine."No.";
            Variant.Code := VariantCode;
            Variant.Insert(false);
        end;
        SalesLine."Location Code" := LocationCode;
        SalesLine."Variant Code" := VariantCode;
        SalesLine.Modify(false);
    end;

    local procedure CreateSKU(SalesLine: Record "Sales Line"; VariantCode: Code[10]; RoutingNo: Code[20])
    var
        SKU: Record "Stockkeeping Unit";
    begin
        SKU."Item No." := SalesLine."No.";
        SKU."Location Code" := SalesLine."Location Code";
        SKU."Variant Code" := VariantCode;
        SKU."Routing No." := RoutingNo;
        SKU.Insert(false);
    end;

    local procedure AddOptionWithDefault(ExistingChoice: Record CF_OptionChoiceLookup; OptionCode: Code[10]; var NewChoice: Record CF_OptionChoiceLookup)
    var
        OptionSetup: Record CF_ConfiguratorBOM;
    begin
        OptionSetup."Item Category Code" := ExistingChoice."Item Category Code";
        OptionSetup."Configuration Option" := OptionCode;
        OptionSetup.Insert(true);
        NewChoice := ExistingChoice;
        NewChoice."Configuration Option" := OptionCode;
        NewChoice.Code := 'DEFAULT';
        Clear(NewChoice.SystemId);
        NewChoice.Insert(true);
        SetDefault(NewChoice, NewChoice.Code);
    end;

    local procedure CopyLine(SourceLine: Record "Sales Line"; var DestinationLine: Record "Sales Line")
    begin
        DestinationLine.TransferFields(SourceLine);
        DestinationLine."Line No." := SourceLine."Line No." + 10000;
        Clear(DestinationLine.SystemId);
        DestinationLine.Insert(false);
    end;

    local procedure CreateLinkedOrder(SalesLine: Record "Sales Line")
    var
        ProductionOrder: Record "Production Order";
    begin
        ProductionOrder.Status := ProductionOrder.Status::"Firm Planned";
        ProductionOrder."No." := NewCode('PROD');
        ProductionOrder."Source Type" := ProductionOrder."Source Type"::Item;
        ProductionOrder."Source No." := SalesLine."No.";
        ProductionOrder.CF_DocumentType := CF_ConfigDocumentType::SalesOrder;
        ProductionOrder.CF_SourceTableId := Database::"Sales Line";
        ProductionOrder.CF_SourceLineId := SalesLine.SystemId;
        ProductionOrder.CF_DocumentNo := SalesLine."Document No.";
        ProductionOrder.CF_DocumentLineNo := SalesLine."Line No.";
        ProductionOrder.CF_ParentItemNo := SalesLine."No.";
        ProductionOrder.CF_ConfigVersion := 1;
        ProductionOrder.Insert(false);
    end;

    local procedure SaveChoice(SalesLine: Record "Sales Line"; ChoiceCode: Code[20])
    var
        TempConfig: Record CF_DocumentLineProductConfig temporary;
    begin
        Mgt.Load(SalesLine, TempConfig);
        GetWood(SalesLine, TempConfig);
        TempConfig.Validate("Choice Code", ChoiceCode);
        TempConfig.Modify();
        Mgt.Save(SalesLine, TempConfig);
    end;

    local procedure GetWood(SalesLine: Record "Sales Line"; var TempConfig: Record CF_DocumentLineProductConfig temporary)
    begin
        TempConfig.Get(CF_ConfigDocumentType::SalesOrder, Database::"Sales Line", SalesLine.SystemId, 'WOOD');
    end;

    local procedure NewCode(Prefix: Text): Code[20]
    begin
        exit(CopyStr(Prefix + DelChr(Format(CreateGuid()), '=', '{}-'), 1, 20));
    end;

    local procedure AssertErrorContains(ExpectedText: Text)
    begin
        if StrPos(GetLastErrorText(), ExpectedText) = 0 then
            Error('Expected error containing "%1", received "%2".', ExpectedText, GetLastErrorText());
    end;

    local procedure AssertTrue(Condition: Boolean; FailureMessage: Text)
    begin
        if not Condition then
            Error(FailureMessage);
    end;

    var
        Mgt: Codeunit CF_DocumentConfigMgt;
        ExpectedCategory: Code[20];
        ExpectedComponent: Code[20];
        ExpectedRoutingLink: Code[10];
        ExpectedReferenceItem: Code[20];
        ExpectedReferenceLocation: Code[10];
        ExpectedReferenceVariant: Code[10];
        ExpectedReferenceDate: Date;
}
