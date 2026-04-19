import { V as escape_html, a as ensure_array_like, l as stringify, n as attr_class, o as head } from "../../../chunks/dev.js";
//#region src/routes/dashboard/+page.svelte
function _page($$renderer, $$props) {
	$$renderer.component(($$renderer) => {
		let contracts = [];
		let invoices = [];
		head("x1i5gj", $$renderer, ($$renderer) => {
			$$renderer.title(($$renderer) => {
				$$renderer.push(`<title>Dashboard — FMRZ</title>`);
			});
		});
		$$renderer.push(`<div class="container"><div class="page-header"><h1>My <span class="text-gradient svelte-x1i5gj">Dashboard</span></h1></div> <div class="grid-3"><div class="stat-card"><span class="stat-label">Active Contracts</span> <span class="stat-value">${escape_html(contracts.filter((c) => c.status === "active").length)}</span></div> <div class="stat-card"><span class="stat-label">Total Invoices</span> <span class="stat-value">${escape_html(invoices.length)}</span></div> <div class="stat-card"><span class="stat-label">Account Status</span> <span class="stat-value" style="font-size: 1.5rem;">✅ Active</span></div></div> `);
		$$renderer.push("<!--[-1-->");
		$$renderer.push(`<!--]--> `);
		if (contracts.length > 0) {
			$$renderer.push("<!--[0-->");
			$$renderer.push(`<div class="section svelte-x1i5gj"><h2 class="svelte-x1i5gj">My Contracts</h2> <div class="table-wrapper"><table><thead><tr><th>MSISDN</th><th>Plan</th><th>Status</th><th>Credit</th></tr></thead><tbody><!--[-->`);
			const each_array = ensure_array_like(contracts);
			for (let $$index = 0, $$length = each_array.length; $$index < $$length; $$index++) {
				let c = each_array[$$index];
				$$renderer.push(`<tr><td style="font-weight: 600;">${escape_html(c.msisdn)}</td><td>${escape_html(c.rateplanName || "—")}</td><td><span${attr_class(`badge badge-${stringify(c.status)}`, "svelte-x1i5gj")}>${escape_html(c.status)}</span></td><td>${escape_html(c.availableCredit)} EGP</td></tr>`);
			}
			$$renderer.push(`<!--]--></tbody></table></div></div>`);
		} else $$renderer.push("<!--[-1-->");
		$$renderer.push(`<!--]--></div>`);
	});
}
//#endregion
export { _page as default };
