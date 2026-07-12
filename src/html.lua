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
            color: #334155;
            background: #ffffff;
            padding: 28px;
            border-radius: 16px;
            box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.05), 0 8px 10px -6px rgba(0, 0, 0, 0.05);
            margin: 20px auto;
            max-width: 1200px;
            border: 1px solid #f1f5f9;
        }
        .fossci-header {
            margin-bottom: 24px;
            border-bottom: 1px solid #f1f5f9;
            padding-bottom: 16px;
        }
        .fossci-header h2 {
            margin: 0 0 6px 0;
            font-size: 1.6rem;
            font-weight: 700;
            color: #0f172a;
            letter-spacing: -0.02em;
        }
        .fossci-header p {
            color: #64748b;
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
            border: 1px solid #e2e8f0;
            border-radius: 12px;
            box-shadow: inset 0 2px 4px 0 rgba(0,0,0,0.02);
            background: #f8fafc;
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
            border-bottom: 1px solid #e2e8f0;
        }
        #registration-table th {
            background: #f1f5f9;
            font-weight: 600;
            font-size: 0.8rem;
            color: #475569;
            text-transform: uppercase;
            letter-spacing: 0.06em;
            border-top: 1px solid #e2e8f0;
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
            border: 1px solid #cbd5e1;
            border-radius: 8px;
            font-size: 0.9rem;
            background: #ffffff;
            transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
            box-sizing: border-box;
            color: #1e293b;
        }
        .cell-input:focus {
            border-color: #6366f1;
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
            border: 1px solid #e2e8f0;
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
            color: #334155;
        }
        .autocomplete-item:hover { background: #f1f5f9; color: #0f172a; }
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
            background: linear-gradient(135deg, #4f46e5, #6366f1);
            color: #ffffff;
            box-shadow: 0 4px 12px rgba(99, 102, 241, 0.2);
        }
        .btn-primary:hover { box-shadow: 0 6px 16px rgba(99, 102, 241, 0.3); filter: brightness(1.05); }
        .btn-primary:active { transform: scale(0.98); }
        .btn-secondary {
            background: #f8fafc;
            color: #475569;
            border: 1px solid #e2e8f0;
        }
        .btn-secondary:hover { background: #f1f5f9; color: #0f172a; }
        .btn-delete {
            background: transparent;
            color: #94a3b8;
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
            <p><a href="browse?type=%s">Browse existing %s entities &rarr;</a></p>
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

            fetch(`${baseUrl}/api/submit?type=${entityType}`, {
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

-- Browse view: a read-only table of every entity of a type, linking to
-- each one's detail page. Pure server-rendered HTML -- no JS, so none
-- of the CSP/nonce concerns the registration table's client-side JS
-- has (see html.render's header comment for why that one needs one).
function html.render_browse(entity_type, layout, rows)
    escaped_type = html_escape(entity_type)

    header_cells = "<th>ID</th>"
    for _, field in ipairs(layout.fields) do
        header_cells = header_cells .. "<th>" .. html_escape(field.label) .. "</th>"
    end

    body_rows = ""
    for _, row in ipairs(rows) do
        cells = "<td><a href=\"detail?type=" .. escaped_type .. "&id=" .. tostring(row.id) ..
            "\">#" .. tostring(row.id) .. "</a></td>"
        for _, field in ipairs(layout.fields) do
            cells = cells .. "<td>" .. display_value(row[field.name]) .. "</td>"
        end
        body_rows = body_rows .. "<tr>" .. cells .. "</tr>"
    end

    table_or_empty = "<div class=\"fossci-table-wrapper\"><table id=\"browse-table\"><thead><tr>" ..
        header_cells .. "</tr></thead><tbody>" .. body_rows .. "</tbody></table></div>"
    if #rows == 0 then
        table_or_empty = "<p class=\"fossci-empty\">No " .. escaped_type .. " entities registered yet.</p>"
    end

    return string.format("""
<div class="fossil-doc" data-title="Browse %s">
    <style>
        .fossci-container {
            font-family: 'Outfit', 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            color: #334155;
            background: #ffffff;
            padding: 28px;
            border-radius: 16px;
            box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.05), 0 8px 10px -6px rgba(0, 0, 0, 0.05);
            margin: 20px auto;
            max-width: 1200px;
            border: 1px solid #f1f5f9;
        }
        .fossci-header {
            margin-bottom: 24px;
            border-bottom: 1px solid #f1f5f9;
            padding-bottom: 16px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .fossci-header h2 { margin: 0 0 6px 0; font-size: 1.6rem; font-weight: 700; color: #0f172a; letter-spacing: -0.02em; }
        .fossci-header p { color: #64748b; margin: 0; font-size: 0.95rem; }
        .fossci-header a { color: #4f46e5; text-decoration: none; font-weight: 600; }
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
            background: linear-gradient(135deg, #4f46e5, #6366f1);
            color: #ffffff;
            box-shadow: 0 4px 12px rgba(99, 102, 241, 0.2);
        }
        .fossci-table-wrapper {
            overflow-x: auto;
            border: 1px solid #e2e8f0;
            border-radius: 12px;
            background: #f8fafc;
        }
        #browse-table { width: 100%%; border-collapse: separate; border-spacing: 0; min-width: 600px; }
        #browse-table th, #browse-table td {
            padding: 12px 16px;
            text-align: left;
            border-bottom: 1px solid #e2e8f0;
            font-size: 0.9rem;
        }
        #browse-table th {
            background: #f1f5f9;
            font-weight: 600;
            font-size: 0.78rem;
            color: #475569;
            text-transform: uppercase;
            letter-spacing: 0.06em;
        }
        #browse-table td { background: #ffffff; }
        #browse-table a { color: #4f46e5; text-decoration: none; font-weight: 600; }
        #browse-table a:hover { text-decoration: underline; }
        .fossci-empty {
            padding: 32px;
            text-align: center;
            color: #64748b;
            background: #f8fafc;
            border: 1px dashed #e2e8f0;
            border-radius: 12px;
        }
    </style>

    <div class="fossci-container">
        <div class="fossci-header">
            <div>
                <h2>Browse %s</h2>
                <p>%d registered</p>
            </div>
            <a class="btn btn-primary" href="register?type=%s">+ Register new</a>
        </div>
        %s
    </div>
</div>
""", escaped_type, escaped_type, #rows, escaped_type, table_or_empty)
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
            display_value(row[field.name]) .. "</span></div>"
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
            color: #334155;
            background: #ffffff;
            padding: 28px;
            border-radius: 16px;
            box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.05), 0 8px 10px -6px rgba(0, 0, 0, 0.05);
            margin: 20px auto;
            max-width: 1200px;
            border: 1px solid #f1f5f9;
        }
        .fossci-header { margin-bottom: 24px; border-bottom: 1px solid #f1f5f9; padding-bottom: 16px; }
        .fossci-header h2 { margin: 0 0 6px 0; font-size: 1.6rem; font-weight: 700; color: #0f172a; letter-spacing: -0.02em; }
        .fossci-header a { color: #4f46e5; text-decoration: none; font-weight: 600; font-size: 0.9rem; }
        .fossci-header a:hover { text-decoration: underline; }
        .fossci-subheading { font-size: 1.05rem; color: #0f172a; margin: 28px 0 14px 0; }
        .fossci-detail-fields {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
            gap: 16px 24px;
            padding: 20px;
            background: #f8fafc;
            border: 1px solid #e2e8f0;
            border-radius: 12px;
        }
        .detail-row { display: flex; flex-direction: column; gap: 4px; }
        .detail-label { font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.06em; color: #64748b; font-weight: 600; }
        .detail-value { font-size: 0.95rem; color: #0f172a; word-break: break-word; }
        .fossci-table-wrapper { overflow-x: auto; border: 1px solid #e2e8f0; border-radius: 12px; background: #f8fafc; }
        #history-table { width: 100%%; border-collapse: separate; border-spacing: 0; min-width: 700px; }
        #history-table th, #history-table td {
            padding: 12px 16px;
            text-align: left;
            border-bottom: 1px solid #e2e8f0;
            font-size: 0.85rem;
            vertical-align: top;
        }
        #history-table th {
            background: #f1f5f9;
            font-weight: 600;
            font-size: 0.75rem;
            color: #475569;
            text-transform: uppercase;
            letter-spacing: 0.06em;
        }
        #history-table td { background: #ffffff; }
        .change-item { margin-bottom: 4px; }
        .change-item:last-child { margin-bottom: 0; }
    </style>

    <div class="fossci-container">
        <div class="fossci-header">
            <h2>%s #%s</h2>
            <a href="browse?type=%s">&larr; Back to browse</a>
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

return html
