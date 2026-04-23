import { h as head, ac as attr, c as ensure_array_like, e as escape_html } from "../../../../chunks/renderer.js";
function _page($$renderer, $$props) {
  $$renderer.component(($$renderer2) => {
    let customers = [];
    let search = "";
    head("zvcdha", $$renderer2, ($$renderer3) => {
      $$renderer3.title(($$renderer4) => {
        $$renderer4.push(`<title>Customers — FMRZ Admin</title>`);
      });
    });
    $$renderer2.push(`<div class="container"><div class="page-header"><h1>Customers</h1> <div style="display:flex;gap:1rem"><input class="input" style="width:250px" placeholder="Search..."${attr("value", search)}/> <button class="btn btn-primary">+ Add</button></div></div> <div class="table-wrapper"><table><thead><tr><th>ID</th><th>Name</th><th>Email</th><th>Address</th><th>Birthdate</th></tr></thead><tbody><!--[-->`);
    const each_array = ensure_array_like(customers);
    for (let $$index = 0, $$length = each_array.length; $$index < $$length; $$index++) {
      let c = each_array[$$index];
      $$renderer2.push(`<tr><td>#${escape_html(c.id)}</td><td style="font-weight:600">${escape_html(c.name)}</td><td>${escape_html(c.email || "—")}</td><td>${escape_html(c.address || "—")}</td><td>${escape_html(c.birthdate || "—")}</td></tr>`);
    }
    $$renderer2.push(`<!--]--></tbody></table></div></div> `);
    {
      $$renderer2.push("<!--[-1-->");
    }
    $$renderer2.push(`<!--]-->`);
  });
}
export {
  _page as default
};
