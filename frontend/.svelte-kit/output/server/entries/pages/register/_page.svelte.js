import { B as attr, V as escape_html, o as head } from "../../../chunks/dev.js";
//#region src/routes/register/+page.svelte
function _page($$renderer) {
	let fullName = "";
	let username = "";
	let password = "";
	let address = "";
	let loading = false;
	head("52fghe", $$renderer, ($$renderer) => {
		$$renderer.title(($$renderer) => {
			$$renderer.push(`<title>Register — FMRZ</title>`);
		});
	});
	$$renderer.push(`<div class="register-page svelte-52fghe"><div class="register-card card-glass animate-fade svelte-52fghe"><div class="register-header svelte-52fghe"><img src="/logo.png" alt="FMRZ" class="register-logo svelte-52fghe"/> <h1 class="svelte-52fghe">Create Account</h1> <p class="svelte-52fghe">Join FMRZ and manage your telecom services</p></div> `);
	$$renderer.push("<!--[-1-->");
	$$renderer.push(`<!--]--> <form><div class="form-group"><label class="label" for="fullName">Full Name</label> <input id="fullName" class="input" type="text"${attr("value", fullName)} placeholder="Ahmed Ali" required=""/></div> <div class="form-group"><label class="label" for="reg-username">Username</label> <input id="reg-username" class="input" type="text"${attr("value", username)} placeholder="ahmed.ali" required=""/></div> <div class="form-group"><label class="label" for="reg-password">Password</label> <input id="reg-password" class="input" type="password"${attr("value", password)} placeholder="Min 6 characters" required="" minlength="6"/></div> <div class="form-group"><label class="label" for="address">Address</label> <input id="address" class="input" type="text"${attr("value", address)} placeholder="Cairo, Egypt"/></div> <button type="submit" class="btn btn-primary" style="width: 100%;"${attr("disabled", loading, true)}>${escape_html("Create Account")}</button></form> <p class="register-footer svelte-52fghe">Already have an account? <a href="/login" class="link-red svelte-52fghe">Sign In</a></p></div></div>`);
}
//#endregion
export { _page as default };
