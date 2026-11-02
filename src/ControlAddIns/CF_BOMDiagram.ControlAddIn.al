namespace CloudFactory.SalesConfigurator;

controladdin CF_BOMDiagram
{
    Scripts = 'src/ControlAddIns/BOMDiagram/diagram.js';
    StartupScript = 'src/ControlAddIns/BOMDiagram/startup.js';
    RefreshScript = 'src/ControlAddIns/BOMDiagram/startup.js';
    RecreateScript = 'src/ControlAddIns/BOMDiagram/startup.js';
    StyleSheets = 'src/ControlAddIns/BOMDiagram/diagram.css';
    HorizontalStretch = true;
    VerticalStretch = true;
    RequestedHeight = 650;
    MinimumHeight = 420;

    event ControlReady();
    event RenderFailed(Details: Text);
    event OpenNode(NodeId: Text);
    procedure Load(Payload: JsonObject);
}
