namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.BOM;
using Microsoft.Inventory.Item;
using Microsoft.Manufacturing.Document;
using Microsoft.Sales.Document;

codeunit 91010 CF_BOMDraftMgt
{
    Permissions = tabledata CF_BOMBuffer = rimd;

    procedure ApplyConfiguration(SalesLine: Record "Sales Line"; var Choices: Record CF_DocumentLineProductConfig temporary): Boolean
    var
        Root: Record CF_BOMBuffer;
        Rows: Record CF_BOMBuffer temporary;
        Tree: Codeunit CF_BOMTreeMgt;
        DocumentMgt: Codeunit CF_DocumentConfigMgt;
        Revision: Integer;
        SavedId: Guid;
        Signature: Text;
    begin
        DocumentMgt.InitializeBase(SalesLine);
        SalesLine.CF_BaseSetupSet := true;
        DocumentMgt.ValidateBase(SalesLine);
        DocumentMgt.StampBase(SalesLine, Choices);
        if GetRoot(SalesLine.SystemId, Root) then begin
            if MatchesChoices(Root, Choices) and (Root."Source Context" = Tree.Context(SalesLine)) then begin
                DocumentMgt.Save(SalesLine, Choices);
                exit(true);
            end;
            if not Confirm('The selected base BOM/routing or choices differ from the saved structure. Rebuild and replace that structure on Apply? Manual component edits will be replaced.', false) then
                exit(false);
            Revision := Root.Revision;
            SavedId := Root.SystemId;
        end;
        Signature := SavedChoiceSignature(SalesLine.SystemId);
        Tree.Generate(SalesLine, Choices, Rows);
        Save(SalesLine, Choices, Rows, Revision, SavedId, Signature);
        exit(true);
    end;

    procedure Open(SalesLine: Record "Sales Line"; var Choices: Record CF_DocumentLineProductConfig temporary): Boolean
    var
        Rows: Record CF_BOMBuffer temporary;
        SavedRoot: Record CF_BOMBuffer;
        Tree: Codeunit CF_BOMTreeMgt;
        Editor: Page CF_BOMDraftEditor;
        Revision: Integer;
        SavedId: Guid;
        CurrentSalesLine: Record "Sales Line";
        DocumentMgt: Codeunit CF_DocumentConfigMgt;
    begin
        if not CurrentSalesLine.GetBySystemId(SalesLine.SystemId) then
            Error('The source sales line no longer exists.');
        if SalesLine.CF_BaseSetupSet then
            DocumentMgt.CopyBase(SalesLine, CurrentSalesLine);
        SalesLine := CurrentSalesLine;
        DocumentMgt.InitializeBase(SalesLine);
        if GetRoot(SalesLine.SystemId, SavedRoot) then begin
            Revision := SavedRoot.Revision;
            SavedId := SavedRoot.SystemId;
            if MatchesChoices(SavedRoot, Choices) and (SavedRoot."Source Context" = Tree.Context(SalesLine)) then
                LoadRows(SalesLine.SystemId, Rows)
            else begin
                if not Confirm('The saved BOM structure was built for different choices or parent context. Generate a replacement draft? The saved structure remains unchanged until Apply.', false) then
                    exit;
                Tree.Generate(SalesLine, Choices, Rows);
            end;
        end else
            Tree.Generate(SalesLine, Choices, Rows);
        Editor.SetDraft(SalesLine, Choices, Rows, Revision, SavedId, SavedChoiceSignature(SalesLine.SystemId));
        Editor.RunModal();
        Editor.GetAppliedChoices(Choices);
        exit(Editor.WasApplied());
    end;

    procedure GetPreview(SalesLine: Record "Sales Line"; var Choices: Record CF_DocumentLineProductConfig temporary; var Rows: Record CF_BOMBuffer temporary)
    var
        Root: Record CF_BOMBuffer;
        Tree: Codeunit CF_BOMTreeMgt;
        DocumentMgt: Codeunit CF_DocumentConfigMgt;
    begin
        DocumentMgt.InitializeBase(SalesLine);
        SalesLine.CF_BaseSetupSet := true;
        DocumentMgt.StampBase(SalesLine, Choices);
        DocumentMgt.ValidatePreview(SalesLine, Choices);
        if GetRoot(SalesLine.SystemId, Root) then
            if MatchesChoices(Root, Choices) and (Root."Source Context" = Tree.Context(SalesLine)) then begin
                LoadRows(SalesLine.SystemId, Rows);
                ValidateTree(SalesLine, Rows);
                exit;
            end;
        Tree.Generate(SalesLine, Choices, Rows);
        ValidateTree(SalesLine, Rows);
    end;

    procedure HasSaved(SourceId: Guid): Boolean
    var
        Root: Record CF_BOMBuffer;
    begin
        exit(GetRoot(SourceId, Root));
    end;

    procedure CheckChoices(SalesLine: Record "Sales Line"; var Choices: Record CF_DocumentLineProductConfig)
    var
        Root: Record CF_BOMBuffer;
        Tree: Codeunit CF_BOMTreeMgt;
    begin
        if not GetRoot(SalesLine.SystemId, Root) then
            exit;
        if (Root."Source Context" <> Tree.Context(SalesLine)) or not MatchesChoices(Root, Choices) then
            Error('The saved BOM structure no longer matches this configuration. Open Show New Configured BOM, rebuild the draft, and apply it there.');
    end;

    procedure Save(SalesLine: Record "Sales Line"; var Choices: Record CF_DocumentLineProductConfig temporary; var Rows: Record CF_BOMBuffer temporary; ExpectedRevision: Integer; ExpectedSavedId: Guid; ExpectedChoicesSignature: Text)
    var
        Saved: Record CF_BOMBuffer;
        Root: Record CF_BOMBuffer;
        HeaderContext: Record CF_DocumentLineProductConfig;
        Item: Record Item;
        DocumentMgt: Codeunit CF_DocumentConfigMgt;
        HeaderMgt: Codeunit CF_ConfigHeaderMgt;
        Tree: Codeunit CF_BOMTreeMgt;
        CurrentRevision: Integer;
        TemplateMgt: Codeunit CF_TemplateMgt;
        Output: OutStream;
        CurrentSavedId: Guid;
        CurrentSalesLine: Record "Sales Line";
    begin
        CurrentSalesLine.LockTable();
        if not CurrentSalesLine.GetBySystemId(SalesLine.SystemId) then
            Error('The source sales line no longer exists.');
        if SalesLine.CF_BaseSetupSet then
            DocumentMgt.CopyBase(SalesLine, CurrentSalesLine);
        SalesLine := CurrentSalesLine;
        Rows.Reset();
        Rows.SetRange(Indentation, 0);
        Rows.FindFirst();
        if Rows."Base Selection Set" then begin
            if SalesLine.CF_BaseSetupSet and
               ((SalesLine.CF_BaseBOMNo <> Rows."Base BOM") or (SalesLine.CF_BaseRoutingNo <> Rows."Base Routing"))
            then
                Error('The draft does not match the selected base BOM/routing. Rebuild it before applying.');
            SalesLine.CF_BaseBOMNo := Rows."Base BOM";
            SalesLine.CF_BaseRoutingNo := Rows."Base Routing";
            SalesLine.CF_BaseSetupSet := true;
            Rows."Source Context" := Tree.Context(SalesLine);
            Rows.Modify(false);
            DocumentMgt.StampBase(SalesLine, Choices);
        end;
        Rows.Reset();
        DocumentMgt.EnsureEditable(SalesLine);
        Saved.LockTable();
        if GetRoot(SalesLine.SystemId, Root) then begin
            CurrentRevision := Root.Revision;
            CurrentSavedId := Root.SystemId;
        end;
        if (CurrentRevision <> ExpectedRevision) or (CurrentSavedId <> ExpectedSavedId) then
            Error('Another user changed or deleted this BOM structure. Reopen it before applying your changes.');
        if SavedChoiceSignature(SalesLine.SystemId) <> ExpectedChoicesSignature then
            Error('Another user changed this sales-line configuration. Reopen it before applying your BOM draft.');
        ValidateTree(SalesLine, Rows);
        ValidateChoiceRoots(SalesLine, Choices, Rows);
        // Keep a root present while replacing choices so the originating configuration number survives.
        DeleteSaved(SalesLine.SystemId);
        Rows.Reset();
        Rows.SetRange(Indentation, 0);
        Rows.FindFirst();
        Saved := Rows;
        Saved."Source Context" := Tree.Context(SalesLine);
        Clear(Saved."Choice Signature");
        Saved."Choice Signature".CreateOutStream(Output, TextEncoding::UTF8);
        Output.WriteText(ChoiceSignature(SalesLine.SystemId, Choices));
        Saved.Insert(false);
        DocumentMgt.Save(SalesLine, Choices);
        DeleteSaved(SalesLine.SystemId);
        Item.Get(SalesLine."No.");
        HeaderContext."Document Type" := DocumentMgt.GetConfigDocumentType(SalesLine);
        HeaderContext."Source Table ID" := Database::"Sales Line";
        HeaderContext."Source Line SystemId" := SalesLine.SystemId;
        HeaderContext."Document No." := SalesLine."Document No.";
        HeaderContext."Document Line No." := SalesLine."Line No.";
        HeaderContext."Parent Item No." := SalesLine."No.";
        HeaderContext."Parent Variant Code" := SalesLine."Variant Code";
        HeaderContext."Item Category Code" := Item."Item Category Code";
        TemplateMgt.Stamp(SalesLine, HeaderContext);
        HeaderMgt.EnsureHeader(HeaderContext);
        SalesLine.GetBySystemId(SalesLine.SystemId);
        Rows.Reset();
        if Rows.FindSet() then
            repeat
                Saved := Rows;
                Saved."Configuration No." := SalesLine.CF_ProductConfigurationNo;
                Saved.Revision := CurrentRevision + 1;
                if Saved.Indentation = 0 then begin
                    Saved."Source Context" := Tree.Context(SalesLine);
                    Clear(Saved."Choice Signature");
                    Saved."Choice Signature".CreateOutStream(Output, TextEncoding::UTF8);
                    Output.WriteText(ChoiceSignature(SalesLine.SystemId, Choices));
                end;
                Saved.Insert(false);
            until Rows.Next() = 0;
    end;

    procedure DeleteSaved(SourceId: Guid)
    var
        Saved: Record CF_BOMBuffer;
        SalesLine: Record "Sales Line";
        DocumentMgt: Codeunit CF_DocumentConfigMgt;
    begin
        if SalesLine.GetBySystemId(SourceId) then
            DocumentMgt.EnsureEditable(SalesLine);
        Saved.SetRange("Source Line ID", SourceId);
        Saved.DeleteAll(false);
    end;

    procedure MoveSaved(FromSourceId: Guid; ToSourceId: Guid)
    var
        Rows: Record CF_BOMBuffer temporary;
        Saved: Record CF_BOMBuffer;
    begin
        if HasSaved(ToSourceId) then
            Error('The destination sales line already has a saved BOM structure.');
        LoadRows(FromSourceId, Rows);
        DeleteSaved(FromSourceId);
        if Rows.FindSet() then
            repeat
                Saved := Rows;
                Saved."Source Line ID" := ToSourceId;
                Saved.Revision += 1;
                Saved.Insert(false);
            until Rows.Next() = 0;
    end;

    procedure LoadRows(SourceId: Guid; var Rows: Record CF_BOMBuffer temporary)
    var
        Saved: Record CF_BOMBuffer;
    begin
        Rows.Reset();
        Rows.DeleteAll();
        Saved.SetRange("Source Line ID", SourceId);
        if Saved.FindSet() then
            repeat
                Saved.CalcFields("Choice Signature");
                Rows := Saved;
                Rows.Insert();
            until Saved.Next() = 0;
        Rows.SetCurrentKey("Source Line ID", "Sort Order");
    end;

    procedure AddComponent(SalesLine: Record "Sales Line"; Parent: Record CF_BOMBuffer; No: Code[20]; IsBOM: Boolean; var Rows: Record CF_BOMBuffer temporary)
    var
        Branch: Record CF_BOMBuffer temporary;
        Reader: Record CF_BOMBuffer temporary;
        Tree: Codeunit CF_BOMTreeMgt;
        InsertAfter: Integer;
        Shift: Integer;
    begin
        if not Parent.IsComponent() then
            Error('Select an item or Production BOM parent before inserting a component.');
        InsertAfter := Parent."Sort Order";
        Reader.Copy(Rows, true);
        Reader.Reset();
        Reader.SetCurrentKey("Source Line ID", "Sort Order");
        Reader.SetFilter("Sort Order", '>%1', Parent."Sort Order");
        if Reader.FindSet() then
            repeat
                if Reader.Indentation <= Parent.Indentation then
                    break;
                InsertAfter := Reader."Sort Order";
            until Reader.Next() = 0;
        Tree.GenerateBranch(SalesLine, Parent, No, IsBOM, Branch);
        Shift := Branch.Count() * 10000;
        Reader.SetFilter("Sort Order", '>%1', InsertAfter);
        if Reader.FindLast() then
            repeat
                Reader."Sort Order" += Shift;
                Reader.Modify();
            until Reader.Next(-1) = 0;
        Branch.SetCurrentKey("Source Line ID", "Sort Order");
        if Branch.FindSet() then
            repeat
                Rows := Branch;
                Rows."Direct Addition" := Branch."Parent Node ID" = Parent."Node ID";
                Rows."Sort Order" += InsertAfter;
                Rows.Insert();
            until Branch.Next() = 0;
    end;

    procedure DeleteBranch(Node: Record CF_BOMBuffer; var Rows: Record CF_BOMBuffer temporary; var Choices: Record CF_DocumentLineProductConfig temporary)
    var
        Reader: Record CF_BOMBuffer temporary;
        Ids: List of [Guid];
        Id: Guid;
    begin
        if Node.Indentation = 0 then
            Error('The finished-item root cannot be deleted.');
        if not Node.IsComponent() then
            Error('Routing operations are read-only. Delete their parent component to remove the whole branch.');
        Reader.Copy(Rows, true);
        Reader.Reset();
        Reader.SetCurrentKey("Source Line ID", "Sort Order");
        Reader.SetFilter("Sort Order", '>=%1', Node."Sort Order");
        Reader.FindSet();
        repeat
            if (Reader."Node ID" <> Node."Node ID") and (Reader.Indentation <= Node.Indentation) then
                break;
            if Reader."Choice Root" then begin
                Choices.Get(Choices."Document Type", Database::"Sales Line", Node."Source Line ID", Reader."Configuration Option");
                Choices.Validate("Choice Code", '');
                Choices.Modify();
            end;
            Ids.Add(Reader."Node ID");
        until Reader.Next() = 0;
        foreach Id in Ids do begin
            Rows.Get(Node."Source Line ID", Id);
            Rows.Delete();
        end;
        Rows.Reset();
        Rows.SetCurrentKey("Source Line ID", "Sort Order");
    end;

    procedure ValidateTree(SalesLine: Record "Sales Line"; var Rows: Record CF_BOMBuffer temporary)
    begin
        ValidateTree(SalesLine, Rows, true);
    end;

    local procedure ValidateTree(SalesLine: Record "Sales Line"; var Rows: Record CF_BOMBuffer temporary; ValidateMasters: Boolean)
    var
        Reader: Record CF_BOMBuffer temporary;
        Parent: Record CF_BOMBuffer temporary;
        Ancestor: Record CF_BOMBuffer temporary;
        RootItem: Record Item;
        DocumentMgt: Codeunit CF_DocumentConfigMgt;
        Ancestors: Dictionary of [Integer, Guid];
        ParentId: Guid;
        RootCount: Integer;
        Tree: Codeunit CF_BOMTreeMgt;
    begin
        Reader.Copy(Rows, true);
        Parent.Copy(Rows, true);
        Ancestor.Copy(Rows, true);
        Reader.Reset();
        Reader.SetCurrentKey("Source Line ID", "Sort Order");
        if Reader.Count() > 10000 then
            Error('A configured BOM structure cannot exceed 10000 rows.');
        if not Reader.FindSet() then
            Error('The configured BOM structure is empty.');
        repeat
            Reader.TestField("Source Line ID", SalesLine.SystemId);
            Reader.TestField("Node ID");
            if Reader.Indentation = 0 then begin
                RootCount += 1;
                if (Reader.Type <> Reader.Type::Item) or not IsNullGuid(Reader."Parent Node ID") then
                    Error('The BOM root must be the source finished item.');
                Reader.TestField("No.", SalesLine."No.");
                Reader.TestField("Variant Code", SalesLine."Variant Code");
                if ValidateMasters then begin
                    RootItem.Get(Reader."No.");
                    RootItem.TestField(Type, RootItem.Type::Inventory);
                    Reader.TestField("Source Context", Tree.Context(SalesLine));
                end;
                if ValidateMasters and Reader."Base Selection Set" then begin
                    Reader.TestField("Base BOM", SalesLine.CF_BaseBOMNo);
                    Reader.TestField("Base Routing", SalesLine.CF_BaseRoutingNo);
                end;
            end else begin
                Reader.TestField("Base Selection Set", false);
                if (Reader.Indentation < 1) or (Reader.Indentation > 50) or
                   not Ancestors.Get(Reader.Indentation - 1, ParentId) or (ParentId <> Reader."Parent Node ID")
                then
                    Error('Component %1 has an invalid parent or tree order.', Reader."No.");
                Parent.Get(SalesLine.SystemId, ParentId);
                if not Parent.IsComponent() then
                    Error('A routing operation cannot contain components.');
                if Reader.IsComponent() then begin
                    Ancestor := Parent;
                    repeat
                        if (Ancestor.Type = Reader.Type) and (Ancestor."No." = Reader."No.") then
                            Error('Component %1 creates a circular structure.', Reader."No.");
                        if IsNullGuid(Ancestor."Parent Node ID") then
                            break;
                        Ancestor.Get(SalesLine.SystemId, Ancestor."Parent Node ID");
                    until false;
                end;
            end;
            Ancestors.Set(Reader.Indentation, Reader."Node ID");
            if ValidateMasters and (Reader.Type = Reader.Type::Item) then
                DocumentMgt.ValidateItem(Reader."No.", Reader."Variant Code", Reader."Unit of Measure Code");
            if Reader."Choice Root" then
                if Reader."Quantity per" <= 0 then
                    Error('Component %1 requires a positive quantity.', Reader."No.");
            if not (Reader.Type in [Reader.Type::Item, Reader.Type::CF_ProductionBOM, Reader.Type::"Work Center", Reader.Type::"Machine Center"]) then
                Error('BOM row type %1 is not supported in a production configuration.', Reader.Type);
        until Reader.Next() = 0;
        if RootCount <> 1 then
            Error('The configured BOM must contain exactly one finished-item root.');
    end;

    local procedure ValidateChoiceRoots(SalesLine: Record "Sales Line"; var Choices: Record CF_DocumentLineProductConfig temporary; var Rows: Record CF_BOMBuffer temporary)
    var
        Reader: Record CF_BOMBuffer temporary;
    begin
        Reader.Copy(Rows, true);
        Choices.Reset();
        if Choices.FindSet() then
            repeat
                if Choices."Choice Code" <> '' then begin
                    Reader.Reset();
                    Reader.SetRange("Choice Root", true);
                    Reader.SetRange("Configuration Option", Choices."Configuration Option");
                    Reader.SetRange("Choice Code", Choices."Choice Code");
                    if Reader.Count() <> 1 then
                        Error('Option %1 must have exactly one matching component branch.', Choices."Configuration Option");
                    Reader.FindFirst();
                    Reader.TestField("Parent Node ID");
                    Reader.TestField("Source Line ID", SalesLine.SystemId);
                    Reader.TestField("Selection ID", Choices.SystemId);
                    if ((Choices."Component Type" = Choices."Component Type"::Item) and (Reader.Type <> Reader.Type::Item)) or
                       ((Choices."Component Type" = Choices."Component Type"::"Production BOM") and (Reader.Type <> Reader.Type::CF_ProductionBOM))
                    then
                        Error('Option %1 has an incorrect component branch type.', Choices."Configuration Option");
                    Reader.TestField("No.", Choices."Component Item No.");
                    Reader.TestField("Variant Code", Choices."Component Variant Code");
                    Reader.TestField("Unit of Measure Code", Choices."Component UOM Code");
                    Reader.TestField("Quantity per", Choices."Quantity per Unit");
                    Reader.TestField("Routing Link Code", Choices."Routing Link Code");
                end;
            until Choices.Next() = 0;
    end;

    local procedure GetRoot(SourceId: Guid; var Root: Record CF_BOMBuffer): Boolean
    begin
        Root.Reset();
        Root.SetRange("Source Line ID", SourceId);
        Root.SetRange(Indentation, 0);
        exit(Root.FindFirst());
    end;

    local procedure MatchesChoices(var Root: Record CF_BOMBuffer; var Choices: Record CF_DocumentLineProductConfig): Boolean
    var
        Input: InStream;
        SavedSignature: Text;
    begin
        Root.CalcFields("Choice Signature");
        Root."Choice Signature".CreateInStream(Input, TextEncoding::UTF8);
        Input.ReadText(SavedSignature);
        exit(SavedSignature = ChoiceSignature(Root."Source Line ID", Choices));
    end;

    local procedure SavedChoiceSignature(SourceId: Guid): Text
    var
        Choices: Record CF_DocumentLineProductConfig;
    begin
        exit(ChoiceSignature(SourceId, Choices));
    end;

    local procedure ChoiceSignature(SourceId: Guid; var Choices: Record CF_DocumentLineProductConfig): Text
    var
        Entries: JsonArray;
        Entry: JsonObject;
        Signature: Text;
        OriginalView: Text;
    begin
        OriginalView := Choices.GetView(false);
        Choices.Reset();
        Choices.SetCurrentKey("Document Type", "Source Table ID", "Source Line SystemId", "Configuration Option");
        Choices.SetRange("Source Table ID", Database::"Sales Line");
        Choices.SetRange("Source Line SystemId", SourceId);
        if Choices.FindSet() then
            repeat
                if Choices."Choice Code" <> '' then begin
                    Clear(Entry);
                    Entry.Add('option', Choices."Configuration Option");
                    Entry.Add('choice', Choices."Choice Code");
                    Entry.Add('type', Choices."Component Type".AsInteger());
                    Entry.Add('no', Choices."Component Item No.");
                    Entry.Add('variant', Choices."Component Variant Code");
                    Entry.Add('uom', Choices."Component UOM Code");
                    Entry.Add('qty', Choices."Quantity per Unit");
                    Entry.Add('link', Choices."Routing Link Code");
                    Entries.Add(Entry);
                end;
            until Choices.Next() = 0;
        Entries.WriteTo(Signature);
        Choices.SetView(OriginalView);
        exit(Signature);
    end;

    procedure WriteSnapshot(SourceId: Guid; var Snapshot: JsonObject)
    var
        Rows: Record CF_BOMBuffer temporary;
    begin
        LoadRows(SourceId, Rows);
        WriteSnapshot(Rows, Snapshot);
    end;

    procedure WriteSnapshot(var SourceRows: Record CF_BOMBuffer temporary; var Snapshot: JsonObject)
    var
        Rows: Record CF_BOMBuffer temporary;
        Entries: JsonArray;
        Entry: JsonObject;
        RowRef: RecordRef;
        Field: FieldRef;
        FieldNo: Integer;
        IntegerValue: Integer;
    begin
        Rows.Copy(SourceRows, true);
        Rows.Reset();
        Rows.SetCurrentKey("Source Line ID", "Sort Order");
        if Rows.FindSet() then
            repeat
                Clear(Entry);
                RowRef.GetTable(Rows);
                for FieldNo := 1 to 38 do begin
                    if FieldNo in [31, 32, 33] then
                        continue;
                    Field := RowRef.Field(FieldNo);
                    if Field.Type = FieldType::Option then begin
                        IntegerValue := Field.Value;
                        Entry.Add(Format(FieldNo, 0, 9), Format(IntegerValue, 0, 9));
                    end else
                        Entry.Add(Format(FieldNo, 0, 9), Format(Field.Value, 0, 9));
                end;
                Entries.Add(Entry);
            until Rows.Next() = 0;
        Snapshot.Add('structure', Entries);
    end;

    procedure ReadSnapshot(var Order: Record "Production Order"; var Rows: Record CF_BOMBuffer temporary)
    var
        Snapshot: JsonObject;
        Entry: JsonObject;
        Entries: JsonArray;
        Token: JsonToken;
        Input: InStream;
        RowRef: RecordRef;
        Field: FieldRef;
        Index: Integer;
        FieldNo: Integer;
        IntegerValue: Integer;
        DecimalValue: Decimal;
        BooleanValue: Boolean;
        GuidValue: Guid;
        FormulaValue: DateFormula;
        Value: Text;
        ValidationLine: Record "Sales Line" temporary;
    begin
        Order.TestField(CF_ConfigVersion, 3);
        Order.CalcFields(CF_ConfigSnapshot);
        Order.CF_ConfigSnapshot.CreateInStream(Input, TextEncoding::UTF8);
        Snapshot.ReadFrom(Input);
        if not Snapshot.Get('structure', Token) or not Token.IsArray() then
            Error('Production order %1 has no valid BOM structure snapshot.', Order."No.");
        Entries := Token.AsArray();
        Rows.Reset();
        Rows.DeleteAll();
        if (Entries.Count() < 1) or (Entries.Count() > 10000) then
            Error('Production order %1 has an invalid BOM structure size.', Order."No.");
        for Index := 0 to Entries.Count() - 1 do begin
            Entries.Get(Index, Token);
            Entry := Token.AsObject();
            Rows.Init();
            RowRef.GetTable(Rows);
            for FieldNo := 1 to 38 do begin
                if FieldNo in [31, 32, 33] then
                    continue;
                if not Entry.Get(Format(FieldNo, 0, 9), Token) then begin
                    if FieldNo >= 34 then
                        continue;
                    Error('Production order %1 has an incomplete BOM structure snapshot.', Order."No.");
                end;
                Value := Token.AsValue().AsText();
                Field := RowRef.Field(FieldNo);
                case Field.Type of
                    FieldType::Integer, FieldType::Option:
                        begin
                            Evaluate(IntegerValue, Value, 9);
                            Field.Value := IntegerValue;
                        end;
                    FieldType::Decimal:
                        begin
                            Evaluate(DecimalValue, Value, 9);
                            Field.Value := DecimalValue;
                        end;
                    FieldType::Boolean:
                        begin
                            Evaluate(BooleanValue, Value, 9);
                            Field.Value := BooleanValue;
                        end;
                    FieldType::Guid:
                        begin
                            Evaluate(GuidValue, Value);
                            Field.Value := GuidValue;
                        end;
                    FieldType::DateFormula:
                        begin
                            Evaluate(FormulaValue, Value, 9);
                            Field.Value := FormulaValue;
                        end;
                    FieldType::Code, FieldType::Text:
                        Field.Value := Value;
                    else
                        Error('Unsupported BOM snapshot field %1.', FieldNo);
                end;
            end;
            RowRef.SetTable(Rows);
            if Rows."Base Selection Set" then
                if not Entry.Contains('34') or not Entry.Contains('35') then
                    Error('Production order %1 has an incomplete base manufacturing selection.', Order."No.");
            Rows.TestField("Source Line ID", Order.CF_SourceLineId);
            Rows.Insert();
        end;
        Rows.SetCurrentKey("Source Line ID", "Sort Order");
        ValidationLine.SystemId := Order.CF_SourceLineId;
        ValidationLine."No." := Order.CF_ParentItemNo;
        ValidationLine."Variant Code" := Order.CF_ParentVariantCode;
        ValidateTree(ValidationLine, Rows, false);
    end;
}
