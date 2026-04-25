import { h as head, a as attr, d as ensure_array_like, e as escape_html } from "../../../../chunks/renderer.js";
function _page($$renderer, $$props) {
  $$renderer.component(($$renderer2) => {
    let customers = [];
    let search = "";
    head("zvcdha", $$renderer2, ($$renderer3) => {
      $$renderer3.title(($$renderer4) => {
        $$renderer4.push(`<title>Customers — FMRZ Admin</title>`);
      });
    });
    $$renderer2.push(`<div class="container"><div class="page-header"><h1>Customer <span class="text-gradient">Directory</span></h1> <p class="text-muted">Manage subscriber profiles and account information</p></div> <div class="search-bar animate-fade"><div style="display:flex;gap:1rem"><input class="input" style="width:250px" placeholder="Search by name or email..."${attr("value", search)} aria-label="Search customers"/> <button class="btn btn-primary">+ Add New Customer</button></div></div> <div class="table-wrapper animate-fade"><table><thead><tr><th>ID</th><th>MSISDN</th><th>Name</th><th>Category</th><th>Email</th><th>Address</th></tr></thead><tbody><!--[-->`);
    const each_array = ensure_array_like(customers);
    for (let $$index = 0, $$length = each_array.length; $$index < $$length; $$index++) {
      let c = each_array[$$index];
      $$renderer2.push(`<tr><td><span class="id-badge">#${escape_html(c.id)}</span></td><td><span class="phone-num">${escape_html(c.msisdn)}</span></td><td style="font-weight:600">${escape_html(c.name)}</td><td><span class="badge badge-customer">${escape_html(c.category)}</span></td><td class="text-muted">${escape_html(c.email || "—")}</td><td class="text-muted">${escape_html(c.address || "—")}</td></tr>`);
    }
    $$renderer2.push(`<!--]--></tbody></table></div></div> `);
    {
      $$renderer2.push("<!--[-1-->");
    }
    $$renderer2.push(`<!--]--> `);
    {
      $$renderer2.push("<!--[-1-->");
    }
    $$renderer2.push(`<!--]-->`);
  });
}
export {
  _page as default
};
