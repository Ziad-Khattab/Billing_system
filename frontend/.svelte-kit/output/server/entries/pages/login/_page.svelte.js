import { B as attr, V as escape_html, o as head } from "../../../chunks/dev.js";
//#region src/routes/login/+page.svelte
function _page($$renderer) {
	let username = "";
	let password = "";
	let loading = false;
	head("1x05zx6", $$renderer, ($$renderer) => {
		$$renderer.title(($$renderer) => {
			$$renderer.push(`<title>Login — FMRZ</title>`);
		});
	});
	$$renderer.push(`<div class="login-page svelte-1x05zx6"><div class="login-card card-glass animate-fade svelte-1x05zx6"><div class="login-header svelte-1x05zx6"><img src="/logo.png" alt="FMRZ" class="login-logo svelte-1x05zx6"/> <h1 class="svelte-1x05zx6">Welcome back</h1> <p class="svelte-1x05zx6">Sign in to your account</p></div> `);
	$$renderer.push("<!--[-1-->");
	$$renderer.push(`<!--]--> <form><div class="form-group"><label class="label" for="username">Username</label> <input id="username" class="input" type="text"${attr("value", username)} placeholder="Enter username" required=""/></div> <div class="form-group"><label class="label" for="password">Password</label> <input id="password" class="input" type="password"${attr("value", password)} placeholder="Enter password" required=""/></div> <button type="submit" class="btn btn-primary" style="width: 100%;"${attr("disabled", loading, true)}>${escape_html("Sign In")}</button></form> <p class="login-footer svelte-1x05zx6">Don't have an account? <a href="/register" class="link-red svelte-1x05zx6">Register</a></p></div></div>`);
}
//#endregion
export { _page as default };
