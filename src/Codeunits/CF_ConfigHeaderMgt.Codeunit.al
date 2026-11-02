namespace CloudFactory.SalesConfigurator;

using Microsoft.Sales.Document;

codeunit 91005 CF_ConfigHeaderMgt
{
    Permissions = tabledata CF_ProductConfigHeader = rimd,
                  tabledata CF_SalesConfiguratorSetup = rim,
                  tabledata "Sales Line" = rm;

    procedure InitializeSetup()
    var
        Setup: Record CF_SalesConfiguratorSetup;
    begin
        Setup.LockTable();
        if not Setup.Get() then begin
            Setup.Init();
            Setup.Insert(true);
        end;
    end;

    procedure UpgradeDocumentNumbers()
    var
        Header: Record CF_ProductConfigHeader;
        Existing: Record CF_ProductConfigHeader;
        TempHeaders: Record CF_ProductConfigHeader temporary;
        NewNumber: Code[100];
    begin
        Header.LockTable();
        if Header.FindSet() then
            repeat
                NewNumber := Header."No.";
                if Header."No. Series" <> '' then
                    NewNumber := Header.GetDocumentLineNumber();
                if Existing.Get(NewNumber) and (Existing."No." <> Header."No.") then
                    Error(NumberCollisionErr, NewNumber);
                if TempHeaders.Get(NewNumber) then
                    Error(NumberCollisionErr, NewNumber);
                TempHeaders := Header;
                TempHeaders."No." := NewNumber;
                TempHeaders.Insert(false);
            until Header.Next() = 0;
        if TempHeaders.FindSet() then
            repeat
                Header.Reset();
                FilterHeaderFromHeader(TempHeaders, Header);
                Header.FindFirst();
                NewNumber := TempHeaders."No.";
                if Header."No." <> NewNumber then
                    Header.Rename(NewNumber);
                Header."No. Series" := '';
                Header.Modify(true);
                SyncSalesLineNumber(Header);
            until TempHeaders.Next() = 0;
    end;

    procedure BackfillHeaders()
    var
        Config: Record CF_DocumentLineProductConfig;
    begin
        if Config.FindSet() then
            repeat
                EnsureHeader(Config);
            until Config.Next() = 0;
    end;

    procedure EnsureHeader(Config: Record CF_DocumentLineProductConfig)
    var
        Header: Record CF_ProductConfigHeader;
    begin
        Header.LockTable();
        FilterHeader(Config, Header);
        if not Header.FindFirst() then begin
            Header.Init();
            Header."No." := '';
            CopyContext(Config, Header);
            Header.Insert(true);
        end else begin
            Header.TestField("Template Code", Config.GetTemplateCode());
            Header.TestField("Template Assignment", Config."Template Assignment");
            if (Header."Document No." <> Config."Document No.") or
               (Header."Document Line No." <> Config."Document Line No.") or
               (Header."Item Category Code" <> Config."Item Category Code") or
               (Header."Parent Item No." <> Config."Parent Item No.") or
               (Header."Parent Variant Code" <> Config."Parent Variant Code")
            then begin
                CopyContext(Config, Header);
                Header.Modify(true);
            end;
        end;
        SyncSalesLineNumber(Header);
    end;

    procedure MoveQuoteHeader(QuoteLine: Record "Sales Line"; OrderLine: Record "Sales Line"; Config: Record CF_DocumentLineProductConfig)
    var
        Header: Record CF_ProductConfigHeader;
    begin
        if (Config."Document Type" <> CF_ConfigDocumentType::SalesOrder) or
           (Config."Source Line SystemId" <> OrderLine.SystemId)
        then
            Error('The transferred configuration must belong to the new sales order line.');
        Header.LockTable();
        Header.SetRange("Document Type", CF_ConfigDocumentType::SalesQuote);
        Header.SetRange("Source Table ID", Database::"Sales Line");
        Header.SetRange("Source Line SystemId", QuoteLine.SystemId);
        Header.FindFirst();
        Header.TestField("No.", QuoteLine.CF_ProductConfigurationNo);
        CopyContext(Config, Header);
        Header.Modify(true);
        SyncSalesLineNumber(Header);
    end;

    procedure RemoveEmptyHeader(Config: Record CF_DocumentLineProductConfig)
    var
        Remaining: Record CF_DocumentLineProductConfig;
        Header: Record CF_ProductConfigHeader;
    begin
        Remaining.SetRange("Document Type", Config."Document Type");
        Remaining.SetRange("Source Table ID", Config."Source Table ID");
        Remaining.SetRange("Source Line SystemId", Config."Source Line SystemId");
        if not Remaining.IsEmpty() then
            exit;
        Header.LockTable();
        FilterHeader(Config, Header);
        if Header.FindFirst() then
            Header.Delete(true);
        ClearSalesLineNumber(Config);
    end;

    local procedure SyncSalesLineNumber(Header: Record CF_ProductConfigHeader)
    var
        SalesLine: Record "Sales Line";
    begin
        if (Header."Source Table ID" <> Database::"Sales Line") or
           not (Header."Document Type" in [CF_ConfigDocumentType::SalesOrder, CF_ConfigDocumentType::SalesQuote])
        then
            exit;
        if not SalesLine.GetBySystemId(Header."Source Line SystemId") then
            exit;
        if SalesLine.CF_ProductConfigurationNo = Header."No." then
            exit;
        SalesLine.CF_ProductConfigurationNo := Header."No.";
        SalesLine.Modify(false);
    end;

    local procedure ClearSalesLineNumber(Config: Record CF_DocumentLineProductConfig)
    var
        SalesLine: Record "Sales Line";
    begin
        if (Config."Source Table ID" <> Database::"Sales Line") or
           not (Config."Document Type" in [CF_ConfigDocumentType::SalesOrder, CF_ConfigDocumentType::SalesQuote])
        then
            exit;
        if not SalesLine.GetBySystemId(Config."Source Line SystemId") then
            exit;
        if SalesLine.CF_ProductConfigurationNo = '' then
            exit;
        Clear(SalesLine.CF_ProductConfigurationNo);
        SalesLine.Modify(false);
    end;

    local procedure FilterHeaderFromHeader(SourceHeader: Record CF_ProductConfigHeader; var Header: Record CF_ProductConfigHeader)
    begin
        Header.SetRange("Document Type", SourceHeader."Document Type");
        Header.SetRange("Source Table ID", SourceHeader."Source Table ID");
        Header.SetRange("Source Line SystemId", SourceHeader."Source Line SystemId");
    end;

    local procedure FilterHeader(Config: Record CF_DocumentLineProductConfig; var Header: Record CF_ProductConfigHeader)
    begin
        Header.SetCurrentKey("Document Type", "Source Table ID", "Source Line SystemId");
        Header.SetRange("Document Type", Config."Document Type");
        Header.SetRange("Source Table ID", Config."Source Table ID");
        Header.SetRange("Source Line SystemId", Config."Source Line SystemId");
    end;

    local procedure CopyContext(Config: Record CF_DocumentLineProductConfig; var Header: Record CF_ProductConfigHeader)
    var
        Template: Record CF_ConfigTemplate;
    begin
        Header."Document Type" := Config."Document Type";
        Header."Source Table ID" := Config."Source Table ID";
        Header."Source Line SystemId" := Config."Source Line SystemId";
        Header."Document No." := Config."Document No.";
        Header."Document Line No." := Config."Document Line No.";
        Header."Item Category Code" := Config."Item Category Code";
        Header."Parent Item No." := Config."Parent Item No.";
        Header."Parent Variant Code" := Config."Parent Variant Code";
        Header."Template Code" := Config.GetTemplateCode();
        Header."Template Assignment" := Config."Template Assignment";
        if Header."Template Code" <> '' then begin
            Template.Get(Header."Template Code");
            Header."Template Assignment" := Template."Template Type";
        end;
    end;

    var
        NumberCollisionErr: Label 'Cannot migrate product configuration number %1 because another configuration uses the same Document No.-Line No. Resolve the duplicate before upgrading.', Comment = '%1 = generated configuration number';
}
