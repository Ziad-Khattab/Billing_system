import { o as head } from "../../../chunks/dev.js";
//#region src/routes/packages/+page.svelte
function _page($$renderer, $$props) {
	$$renderer.component(($$renderer) => {
		head("disfw2", $$renderer, ($$renderer) => {
			$$renderer.title(($$renderer) => {
				$$renderer.push(`<title>Packages — FMRZ</title>`);
			});
		});
		$$renderer.push(`<div class="container"><div class="page-header"><div><h1>Rate Plans &amp; <span class="text-gradient svelte-disfw2">Packages</span></h1> <p class="page-subtitle svelte-disfw2">Choose the perfect plan for your communication needs</p></div></div> `);
		$$renderer.push("<!--[0-->");
		$$renderer.push(`<div class="loading svelte-disfw2">Loading packages...</div>`);
		$$renderer.push(`<!--]--></div>`);
	});
}
//#endregion
export { _page as default };
