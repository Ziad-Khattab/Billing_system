import { V as escape_html, a as ensure_array_like, l as stringify, n as attr_class, o as head } from "../../../../chunks/dev.js";
//#region src/routes/admin/contracts/+page.svelte
function _page($$renderer, $$props) {
	$$renderer.component(($$renderer) => {
		let contracts = [];
		head("2nyem4", $$renderer, ($$renderer) => {
			$$renderer.title(($$renderer) => {
				$$renderer.push(`<title>Contracts — FMRZ Admin</title>`);
			});
		});
		$$renderer.push(`<div class="container"><div class="page-header"><h1>Contracts</h1></div> <div class="table-wrapper"><table><thead><tr><th>ID</th><th>MSISDN</th><th>Customer</th><th>Plan</th><th>Status</th><th>Credit</th></tr></thead><tbody><!--[-->`);
		const each_array = ensure_array_like(contracts);
		for (let $$index = 0, $$length = each_array.length; $$index < $$length; $$index++) {
			let c = each_array[$$index];
			$$renderer.push(`<tr><td>#${escape_html(c.id)}</td><td style="font-weight:600">${escape_html(c.msisdn)}</td><td>${escape_html(c.customerName || "—")}</td><td>${escape_html(c.rateplanName || "—")}</td><td><span${attr_class(`badge badge-${stringify(c.status)}`)}>${escape_html(c.status)}</span></td><td>${escape_html(c.availableCredit)} EGP</td></tr>`);
		}
		$$renderer.push(`<!--]--></tbody></table></div></div>`);
	});
}
//#endregion
export { _page as default };
