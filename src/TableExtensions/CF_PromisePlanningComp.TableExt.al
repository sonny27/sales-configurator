namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Planning;

tableextension 91005 CF_PromisePlanningComp extends "Planning Component"
{
    fields
    {
        field(91000; CF_BOMNodeId; Guid) { Caption = 'Configuration BOM Node ID'; DataClassification = CustomerContent; Editable = false; }
    }
}
