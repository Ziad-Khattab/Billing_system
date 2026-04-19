import { B as attr, V as escape_html, a as ensure_array_like, o as head } from "../../../../chunks/dev.js";
//#region src/routes/admin/customers/+page.svelte
function _page($$renderer, $$props) {
	$$renderer.component(($$renderer) => {
		let customers = [];
		let search = "";
		head("zvcdha", $$renderer, ($$renderer) => {
			$$renderer.title(($$renderer) => {
				$$renderer.push(`<title>Customers — FMRZ Admin</title>`);
			});
		});
		$$renderer.push(`<div class="container"><div class="page-header"><h1>Customers</h1> <div style="display:flex;gap:1rem"><input class="input" style="width:250px" placeholder="Search..."${attr("value", search)}/> <button class="btn btn-primary">+ Add</button></div></div> <div class="table-wrapper"><table><thead><tr><th>ID</th><th>Name</th><th>Address</th><th>Birthdate</th></tr></thead><tbody><!--[-->`);
		const each_array = ensure_array_like(customers);
		for (let $$index = 0, $$length = each_array.length; $$index < $$length; $$index++) {
			let c = each_array[$$index];
			$$renderer.push(`<tr><td>#${escape_html(c.id)}</td><td style="font-weight:600">${escape_html(c.name)}</td><td>${escape_html(c.address || "—")}</td><td>${escape_html(c.birthdate || "—")}</td></tr>`);
		}
		$$renderer.push(`<!--]--></tbody></table></div></div> `);
		$$renderer.push("<!--[-1-->");
		$$renderer.push(`<!--]-->`);
	});
}
//#endregion
export { _page as default };
