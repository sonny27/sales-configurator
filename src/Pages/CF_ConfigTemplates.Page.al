namespace CloudFactory.SalesConfigurator;

page 91012 CF_ConfigTemplates
{
    Caption = 'Configuration Templates';
    PageType = List;
    SourceTable = CF_ConfigTemplate;
    ApplicationArea = All;
    UsageCategory = Administration;
    CardPageId = CF_CategoryTemplateDesigner;
    InsertAllowed = false;
    ModifyAllowed = false;
    layout
    {
        area(Content)
        {
            repeater(Templates)
            {
                field(Code; Rec.Code) { ApplicationArea = All; ToolTip = 'Specifies the unique template code.'; }
                field(Description; Rec.Description) { ApplicationArea = All; ToolTip = 'Specifies the template description.'; }
                field(TemplateType; Rec."Template Type") { ApplicationArea = All; ToolTip = 'Specifies item-specific or category-specific assignment.'; }
                field(ItemNo; Rec."Item No.") { ApplicationArea = All; ToolTip = 'Specifies the assigned inventory item for an item-specific template.'; }
                field(ItemCategoryCode; Rec."Item Category Code") { ApplicationArea = All; ToolTip = 'Specifies the assigned category for a category-specific template.'; }
            }
        }
    }
    actions
    {
        area(Processing)
        {
            action(NewTemplate)
            {
                Caption = 'New Template';
                ApplicationArea = All;
                AccessByPermission = tabledata CF_ConfiguratorBOM = M;
                Image = New;
                ToolTip = 'Create one template for a new item or category assignment.';
                trigger OnAction()
                var
                    Wizard: Page CF_NewConfigTemplate;
                    Template: Record CF_ConfigTemplate;
                begin
                    if Wizard.RunModal() = Action::OK then begin
                        Wizard.GetTemplate(Template);
                        Commit();
                        Page.RunModal(Page::CF_CategoryTemplateDesigner, Template);
                        CurrPage.Update(false);
                    end;
                end;
            }
            action(CopyTemplate)
            {
                Caption = 'Copy Template';
                ApplicationArea = All;
                AccessByPermission = tabledata CF_ConfiguratorBOM = M;
                Image = Copy;
                ToolTip = 'Copy all options and choices to a new or empty item/category template. Existing populated destinations cannot be overwritten.';
                trigger OnAction()
                var
                    Wizard: Page CF_NewConfigTemplate;
                    Template: Record CF_ConfigTemplate;
                begin
                    Wizard.SetCopySource(Rec);
                    if Wizard.RunModal() = Action::OK then begin
                        Wizard.GetTemplate(Template);
                        Commit();
                        Page.RunModal(Page::CF_CategoryTemplateDesigner, Template);
                        CurrPage.Update(false);
                    end;
                end;
            }
        }
        area(Promoted)
        {
            actionref(NewPromoted; NewTemplate) { }
            actionref(CopyPromoted; CopyTemplate) { }
        }
    }
}
