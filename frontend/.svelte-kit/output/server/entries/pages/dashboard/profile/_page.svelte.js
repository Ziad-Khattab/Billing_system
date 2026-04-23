import { h as head } from "../../../../chunks/renderer.js";
function _page($$renderer, $$props) {
  $$renderer.component(($$renderer2) => {
    head("1f9xdep", $$renderer2, ($$renderer3) => {
      $$renderer3.title(($$renderer4) => {
        $$renderer4.push(`<title>Edit Profile — FMRZ</title>`);
      });
    });
    $$renderer2.push(`<div class="container narrow animate-fade svelte-1f9xdep"><div class="page-header"><a href="/dashboard" class="back-link svelte-1f9xdep">← Back to Dashboard</a> <h1>Edit <span class="text-gradient svelte-1f9xdep">Profile</span></h1></div> `);
    {
      $$renderer2.push("<!--[0-->");
      $$renderer2.push(`<div class="loading svelte-1f9xdep">Loading profile...</div>`);
    }
    $$renderer2.push(`<!--]--></div>`);
  });
}
export {
  _page as default
};
