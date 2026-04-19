import "../../chunks/environment.js";
import { c as store_get, et as getContext, n as attr_class, u as unsubscribe_stores } from "../../chunks/dev.js";
import "../../chunks/client.js";
//#region node_modules/@sveltejs/kit/src/runtime/app/stores.js
/**
* A function that returns all of the contextual stores. On the server, this must be called during component initialization.
* Only use this if you need to defer store subscription until after the component has mounted, for some reason.
*
* @deprecated Use `$app/state` instead (requires Svelte 5, [see docs for more info](https://svelte.dev/docs/kit/migrating-to-sveltekit-2#SvelteKit-2.12:-$app-stores-deprecated))
*/
var getStores = () => {
	const stores$1 = getContext("__svelte__");
	return {
		page: { subscribe: stores$1.page.subscribe },
		navigating: { subscribe: stores$1.navigating.subscribe },
		updated: stores$1.updated
	};
};
/**
* A readable store whose value contains page data.
*
* On the server, this store can only be subscribed to during component initialization. In the browser, it can be subscribed to at any time.
*
* @deprecated Use `page` from `$app/state` instead (requires Svelte 5, [see docs for more info](https://svelte.dev/docs/kit/migrating-to-sveltekit-2#SvelteKit-2.12:-$app-stores-deprecated))
* @type {import('svelte/store').Readable<import('@sveltejs/kit').Page>}
*/
var page = { subscribe(fn) {
	return getStores().page.subscribe(fn);
} };
//#endregion
//#region src/routes/+layout.svelte
function _layout($$renderer, $$props) {
	$$renderer.component(($$renderer) => {
		var $$store_subs;
		/** @type {{ children: import('svelte').Snippet }} */
		let { children } = $$props;
		$$renderer.push(`<div class="app svelte-12qhfyh"><nav class="navbar svelte-12qhfyh"><div class="nav-inner container svelte-12qhfyh"><a href="/" class="nav-brand svelte-12qhfyh"><img src="/logo.png" alt="FMRZ" class="nav-logo svelte-12qhfyh"/></a> <button class="nav-toggle svelte-12qhfyh"><span class="svelte-12qhfyh"></span><span class="svelte-12qhfyh"></span><span class="svelte-12qhfyh"></span></button> <div${attr_class("nav-links svelte-12qhfyh", void 0, { "open": false })}><a href="/"${attr_class("nav-link svelte-12qhfyh", void 0, { "active": store_get($$store_subs ??= {}, "$page", page).url.pathname === "/" })}>Home</a> <a href="/packages"${attr_class("nav-link svelte-12qhfyh", void 0, { "active": store_get($$store_subs ??= {}, "$page", page).url.pathname === "/packages" })}>Packages</a> `);
		$$renderer.push("<!--[-1-->");
		$$renderer.push(`<!--]--> <div class="nav-spacer svelte-12qhfyh"></div> `);
		$$renderer.push("<!--[-1-->");
		$$renderer.push(`<a href="/login" class="btn btn-ghost">Login</a> <a href="/register" class="btn btn-primary">Register</a>`);
		$$renderer.push(`<!--]--></div></div></nav> <main class="main-content svelte-12qhfyh">`);
		children($$renderer);
		$$renderer.push(`<!----></main> <footer class="footer svelte-12qhfyh"><div class="container"><p>© 2026 FMRZ Telecom Billing — ITI Project</p></div></footer></div>`);
		if ($$store_subs) unsubscribe_stores($$store_subs);
	});
}
//#endregion
export { _layout as default };
