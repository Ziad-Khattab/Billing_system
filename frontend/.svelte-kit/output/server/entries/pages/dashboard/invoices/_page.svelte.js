import { h as head } from "../../../../chunks/renderer.js";
function _page($$renderer, $$props) {
  $$renderer.component(($$renderer2) => {
    head("1qiab06", $$renderer2, ($$renderer3) => {
      $$renderer3.title(($$renderer4) => {
        $$renderer4.push(`<title>My Invoices — FMRZ</title>`);
      });
    });
    $$renderer2.push(`<div class="container animate-fade"><div class="page-header"><a href="/dashboard" class="back-link svelte-1qiab06">← Back to Dashboard</a> <h1>My <span class="text-gradient svelte-1qiab06">Invoices</span></h1></div> `);
    {
      $$renderer2.push("<!--[0-->");
      $$renderer2.push(`<div class="loading svelte-1qiab06">Loading your billing history...</div>`);
    }
    $$renderer2.push(`<!--]--></div>`);
  });
}
export {
  _page as default
};
