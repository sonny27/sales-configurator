# Base App: Sales Order to Production Order Flow

## Scope

This document describes the standard Business Central **Create Prod. Order** action shown in the Sales Order Planning page. The behavior below was traced in the supplied Base Application 28 AL source. It is reference material for the Sales Configurator project; it does not describe customizations in this project.

## User flow

1. Open **Sales Order Planning** from a sales order. The page builds temporary planning lines for the order's item sales lines, showing their item, variant, shipment date, reservation/planning status, and availability.
2. Choose **Create Prod. Order**. The Manufacturing page extension adds this action to Sales Order Planning and opens the **Create Order From Sales** confirmation dialog.
3. In the dialog, choose a production order status and an order type:
   - The default status is **Firm Planned**.
   - The first/default order type is **Item Order**. The other option is **Project Order**.
4. Confirm to create the order(s). Canceling the dialog exits without creating production orders.

## Which sales lines are processed

The action iterates the planning lines in its current record set; it is not limited to the highlighted row. For each planning line, the base application retrieves its sales order line and:

- Requires a **Shipment Date**.
- Requires outstanding quantity (base) to exceed reserved quantity (base).
- Checks that the item/SKU replenishment system is **Prod. Order** and that the item and, when applicable, the variant are not blocked from production.

The action does not require the item to have a BOM or routing in order to pass this eligibility check. Missing or invalid manufacturing setup may still affect the later production-order calculation.

## Item Order behavior

For each eligible planning line, the base application creates an item-sourced production order. It sets the production order's due date from the sales line's shipment date, and uses the sales line's item, variant, description, location, bin, and outstanding unreserved quantity.

The production order line is initialized by validating its item number. That loads the item's production BOM and routing. A matching SKU for the location and variant can override the item's routing or BOM when the SKU field is populated. The line's BOM/routing versions are validated according to the production setup and relevant dates.

The application then calculates the production order structure:

- Routing operations are copied from the applicable routing to production order routing lines.
- Production BOM components are copied to production order components, with component requirements calculated from the order quantity and BOM quantities.
- Nested production BOMs are transferred recursively.
- Component routing links, scrap, and applicable version/date rules are considered during calculation.

For an item with a valid BOM and routing, the resulting firm-planned order therefore contains the item production line, its routing operations, and its BOM component lines. Item tracking/reservations are also copied or linked where applicable. If the chosen status is **Released**, the order is created in that status and status-management code flushes it after line creation.

The Sales Configurator extension adds selected component items after standard BOM calculation without changing the item/SKU BOM. See [Configure to Sales Order Create Production Order](<Configure to Sales Order Create Production Order.md>) for the implementation, safeguards, and setup steps.

## Project Order behavior

Project Order creates one production order sourced from the sales order header, rather than one item-sourced order for each planning line. The code stops iterating after the project order is created. While building the order, it collects eligible item lines from that sales order and creates the corresponding production order lines, ordered by low-level code. It can therefore include multiple eligible production-replenished lines from the sales order, not just the currently highlighted line.

## Practical checks when the action creates no order

Check the following:

1. The sales line has a shipment date.
2. The line has outstanding quantity that is not already reserved.
3. The item's replenishment system, or the applicable SKU's replenishment system, is **Prod. Order**.
4. The item and variant are not blocked from production.
5. The production BOM/routing assigned on the item or SKU is certified/valid for the applicable date and has valid versions and lines.
6. The current planning page record set includes the sales line you expect to process.

The action's eligibility check is driven by replenishment, blocking, shipment date, and unreserved quantity—not by the mere presence of a BOM or routing.

## Base Application objects traced

| Object | Role |
|---|---|
| Page 99000883, **Sales Order Planning** | Builds and displays planning lines for a sales order. |
| Page extension 99000883, **Mfg. Sales Order Planning** | Adds **Create Prod. Order**, gathers dialog parameters, checks eligibility, and calls the creation codeunit. |
| Page 99000884, **Create Order From Sales** | Collects production order status and order type. |
| Codeunit 99000792, **Create Prod. Order from Sale** | Creates the production order, sets source and dates/quantity, then invokes production-line creation. |
| Codeunit 99000787, **Create Prod. Order Lines** | Creates production order lines and drives calculation of routing, BOM components, and multilevel structure. |
| Codeunit **Calculate Prod. Order** | Transfers routing operations and BOM components and calculates their requirements. |
| Table **Prod. Order Line** | Loads item manufacturing data and applies SKU overrides when initializing a production order line. |

## Source files

The analysis used these files in the supplied Base Application 28 source:

- `src/Sales/Document/SalesOrderPlanning.Page.al`
- `src/Manufacturing/Sales/Document/MfgSalesOrderPlanning.PageExt.al`
- `src/Manufacturing/Document/CreateOrderFromSales.Page.al`
- `src/Manufacturing/Document/CreateProdOrderfromSale.Codeunit.al`
- `src/Manufacturing/Document/CreateProdOrderLines.Codeunit.al`
- `src/Manufacturing/Document/CalculateProdOrder.Codeunit.al`
- `src/Manufacturing/Document/ProdOrderLine.Table.al`
- `src/Manufacturing/Document/CreateProductionOrderType.Enum.al`
