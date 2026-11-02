namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Requisition;

tableextension 91004 CF_PromiseReqLine extends "Requisition Line"
{
    fields
    {
        field(91000; CF_PromiseContextId; Guid) { Caption = 'Configuration Promising Context ID'; DataClassification = CustomerContent; Editable = false; }
        field(91001; CF_BOMNodeId; Guid) { Caption = 'Configuration BOM Node ID'; DataClassification = CustomerContent; Editable = false; }
    }
    keys
    {
        key(CF_Promise; CF_PromiseContextId) { }
    }
}
