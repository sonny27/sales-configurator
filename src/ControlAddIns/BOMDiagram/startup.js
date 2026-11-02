(function () {
    function start() {
        try {
            window.CFBOMDiagram.initialize();
            Microsoft.Dynamics.NAV.InvokeExtensibilityMethod("ControlReady", []);
        } catch (error) {
            if (window.CFBOMDiagram && window.CFBOMDiagram.reportError) {
                window.CFBOMDiagram.reportError(error);
                return;
            }
            const alert = document.createElement("p");
            alert.textContent = "BOM diagram startup failed: " + error.message;
            alert.className = "error";
            alert.setAttribute("role", "alert");
            (document.getElementById("controlAddIn") || document.body).prepend(alert);
            console.error("Configured BOM diagram startup:", error);
            Microsoft.Dynamics.NAV.InvokeExtensibilityMethod("RenderFailed", [error.message]);
        }
    }
    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", start, { once: true });
    } else {
        start();
    }
}());
