namespace CloudFactory.SalesConfigurator;

using Microsoft.Manufacturing.Document;

reportextension 91000 CF_ReplanProductionOrder extends "Replan Production Order"
{
    dataset
    {
        modify("Production Order")
        {
            trigger OnBeforeAfterGetRecord()
            var
                ConfiguratorMgt: Codeunit CF_ConfiguratorMgt;
            begin
                ConfiguratorMgt.CheckUnsupportedOperation("Production Order", 'Replan Production Order');
            end;
        }
    }
}
