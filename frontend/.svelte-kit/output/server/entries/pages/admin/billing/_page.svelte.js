import { h as head, ac as attr, c as ensure_array_like, e as escape_html } from "../../../../chunks/renderer.js";
function _page($$renderer) {
  let contractId = "";
  let bills = [];
  head("sycr78", $$renderer, ($$renderer2) => {
    $$renderer2.title(($$renderer3) => {
      $$renderer3.push(`<title>Billing — FMRZ Admin</title>`);
    });
  });
  $$renderer.push(`<div class="container"><div class="page-header"><h1>Billing &amp; Invoices</h1></div> <div style="display:flex;gap:1rem;margin-bottom:2rem"><input class="input" style="width:200px" placeholder="Contract ID"${attr("value", contractId)} type="number"/> <button class="btn btn-primary">Load Bills</button></div> `);
  if (bills.length > 0) {
    $$renderer.push("<!--[0-->");
    $$renderer.push(`<div class="table-wrapper"><table><thead><tr><th>Bill ID</th><th>Date</th><th>Recurring</th><th>One-time</th><th>Voice</th><th>Data</th><th>SMS</th><th>Tax</th></tr></thead><tbody><!--[-->`);
    const each_array = ensure_array_like(bills);
    for (let $$index = 0, $$length = each_array.length; $$index < $$length; $$index++) {
      let b = each_array[$$index];
      $$renderer.push(`<tr><td>#${escape_html(b.id)}</td><td>${escape_html(b.billingDate)}</td><td>${escape_html(b.recurringFees)} EGP</td><td>${escape_html(b.oneTimeFees)} EGP</td><td>${escape_html(b.voiceUsage)}s</td><td>${escape_html(b.dataUsage)} MB</td><td>${escape_html(b.smsUsage)}</td><td>${escape_html(b.taxes)} EGP</td></tr>`);
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
