namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.BOM;
using Microsoft.Inventory.BOM.Tree;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Planning;
using Microsoft.Inventory.Location;
using Microsoft.Manufacturing.ProductionBOM;
using Microsoft.Manufacturing.Routing;
using Microsoft.Sales.Document;
using Microsoft.Foundation.UOM;

codeunit 91009 CF_BOMTreeMgt
{
    EventSubscriberInstance = Manual;

    procedure Generate(SalesLine: Record "Sales Line"; var Choices: Record CF_DocumentLineProductConfig temporary; var Rows: Record CF_BOMBuffer temporary)
    var
        Reader: Record CF_DocumentLineProductConfig temporary;
        Root: Record CF_BOMBuffer temporary;
        ChoiceRoot: Record CF_BOMBuffer temporary;
        DocumentMgt: Codeunit CF_DocumentConfigMgt;
        BOMPath: List of [Code[20]];
    begin
        Rows.Reset();
        Rows.DeleteAll();
        Source := SalesLine;
        GeneratingAddedBranch := false;
        DocumentMgt.InitializeBase(Source);
        Clear(ItemPath);
        AppendItem(SalesLine."No.", SalesLine."Variant Code", '', Root, Rows, true, false, SalesLine."Location Code");
        Resequence(Rows);
        Rows.SetCurrentKey("Source Line ID", "Sort Order");
        Rows.FindFirst();
        Root := Rows;
        Root."Source Context" := Context(SalesLine);
        Root."Generated Date" := WorkDate();
        Root."Base BOM" := Source.CF_BaseBOMNo;
        Root."Base Routing" := Source.CF_BaseRoutingNo;
        Root."Base Selection Set" := true;
        Rows := Root;
        Rows.Modify();
        GeneratingAddedBranch := true;
        Reader.Copy(Choices, true);
        Reader.Reset();
        if Reader.FindSet() then
            repeat
                if Reader."Choice Code" <> '' then begin
                    if Reader."Component Type" = Reader."Component Type"::Item then
                        AppendItem(Reader."Component Item No.", Reader."Component Variant Code", Reader."Component UOM Code", Root, Rows, false, false,
                            ComponentLocation(Root))
                    else begin
                        NewRow(Root, Rows);
                        Rows.Type := Rows.Type::CF_ProductionBOM;
                        Rows."No." := Reader."Component Item No.";
                        Rows."Unit of Measure Code" := Reader."Component UOM Code";
                        Rows."Location Code" := ComponentLocation(Root);
                        SetBOMDescription(Rows);
                        Rows.Insert();
                    end;
                    ChoiceRoot := Rows;
                    // AppendItem leaves the new item root selected, not its final descendant.
                    ChoiceRoot."Quantity per" := Reader."Quantity per Unit";
                    ChoiceRoot."Routing Link Code" := Reader."Routing Link Code";
                    ChoiceRoot."Configuration Option" := Reader."Configuration Option";
                    ChoiceRoot."Choice Code" := Reader."Choice Code";
                    ChoiceRoot."Selection ID" := Reader.SystemId;
                    ChoiceRoot."Choice Root" := true;
                    ChoiceRoot."Direct Addition" := true;
                    Rows := ChoiceRoot;
                    Rows.Modify();
                    if ChoiceRoot.Type = ChoiceRoot.Type::CF_ProductionBOM then
                        AppendBOM(ChoiceRoot, Rows, BOMPath);
                end;
            until Reader.Next() = 0;
        Resequence(Rows);
        Rows.Reset();
        Rows.SetCurrentKey("Source Line ID", "Sort Order");
        Rows.FindFirst();
    end;

    procedure GenerateBranch(SalesLine: Record "Sales Line"; Parent: Record CF_BOMBuffer; ItemNo: Code[20]; BOM: Boolean; var Branch: Record CF_BOMBuffer temporary)
    var
        BOMHeader: Record "Production BOM Header";
        VersionMgt: Codeunit VersionManagement;
        Path: List of [Code[20]];
    begin
        Source := SalesLine;
        GeneratingAddedBranch := true;
        Clear(ItemPath);
        Branch.Reset();
        Branch.DeleteAll();
        if not BOM then
            AppendItem(ItemNo, '', '', Parent, Branch, false, false, ComponentLocation(Parent))
        else begin
            NewRow(Parent, Branch);
            Branch.Type := Branch.Type::CF_ProductionBOM;
            Branch."No." := ItemNo;
            Branch."Location Code" := ComponentLocation(Parent);
            BOMHeader.Get(ItemNo);
            Branch.Description := BOMHeader.Description;
            Branch."Unit of Measure Code" := VersionMgt.GetBOMUnitOfMeasure(ItemNo, VersionMgt.GetBOMVersion(ItemNo, WorkDate(), true));
            Branch.Insert();
            AppendBOM(Branch, Branch, Path);
        end;
        Resequence(Branch);
    end;

    procedure GetComponents(var Rows: Record CF_BOMBuffer temporary; ParentId: Guid; var Components: Record CF_BOMBuffer temporary)
    begin
        Components.Reset();
        Components.DeleteAll();
        CollectComponents(Rows, ParentId, Components, 1, 0, '');
    end;

    local procedure CollectComponents(var Rows: Record CF_BOMBuffer temporary; ParentId: Guid; var Components: Record CF_BOMBuffer temporary; Factor: Decimal; ParentScrap: Decimal; RoutingLink: Code[10])
    var
        Children: Record CF_BOMBuffer temporary;
        Scrap: Decimal;
        Link: Code[10];
    begin
        Children.Copy(Rows, true);
        Children.Reset();
        Children.SetCurrentKey("Source Line ID", "Sort Order");
        Children.SetRange("Parent Node ID", ParentId);
        if Children.FindSet() then
            repeat
                Scrap := (1 + ParentScrap / 100) * (1 + Children."Scrap %" / 100) * 100 - 100;
                Link := Children."Routing Link Code";
                if Link = '' then
                    Link := RoutingLink;
                case Children.Type of
                    Children.Type::CF_ProductionBOM:
                        CollectComponents(Rows, Children."Node ID", Components, Factor * Children."Quantity per", Scrap, Link);
                    Children.Type::Item:
                        begin
                            Components := Children;
                            Components."Quantity per" *= Factor;
                            Components."Scrap %" := Scrap;
                            Components."Routing Link Code" := Link;
                            Components.Insert(false);
                        end;
                end;
            until Children.Next() = 0;
    end;

    procedure GetComponentQuantityPer(Row: Record CF_BOMBuffer; ParentQtyPerUOM: Decimal): Decimal
    var
        Item: Record Item;
        UOMMgt: Codeunit "Unit of Measure Management";
        Precision: Decimal;
        QuantityPer: Decimal;
    begin
        Item.Get(Row."No.");
        QuantityPer := Row."Quantity per" * ParentQtyPerUOM;
        Precision := UOMMgt.GetQtyRoundingPrecision(Item, Row."Unit of Measure Code");
        if not Row."Choice Root" and (Precision > 0) and (Precision < 1) then
            QuantityPer := Round(QuantityPer, Precision);
        exit(QuantityPer);
    end;

    procedure Context(SalesLine: Record "Sales Line"): Text[250]
    begin
        if SalesLine.CF_BaseSetupSet then
            exit(StrSubstNo('%1|%2|%3|%4|%5|%6', SalesLine."No.", SalesLine."Variant Code", SalesLine."Location Code",
                SalesLine."Unit of Measure Code", SalesLine.CF_BaseBOMNo, SalesLine.CF_BaseRoutingNo));
        exit(StrSubstNo('%1|%2|%3|%4', SalesLine."No.", SalesLine."Variant Code", SalesLine."Location Code", SalesLine."Unit of Measure Code"));
    end;

    local procedure AppendItem(ItemNo: Code[20]; Variant: Code[10]; UOM: Code[10]; Parent: Record CF_BOMBuffer; var Rows: Record CF_BOMBuffer temporary; IsRoot: Boolean; ReuseRoot: Boolean; Location: Code[10])
    var
        Item: Record Item;
        Native: Record "BOM Buffer" temporary;
        Row: Record CF_BOMBuffer temporary;
        NewRoot: Record CF_BOMBuffer temporary;
        NativeTree: Codeunit "Calculate BOM Tree";
        Parents: Dictionary of [Integer, Guid];
        RootIndent: Integer;
        EntryNo: Integer;
        ParentId: Guid;
        Children: List of [Guid];
        ChildId: Guid;
        Child: Record CF_BOMBuffer temporary;
    begin
        if ItemPath.Contains(ItemNo) or (ItemPath.Count() >= 50) then
            Error('Circular or excessive-depth item structure at item %1.', ItemNo);
        ItemPath.Add(ItemNo);
        Item.Get(ItemNo);
        Item.SetRange("Location Filter", Location);
        Item.SetRange("Variant Filter", Variant);
        Item.SetRange("Date Filter", 0D, WorkDate());
        ActiveRootItem := ItemNo;
        ActiveRootVariant := Variant;
        ActiveRootLocation := Location;
        OverrideRootSKU := true;
        SalesRoot := IsRoot;
        Metadata.Reset();
        Metadata.DeleteAll();
        BindSubscription(this);
        NativeTree.GenerateTreeForOneItem(Item, Native, WorkDate(), "BOM Tree Type"::" ");
        UnbindSubscription(this);
        OverrideRootSKU := false;
        Native.Reset();
        if Native.IsEmpty() then
            Native.TransferFromItem(EntryNo, Item, WorkDate());
        if ReuseRoot then
            RootIndent := Parent.Indentation
        else
            if IsRoot then
            RootIndent := 0
            else
                RootIndent := Parent.Indentation + 1;
        Native.FindSet();
        repeat
            if (Native.Indentation = 0) and ReuseRoot then begin
                NewRoot := Parent;
                Parents.Set(0, Parent."Node ID");
                continue;
            end;
            NewRow(Parent, Rows);
            Row := Rows;
            Row.Indentation := RootIndent + Native.Indentation;
            if Native.Indentation = 0 then begin
                Row."Parent Node ID" := Parent."Node ID";
                if IsRoot then
                    Clear(Row."Parent Node ID");
            end else begin
                if not Parents.Get(Native.Indentation - 1, ParentId) then
                    Error('The native BOM tree has an invalid hierarchy at entry %1.', Native."Entry No.");
                Row."Parent Node ID" := ParentId;
            end;
            Parents.Set(Native.Indentation, Row."Node ID");
            Row.Type := Native.Type;
            Row."No." := Native."No.";
            Row.Description := Native.Description;
            Row."Variant Code" := Native."Variant Code";
            Row."Unit of Measure Code" := Native."Unit of Measure Code";
            Row."Quantity per" := Native."Qty. per Parent";
            if Native.Indentation = 0 then
                Row."Location Code" := Location
            else begin
                Child := Parent;
                Child.Type := Child.Type::Item;
                Child."No." := ItemNo;
                Child."Variant Code" := Variant;
                Child."Location Code" := Location;
                Row."Location Code" := ComponentLocation(Child);
            end;
            Metadata.Reset();
            Metadata.SetRange("Sort Order", Native."Entry No.");
            if Metadata.FindFirst() then begin
                Row."Routing Link Code" := Metadata."Routing Link Code";
                Row."Calculation Formula" := Metadata."Calculation Formula";
                Row.Length := Metadata.Length;
                Row.Width := Metadata.Width;
                Row.Depth := Metadata.Depth;
                Row.Weight := Metadata.Weight;
                Row."Scrap %" := Metadata."Scrap %";
                Row."Lead-Time Offset" := Metadata."Lead-Time Offset";
                Row.Position := Metadata.Position;
                Row."Position 2" := Metadata."Position 2";
                Row."Position 3" := Metadata."Position 3";
                Row."Description 2" := Metadata."Description 2";
                Row."Quantity per" := Metadata."Quantity per";
            end;
            if Native.Indentation = 0 then begin
                Row."Quantity per" := 1;
                Row."Variant Code" := Variant;
                if UOM <> '' then
                    Row."Unit of Measure Code" := UOM;
                NewRoot := Row;
            end;
            Rows := Row;
            Rows.Insert();
            if Native.Indentation > 0 then
                if IsProductionItem(Row) then
                    Children.Add(Row."Node ID");
        until Native.Next() = 0;
        foreach ChildId in Children do begin
            Rows.Get(Source.SystemId, ChildId);
            Child := Rows;
            AppendItem(Child."No.", Child."Variant Code", Child."Unit of Measure Code", Child, Rows, false, true, Child."Location Code");
        end;
        ItemPath.Remove(ItemNo);
        Rows := NewRoot;
    end;

    local procedure AppendBOM(Parent: Record CF_BOMBuffer; var Rows: Record CF_BOMBuffer temporary; var Path: List of [Code[20]])
    var
        Header: Record "Production BOM Header";
        Version: Record "Production BOM Version";
        Line: Record "Production BOM Line";
        Child: Record CF_BOMBuffer temporary;
        VersionMgt: Codeunit VersionManagement;
        VersionCode: Code[20];
    begin
        if Path.Contains(Parent."No.") or (Path.Count() >= 50) then
            Error('Circular or excessive-depth production BOM reference %1.', Parent."No.");
        Path.Add(Parent."No.");
        Header.Get(Parent."No.");
        VersionCode := VersionMgt.GetBOMVersion(Parent."No.", WorkDate(), true);
        if VersionCode = '' then
            Header.TestField(Status, Header.Status::Certified)
        else begin
            Version.Get(Parent."No.", VersionCode);
            Version.TestField(Status, Version.Status::Certified);
        end;
        Parent.TestField("Unit of Measure Code", VersionMgt.GetBOMUnitOfMeasure(Parent."No.", VersionCode));
        Line.SetRange("Production BOM No.", Parent."No.");
        Line.SetRange("Version Code", VersionCode);
        Line.SetFilter("Starting Date", '%1|..%2', 0D, WorkDate());
        Line.SetFilter("Ending Date", '%1|%2..', 0D, WorkDate());
        if Line.FindSet() then
            repeat
                case Line.Type of
                    Line.Type::Item:
                        AppendItem(Line."No.", Line."Variant Code", Line."Unit of Measure Code", Parent, Rows, false, false, Parent."Location Code");
                    Line.Type::"Production BOM":
                        begin
                            NewRow(Parent, Rows);
                            Rows.Type := Rows.Type::CF_ProductionBOM;
                            Rows."No." := Line."No.";
                            Rows."Unit of Measure Code" := Line."Unit of Measure Code";
                            SetBOMDescription(Rows);
                            Rows.Insert();
                        end;
                    else
                        continue;
                end;
                Child := Rows;
                Child.CopyBOMFields(Line);
                Child."Quantity per" := Line."Quantity per";
                Rows := Child;
                Rows.Modify();
                if Child.Type = Child.Type::CF_ProductionBOM then begin
                    // Phantom multiplication uses its calculated quantity; item formulas stay native.
                    Child."Quantity per" := Line.Quantity;
                    Child."Calculation Formula" := Child."Calculation Formula"::" ";
                    Rows := Child;
                    Rows.Modify();
                    AppendBOM(Child, Rows, Path);
                end;
            until Line.Next() = 0;
        Path.Remove(Parent."No.");
    end;

    local procedure NewRow(Parent: Record CF_BOMBuffer; var Rows: Record CF_BOMBuffer temporary)
    var
        Last: Record CF_BOMBuffer temporary;
        SortOrder: Integer;
    begin
        Last.Copy(Rows, true);
        Last.Reset();
        Last.SetCurrentKey("Source Line ID", "Sort Order");
        if Last.FindLast() then
            SortOrder := Last."Sort Order";
        Rows.Init();
        Rows."Source Line ID" := Source.SystemId;
        Rows."Node ID" := CreateGuid();
        Rows."Parent Node ID" := Parent."Node ID";
        Rows.Indentation := Parent.Indentation + 1;
        Rows."Sort Order" := SortOrder + 10000;
        Rows."Quantity per" := 1;
        Rows."Location Code" := Parent."Location Code";
        Rows."Configurator Added" := GeneratingAddedBranch;
    end;

    local procedure ComponentLocation(Parent: Record CF_BOMBuffer): Code[10]
    var
        SKU: Record "Stockkeeping Unit";
        Planning: Codeunit "Planning-Get Parameters";
    begin
        if Parent.Type = Parent.Type::CF_ProductionBOM then
            exit(Parent."Location Code");
        Planning.AtSKU(SKU, Parent."No.", Parent."Variant Code", Parent."Location Code");
        exit(SKU."Components at Location");
    end;

    local procedure IsProductionItem(Row: Record CF_BOMBuffer): Boolean
    var
        SKU: Record "Stockkeeping Unit";
        Planning: Codeunit "Planning-Get Parameters";
    begin
        if Row.Type <> Row.Type::Item then
            exit(false);
        Planning.AtSKU(SKU, Row."No.", Row."Variant Code", Row."Location Code");
        exit(SKU.IsMfgSKU());
    end;

    local procedure Resequence(var Rows: Record CF_BOMBuffer temporary)
    var
        Reader: Record CF_BOMBuffer temporary;
        Ids: List of [Guid];
        Id: Guid;
        ParentId: Guid;
        Counter: Integer;
    begin
        Reader.Copy(Rows, true);
        Reader.Reset();
        Reader.SetCurrentKey("Source Line ID", "Sort Order");
        if not Reader.FindSet() then
            exit;
        ParentId := Reader."Parent Node ID";
        repeat
            Ids.Add(Reader."Node ID");
        until Reader.Next() = 0;
        foreach Id in Ids do begin
            Rows.Get(Source.SystemId, Id);
            Rows."Sort Order" := -Rows."Sort Order";
            Rows.Modify();
        end;
        SequenceChildren(ParentId, Rows, Counter);
    end;

    local procedure SequenceChildren(ParentId: Guid; var Rows: Record CF_BOMBuffer temporary; var Counter: Integer)
    var
        Reader: Record CF_BOMBuffer temporary;
        Ids: List of [Guid];
        Id: Guid;
    begin
        Reader.Copy(Rows, true);
        Reader.Reset();
        Reader.SetCurrentKey("Source Line ID", "Sort Order");
        Reader.Ascending(false);
        Reader.SetRange("Parent Node ID", ParentId);
        if Reader.FindSet() then
            repeat
                Ids.Add(Reader."Node ID");
            until Reader.Next() = 0;
        foreach Id in Ids do begin
            Rows.Get(Source.SystemId, Id);
            Counter += 10000;
            Rows."Sort Order" := Counter;
            Rows.Modify();
            SequenceChildren(Id, Rows, Counter);
        end;
    end;

    local procedure SetBOMDescription(var Row: Record CF_BOMBuffer)
    var
        Header: Record "Production BOM Header";
    begin
        Header.Get(Row."No.");
        Row.Description := Header.Description;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Calculate BOM Tree", 'OnBeforeGenerateTreeForItemLocal', '', false, false)]
    local procedure SetRootSKU(var ParentItem: Record Item; DemandDate: Date; TreeType: Option; var BOMBuffer: Record "BOM Buffer"; var IsHandled: Boolean)
    begin
        ApplyRootSKU(ParentItem);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Calculate BOM Tree", 'OnGenerateItemSubTreeOnAfterParentItemGet', '', false, false)]
    local procedure SetSubtreeSKU(var ParentItem: Record Item)
    begin
        if ParentItem."No." <> ActiveRootItem then begin
            // Expand manufactured children separately with their own variant/location SKU context.
            ParentItem."Production BOM No." := '';
            ParentItem."Routing No." := '';
            exit;
        end;
        ApplyRootSKU(ParentItem);
    end;

    local procedure ApplyRootSKU(var ParentItem: Record Item)
    var
        SKU: Record "Stockkeeping Unit";
        Planning: Codeunit "Planning-Get Parameters";
    begin
        if not OverrideRootSKU or (ParentItem."No." <> ActiveRootItem) then
            exit;
        Planning.AtSKU(SKU, ParentItem."No.", ActiveRootVariant, ActiveRootLocation);
        ParentItem."Production BOM No." := SKU."Production BOM No.";
        ParentItem."Routing No." := SKU."Routing No.";
        if SalesRoot then begin
            ParentItem."Production BOM No." := Source.CF_BaseBOMNo;
            ParentItem."Routing No." := Source.CF_BaseRoutingNo;
        end;
        ParentItem."Replenishment System" := SKU."Replenishment System";
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Mfg. Calculate BOM Tree", 'OnAfterTransferFromProdItem', '', false, false)]
    local procedure CaptureSource(var BOMBuffer: Record "BOM Buffer"; ProdBOMLine: Record "Production BOM Line"; var EntryNo: Integer)
    begin
        Metadata.Reset();
        Metadata.SetRange("Sort Order", BOMBuffer."Entry No.");
        Metadata.FindFirst();
        if ProdBOMLine."Quantity per" <> 0 then
            Metadata."Quantity per" *= BOMBuffer."Qty. per BOM Line" / ProdBOMLine."Quantity per";
        Metadata.Modify();
    end;

    [EventSubscriber(ObjectType::Table, Database::"BOM Buffer", 'OnBeforeTransferFromProdComp', '', false, false)]
    local procedure CaptureBOMUnit(var EntryNo: Integer; ProductionBOMLine: Record "Production BOM Line"; NewIndentation: Integer; ParentQtyPer: Decimal; ParentScrapQtyPer: Decimal; ParentScrapPct: Decimal; NeedByDate: Date; ParentLocationCode: Code[10]; ParentItem: Record Item; BOMQtyPerUOM: Decimal; var IsHandled: Boolean)
    begin
        if BOMQtyPerUOM <= 0 then
            Error('The native BOM unit conversion must be positive.');
        Metadata.Init();
        Metadata."Source Line ID" := Source.SystemId;
        Metadata."Node ID" := CreateGuid();
        Metadata."Sort Order" := EntryNo + 1;
        Metadata.CopyBOMFields(ProductionBOMLine);
        Metadata."Quantity per" := ProductionBOMLine."Quantity per" / BOMQtyPerUOM;
        // Native item scrap is recalculated from output demand; retain only phantom ancestry scrap.
        Metadata."Scrap %" := ((1 + ProductionBOMLine."Scrap %" / 100) *
            (1 + ParentScrapPct / 100) / (1 + ParentItem."Scrap %" / 100) - 1) * 100;
        Metadata.Insert();
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Mfg. Calculate BOM Tree", 'OnAfterTransferFromProdRouting', '', false, false)]
    local procedure CaptureOperation(var BOMBuffer: Record "BOM Buffer"; var RoutingLine: Record "Routing Line")
    begin
        Metadata.Init();
        Metadata."Source Line ID" := Source.SystemId;
        Metadata."Node ID" := CreateGuid();
        Metadata."Sort Order" := BOMBuffer."Entry No.";
        Metadata."Routing Link Code" := RoutingLine."Routing Link Code";
        Metadata."Quantity per" := BOMBuffer."Qty. per Parent";
        Metadata.Insert();
    end;

    var
        Source: Record "Sales Line";
        Metadata: Record CF_BOMBuffer temporary;
        ActiveRootItem: Code[20];
        ActiveRootVariant: Code[10];
        ActiveRootLocation: Code[10];
        ItemPath: List of [Code[20]];
        OverrideRootSKU: Boolean;
        SalesRoot: Boolean;
        GeneratingAddedBranch: Boolean;
}
