namespace CloudFactory.SalesConfigurator;

using Microsoft.Inventory.Availability;

pageextension 91004 CF_ConfigOrderPromising extends "Order Promising Lines"
{
    layout
    {
        modify("Item No.")
        {
            Style = Unfavorable;
            StyleExpr = LatePromise;
        }
        modify(Description)
        {
            Style = Unfavorable;
            StyleExpr = LatePromise;
        }
        modify("Requested Delivery Date")
        {
            Style = Unfavorable;
            StyleExpr = LatePromise;
        }
        modify("Requested Shipment Date")
        {
            Style = Unfavorable;
            StyleExpr = LatePromise;
        }
        modify("Planned Delivery Date")
        {
            Style = Unfavorable;
            StyleExpr = LatePromise;
        }
        modify("Original Shipment Date")
        {
            Style = Unfavorable;
            StyleExpr = LatePromise;
        }
        modify("Earliest Shipment Date")
        {
            Style = Unfavorable;
            StyleExpr = LatePromise;
        }
        modify(Quantity)
        {
            Style = Unfavorable;
            StyleExpr = LatePromise;
        }
        modify("Required Quantity")
        {
            Style = Unfavorable;
            StyleExpr = LatePromise;
        }
        modify(CalcAvailability)
        {
            Style = Unfavorable;
            StyleExpr = LatePromise;
        }
        modify("Unavailability Date")
        {
            Style = Unfavorable;
            StyleExpr = LatePromise;
        }
        modify("Unavailable Quantity")
        {
            Style = Unfavorable;
            StyleExpr = LatePromise;
        }
        modify("Unit of Measure Code")
        {
            Style = Unfavorable;
            StyleExpr = LatePromise;
        }
    }

    actions
    {
        modify(AvailableToPromise)
        {
            trigger OnAfterAction()
            begin
                CalculationDone := true;
                CurrPage.Update(false);
            end;
        }
        modify(CapableToPromise)
        {
            trigger OnAfterAction()
            begin
                CalculationDone := true;
                CurrPage.Update(false);
            end;
        }
        modify(AcceptButton)
        {
            trigger OnBeforeAction()
            var
                PlanMgt: Codeunit CF_PromisePlanMgt;
            begin
                PlanMgt.CheckAccept(Rec);
            end;
        }
    }

    trigger OnAfterGetRecord()
    begin
        UpdatePromiseStyle();
    end;

    trigger OnAfterGetCurrRecord()
    begin
        UpdatePromiseStyle();
    end;

    var
        CalculationDone: Boolean;
        LatePromise: Boolean;

    local procedure UpdatePromiseStyle()
    begin
        LatePromise := false;
        if not CalculationDone then
            exit;
        if Rec."Source Type" <> Rec."Source Type"::Sales then
            exit;
        if Rec.Quantity <= 0 then
            exit;

        if Rec."Requested Delivery Date" <> 0D then begin
            LatePromise := (Rec."Planned Delivery Date" = 0D) or
                (Rec."Planned Delivery Date" > Rec."Requested Delivery Date");
            exit;
        end;

        if Rec."Requested Shipment Date" <> 0D then
            LatePromise := (Rec."Earliest Shipment Date" = 0D) or
                (Rec."Earliest Shipment Date" > Rec."Requested Shipment Date")
        else
            if Rec."Original Shipment Date" <> 0D then
                LatePromise := (Rec."Earliest Shipment Date" = 0D) or
                    (Rec."Earliest Shipment Date" > Rec."Original Shipment Date")
            else
                LatePromise := Rec."Earliest Shipment Date" = 0D;
    end;
}
