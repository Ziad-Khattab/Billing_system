import { g as getContext, a as attr, b as attr_class, s as store_get, u as unsubscribe_stores } from "../../chunks/renderer.js";
import "clsx";
import "@sveltejs/kit/internal";
import "../../chunks/url.js";
import "../../chunks/utils.js";
import "@sveltejs/kit/internal/server";
import "../../chunks/root.js";
import "../../chunks/exports.js";
import "../../chunks/state.svelte.js";
const getStores = () => {
  const stores$1 = getContext("__svelte__");
  return {
    /** @type {typeof page} */
    page: {
      subscribe: stores$1.page.subscribe
    },
    /** @type {typeof navigating} */
    navigating: {
      subscribe: stores$1.navigating.subscribe
    },
    /** @type {typeof updated} */
    updated: stores$1.updated
  };
};
const page = {
  subscribe(fn) {
    const store = getStores().page;
    return store.subscribe(fn);
  }
};
function _layout($$renderer, $$props) {
  $$renderer.component(($$renderer2) => {
    var $$store_subs;
    let { children } = $$props;
    let navOpen = false;
    $$renderer2.push(`<div class="app"><nav class="navbar svelte-12qhfyh"><div class="nav-inner container svelte-12qhfyh"><a href="/" class="nav-brand svelte-12qhfyh" aria-label="Home"><img src="/eand_logo.svg" alt="e&amp;" class="nav-logo svelte-12qhfyh" style="height: 40px;"/></a> <button class="nav-toggle svelte-12qhfyh"${attr("aria-label", "Open navigation")}${attr("aria-expanded", navOpen)}><span class="svelte-12qhfyh"></span><span class="svelte-12qhfyh"></span><span class="svelte-12qhfyh"></span></button> <div${attr_class("nav-links svelte-12qhfyh", void 0, { "open": navOpen })}><a href="/"${attr_class("nav-link svelte-12qhfyh", void 0, {
      "active": store_get($$store_subs ??= {}, "$page", page).url.pathname === "/"
    })}>Home</a> <a href="/packages"${attr_class("nav-link svelte-12qhfyh", void 0, {
      "active": store_get($$store_subs ??= {}, "$page", page).url.pathname.startsWith("/packages")
    })}>Packages</a> `);
    {
      $$renderer2.push("<!--[-1-->");
    }
    $$renderer2.push(`<!--]--> <div class="nav-spacer svelte-12qhfyh"></div> `);
    {
      $$renderer2.push("<!--[-1-->");
      $$renderer2.push(`<a href="/login" class="btn btn-ghost">Login</a> <a href="/register" class="btn btn-primary">Register</a>`);
    }
    $$renderer2.push(`<!--]--></div></div></nav> <main class="main-content svelte-12qhfyh">`);
    children($$renderer2);
    $$renderer2.push(`<!----></main> <footer class="footer svelte-12qhfyh"><div class="container"><p>© 2026 FMRZ Telecom Billing — ITI Project</p></div></footer></div>`);
    if ($$store_subs) unsubscribe_stores($$store_subs);
  });
}
export {
  _layout as default
};
