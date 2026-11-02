namespace CloudFactory.SalesConfigurator;

using Microsoft.Foundation.NoSeries;
using Microsoft.Inventory.Item;
using Microsoft.Sales.Document;

table 91003 CF_ProductConfigHeader
{
    Caption = 'Product Configuration Header';
    DataClassification = CustomerContent;
    LookupPageId = CF_ProductConfigurations;
    DrillDownPageId = CF_ProductConfigurations;
    fields
    {
        field(1; "No."; Code[100]) { Caption = 'Configuration No.'; Editable = false; }
        field(2; "Document Type"; Enum CF_ConfigDocumentType) { Caption = 'Document Type'; Editable = false; }
        field(3; "Source Table ID"; Integer) { Caption = 'Source Table ID'; Editable = false; }
        field(4; "Source Line SystemId"; Guid) { Caption = 'Source Line SystemId'; Editable = false; }
        field(5; "Document No."; Code[20]) { Caption = 'Document No.'; Editable = false; }
        field(6; "Document Line No."; Integer) { Caption = 'Document Line No.'; Editable = false; }
        field(7; "Item Category Code"; Code[20]) { Caption = 'Item Category Code'; Editable = false; TableRelation = "Item Category"; }
        field(8; "Parent Item No."; Code[20]) { Caption = 'Parent Item No.'; Editable = false; TableRelation = Item; }
        field(9; "Parent Variant Code"; Code[10]) { Caption = 'Parent Variant Code'; Editable = false; }
        field(10; "No. Series"; Code[20]) { Caption = 'No. Series (Legacy)'; Editable = false; TableRelation = "No. Series"; }
        field(11; "Saved Options"; Integer)
        {
            Caption = 'Saved Options';
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = count(CF_DocumentLineProductConfig where("Document Type" = field("Document Type"),
                "Source Table ID" = field("Source Table ID"), "Source Line SystemId" = field("Source Line SystemId")));
        }
        field(12; "Template Code"; Code[20]) { Caption = 'Template Code'; Editable = false; TableRelation = CF_ConfigTemplate; }
        field(13; "Template Assignment"; Enum CF_TemplateAssignment) { Caption = 'Template Assignment'; Editable = false; }
    }
    keys
    {
        key(PK; "No.") { Clustered = true; }
        key(Source; "Document Type", "Source Table ID", "Source Line SystemId") { Unique = true; }
        key(Document; "Document Type", "Source Table ID", "Document No.", "Document Line No.") { }
    }
    trigger OnInsert()
    var
        Existing: Record CF_ProductConfigHeader;
    begin
        TestField("No.", '');
        TestField("Source Table ID");
        TestField("Source Line SystemId");
        TestField("Document No.");
        TestField("Document Line No.");
        "No." := GetDocumentLineNumber();
        if Existing.Get("No.") then
            Error(NumberCollisionErr, "No.", Existing."Document Type", Existing."Document No.", Existing."Document Line No.");
        TestField("No.");
    end;

    trigger OnModify()
    begin
        if ("Template Code" <> xRec."Template Code") or ("Template Assignment" <> xRec."Template Assignment") then
            Error('A saved configuration must retain its original template assignment. Delete and recreate the configuration to use another template.');
        if "No." <> xRec."No." then
            Error(IdentityChangeErr);
        if ("No. Series" <> xRec."No. Series") and not IsNumberUpgrade() then
            Error(IdentityChangeErr);
        if ("Document Type" <> xRec."Document Type") or ("Source Table ID" <> xRec."Source Table ID") or
           ("Source Line SystemId" <> xRec."Source Line SystemId")
        then
            ValidateQuoteToOrderMove();
    end;

    trigger OnDelete()
    var
        Config: Record CF_DocumentLineProductConfig;
        SalesLine: Record "Sales Line";
        Mgt: Codeunit CF_DocumentConfigMgt;
        DraftMgt: Codeunit CF_BOMDraftMgt;
    begin
        GetConfigIdentity(Config);
        Config.SetRange("Document Type", "Document Type");
        Config.SetRange("Source Table ID", "Source Table ID");
        Config.SetRange("Source Line SystemId", "Source Line SystemId");
        if not Config.IsEmpty() then
            Error(DeleteChoicesFirstErr);
        if DraftMgt.HasSaved("Source Line SystemId") then
            Error('Delete the saved BOM structure through Delete Configuration before deleting its configuration header.');
        if ("Document Type" in [CF_ConfigDocumentType::SalesOrder, CF_ConfigDocumentType::SalesQuote]) and ("Source Table ID" = Database::"Sales Line") then
            if SalesLine.GetBySystemId("Source Line SystemId") then
                Mgt.EnsureEditable(SalesLine);
    end;

    trigger OnRename()
    begin
        if not IsNumberUpgrade() or (xRec."No. Series" = '') or ("No." <> GetDocumentLineNumber()) then
            Error(IdentityChangeErr);
    end;

    procedure GetDocumentLineNumber(): Code[100]
    begin
        exit(CopyStr("Document No." + '-' + Format("Document Line No.", 0, 9), 1, MaxStrLen("No.")));
    end;

    local procedure IsNumberUpgrade(): Boolean
    var
        Module: ModuleInfo;
    begin
        if not NavApp.GetCurrentModuleInfo(Module) then
            Error(ModuleInfoUnavailableErr);
        exit(Module.DataVersion() < Version.Create(1, 0, 0, 4));
    end;

    local procedure ValidateQuoteToOrderMove()
    var
        QuoteLine: Record "Sales Line";
        OrderLine: Record "Sales Line";
        OrderHeader: Record "Sales Header";
    begin
        if (xRec."Document Type" <> CF_ConfigDocumentType::SalesQuote) or ("Document Type" <> CF_ConfigDocumentType::SalesOrder) or
           (xRec."Source Table ID" <> Database::"Sales Line") or ("Source Table ID" <> Database::"Sales Line")
        then
            Error(IdentityChangeErr);
        QuoteLine.GetBySystemId(xRec."Source Line SystemId");
        OrderLine.GetBySystemId("Source Line SystemId");
        QuoteLine.TestField("Document Type", QuoteLine."Document Type"::Quote);
        OrderLine.TestField("Document Type", OrderLine."Document Type"::Order);
        QuoteLine.TestField(CF_ProductConfigurationNo, "No.");
        OrderHeader.Get(OrderLine."Document Type", OrderLine."Document No.");
        OrderHeader.TestField("Quote No.", QuoteLine."Document No.");
        if ("Document No." <> OrderLine."Document No.") or ("Document Line No." <> OrderLine."Line No.") or
           ("Parent Item No." <> OrderLine."No.") or ("Parent Variant Code" <> OrderLine."Variant Code") or
           (QuoteLine."No." <> OrderLine."No.") or (QuoteLine."Variant Code" <> OrderLine."Variant Code") or
           (OrderLine.CF_ProductConfigurationNo <> '')
        then
            Error(IdentityChangeErr);
    end;

    procedure GetConfigIdentity(var Config: Record CF_DocumentLineProductConfig)
    begin
        Config.Reset();
        Config.Init();
        Config."Document Type" := "Document Type";
        Config."Source Table ID" := "Source Table ID";
        Config."Source Line SystemId" := "Source Line SystemId";
        Config."Document No." := "Document No.";
        Config."Document Line No." := "Document Line No.";
        Config."Item Category Code" := "Item Category Code";
        Config."Parent Item No." := "Parent Item No.";
        Config."Parent Variant Code" := "Parent Variant Code";
        Config."Template Code" := "Template Code";
        Config."Template Assignment" := "Template Assignment";
        Config."Template Context Set" := true;
    end;

    var
        IdentityChangeErr: Label 'Configuration identity can only change during the numbering upgrade or standard Sales Quote Make Order conversion.';
        DeleteChoicesFirstErr: Label 'Delete the configuration through Product Configurator. A header cannot be deleted while saved choices exist.';
        ModuleInfoUnavailableErr: Label 'The configuration app data version could not be read.';
        NumberCollisionErr: Label 'Product configuration %1 already belongs to %2 %3, line %4. Document No.-Line No. must be unique; no alternative number was generated.', Comment = '%1 = configuration number, %2 = document type, %3 = document number, %4 = line number';
}
