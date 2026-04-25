import { h as head, d as ensure_array_like, e as escape_html, b as attr_class, i as stringify, f as attr_style } from "../../../../chunks/renderer.js";
function _page($$renderer, $$props) {
  $$renderer.component(($$renderer2) => {
    let contracts = [];
    head("2nyem4", $$renderer2, ($$renderer3) => {
      $$renderer3.title(($$renderer4) => {
        $$renderer4.push(`<title>Contracts — FMRZ Admin</title>`);
      });
    });
    $$renderer2.push(`<div class="container"><div class="page-header"><h1>Service <span class="text-gradient">Contracts</span></h1> <p class="text-muted">Manage and provision phone lines across the subscriber base</p></div> <div class="table-wrapper animate-fade"><table><thead><tr><th>ID</th><th>MSISDN</th><th>Customer</th><th>Plan</th><th>Status</th><th>Credit</th></tr></thead><tbody><!--[-->`);
    const each_array = ensure_array_like(contracts);
    for (let $$index = 0, $$length = each_array.length; $$index < $$length; $$index++) {
      let c = each_array[$$index];
      $$renderer2.push(`<tr><td><span class="id-badge">#${escape_html(c.id)}</span></td><td><span class="phone-num">${escape_html(c.msisdn)}</span></td><td style="font-weight:600">${escape_html(c.customerName || "—")}</td><td><span class="badge badge-customer">${escape_html(c.rateplanName || "—")}</span></td><td><span${attr_class(`badge badge-${stringify(c.status)}`)}>${escape_html(c.status)}</span></td><td><span class="amount-num"${attr_style(c.availableCredit < 0 ? "color: #ef4444" : "")}>${escape_html(c.availableCredit)} EGP</span></td></tr>`);
    }
    $$renderer2.push(`<!--]--></tbody></table></div></div>`);
  });
}
export {
  _page as default
};
