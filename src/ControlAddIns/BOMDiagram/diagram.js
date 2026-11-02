(function () {
    "use strict";
    const NS = "http://www.w3.org/2000/svg";
    const CARD_WIDTH = 230;
    const CARD_HEIGHT = 112;
    const GAP_X = 26;
    const GAP_Y = 68;
    const PAD = 30;
    const state = {
        root: null, nodes: [], view: null, bounds: null, selected: null, drag: null, fitted: true,
        payload: null, visibleDepth: null, maxDepth: 0, session: null,
        offsets: new Map(), byId: new Map(), cards: new Map(), connections: new Map()
    };

    function element(name, attributes, text) {
        const node = document.createElementNS(NS, name);
        for (const [key, value] of Object.entries(attributes || {})) {
            node.setAttribute(key, value);
        }
        if (text !== undefined) node.textContent = text;
        return node;
    }

    function initialize() {
        if (state.root && state.root.isConnected) return;
        if (state.observer) state.observer.disconnect();
        const host = document.getElementById("controlAddIn");
        if (!host) throw new Error("The Business Central controlAddIn container is missing.");
        const root = document.createElement("main");
        root.className = "diagram";
        const toolbar = document.createElement("div");
        toolbar.className = "toolbar";
        const help = document.createElement("p");
        help.className = "help";
        const viewport = document.createElement("div");
        viewport.className = "viewport";
        const svg = element("svg", { tabindex: "0" });
        const details = document.createElement("div");
        details.className = "details";
        details.setAttribute("aria-live", "polite");
        details.textContent = "Loading BOM diagram...";
        viewport.append(svg);
        root.append(toolbar, help, viewport, details);
        host.replaceChildren(root);
        Object.assign(state, { root, toolbar, help, viewport, svg, details });
        svg.addEventListener("wheel", event => {
            event.preventDefault();
            if (state.drag) return;
            zoom(event.deltaY < 0 ? 0.85 : 1.18, point(event));
        }, { passive: false });
        svg.addEventListener("pointerdown", event => {
            if (event.button !== 0 || !state.view || state.drag) return;
            const card = event.target.closest("[data-node]");
            const start = point(event);
            if (!start) return;
            state.drag = {
                x: event.clientX, y: event.clientY, view: { ...state.view },
                moved: false, card, start, pointerId: event.pointerId, fitted: state.fitted,
                target: card || svg, movement: card ? branchMovement(card.dataset.node) : null
            };
            state.drag.target.setPointerCapture(event.pointerId);
        });
        svg.addEventListener("pointermove", event => {
            if (!state.drag || event.pointerId !== state.drag.pointerId) return;
            const dx = event.clientX - state.drag.x;
            const dy = event.clientY - state.drag.y;
            if (Math.abs(dx) + Math.abs(dy) < 5 && !state.drag.moved) return;
            state.drag.moved = true;
            svg.classList.add("dragging");
            if (state.drag.movement) {
                const current = point(event);
                if (current) moveBranch(state.drag.movement, current.x - state.drag.start.x, current.y - state.drag.start.y);
                return;
            }
            const matrix = svg.getScreenCTM();
            if (!matrix) return;
            state.view.x = state.drag.view.x - dx / matrix.a;
            state.view.y = state.drag.view.y - dy / matrix.d;
            state.fitted = false;
            updateView();
        });
        svg.addEventListener("pointerup", event => {
            if (state.drag && event.pointerId === state.drag.pointerId) finishDrag(false);
        });
        svg.addEventListener("pointercancel", event => {
            if (state.drag && event.pointerId === state.drag.pointerId) finishDrag(true);
        });
        svg.addEventListener("lostpointercapture", event => {
            if (state.drag && event.pointerId === state.drag.pointerId) finishDrag(true);
        });
        svg.addEventListener("dblclick", event => {
            const card = event.target.closest("[data-node]");
            if (card) openCard(card);
        });
        svg.addEventListener("keydown", event => {
            if (state.drag) {
                if (event.key === "Escape") finishDrag(true);
                event.preventDefault();
                return;
            }
            const card = event.target.closest("[data-node]");
            if (event.shiftKey && card && ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(event.key)) {
                event.preventDefault();
                moveBranch(branchMovement(card.dataset.node),
                    event.key === "ArrowLeft" ? -20 : event.key === "ArrowRight" ? 20 : 0,
                    event.key === "ArrowUp" ? -20 : event.key === "ArrowDown" ? 20 : 0);
                select(card);
                return;
            }
            const actions = {
                ArrowUp: () => pan(0, -0.15), ArrowDown: () => pan(0, 0.15),
                ArrowLeft: () => pan(-0.15, 0), ArrowRight: () => pan(0.15, 0),
                "+": () => zoom(0.8), "=": () => zoom(0.8),
                "-": () => zoom(1.25), "0": fit
            };
            if (actions[event.key]) {
                event.preventDefault();
                actions[event.key]();
            } else if (event.key === "Enter" || event.key === " ") {
                if (card) {
                    event.preventDefault();
                    if (event.key === "Enter") openCard(card);
                    else select(card);
                }
            }
        });
        state.observer = new ResizeObserver(() => {
            if (state.fitted && state.bounds) fit();
        });
        state.observer.observe(viewport);
    }

    function setToolbar(labels, includeOperations) {
        state.toolbar.replaceChildren();
        const buttons = [
            [labels.collapse, "\u2191", () => changeLevel(-1), state.visibleDepth === 0, "collapse"],
            [labels.expand, "\u2193", () => changeLevel(1), state.visibleDepth === state.maxDepth, "expand"],
            [labels.zoomIn, "+", () => zoom(0.8)],
            [labels.zoomOut, "-", () => zoom(1.25)],
            [labels.fit, labels.fit, fit],
            [labels.reset, labels.reset, resetLayout, state.offsets.size === 0, "reset"],
            [labels.openCard, labels.openCard, () => openCard(state.selected), !state.selected, "open"]
        ];
        for (const [label, text, action, disabled = false, command] of buttons) {
            const button = document.createElement("button");
            button.type = "button";
            button.textContent = text;
            button.title = label;
            button.setAttribute("aria-label", label);
            button.disabled = disabled;
            if (command) button.dataset.command = command;
            button.addEventListener("click", action);
            state.toolbar.append(button);
        }
        const mode = document.createElement("span");
        mode.className = "mode";
        mode.textContent = includeOperations ? labels.operations : labels.components;
        state.toolbar.append(mode);
        state.help.textContent = labels.help;
        state.svg.setAttribute("aria-label", labels.title);
    }

    function layout(data, visibleDepth) {
        if (!Array.isArray(data.nodes) || !data.nodes.length || data.nodes.length > 10000) {
            throw new Error("The diagram requires between 1 and 10000 BOM rows.");
        }
        const nodes = new Map();
        for (const item of data.nodes) {
            if (!item.id || nodes.has(item.id) || !["item", "bom", "work", "machine"].includes(item.kind)) {
                throw new Error("The BOM diagram contains an invalid or duplicate node.");
            }
            nodes.set(item.id, { ...item, children: [] });
        }
        const roots = [];
        for (const node of nodes.values()) {
            if (!node.parent) {
                roots.push(node);
            } else {
                const parent = nodes.get(node.parent);
                if (!parent || !["item", "bom"].includes(parent.kind)) throw new Error("A BOM diagram parent is invalid.");
                parent.children.push(node);
            }
        }
        if (roots.length !== 1) throw new Error("The BOM diagram must have one finished-item root.");
        const ordered = [];
        const stack = [{ node: roots[0], depth: 0 }];
        const visited = new Set();
        while (stack.length) {
            const { node, depth } = stack.pop();
            if (visited.has(node.id) || depth > 50) throw new Error("The BOM diagram contains a cycle or excessive depth.");
            visited.add(node.id);
            node.depth = depth;
            ordered.push(node);
            for (let i = node.children.length - 1; i >= 0; i--) {
                stack.push({ node: node.children[i], depth: depth + 1 });
            }
        }
        if (visited.size !== nodes.size) throw new Error("The BOM diagram contains disconnected or circular nodes.");
        const maxDepth = ordered.reduce((maximum, node) => Math.max(maximum, node.depth), 0);
        const depthLimit = visibleDepth === null ? maxDepth : Math.min(visibleDepth, maxDepth);
        const visible = ordered.filter(node => node.depth <= depthLimit);
        for (let i = visible.length - 1; i >= 0; i--) {
            const node = visible[i];
            if (node.depth === depthLimit) node.children = [];
            node.width = Math.max(CARD_WIDTH,
                node.children.reduce((sum, child) => sum + child.width, 0) + Math.max(0, node.children.length - 1) * GAP_X);
        }
        roots[0].left = PAD;
        for (const node of visible) {
            node.x = node.left + (node.width - CARD_WIDTH) / 2;
            node.y = PAD + node.depth * (CARD_HEIGHT + GAP_Y);
            let left = node.left;
            for (const child of node.children) {
                child.left = left;
                left += child.width + GAP_X;
            }
        }
        for (const node of ordered) {
            const parent = nodes.get(node.parent);
            const offset = state.offsets.get(node.id);
            node.offsetX = (parent ? parent.offsetX : 0) + (offset ? offset.x : 0);
            node.offsetY = (parent ? parent.offsetY : 0) + (offset ? offset.y : 0);
        }
        for (const node of visible) {
            node.x += node.offsetX;
            node.y += node.offsetY;
        }
        return { nodes: visible, maxDepth, visibleDepth: depthLimit };
    }

    function lines(text, length, count) {
        const remaining = Array.from(text.trim());
        const result = [];
        while (remaining.length && result.length < count) {
            let take = Math.min(length, remaining.length);
            if (take < remaining.length) {
                const space = remaining.slice(0, take + 1).lastIndexOf(" ");
                if (space > 0) take = space;
            }
            result.push(remaining.splice(0, take).join(""));
            while (remaining[0] === " ") remaining.shift();
        }
        if (remaining.length) {
            result[count - 1] = Array.from(result[count - 1]).slice(0, length - 3).join("") + "...";
        }
        return result;
    }

    function details(node, labels) {
        const parts = [node.type + ": " + node.no, node.description, labels.quantity + ": " + node.quantity + " " + node.unit];
        for (const key of ["variant", "option", "choice"]) {
            if (node[key]) parts.push(labels[key] + ": " + node[key]);
        }
        return parts.filter(Boolean).join(" | ");
    }

    function render(data, visibleDepth) {
        const tree = layout(data, visibleDepth);
        const selectedId = state.selected ? state.selected.dataset.node : null;
        state.payload = data;
        state.visibleDepth = tree.visibleDepth;
        state.maxDepth = tree.maxDepth;
        state.labels = data.labels;
        state.nodes = tree.nodes;
        state.byId = new Map(tree.nodes.map(node => [node.id, node]));
        state.cards = new Map();
        state.connections = new Map(tree.nodes.map(node => [node.id, []]));
        state.bounds = measureBounds();
        state.selected = null;
        state.details.textContent = "";
        state.svg.replaceChildren();
        const definitions = element("defs");
        const clip = element("clipPath", { id: "card-content" });
        clip.append(element("rect", { x: 10, y: 4, width: CARD_WIDTH - 20, height: CARD_HEIGHT - 8 }));
        definitions.append(clip);
        state.svg.append(definitions);
        const edges = element("g", { "aria-hidden": "true" });
        const cards = element("g");
        for (const node of tree.nodes) {
            for (const child of node.children) {
                const edge = { from: node, to: child, path: element("path", { class: "edge" }) };
                drawEdge(edge);
                state.connections.get(node.id).push(edge);
                state.connections.get(child.id).push(edge);
                edges.append(edge.path);
            }
            const caption = details(node, data.labels);
            const card = element("g", {
                class: "node " + node.kind + (node.choiceRoot ? " configured" : ""),
                transform: `translate(${node.x},${node.y})`, "data-node": node.id,
                tabindex: "0", role: "button", "aria-label": caption
            });
            card.append(element("title", {}, caption + "\n" + data.labels.openCard));
            card.append(element("rect", { width: CARD_WIDTH, height: CARD_HEIGHT }));
            const content = element("g", { "clip-path": "url(#card-content)" });
            content.append(element("text", { x: 12, y: 18, class: "type" }, lines(node.type, 32, 1)[0] || ""));
            content.append(element("text", { x: 12, y: 39, class: "number" }, node.no));
            lines(node.description, 31, 2).forEach((line, index) => {
                content.append(element("text", { x: 12, y: 60 + index * 16 }, line));
            });
            content.append(element("text", { x: 12, y: 99, class: "quantity" }, data.labels.quantity + ": " + node.quantity + " " + node.unit));
            card.append(content);
            if (node.id === selectedId) {
                state.selected = card;
                card.classList.add("selected");
                state.details.textContent = caption;
            }
            state.cards.set(node.id, card);
            cards.append(card);
        }
        state.svg.append(edges, cards);
        setToolbar(data.labels, data.includeOperations);
        fit();
    }

    function changeLevel(delta) {
        if (!state.payload || !state.bounds) return;
        finishDrag(true);
        const depth = Math.max(0, Math.min(state.maxDepth, state.visibleDepth + delta));
        if (depth === state.visibleDepth) return;
        try {
            render(state.payload, depth);
            const command = delta < 0 ? "collapse" : "expand";
            const button = state.toolbar.querySelector(`[data-command="${command}"]`);
            if (button.disabled) state.svg.focus();
            else button.focus();
        } catch (error) {
            reportError(error);
        }
    }

    function select(card) {
        if (state.selected) state.selected.classList.remove("selected");
        state.selected = card;
        card.classList.add("selected");
        const node = state.nodes.find(item => item.id === card.dataset.node);
        state.details.textContent = details(node, state.labels);
        state.toolbar.querySelector('[data-command="open"]').disabled = false;
    }

    function openCard(card) {
        if (!card) return;
        select(card);
        Microsoft.Dynamics.NAV.InvokeExtensibilityMethod("OpenNode", [card.dataset.node]);
    }

    function resetLayout() {
        if (!state.payload) return;
        finishDrag(true);
        state.offsets.clear();
        render(state.payload, state.visibleDepth);
    }

    function drawEdge(edge) {
        const x = edge.from.x + CARD_WIDTH / 2;
        const y = edge.from.y + CARD_HEIGHT;
        const endX = edge.to.x + CARD_WIDTH / 2;
        const middle = (y + edge.to.y) / 2;
        edge.path.setAttribute("d", `M${x},${y} C${x},${middle} ${endX},${middle} ${endX},${edge.to.y}`);
    }

    function measureBounds() {
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (const node of state.nodes) {
            minX = Math.min(minX, node.x);
            minY = Math.min(minY, node.y);
            maxX = Math.max(maxX, node.x + CARD_WIDTH);
            maxY = Math.max(maxY, node.y + CARD_HEIGHT);
        }
        return { x: minX - PAD, y: minY - PAD, width: maxX - minX + PAD * 2, height: maxY - minY + PAD * 2 };
    }

    function branchMovement(id) {
        const stack = [state.byId.get(id)];
        const branch = [];
        const edges = new Set();
        while (stack.length) {
            const node = stack.pop();
            branch.push({ node, x: node.x, y: node.y });
            for (const edge of state.connections.get(node.id)) edges.add(edge);
            stack.push(...node.children);
        }
        return { id, branch, edges, hadOffset: state.offsets.has(id), offset: state.offsets.get(id) || { x: 0, y: 0 } };
    }

    function moveBranch(movement, dx, dy) {
        state.offsets.set(movement.id, { x: movement.offset.x + dx, y: movement.offset.y + dy });
        for (const entry of movement.branch) {
            entry.node.x = entry.x + dx;
            entry.node.y = entry.y + dy;
            state.cards.get(entry.node.id).setAttribute("transform", `translate(${entry.node.x},${entry.node.y})`);
        }
        for (const edge of movement.edges) drawEdge(edge);
        state.bounds = measureBounds();
        state.fitted = false;
        state.toolbar.querySelector('[data-command="reset"]').disabled = false;
    }

    function finishDrag(cancelled) {
        const drag = state.drag;
        if (!drag) return;
        state.drag = null;
        state.svg.classList.remove("dragging");
        if (cancelled && drag.moved) {
            if (drag.movement) {
                moveBranch(drag.movement, 0, 0);
                if (!drag.movement.hadOffset) state.offsets.delete(drag.movement.id);
                state.toolbar.querySelector('[data-command="reset"]').disabled = state.offsets.size === 0;
            } else {
                state.view = drag.view;
                updateView();
            }
            state.fitted = drag.fitted;
        } else if (drag.card) {
            select(drag.card);
        }
        if (drag.target.hasPointerCapture(drag.pointerId)) drag.target.releasePointerCapture(drag.pointerId);
    }

    function updateView() {
        if (state.view) {
            const v = state.view;
            state.svg.setAttribute("viewBox", `${v.x} ${v.y} ${v.width} ${v.height}`);
        }
    }

    function fit() {
        if (!state.bounds) return;
        state.fitted = true;
        const width = state.viewport.clientWidth;
        const height = state.viewport.clientHeight;
        if (!width || !height) return;
        const aspect = width / height;
        state.fitWidth = Math.max(state.bounds.width, state.bounds.height * aspect);
        const fitHeight = state.fitWidth / aspect;
        state.view = {
            x: state.bounds.x + (state.bounds.width - state.fitWidth) / 2,
            y: state.bounds.y + (state.bounds.height - fitHeight) / 2,
            width: state.fitWidth, height: fitHeight
        };
        updateView();
    }

    function pan(x, y) {
        if (!state.view) return;
        state.view.x += x * state.view.width;
        state.view.y += y * state.view.height;
        state.fitted = false;
        updateView();
    }

    function point(event) {
        const matrix = state.svg.getScreenCTM();
        return matrix ? new DOMPoint(event.clientX, event.clientY).matrixTransform(matrix.inverse()) : null;
    }

    function zoom(factor, center) {
        if (!state.view) return;
        const old = state.view;
        const maximum = Math.max(state.bounds.width, state.bounds.height * old.width / old.height) * 4;
        const width = Math.min(Math.max(120, old.width * factor), maximum);
        const scale = width / old.width;
        const anchor = center || { x: old.x + old.width / 2, y: old.y + old.height / 2 };
        state.view = {
            x: anchor.x - (anchor.x - old.x) * scale, y: anchor.y - (anchor.y - old.y) * scale,
            width, height: old.height * scale
        };
        state.fitted = false;
        updateView();
    }

    function reportError(error) {
        state.bounds = null;
        state.view = null;
        if (state.svg) state.svg.replaceChildren();
        let alert = state.details;
        if (!alert || !alert.isConnected) {
            alert = document.createElement("p");
            (document.getElementById("controlAddIn") || document.body).prepend(alert);
        }
        alert.textContent = error.message;
        alert.classList.add("error");
        alert.setAttribute("role", "alert");
        console.error("Configured BOM diagram:", error);
        Microsoft.Dynamics.NAV.InvokeExtensibilityMethod("RenderFailed", [error.message]);
    }

    window.CFBOMDiagram = { initialize, reportError };
    window.Load = function (payload) {
        try {
            initialize();
            const data = typeof payload === "string" ? JSON.parse(payload) : payload;
            if (typeof data.session !== "string" || !data.session) throw new Error("The BOM diagram session identifier is missing.");
            finishDrag(true);
            if (state.session !== data.session) {
                state.offsets.clear();
                state.visibleDepth = null;
                state.maxDepth = 0;
                state.selected = null;
                state.session = data.session;
            }
            render(data, state.visibleDepth === state.maxDepth ? null : state.visibleDepth);
        } catch (error) {
            reportError(error);
            return;
        }
        state.details.classList.remove("error");
        state.details.removeAttribute("role");
    };
}());
