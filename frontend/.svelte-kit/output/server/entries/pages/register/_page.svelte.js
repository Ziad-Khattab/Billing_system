import { h as head, a as attr, e as escape_html } from "../../../chunks/renderer.js";
function _page($$renderer, $$props) {
  $$renderer.component(($$renderer2) => {
    let username = "";
    let password = "";
    let name = "";
    let email = "";
    let address = "";
    let birthdate = "";
    let loading = false;
    head("52fghe", $$renderer2, ($$renderer3) => {
      $$renderer3.title(($$renderer4) => {
        $$renderer4.push(`<title>Register — FMRZ</title>`);
      });
    });
    $$renderer2.push(`<div class="register-page svelte-52fghe"><div class="register-card card-glass animate-fade svelte-52fghe"><div class="register-header svelte-52fghe"><img src="/eand_logo.svg" alt="e&amp;" class="register-logo svelte-52fghe"/> <h1 class="svelte-52fghe">Join e&amp; Billing</h1> <p class="svelte-52fghe">Create your account to get started</p></div> `);
    {
      $$renderer2.push("<!--[-1-->");
    }
    $$renderer2.push(`<!--]--> <form><div class="form-group svelte-52fghe"><label class="label" for="reg-name">Full Name</label> <input id="reg-name" class="input" type="text"${attr("value", name)} placeholder="Alice Smith" required=""/></div> <div class="form-group svelte-52fghe"><label class="label" for="reg-username">Username</label> <input id="reg-username" class="input" type="text"${attr("value", username)} placeholder="Choose a username" required=""/></div> <div class="form-group svelte-52fghe"><label class="label" for="reg-email">Email</label> <input id="reg-email" class="input" type="email"${attr("value", email)} placeholder="alice@example.com" required=""/></div> <div class="form-group svelte-52fghe"><label class="label" for="reg-password">Password</label> <input id="reg-password" class="input" type="password"${attr("value", password)} placeholder="Min 6 characters" required="" minlength="6"/></div> <div class="form-group svelte-52fghe"><label class="label" for="reg-address">Address</label> <input id="reg-address" class="input" type="text"${attr("value", address)} placeholder="123 Main St"/></div> <div class="form-group svelte-52fghe"><label class="label" for="reg-birthdate">Date of Birth</label> <input id="reg-birthdate" class="input" type="date"${attr("value", birthdate)}/></div> <button type="submit" class="btn btn-primary" style="width: 100%; margin-top: 0.5rem;"${attr("disabled", loading, true)}>${escape_html("Create Account")}</button></form> <p class="register-footer svelte-52fghe">Already have an account? <a href="/login" class="link-red svelte-52fghe">Sign In</a></p></div></div>`);
  });
}
export {
  _page as default
};
