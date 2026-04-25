import { h as head, a as attr, d as ensure_array_like, e as escape_html } from "../../../../chunks/renderer.js";
function _page($$renderer) {
  let contractId = "";
  let bills = [];
  head("sycr78", $$renderer, ($$renderer2) => {
    $$renderer2.title(($$renderer3) => {
      $$renderer3.push(`<title>Billing — FMRZ Admin</title>`);
    });
  });
  $$renderer.push(`<div class="container"><div class="page-header"><h1>Billing &amp; <span class="text-gradient">Invoices</span></h1> <p class="text-muted">Track and audit historical billing records across the network</p></div> <div class="search-bar animate-fade"><div style="display:flex;gap:1rem;margin-bottom:2rem"><input class="input" style="width:200px" placeholder="Enter Contract ID..."${attr("value", contractId)} type="number"/> <button class="btn btn-primary">Load Bills</button></div></div> `);
  if (bills.length > 0) {
    $$renderer.push("<!--[1-->");
    $$renderer.push(`<div class="table-wrapper"><table><thead><tr><th>Bill ID</th><th>Date</th><th>Recurring</th><th>One-time</th><th>Voice</th><th>Data</th><th>SMS</th><th>Tax</th></tr></thead><tbody><!--[-->`);
    const each_array = ensure_array_like(bills);
    for (let $$index = 0, $$length = each_array.length; $$index < $$length; $$index++) {
      let b = each_array[$$index];
      $$renderer.push(`<tr><td><span class="id-badge">#${escape_html(b.id)}</span></td><td class="text-muted">${escape_html(b.billingDate)}</td><td><span class="amount-num">${escape_html(b.recurringFees)} EGP</span></td><td><span class="amount-num">${escape_html(b.oneTimeFees)} EGP</span></td><td><span class="duration-num">${escape_html(b.voiceUsage)}s</span></td><td><span class="duration-num">${escape_html(b.dataUsage)} MB</span></td><td><span class="duration-num">${escape_html(b.smsUsage)}</span></td><td><span class="amount-num">${escape_html(b.taxes)} EGP</span></td></tr>`);
    }
    $$renderer.push(`<!--]--></tbody></table></div>`);
  } else {
    $$renderer.push("<!--[-1-->");
    $$renderer.push(`<div class="card" style="text-align:center;padding:3rem;color:var(--text-muted)">Enter a contract ID and click "Load Bills" to view billing data</div>`);
  }
  $$renderer.push(`<!--]--></div>`);
}
export {
  _page as default
};
