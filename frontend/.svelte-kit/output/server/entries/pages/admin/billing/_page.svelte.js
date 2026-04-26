import { h as head, a as attr, e as escape_html } from "../../../../chunks/renderer.js";
function _page($$renderer, $$props) {
  $$renderer.component(($$renderer2) => {
    let contractId = "";
    let missingBills = [];
    let processingBills = false;
    head("sycr78", $$renderer2, ($$renderer3) => {
      $$renderer3.title(($$renderer4) => {
        $$renderer4.push(`<title>Billing — FMRZ Admin</title>`);
      });
    });
    $$renderer2.push(`<div class="container"><div class="page-header" style="display:flex; justify-content:space-between; align-items:center;"><div><h1>Billing &amp; <span class="text-gradient svelte-sycr78">Invoices</span></h1> <p class="text-muted">Monitor network revenue and audit historical subscriber statements</p></div> <button class="btn btn-primary"${attr("disabled", processingBills, true)}>`);
    {
      $$renderer2.push("<!--[-1-->");
      $$renderer2.push(`<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="margin-right:8px"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="17 8 12 3 7 8"></polyline><line x1="12" y1="3" x2="12" y2="15"></line></svg> Run Billing Cycle Now`);
    }
    $$renderer2.push(`<!--]--></button></div> <div class="stats-grid svelte-sycr78"><div class="card stat-card info-card card-static svelte-sycr78"><div class="stat-icon svelte-sycr78"><svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--red)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="1" x2="12" y2="23"></line><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"></path></svg></div> <div class="stat-info svelte-sycr78"><span class="stat-label svelte-sycr78">Total Revenue</span> <span class="stat-value svelte-sycr78">${escape_html(0)} EGP</span></div></div> <div class="card stat-card info-card card-static svelte-sycr78"><div class="stat-icon svelte-sycr78"><svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--red)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="16" y1="13" x2="8" y2="13"></line><line x1="16" y1="17" x2="8" y2="17"></line><polyline points="10 9 9 9 8 9"></polyline></svg></div> <div class="stat-info svelte-sycr78"><span class="stat-label svelte-sycr78">Pending Collection</span> <span class="stat-value svelte-sycr78">${escape_html(0)}</span></div></div> <div class="card stat-card info-card card-static svelte-sycr78" style="cursor:pointer"><div class="stat-icon svelte-sycr78"><svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none"${attr("stroke", missingBills.length > 0 ? "var(--red)" : "var(--text-muted)")} stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"></path><line x1="12" y1="9" x2="12" y2="13"></line><line x1="12" y1="17" x2="12.01" y2="17"></line></svg></div> <div class="stat-info svelte-sycr78"><span class="stat-label svelte-sycr78">Missing Statements</span> <span class="stat-value svelte-sycr78">${escape_html(missingBills.length)}</span></div> <div class="card-hint svelte-sycr78">${escape_html("Show Audit")}</div></div></div> `);
    {
      $$renderer2.push("<!--[-1-->");
    }
    $$renderer2.push(`<!--]--> <div class="search-bar animate-fade"><div style="display:flex;gap:1rem;margin-bottom:2rem"><div class="input-wrapper" style="flex:1; max-width: 300px;"><input class="input" placeholder="Filter by Contract ID..."${attr("value", contractId)} type="number"/></div> <button class="btn btn-primary">Search Records</button> `);
    {
      $$renderer2.push("<!--[-1-->");
    }
    $$renderer2.push(`<!--]--></div></div> `);
    {
      $$renderer2.push("<!--[0-->");
      $$renderer2.push(`<div class="loading-state svelte-sycr78"><div class="spinner"></div> <p>Synchronizing billing records...</p></div>`);
    }
    $$renderer2.push(`<!--]--></div>`);
  });
}
export {
  _page as default
};
