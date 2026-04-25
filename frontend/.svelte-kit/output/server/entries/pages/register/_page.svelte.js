import { h as head, a as attr, e as escape_html } from "../../../chunks/renderer.js";
import "../../../chunks/url.js";
import "@sveltejs/kit/internal/server";
import "../../../chunks/root.js";
function _page($$renderer, $$props) {
  $$renderer.component(($$renderer2) => {
    let username = "";
    let password = "";
    let msisdn = "";
    let loading = false;
    head("52fghe", $$renderer2, ($$renderer3) => {
      $$renderer3.title(($$renderer4) => {
        $$renderer4.push(`<title>Register — FMRZ</title>`);
      });
    });
    $$renderer2.push(`<div class="register-page svelte-52fghe"><div class="register-card card-glass animate-fade svelte-52fghe"><div class="register-header svelte-52fghe"><img src="/eand_logo.svg" alt="e&amp;" class="register-logo svelte-52fghe"/> <h1 class="svelte-52fghe">Join e&amp; Billing</h1> <p class="svelte-52fghe">Enter your phone number to create an account</p></div> `);
    {
      $$renderer2.push("<!--[-1-->");
    }
    $$renderer2.push(`<!--]--> <form><div class="form-group"><label class="label" for="msisdn">Phone Number (MSISDN)</label> <input id="msisdn" class="input" type="text"${attr("value", msisdn)} placeholder="201000000000" required=""/></div> <div class="form-group"><label class="label" for="reg-username">Username</label> <input id="reg-username" class="input" type="text"${attr("value", username)} placeholder="choose a username" required=""/></div> <div class="form-group"><label class="label" for="reg-password">Password</label> <input id="reg-password" class="input" type="password"${attr("value", password)} placeholder="Min 6 characters" required="" minlength="6"/></div> <button type="submit" class="btn btn-primary" style="width: 100%;"${attr("disabled", loading, true)}>${escape_html("Create Account")}</button></form> <p class="register-footer svelte-52fghe">Already have an account? <a href="/login" class="link-red svelte-52fghe">Sign In</a></p></div></div>`);
  });
}
export {
  _page as default
};
