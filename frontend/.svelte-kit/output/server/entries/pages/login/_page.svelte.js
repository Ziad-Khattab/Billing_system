import { h as head, a as attr, e as escape_html } from "../../../chunks/renderer.js";
import "../../../chunks/url.js";
import "@sveltejs/kit/internal/server";
import "../../../chunks/root.js";
function _page($$renderer, $$props) {
  $$renderer.component(($$renderer2) => {
    let username = "";
    let password = "";
    let loading = false;
    head("1x05zx6", $$renderer2, ($$renderer3) => {
      $$renderer3.title(($$renderer4) => {
        $$renderer4.push(`<title>Login — FMRZ</title>`);
      });
    });
    $$renderer2.push(`<div class="login-page svelte-1x05zx6"><div class="login-card card-glass animate-fade svelte-1x05zx6"><div class="login-header svelte-1x05zx6"><img src="/eand_logo.svg" alt="e&amp;" class="login-logo svelte-1x05zx6"/> <h1 class="svelte-1x05zx6">Welcome back</h1> <p class="svelte-1x05zx6">Sign in to your account</p></div> `);
    {
      $$renderer2.push("<!--[-1-->");
    }
    $$renderer2.push(`<!--]--> <form><div class="form-group"><label class="label" for="username">Username</label> <input id="username" class="input" type="text"${attr("value", username)} placeholder="Enter username" required=""/></div> <div class="form-group"><label class="label" for="password">Password</label> <input id="password" class="input" type="password"${attr("value", password)} placeholder="Enter password" required=""/></div> <button type="submit" class="btn btn-primary" style="width: 100%;"${attr("disabled", loading, true)}>${escape_html("Sign In")}</button></form> <p class="login-footer svelte-1x05zx6">Don't have an account? <a href="/register" class="link-red svelte-1x05zx6">Register</a></p></div></div>`);
  });
}
export {
  _page as default
};
