import { h as head, e as escape_html, a as attr_class, c as ensure_array_like, f as stringify } from "../../../chunks/renderer.js";
function _page($$renderer, $$props) {
  $$renderer.component(($$renderer2) => {
    let contracts = [];
    let invoices = [];
    head("x1i5gj", $$renderer2, ($$renderer3) => {
      $$renderer3.title(($$renderer4) => {
        $$renderer4.push(`<title>Dashboard — FMRZ</title>`);
      });
    });
    $$renderer2.push(`<div class="container svelte-x1i5gj"><div class="page-header svelte-x1i5gj"><h1 class="svelte-x1i5gj">My <span class="text-gradient svelte-x1i5gj">Dashboard</span></h1></div> <div class="grid-3 svelte-x1i5gj"><div class="stat-card animate-fade svelte-x1i5gj"><span class="stat-label svelte-x1i5gj">Active Contracts</span> <span class="stat-value svelte-x1i5gj">${escape_html(contracts.filter((c) => c.status === "active").length)}</span></div> <div class="stat-card animate-fade svelte-x1i5gj" style="animation-delay: 0.1s"><span class="stat-label svelte-x1i5gj">Total Invoices</span> <span class="stat-value svelte-x1i5gj">${escape_html(invoices.length)}</span></div> <div class="stat-card animate-fade svelte-x1i5gj" style="animation-delay: 0.2s"><span class="stat-label svelte-x1i5gj">Account Status</span> <div${attr_class(`status-indicator ${stringify("active")}`, "svelte-x1i5gj")}><span class="status-dot svelte-x1i5gj"></span> <span class="status-text svelte-x1i5gj">${escape_html("Active")}</span></div></div></div> `);
    {
      $$renderer2.push("<!--[-1-->");
    }
    $$renderer2.push(`<!--]--> `);
    if (contracts.length > 0) {
      $$renderer2.push("<!--[0-->");
      $$renderer2.push(`<div class="section animate-fade svelte-x1i5gj" style="animation-delay: 0.4s"><h2 class="svelte-x1i5gj">My Contracts</h2> <div class="table-wrapper svelte-x1i5gj"><table class="svelte-x1i5gj"><thead class="svelte-x1i5gj"><tr class="svelte-x1i5gj"><th class="svelte-x1i5gj">MSISDN</th><th class="svelte-x1i5gj">Plan</th><th class="svelte-x1i5gj">Status</th><th class="svelte-x1i5gj">Credit</th></tr></thead><tbody class="svelte-x1i5gj"><!--[-->`);
      const each_array = ensure_array_like(contracts);
      for (let $$index = 0, $$length = each_array.length; $$index < $$length; $$index++) {
        let c = each_array[$$index];
        $$renderer2.push(`<tr class="svelte-x1i5gj"><td style="font-weight: 600;" class="svelte-x1i5gj">${escape_html(c.msisdn)}</td><td class="svelte-x1i5gj">${escape_html(c.rateplanName || "—")}</td><td class="svelte-x1i5gj"><div class="flex items-center gap-2 svelte-x1i5gj"><span${attr_class(`status-dot-sm ${stringify(c.status)}`, "svelte-x1i5gj")}></span> <span${attr_class(`badge badge-${stringify(c.status)}`, "svelte-x1i5gj")}>${escape_html(c.status)}</span></div></td><td style="font-weight: 700;" class="svelte-x1i5gj">${escape_html(c.availableCredit)} EGP</td></tr>`);
      }
      $$renderer2.push(`<!--]--></tbody></table></div></div>`);
    } else {
      $$renderer2.push("<!--[-1-->");
    }
    $$renderer2.push(`<!--]--></div>`);
  });
}
export {
  _page as default
};
