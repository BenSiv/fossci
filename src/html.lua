html = {}

-- Entity field values and (in principle) entity_type ultimately come
-- from user-submitted data -- escape before ever interpolating into
-- HTML text/attributes.
function html_escape(s)
    s = tostring(s)
    s = string.gsub(s, "&", "&amp;")
    s = string.gsub(s, "<", "&lt;")
    s = string.gsub(s, ">", "&gt;")
    s = string.gsub(s, "\"", "&quot;")
    s = string.gsub(s, "'", "&#39;")
    return s
end

-- `nonce` must be Fossil's own per-request CSP nonce (the FOSSIL_NONCE
-- CGI env var Fossil already injects, see doc/architecture.md) --
-- Fossil's page wrapper sets a strict `script-src 'self' 'nonce-...'`
-- CSP, so an inline <script> without the matching nonce is silently
-- blocked by the browser: the page loads, but no JS in it ever runs.
function html.render(entity_type, layout_json, nonce)
    escaped_type = html_escape(entity_type)
    return string.format("""
<div class="fossil-doc" data-title="Register %s">
    <style>
        .fossci-container {
            font-family: 'Outfit', 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            color: var(--fossci-text, #334155);
            background: #ffffff;
            padding: 28px;
            border-radius: 16px;
            box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.05), 0 8px 10px -6px rgba(0, 0, 0, 0.05);
            margin: 20px auto;
            max-width: 1200px;
            border: 1px solid var(--fossci-bg-2, #f1f5f9);
        }
        .fossci-header {
            margin-bottom: 24px;
            border-bottom: 1px solid var(--fossci-bg-2, #f1f5f9);
            padding-bottom: 16px;
        }
        .fossci-header h2 {
            margin: 0 0 6px 0;
            font-size: 1.6rem;
            font-weight: 700;
            color: var(--fossci-heading, #0f172a);
            letter-spacing: -0.02em;
        }
        .fossci-header p {
            color: var(--fossci-muted, #64748b);
            margin: 0;
            font-size: 0.95rem;
        }
        .fossci-header span.req-dot {
            color: #ef4444;
            font-weight: bold;
        }
        .fossci-table-wrapper {
            overflow-x: auto;
            margin-bottom: 24px;
            border: 1px solid var(--fossci-border, #e2e8f0);
            border-radius: 12px;
            box-shadow: inset 0 2px 4px 0 rgba(0,0,0,0.02);
            background: var(--fossci-bg, #f8fafc);
        }
        #registration-table {
            width: 100%%;
            border-collapse: separate;
            border-spacing: 0;
            min-width: 700px;
        }
        #registration-table th, #registration-table td {
            padding: 14px 16px;
            text-align: left;
            border-bottom: 1px solid var(--fossci-border, #e2e8f0);
        }
        #registration-table th {
            background: var(--fossci-bg-2, #f1f5f9);
            font-weight: 600;
            font-size: 0.8rem;
            color: var(--fossci-th-text, #475569);
            text-transform: uppercase;
            letter-spacing: 0.06em;
            border-top: 1px solid var(--fossci-border, #e2e8f0);
        }
        #registration-table th:first-child { border-top-left-radius: 10px; }
        #registration-table th:last-child  { border-top-right-radius: 10px; }
        #registration-table td { background: #ffffff; }
        #registration-table tr:last-child td { border-bottom: none; }
        #registration-table tr:last-child td:first-child { border-bottom-left-radius: 10px; }
        #registration-table tr:last-child td:last-child  { border-bottom-right-radius: 10px; }
        #registration-table th.required::after {
            content: " *";
            color: #ef4444;
        }
        .cell-input-wrapper { position: relative; }
        .cell-input {
            width: 100%%;
            padding: 9px 12px;
            border: 1px solid var(--fossci-border-2, #cbd5e1);
            border-radius: 8px;
            font-size: 0.9rem;
            background: #ffffff;
            transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
            box-sizing: border-box;
            color: var(--fossci-input-text, #1e293b);
        }
        .cell-input:focus {
            border-color: var(--fossci-accent-2, #6366f1);
            outline: none;
            box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.12);
            background: #fff;
        }
        .cell-input.error {
            border-color: #f87171;
            background-color: #fef2f2;
            box-shadow: 0 0 0 3px rgba(239, 68, 68, 0.08);
        }
        .error-badge {
            color: #ef4444;
            font-size: 0.75rem;
            margin-top: 4px;
            display: block;
            font-weight: 500;
        }
        .autocomplete-results {
            position: absolute;
            top: 100%%;
            left: 0;
            right: 0;
            background: #ffffff;
            border: 1px solid var(--fossci-border, #e2e8f0);
            border-radius: 8px;
            max-height: 220px;
            overflow-y: auto;
            z-index: 1000;
            box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05);
            margin-top: 6px;
            padding: 4px 0;
        }
        .autocomplete-item {
            padding: 9px 14px;
            cursor: pointer;
            font-size: 0.85rem;
            transition: all 0.15s ease;
            color: var(--fossci-text, #334155);
        }
        .autocomplete-item:hover { background: var(--fossci-bg-2, #f1f5f9); color: var(--fossci-heading, #0f172a); }
        .fossci-actions {
            display: flex;
            gap: 14px;
            justify-content: flex-start;
            align-items: center;
        }
        .btn {
            padding: 10px 20px;
            border-radius: 8px;
            font-weight: 600;
            font-size: 0.9rem;
            cursor: pointer;
            transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
            border: none;
            display: inline-flex;
            align-items: center;
            justify-content: center;
        }
        .btn-primary {
            background: linear-gradient(135deg, var(--fossci-accent, #4f46e5), var(--fossci-accent-2, #6366f1));
            color: #ffffff;
            box-shadow: 0 4px 12px rgba(99, 102, 241, 0.2);
        }
        .btn-primary:hover { box-shadow: 0 6px 16px rgba(99, 102, 241, 0.3); filter: brightness(1.05); }
        .btn-primary:active { transform: scale(0.98); }
        .btn-secondary {
            background: var(--fossci-bg, #f8fafc);
            color: var(--fossci-th-text, #475569);
            border: 1px solid var(--fossci-border, #e2e8f0);
        }
        .btn-secondary:hover { background: var(--fossci-bg-2, #f1f5f9); color: var(--fossci-heading, #0f172a); }
        .btn-delete {
            background: transparent;
            color: var(--fossci-muted-2, #94a3b8);
            font-size: 1.25rem;
            cursor: pointer;
            transition: color 0.15s ease;
            border: none;
            padding: 4px;
        }
        .btn-delete:hover { color: #ef4444; }
        .status-msg {
            margin-top: 24px;
            padding: 14px 20px;
            border-radius: 8px;
            font-size: 0.95rem;
            display: none;
            font-weight: 500;
            box-shadow: 0 2px 4px rgba(0, 0, 0, 0.02);
        }
        .status-msg.success {
            display: block;
            background: #f0fdf4;
            color: #166534;
            border: 1px solid #bbf7d0;
            animation: fadeIn 0.25s ease;
        }
        .status-msg.error {
            display: block;
            background: #fef2f2;
            color: #991b1b;
            border: 1px solid #fecaca;
            animation: fadeIn 0.25s ease;
        }
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(4px); }
            to   { opacity: 1; transform: translateY(0); }
        }
    </style>

    <div class="fossci-container">
        <div class="fossci-header">
            <h2>Register %s</h2>
            <p>Fill out the sheet. Fields marked with <span class="req-dot">*</span> are required.</p>
            <p><a href="fossci/browse?type=%s">Browse existing %s entities &rarr;</a></p>
        </div>

        <div class="fossci-table-wrapper">
            <table id="registration-table">
                <thead>
                    <tr id="table-headers">
                        <!-- headers dynamically injected -->
                    </tr>
                </thead>
                <tbody id="table-body">
                    <!-- rows dynamically injected -->
                </tbody>
            </table>
        </div>

        <div class="fossci-actions">
            <button type="button" class="btn btn-secondary" id="btn-add-row">+ Add Row</button>
            <button type="button" class="btn btn-primary"   id="btn-submit-batch">Submit Batch</button>
        </div>

        <div id="status-message" class="status-msg"></div>
    </div>

    <script nonce="%s">
        const layout = %s;
        const entityType = "%s";
        const baseUrl = window.location.pathname.replace(/\/register\/?$/, "");
        let rowCounter = 0;

        // Which notebook entry (wiki page) this registration table is
        // embedded in, for ledger provenance (source_notebook_entry_id).
        // An explicit ?entry= on this iframe's own src overrides
        // auto-detection via document.referrer (the parent page's URL,
        // set by the browser for a same-origin iframe navigation) --
        // useful when referrer policies strip it, or to label it by
        // something other than a raw URL.
        const urlParams = new URLSearchParams(window.location.search);
        let notebookEntry = urlParams.get("entry");
        if (!notebookEntry && document.referrer) {
            notebookEntry = document.referrer;
        }

        function initTable() {
            const headerRow = document.getElementById("table-headers");
            headerRow.innerHTML = "";

            layout.fields.forEach(field => {
                const th = document.createElement("th");
                th.innerText = field.label;
                if (field.required) { th.classList.add("required"); }
                headerRow.appendChild(th);
            });

            const deleteTh = document.createElement("th");
            deleteTh.style.width = "40px";
            headerRow.appendChild(deleteTh);

            addRow();
        }

        function addRow() {
            rowCounter++;
            const tbody = document.getElementById("table-body");
            const tr = document.createElement("tr");
            tr.id = `row-${rowCounter}`;

            layout.fields.forEach(field => {
                const td = document.createElement("td");
                const wrapper = document.createElement("div");
                wrapper.classList.add("cell-input-wrapper");

                let input;
                if (field.type === "select") {
                    input = document.createElement("select");
                    input.classList.add("cell-input");
                    const optEmpty = document.createElement("option");
                    optEmpty.value = "";
                    optEmpty.innerText = "";
                    input.appendChild(optEmpty);
                    field.values.forEach(val => {
                        const opt = document.createElement("option");
                        opt.value = val;
                        opt.innerText = val;
                        input.appendChild(opt);
                    });
                } else {
                    input = document.createElement("input");
                    input.classList.add("cell-input");
                    if (field.type === "number") {
                        input.type = "number";
                        input.step = "any";
                    } else if (field.type === "date") {
                        input.type = "date";
                    } else {
                        input.type = "text";
                    }
                    if (field.type === "reference") {
                        input.setAttribute("autocomplete", "off");
                        input.placeholder = "Search ID or name...";
                        setupAutocomplete(input, field.ref_entity_type);
                    }
                }

                input.name = field.name;
                input.addEventListener("input",  () => clearCellError(input));
                input.addEventListener("change", () => clearCellError(input));
                wrapper.appendChild(input);
                td.appendChild(wrapper);
                tr.appendChild(td);
            });

            const deleteTd = document.createElement("td");
            const deleteBtn = document.createElement("button");
            deleteBtn.type = "button";
            deleteBtn.classList.add("btn-delete");
            deleteBtn.innerHTML = "&times;";
            deleteBtn.onclick = () => {
                const rows = tbody.getElementsByTagName("tr");
                if (rows.length > 1) {
                    tr.remove();
                } else {
                    alert("Cannot delete the only row.");
                }
            };
            deleteTd.appendChild(deleteBtn);
            tr.appendChild(deleteTd);
            tbody.appendChild(tr);
        }

        function clearCellError(input) {
            input.classList.remove("error");
            const parent = input.parentElement;
            const existingBadge = parent.querySelector(".error-badge");
            if (existingBadge) { existingBadge.remove(); }
        }

        function highlightError(rowIndex, fieldName, message) {
            const tbody = document.getElementById("table-body");
            const tr = tbody.getElementsByTagName("tr")[rowIndex];
            if (!tr) return;
            const input = tr.querySelector(`[name="${fieldName}"]`);
            if (!input) return;
            input.classList.add("error");
            const parent = input.parentElement;
            let badge = parent.querySelector(".error-badge");
            if (!badge) {
                badge = document.createElement("span");
                badge.classList.add("error-badge");
                parent.appendChild(badge);
            }
            badge.innerText = message;
        }

        function clearAllErrors() {
            document.querySelectorAll(".cell-input").forEach(input => clearCellError(input));
            const msg = document.getElementById("status-message");
            msg.className = "status-msg";
            msg.innerText = "";
            msg.style.display = "none";
        }

        function setupAutocomplete(input, refType) {
            const wrapper = input.parentElement;
            let resultsContainer = null;
            let debounceTimer;

            input.addEventListener("input", () => {
                clearTimeout(debounceTimer);
                const query = input.value.trim();
                if (resultsContainer) { resultsContainer.remove(); resultsContainer = null; }
                if (query.length === 0) return;

                debounceTimer = setTimeout(() => {
                    fetch(`${baseUrl}/api/autocomplete?type=${refType}&query=${encodeURIComponent(query)}`)
                        .then(res => res.json())
                        .then(data => {
                            if (resultsContainer) resultsContainer.remove();
                            if (data.length === 0) return;
                            resultsContainer = document.createElement("div");
                            resultsContainer.classList.add("autocomplete-results");
                            data.forEach(item => {
                                const div = document.createElement("div");
                                div.classList.add("autocomplete-item");
                                div.innerText = `[#${item.id}] ${item.name}`;
                                div.onclick = () => {
                                    input.value = item.id;
                                    clearCellError(input);
                                    resultsContainer.remove();
                                    resultsContainer = null;
                                };
                                resultsContainer.appendChild(div);
                            });
                            wrapper.appendChild(resultsContainer);
                        })
                        .catch(err => console.error("Autocomplete fetch error", err));
                }, 200);
            });

            document.addEventListener("click", (e) => {
                if (e.target !== input && resultsContainer && !resultsContainer.contains(e.target)) {
                    resultsContainer.remove();
                    resultsContainer = null;
                }
            });
        }

        function submitBatch() {
            clearAllErrors();
            const tbody = document.getElementById("table-body");
            const trs = tbody.getElementsByTagName("tr");
            const payload = [];

            for (let i = 0; i < trs.length; i++) {
                const tr = trs[i];
                const rowData = {};
                layout.fields.forEach(field => {
                    const el = tr.querySelector(`[name="${field.name}"]`);
                    if (el) {
                        let val = el.value;
                        if (field.type === "number" && val !== "") { val = parseFloat(val); }
                        rowData[field.name] = val;
                    }
                });
                payload.push(rowData);
            }

            const msg = document.getElementById("status-message");
            msg.className = "status-msg";
            msg.innerText = "Validating and submitting...";
            msg.style.display = "block";

            const entryParam = notebookEntry ? `&entry=${encodeURIComponent(notebookEntry)}` : "";
            fetch(`${baseUrl}/api/submit?type=${entityType}${entryParam}`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(payload)
            })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    msg.className = "status-msg success";
                    msg.innerText = `Successfully registered ${data.created_ids.length} entities (IDs: ${data.created_ids.join(", ")}).`;
                    tbody.innerHTML = "";
                    rowCounter = 0;
                    addRow();
                } else {
                    msg.className = "status-msg error";
                    msg.innerText = "Submission failed. Please check highlighted errors in the form.";
                    if (data.issues && data.issues.length > 0) {
                        data.issues.forEach(issue => {
                            highlightError(issue.row_index - 1, issue.field, issue.message);
                        });
                    }
                }
            })
            .catch(err => {
                console.error("Submit error", err);
                msg.className = "status-msg error";
                msg.innerText = "An unexpected error occurred during submission.";
            });
        }

        window.onload = initTable;
        document.getElementById("btn-add-row").addEventListener("click", addRow);
        document.getElementById("btn-submit-batch").addEventListener("click", submitBatch);
    </script>
</div>
""", escaped_type, escaped_type, escaped_type, escaped_type, nonce, layout_json, entity_type)
end

function display_value(value)
    if value == nil or tostring(value) == "" then
        return "&mdash;"
    end
    return html_escape(value)
end

-- Reference-type field values are a raw entity id -- fossci has no
-- general "display name" concept for entities (confirmed directly:
-- entity tables carry no "name" column at all, only whatever fields
-- each schema declares; /browse and /detail already only ever show
-- "#<id>" for the row's own identity too), so this can't resolve to a
-- human-readable name -- it renders the id as a real, styled link to
-- the referenced entity's own detail page instead of a disconnected
-- bare number, matching how the row's own id already links out in
-- render_browse below. "fossci/detail..." (no leading slash) is
-- intentional -- see render_browse's own identical link for why
-- (relative to this page's own <base>, which lacks a trailing slash).
function render_reference_value(ref_entity_type, value)
    if value == nil or tostring(value) == "" then
        return "&mdash;"
    end
    escaped_type = html_escape(ref_entity_type)
    escaped_id = html_escape(tostring(value))
    return "<a href=\"fossci/detail?type=" .. escaped_type .. "&entity_id=" .. escaped_id ..
        "\" class=\"fossci-entity-ref\">#" .. escaped_id .. "</a>"
end

-- Picks the right renderer for a field's value, given its schema.layout()
-- metadata (type + ref_entity_type, when type=="reference").
function display_field_value(field, value)
    if field.type == "reference" and field.ref_entity_type != nil then
        return render_reference_value(field.ref_entity_type, value)
    end
    return display_value(value)
end

-- Browse view: a read-only table of every entity of a type, linking to
-- each one's detail page. Pure server-rendered HTML -- no JS, so none
-- of the CSP/nonce concerns the registration table's client-side JS
-- has (see html.render's header comment for why that one needs one).
function html.render_browse(entity_type, layout, rows, page, page_size, total)
    escaped_type = html_escape(entity_type)

    header_cells = "<th>ID</th>"
    for _, field in ipairs(layout.fields) do
        header_cells = header_cells .. "<th>" .. html_escape(field.label) .. "</th>"
    end

    body_rows = ""
    for _, row in ipairs(rows) do
        cells = "<td><a href=\"fossci/detail?type=" .. escaped_type .. "&entity_id=" .. tostring(row.id) ..
            "\">#" .. tostring(row.id) .. "</a></td>"
        for _, field in ipairs(layout.fields) do
            cells = cells .. "<td>" .. display_field_value(field, row[field.name]) .. "</td>"
        end
        body_rows = body_rows .. "<tr>" .. cells .. "</tr>"
    end

    table_or_empty = "<div class=\"fossci-table-wrapper\"><table id=\"browse-table\"><thead><tr>" ..
        header_cells .. "</tr></thead><tbody>" .. body_rows .. "</tbody></table></div>"
    if #rows == 0 then
        table_or_empty = "<p class=\"fossci-empty\">No " .. escaped_type .. " entities registered yet.</p>"
    end

    pager = ""
    if total > page_size then
        last_page = math.ceil(total / page_size)
        range_start = ((page - 1) * page_size) + 1
        range_end = range_start + #rows - 1
        pager = "<div class=\"fossci-pager\">"
        pager = pager .. "<span>Showing " .. tostring(range_start) .. "-" .. tostring(range_end) ..
            " of " .. tostring(total) .. "</span>"
        pager = pager .. "<span class=\"fossci-pager-links\">"
        if page > 1 then
            pager = pager .. "<a href=\"fossci/browse?type=" .. escaped_type .. "&page=" .. tostring(page - 1) .. "\">&laquo; Prev</a>"
        end
        pager = pager .. "<span>Page " .. tostring(page) .. " of " .. tostring(last_page) .. "</span>"
        if page < last_page then
            pager = pager .. "<a href=\"fossci/browse?type=" .. escaped_type .. "&page=" .. tostring(page + 1) .. "\">Next &raquo;</a>"
        end
        pager = pager .. "</span></div>"
    end

    return string.format("""
<div class="fossil-doc" data-title="Browse %s">
    <style>
        .fossci-container {
            font-family: 'Outfit', 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            color: var(--fossci-text, #334155);
            background: #ffffff;
            padding: 28px;
            border-radius: 16px;
            box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.05), 0 8px 10px -6px rgba(0, 0, 0, 0.05);
            margin: 20px auto;
            max-width: 1200px;
            border: 1px solid var(--fossci-bg-2, #f1f5f9);
        }
        .fossci-header {
            margin-bottom: 24px;
            border-bottom: 1px solid var(--fossci-bg-2, #f1f5f9);
            padding-bottom: 16px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .fossci-header h2 { margin: 0 0 6px 0; font-size: 1.6rem; font-weight: 700; color: var(--fossci-heading, #0f172a); letter-spacing: -0.02em; }
        .fossci-header p { color: var(--fossci-muted, #64748b); margin: 0; font-size: 0.95rem; }
        .fossci-header a { color: var(--fossci-accent, #4f46e5); text-decoration: none; font-weight: 600; }
        .fossci-header a:hover { text-decoration: underline; }
        .btn {
            padding: 10px 20px;
            border-radius: 8px;
            font-weight: 600;
            font-size: 0.9rem;
            border: none;
            display: inline-flex;
            align-items: center;
            text-decoration: none;
        }
        .btn-primary {
            background: linear-gradient(135deg, var(--fossci-accent, #4f46e5), var(--fossci-accent-2, #6366f1));
            color: #ffffff;
            box-shadow: 0 4px 12px rgba(99, 102, 241, 0.2);
        }
        .fossci-table-wrapper {
            overflow-x: auto;
            border: 1px solid var(--fossci-border, #e2e8f0);
            border-radius: 12px;
            background: var(--fossci-bg, #f8fafc);
        }
        #browse-table { width: 100%%; border-collapse: separate; border-spacing: 0; min-width: 600px; }
        #browse-table th, #browse-table td {
            padding: 12px 16px;
            text-align: left;
            border-bottom: 1px solid var(--fossci-border, #e2e8f0);
            font-size: 0.9rem;
        }
        #browse-table th {
            background: var(--fossci-bg-2, #f1f5f9);
            font-weight: 600;
            font-size: 0.78rem;
            color: var(--fossci-th-text, #475569);
            text-transform: uppercase;
            letter-spacing: 0.06em;
        }
        #browse-table td { background: #ffffff; }
        #browse-table a { color: var(--fossci-accent, #4f46e5); text-decoration: none; font-weight: 600; }
        #browse-table a:hover { text-decoration: underline; }
        .fossci-empty {
            padding: 32px;
            text-align: center;
            color: var(--fossci-muted, #64748b);
            background: var(--fossci-bg, #f8fafc);
            border: 1px dashed var(--fossci-border, #e2e8f0);
            border-radius: 12px;
        }
        .fossci-pager {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-top: 16px;
            font-size: 0.85rem;
            color: var(--fossci-muted, #64748b);
        }
        .fossci-pager-links { display: flex; gap: 14px; align-items: center; }
        .fossci-pager-links a { color: var(--fossci-accent, #4f46e5); text-decoration: none; font-weight: 600; }
        .fossci-pager-links a:hover { text-decoration: underline; }
        .fossci-entity-ref { color: var(--fossci-accent, #4f46e5); text-decoration: none; font-weight: 600; }
        .fossci-entity-ref::after { content: " \2197"; font-size: 0.85em; }
        .fossci-entity-ref:hover { text-decoration: underline; }
    </style>

    <div class="fossci-container">
        <div class="fossci-header">
            <div>
                <h2>Browse %s</h2>
                <p>%d registered</p>
            </div>
            <a class="btn btn-primary" href="fossci/register?type=%s">+ Register new</a>
        </div>
        %s
        %s
    </div>
</div>
""", escaped_type, escaped_type, total, escaped_type, table_or_empty, pager)
end

-- Detail view: current field values plus the full ledger history for
-- one entity. Also pure server-rendered HTML, no JS.
function html.render_detail(entity_type, layout, row, history)
    escaped_type = html_escape(entity_type)
    id_str = tostring(row.id)

    fields_html = ""
    for _, field in ipairs(layout.fields) do
        fields_html = fields_html .. "<div class=\"detail-row\"><span class=\"detail-label\">" ..
            html_escape(field.label) .. "</span><span class=\"detail-value\">" ..
            display_field_value(field, row[field.name]) .. "</span></div>"
    end

    history_rows = ""
    for _, event in ipairs(history) do
        changes = ""
        for field_name, change in pairs(event.field_changes) do
            changes = changes .. "<div class=\"change-item\"><strong>" .. html_escape(field_name) ..
                "</strong>: " .. display_value(change.old) .. " &rarr; " .. display_value(change.new) .. "</div>"
        end
        history_rows = history_rows .. "<tr><td>#" .. tostring(event.event_id) .. "</td><td>" ..
            html_escape(event.event_type) .. "</td><td>" .. display_value(event.author) .. "</td><td>" ..
            html_escape(event.created_at) .. "</td><td>" .. changes .. "</td></tr>"
    end

    return string.format("""
<div class="fossil-doc" data-title="%s #%s">
    <style>
        .fossci-container {
            font-family: 'Outfit', 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            color: var(--fossci-text, #334155);
            background: #ffffff;
            padding: 28px;
            border-radius: 16px;
            box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.05), 0 8px 10px -6px rgba(0, 0, 0, 0.05);
            margin: 20px auto;
            max-width: 1200px;
            border: 1px solid var(--fossci-bg-2, #f1f5f9);
        }
        .fossci-header { margin-bottom: 24px; border-bottom: 1px solid var(--fossci-bg-2, #f1f5f9); padding-bottom: 16px; }
        .fossci-header h2 { margin: 0 0 6px 0; font-size: 1.6rem; font-weight: 700; color: var(--fossci-heading, #0f172a); letter-spacing: -0.02em; }
        .fossci-header a { color: var(--fossci-accent, #4f46e5); text-decoration: none; font-weight: 600; font-size: 0.9rem; }
        .fossci-header a:hover { text-decoration: underline; }
        .fossci-subheading { font-size: 1.05rem; color: var(--fossci-heading, #0f172a); margin: 28px 0 14px 0; }
        .fossci-detail-fields {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
            gap: 16px 24px;
            padding: 20px;
            background: var(--fossci-bg, #f8fafc);
            border: 1px solid var(--fossci-border, #e2e8f0);
            border-radius: 12px;
        }
        .detail-row { display: flex; flex-direction: column; gap: 4px; }
        .detail-label { font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.06em; color: var(--fossci-muted, #64748b); font-weight: 600; }
        .detail-value { font-size: 0.95rem; color: var(--fossci-heading, #0f172a); word-break: break-word; }
        .fossci-table-wrapper { overflow-x: auto; border: 1px solid var(--fossci-border, #e2e8f0); border-radius: 12px; background: var(--fossci-bg, #f8fafc); }
        #history-table { width: 100%%; border-collapse: separate; border-spacing: 0; min-width: 700px; }
        #history-table th, #history-table td {
            padding: 12px 16px;
            text-align: left;
            border-bottom: 1px solid var(--fossci-border, #e2e8f0);
            font-size: 0.85rem;
            vertical-align: top;
        }
        #history-table th {
            background: var(--fossci-bg-2, #f1f5f9);
            font-weight: 600;
            font-size: 0.75rem;
            color: var(--fossci-th-text, #475569);
            text-transform: uppercase;
            letter-spacing: 0.06em;
        }
        #history-table td { background: #ffffff; }
        .change-item { margin-bottom: 4px; }
        .change-item:last-child { margin-bottom: 0; }
        .fossci-entity-ref { color: var(--fossci-accent, #4f46e5); text-decoration: none; font-weight: 600; }
        .fossci-entity-ref::after { content: " \2197"; font-size: 0.85em; }
        .fossci-entity-ref:hover { text-decoration: underline; }
    </style>

    <div class="fossci-container">
        <div class="fossci-header">
            <h2>%s #%s</h2>
            <a href="fossci/browse?type=%s">&larr; Back to browse</a>
        </div>

        <div class="fossci-detail-fields">
            %s
        </div>

        <h3 class="fossci-subheading">Ledger history</h3>
        <div class="fossci-table-wrapper">
            <table id="history-table">
                <thead><tr><th>Event</th><th>Type</th><th>Author</th><th>When</th><th>Changes</th></tr></thead>
                <tbody>%s</tbody>
            </table>
        </div>
    </div>
</div>
""", escaped_type, id_str, escaped_type, id_str, escaped_type, fields_html, history_rows)
end

-- Generic view: any approved custom SQL view rendered as a table.
-- Unlike browse/detail, columns come from the view's own declared
-- `columns` list (name/label), not a schema -- a view can join/select
-- across entity types, so there's no single schema to draw from.
function html.render_view(view_def, rows, param_value)
    title = view_def.title
    if title == nil then
        title = view_def.name
    end
    escaped_title = html_escape(title)

    subtitle = tostring(#rows) .. " rows"
    if view_def.param != nil then
        subtitle = subtitle .. " -- filtered by " .. html_escape(view_def.param.name) ..
            " = " .. html_escape(tostring(param_value))
    end

    header_cells = ""
    for _, col in ipairs(view_def.columns) do
        label = col.label
        if label == nil then
            label = col.name
        end
        header_cells = header_cells .. "<th>" .. html_escape(label) .. "</th>"
    end

    body_rows = ""
    for _, row in ipairs(rows) do
        cells = ""
        for _, col in ipairs(view_def.columns) do
            cells = cells .. "<td>" .. display_value(row[col.name]) .. "</td>"
        end
        body_rows = body_rows .. "<tr>" .. cells .. "</tr>"
    end

    table_or_empty = "<div class=\"fossci-table-wrapper\"><table id=\"view-table\"><thead><tr>" ..
        header_cells .. "</tr></thead><tbody>" .. body_rows .. "</tbody></table></div>"
    if #rows == 0 then
        table_or_empty = "<p class=\"fossci-empty\">No rows.</p>"
    end

    return string.format("""
<div class="fossil-doc" data-title="%s">
    <style>
        .fossci-container {
            font-family: 'Outfit', 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            color: var(--fossci-text, #334155);
            background: #ffffff;
            padding: 28px;
            border-radius: 16px;
            box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.05), 0 8px 10px -6px rgba(0, 0, 0, 0.05);
            margin: 20px auto;
            max-width: 1200px;
            border: 1px solid var(--fossci-bg-2, #f1f5f9);
        }
        .fossci-header { margin-bottom: 24px; border-bottom: 1px solid var(--fossci-bg-2, #f1f5f9); padding-bottom: 16px; }
        .fossci-header h2 { margin: 0 0 6px 0; font-size: 1.6rem; font-weight: 700; color: var(--fossci-heading, #0f172a); letter-spacing: -0.02em; }
        .fossci-header p { color: var(--fossci-muted, #64748b); margin: 0; font-size: 0.95rem; }
        .fossci-table-wrapper { overflow-x: auto; border: 1px solid var(--fossci-border, #e2e8f0); border-radius: 12px; background: var(--fossci-bg, #f8fafc); }
        #view-table { width: 100%%; border-collapse: separate; border-spacing: 0; min-width: 600px; }
        #view-table th, #view-table td { padding: 12px 16px; text-align: left; border-bottom: 1px solid var(--fossci-border, #e2e8f0); font-size: 0.9rem; }
        #view-table th {
            background: var(--fossci-bg-2, #f1f5f9);
            font-weight: 600;
            font-size: 0.78rem;
            color: var(--fossci-th-text, #475569);
            text-transform: uppercase;
            letter-spacing: 0.06em;
        }
        #view-table td { background: #ffffff; }
        .fossci-empty {
            padding: 32px;
            text-align: center;
            color: var(--fossci-muted, #64748b);
            background: var(--fossci-bg, #f8fafc);
            border: 1px dashed var(--fossci-border, #e2e8f0);
            border-radius: 12px;
        }
    </style>
    <div class="fossci-container">
        <div class="fossci-header">
            <h2>%s</h2>
            <p>%s</p>
        </div>
        %s
    </div>
</div>
""", escaped_title, escaped_title, subtitle, table_or_empty)
end

-- fossci's own landing page: every registered entity type, linking to
-- its browse view. This is the page a deployment's Fossil "mainmenu"
-- entry (see doc/deployment.md) should point at, so there's a real
-- entry point into fossci beyond knowing a /browse?type=... URL by hand.
function html.render_index(entity_types, show_sql_widget)
    items = ""
    for _, row in ipairs(entity_types) do
        escaped_name = html_escape(row.name)
        items = items .. "<li><a href=\"fossci/browse?type=" .. escaped_name .. "\">" .. escaped_name .. "</a></li>"
    end

    list_or_empty = "<ul class=\"fossci-index-list\">" .. items .. "</ul>"
    if #entity_types == 0 then
        list_or_empty = "<p class=\"fossci-empty\">No entity types registered yet.</p>"
    end

    -- Setup/Admin only, matching /sql's own gate -- an iframe is legal
    -- here (this page isn't wiki content, so none of Fossil's wiki
    -- sanitizer restrictions on <iframe> apply), unlike the entry
    -- notebook pages, which had to fall back to plain links instead.
    -- No title/description here -- the embedded /sql page (title
    -- "Query" as of this rewrite) already renders its own, and
    -- html.in-iframe's CSS only flattens the *card* styling
    -- (padding/border/shadow), not the heading text, so showing both
    -- was a literal duplicate header, not just visual clutter.
    sql_widget = ""
    if show_sql_widget == true then
        sql_widget = """
    <div class="fossci-container">
        <iframe src="fossci/sql" style="width:100%;height:520px;border:0;border-radius:12px;"></iframe>
    </div>
"""
    end

    return string.format("""
<div class="fossil-doc" data-title="fossci">
    <style>
        .fossci-container {
            font-family: 'Outfit', 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            color: var(--fossci-text, #334155);
            background: #ffffff;
            padding: 28px;
            border-radius: 16px;
            box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.05), 0 8px 10px -6px rgba(0, 0, 0, 0.05);
            margin: 20px auto;
            max-width: 800px;
            border: 1px solid var(--fossci-bg-2, #f1f5f9);
        }
        .fossci-header { margin-bottom: 20px; border-bottom: 1px solid var(--fossci-bg-2, #f1f5f9); padding-bottom: 16px; }
        .fossci-header h2 { margin: 0 0 6px 0; font-size: 1.6rem; font-weight: 700; color: var(--fossci-heading, #0f172a); letter-spacing: -0.02em; }
        .fossci-header p { color: var(--fossci-muted, #64748b); margin: 0; font-size: 0.95rem; }
        .fossci-index-list { list-style: none !important; margin: 0; padding: 0; display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 10px; }
        .fossci-index-list li { list-style: none !important; background: var(--fossci-bg, #f8fafc); border: 1px solid var(--fossci-border, #e2e8f0); border-radius: 10px; }
        .fossci-index-list li::marker { content: ""; }
        .fossci-index-list a { display: block; padding: 12px 16px; color: var(--fossci-accent, #4f46e5); text-decoration: none; font-weight: 600; text-transform: capitalize; }
        .fossci-index-list a:hover { background: var(--fossci-bg-2, #f1f5f9); }
        .fossci-empty {
            padding: 32px;
            text-align: center;
            color: var(--fossci-muted, #64748b);
            background: var(--fossci-bg, #f8fafc);
            border: 1px dashed var(--fossci-border, #e2e8f0);
            border-radius: 12px;
        }
    </style>
    <div class="fossci-container">
        <div class="fossci-header">
            <h2>Entity types</h2>
            <p>%d registered</p>
        </div>
        %s
    </div>
%s
</div>
""", #entity_types, list_or_empty, sql_widget)
end

-- Every entry template found (whether it loaded cleanly or not), each
-- linking to /template?name=... where the actual snippet is rendered.
function html.render_templates_list(entries)
    items = ""
    for _, entry in ipairs(entries) do
        escaped_name = html_escape(entry.name)
        if entry.def == nil then
            items = items .. "<li class=\"fossci-template-error\">" .. escaped_name ..
                " -- ERROR: " .. html_escape(entry.err) .. "</li>"
        else
            label = entry.def.label
            if label == nil then
                label = entry.name
            end
            description = entry.def.description
            if description == nil then
                description = ""
            end
            escaped_label = html_escape(label)
            escaped_desc = html_escape(description)
            items = items .. "<li><a href=\"fossci/template?template_name=" .. escaped_name .. "\">" ..
                escaped_label .. "</a><p>" .. escaped_desc .. "</p></li>"
        end
    end

    list_or_empty = "<ul class=\"fossci-index-list\">" .. items .. "</ul>"
    if #entries == 0 then
        list_or_empty = "<p class=\"fossci-empty\">No entry templates yet.</p>"
    end

    return string.format("""
<div class="fossil-doc" data-title="Entry templates">
    <style>
        .fossci-container {
            font-family: 'Outfit', 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            color: var(--fossci-text, #334155);
            background: #ffffff;
            padding: 28px;
            border-radius: 16px;
            box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.05), 0 8px 10px -6px rgba(0, 0, 0, 0.05);
            margin: 20px auto;
            max-width: 800px;
            border: 1px solid var(--fossci-bg-2, #f1f5f9);
        }
        .fossci-header { margin-bottom: 20px; border-bottom: 1px solid var(--fossci-bg-2, #f1f5f9); padding-bottom: 16px; }
        .fossci-header h2 { margin: 0 0 6px 0; font-size: 1.6rem; font-weight: 700; color: var(--fossci-heading, #0f172a); letter-spacing: -0.02em; }
        .fossci-header p { color: var(--fossci-muted, #64748b); margin: 0; font-size: 0.95rem; }
        .fossci-index-list { list-style: none !important; margin: 0; padding: 0; display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 12px; }
        .fossci-index-list li { list-style: none !important; background: var(--fossci-bg, #f8fafc); border: 1px solid var(--fossci-border, #e2e8f0); border-radius: 10px; padding: 14px 16px; }
        .fossci-index-list li::marker { content: ""; }
        .fossci-index-list a { font-weight: 700; color: var(--fossci-accent, #4f46e5); text-decoration: none; }
        .fossci-index-list a:hover { text-decoration: underline; }
        .fossci-index-list p { margin: 6px 0 0 0; color: var(--fossci-muted, #64748b); font-size: 0.88rem; }
        .fossci-template-error { color: #991b1b; background: #fef2f2; border: 1px solid #fecaca; border-radius: 10px; padding: 14px 16px; }
        .fossci-empty {
            padding: 32px;
            text-align: center;
            color: var(--fossci-muted, #64748b);
            background: var(--fossci-bg, #f8fafc);
            border: 1px dashed var(--fossci-border, #e2e8f0);
            border-radius: 12px;
        }
    </style>
    <div class="fossci-container">
        <div class="fossci-header">
            <h2>Entry templates</h2>
            <p>Pick a template, copy the generated snippet, and paste it into a new wiki page you create.</p>
        </div>
        %s
    </div>
</div>
""", list_or_empty)
end

-- The rendered Markdown snippet for one template, in a read-only
-- textarea for easy select-all-and-copy -- no JS needed (a "Copy"
-- button would need one, and this is simple enough not to bother).
function html.render_template(def, rendered_markdown)
    label = def.label
    if label == nil then
        label = def.name
    end
    description = def.description
    if description == nil then
        description = ""
    end
    escaped_label = html_escape(label)
    escaped_desc = html_escape(description)
    escaped_body = html_escape(rendered_markdown)

    return string.format("""
<div class="fossil-doc" data-title="Template: %s">
    <style>
        .fossci-container {
            font-family: 'Outfit', 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            color: var(--fossci-text, #334155);
            background: #ffffff;
            padding: 28px;
            border-radius: 16px;
            box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.05), 0 8px 10px -6px rgba(0, 0, 0, 0.05);
            margin: 20px auto;
            max-width: 900px;
            border: 1px solid var(--fossci-bg-2, #f1f5f9);
        }
        .fossci-header { margin-bottom: 20px; border-bottom: 1px solid var(--fossci-bg-2, #f1f5f9); padding-bottom: 16px; }
        .fossci-header h2 { margin: 0 0 6px 0; font-size: 1.6rem; font-weight: 700; color: var(--fossci-heading, #0f172a); letter-spacing: -0.02em; }
        .fossci-header p { color: var(--fossci-muted, #64748b); margin: 0; font-size: 0.95rem; }
        .fossci-header a { color: var(--fossci-accent, #4f46e5); text-decoration: none; font-weight: 600; }
        .fossci-header a:hover { text-decoration: underline; }
        .fossci-snippet {
            width: 100%%;
            min-height: 360px;
            box-sizing: border-box;
            font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
            font-size: 0.88rem;
            padding: 16px;
            border: 1px solid var(--fossci-border, #e2e8f0);
            border-radius: 12px;
            background: var(--fossci-bg, #f8fafc);
            color: var(--fossci-input-text, #1e293b);
        }
    </style>
    <div class="fossci-container">
        <div class="fossci-header">
            <h2>%s</h2>
            <p>%s</p>
            <p><a href="fossci/templates">&larr; All templates</a></p>
        </div>
        <p>Click inside, select all (Ctrl/Cmd+A), copy, then paste into a new wiki page (Fossil: All pages &rarr; New).</p>
        <textarea class="fossci-snippet" readonly>%s</textarea>
    </div>
</div>
""", escaped_label, escaped_label, escaped_desc, escaped_body)
end

-- Ad-hoc SQL console (Setup/Admin only -- see cgi.lua's /sql route):
-- a plain GET form (no JS needed, unlike register's autocomplete) so
-- the query is a normal, bookmarkable/shareable URL. `column_names`/
-- `rows` are nil until a query has been run; `err` is set instead if
-- it failed (not select-only, invalid sql, etc.).
function html.render_sql(sql_text, column_names, rows, err, ref_columns)
    if ref_columns == nil then
        ref_columns = {}
    end
    sql_text_or_empty = sql_text
    if sql_text_or_empty == nil then
        sql_text_or_empty = ""
    end
    escaped_sql = html_escape(sql_text_or_empty)

    result_html = ""
    if err != nil then
        result_html = "<div class=\"fossci-sql-error\">Error: " .. html_escape(err) .. "</div>"
    elseif rows != nil then
        header_cells = ""
        for _, name in ipairs(column_names) do
            header_cells = header_cells .. "<th>" .. html_escape(name) .. "</th>"
        end
        body_rows = ""
        for _, row in ipairs(rows) do
            cells = ""
            for _, name in ipairs(column_names) do
                ref_type = ref_columns[name]
                if ref_type != nil then
                    cells = cells .. "<td>" .. render_reference_value(ref_type, row[name]) .. "</td>"
                else
                    cells = cells .. "<td>" .. display_value(row[name]) .. "</td>"
                end
            end
            body_rows = body_rows .. "<tr>" .. cells .. "</tr>"
        end
        if #rows == 0 then
            result_html = "<p class=\"fossci-empty\">No rows.</p>"
        else
            result_html = "<div class=\"fossci-table-wrapper\"><table id=\"sql-table\"><thead><tr>" ..
                header_cells .. "</tr></thead><tbody>" .. body_rows .. "</tbody></table></div>" ..
                "<p class=\"fossci-sql-count\">" .. tostring(#rows) .. " rows</p>"
        end
    elseif sql_text_or_empty == "" then
        -- Submitted with a genuinely empty box -- distinct from the
        -- pre-run, example-prefilled first-load case below, which
        -- needs no message at all (nothing has failed or been skipped).
        result_html = "<p class=\"fossci-empty\">Enter a SQL query above, then click Run.</p>"
    end

    return string.format("""
<div class="fossil-doc" data-title="Query">
    <style>
        .fossci-container {
            font-family: 'Outfit', 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            color: var(--fossci-text, #334155);
            background: #ffffff;
            padding: 28px;
            border-radius: 16px;
            box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.05), 0 8px 10px -6px rgba(0, 0, 0, 0.05);
            margin: 20px auto;
            max-width: 1100px;
            border: 1px solid var(--fossci-bg-2, #f1f5f9);
        }
        .fossci-header { margin-bottom: 20px; border-bottom: 1px solid var(--fossci-bg-2, #f1f5f9); padding-bottom: 16px; }
        .fossci-header h2 { margin: 0 0 6px 0; font-size: 1.6rem; font-weight: 700; color: var(--fossci-heading, #0f172a); letter-spacing: -0.02em; }
        .fossci-header p { color: var(--fossci-muted, #64748b); margin: 0; font-size: 0.95rem; }
        .fossci-sql-input {
            width: 100%%;
            min-height: 140px;
            box-sizing: border-box;
            font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
            font-size: 0.9rem;
            padding: 14px;
            border: 1px solid var(--fossci-border, #e2e8f0);
            border-radius: 10px;
            background: var(--fossci-bg, #f8fafc);
            color: var(--fossci-input-text, #1e293b);
            margin-bottom: 12px;
        }
        .btn-primary {
            padding: 10px 20px;
            border-radius: 8px;
            font-weight: 600;
            font-size: 0.9rem;
            cursor: pointer;
            border: none;
            background: linear-gradient(135deg, var(--fossci-accent, #4f46e5), var(--fossci-accent-2, #6366f1));
            color: #ffffff;
        }
        .fossci-sql-error {
            margin-top: 20px;
            padding: 14px 18px;
            border-radius: 10px;
            background: #fef2f2;
            border: 1px solid #fecaca;
            color: #991b1b;
        }
        .fossci-sql-count { color: var(--fossci-muted, #64748b); font-size: 0.85rem; margin-top: 8px; }
        .fossci-table-wrapper { overflow-x: auto; margin-top: 20px; border: 1px solid var(--fossci-border, #e2e8f0); border-radius: 12px; background: var(--fossci-bg, #f8fafc); }
        #sql-table { width: 100%%; border-collapse: separate; border-spacing: 0; min-width: 600px; }
        #sql-table th, #sql-table td { padding: 10px 14px; text-align: left; border-bottom: 1px solid var(--fossci-border, #e2e8f0); font-size: 0.85rem; }
        #sql-table th { background: var(--fossci-bg-2, #f1f5f9); font-weight: 600; font-size: 0.75rem; color: var(--fossci-th-text, #475569); text-transform: uppercase; letter-spacing: 0.06em; }
        #sql-table td { background: #ffffff; }
        .fossci-empty { margin-top: 20px; padding: 24px; text-align: center; color: var(--fossci-muted, #64748b); background: var(--fossci-bg, #f8fafc); border: 1px dashed var(--fossci-border, #e2e8f0); border-radius: 12px; }
        .fossci-entity-ref { color: var(--fossci-accent, #4f46e5); text-decoration: none; font-weight: 600; }
        .fossci-entity-ref::after { content: " \2197"; font-size: 0.85em; }
        .fossci-entity-ref:hover { text-decoration: underline; }
        .fossci-nlsql { display: flex; align-items: center; gap: 10px; margin-bottom: 12px; }
        .fossci-nlsql input {
            flex: 1;
            padding: 10px 14px;
            border: 1px solid var(--fossci-border, #e2e8f0);
            border-radius: 8px;
            background: var(--fossci-bg, #f8fafc);
            color: var(--fossci-input-text, #1e293b);
            font-size: 0.9rem;
        }
        .btn-secondary {
            padding: 10px 16px;
            border-radius: 8px;
            font-weight: 600;
            font-size: 0.85rem;
            cursor: pointer;
            border: 1px solid var(--fossci-border, #e2e8f0);
            background: var(--fossci-bg-2, #f1f5f9);
            color: var(--fossci-text, #334155);
            white-space: nowrap;
        }
        .btn-secondary:disabled { opacity: 0.6; cursor: default; }
        .fossci-nlsql-status { font-size: 0.8rem; color: var(--fossci-muted, #64748b); white-space: nowrap; }
    </style>
    <div class="fossci-container">
        <div class="fossci-header">
            <h2>Query</h2>
            <p>Read-only (SELECT only) queries against the entity store. Setup/Admin only.</p>
        </div>
        <div class="fossci-nlsql" id="fossci-nlsql">
            <input type="text" id="fossci-nlsql-input" placeholder="Ask the agent to write or update this query in plain English..." autocomplete="off" />
            <button type="button" class="btn-secondary" id="fossci-nlsql-btn">Generate query</button>
            <span class="fossci-nlsql-status" id="fossci-nlsql-status"></span>
        </div>
        <form method="get" action="fossci/sql">
            <textarea class="fossci-sql-input" id="fossci-sql-query" name="q" placeholder="SELECT * FROM sample LIMIT 20;">%s</textarea>
            <button class="btn-primary" type="submit">Run</button>
        </form>
        %s
    </div>
</div>
""", escaped_sql, result_html)
end

return html
