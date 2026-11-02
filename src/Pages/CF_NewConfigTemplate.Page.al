namespace CloudFactory.SalesConfigurator;

page 91013 CF_NewConfigTemplate
{
    Caption = 'New Configuration Template';
    PageType = StandardDialog;
    SourceTable = CF_ConfigTemplate;
    SourceTableTemporary = true;
    InsertAllowed = false;
    DeleteAllowed = false;
    ApplicationArea = All;
    layout
    {
        area(Content)
        {
            group(Assignment)
            {
                Caption = 'Template Assignment';
                field(SourceTemplate; SourceCode)
                {
                    ApplicationArea = All;
                    Caption = 'Copy From Template';
                    TableRelation = CF_ConfigTemplate.Code;
                    ToolTip = 'Select an existing Item No. or Item Category template to copy its options, choices, defaults, quantity limits and routing links. Leave blank to create an empty template. The destination assignment is unchanged.';
                }
                field(TemplateCode; Rec.Code) { ApplicationArea = All; ToolTip = 'Specifies a unique template code. If blank, the selected item or category number is used if available.'; }
                field(TemplateType; Rec."Template Type")
                {
                    ApplicationArea = All;
                    Editable = not AssignmentLocked;
                    ToolTip = 'Specifies whether the new template belongs to one sales-line item or one item category.';
                    trigger OnValidate()
                    begin
                        Clear(Rec."Item No.");
                        Clear(Rec."Item Category Code");
                        UpdateType();
                    end;
                }
                field(ItemNo; Rec."Item No.") { ApplicationArea = All; Enabled = IsItem; Editable = not AssignmentLocked; ShowMandatory = IsItem; ToolTip = 'Specifies the required inventory item when Template Type is Item No.'; }
                field(ItemCategoryCode; Rec."Item Category Code") { ApplicationArea = All; Enabled = not IsItem; Editable = not AssignmentLocked; ShowMandatory = not IsItem; ToolTip = 'Specifies the required category when Template Type is Item Category.'; }
                field(Description; Rec.Description) { ApplicationArea = All; ToolTip = 'Specifies the template description. Blank uses the assigned item or category description.'; }
            }
        }
    }

    trigger OnOpenPage()
    begin
        Rec := InitialTemplate;
        if AssignmentLocked then begin
            Rec.CheckAssignment();
            Rec.Code := Rec.GetAssignmentNo();
        end;
        Rec.Insert(true);
        UpdateType();
        CurrPage.Editable(true);
    end;

    trigger OnQueryClosePage(CloseAction: Action): Boolean
    var
        Mgt: Codeunit CF_TemplateMgt;
        DocumentMgt: Codeunit CF_DocumentConfigMgt;
    begin
        if CloseAction <> Action::OK then
            exit(true);
        if not DocumentMgt.CanMaintainTemplates() then
            Error('Product Configurator Setup permission is required.');
        Target := Rec;
        if SourceCode = '' then
            Mgt.Create(Target, false)
        else
            Mgt.CopyTemplate(SourceCode, Target);
        exit(true);
    end;

    procedure SetAssignment(Assignment: Enum CF_TemplateAssignment; ItemNo: Code[20]; CategoryCode: Code[20])
    begin
        AssignmentLocked := true;
        InitialTemplate."Template Type" := Assignment;
        if Assignment = Assignment::SalesLineItem then
            InitialTemplate."Item No." := ItemNo
        else
            InitialTemplate."Item Category Code" := CategoryCode;
    end;

    procedure SetCopySource(Source: Record CF_ConfigTemplate)
    begin
        SourceCode := Source.Code;
        InitialTemplate."Template Type" := Source."Template Type";
        InitialTemplate.Description := Source.Description;
    end;

    procedure GetTemplate(var Result: Record CF_ConfigTemplate)
    begin
        Result := Target;
    end;

    local procedure UpdateType()
    begin
        IsItem := Rec."Template Type" = Rec."Template Type"::SalesLineItem;
    end;

    var
        Target: Record CF_ConfigTemplate;
        InitialTemplate: Record CF_ConfigTemplate;
        SourceCode: Code[20];
        IsItem: Boolean;
        AssignmentLocked: Boolean;
}
