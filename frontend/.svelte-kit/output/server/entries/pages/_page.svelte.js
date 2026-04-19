import { V as escape_html, a as ensure_array_like, l as stringify, n as attr_class, o as head, r as attr_style } from "../../chunks/dev.js";
//#region src/routes/+page.svelte
function _page($$renderer, $$props) {
	$$renderer.component(($$renderer) => {
		let currentSlide = 0;
		const features = [
			{
				icon: "📱",
				title: "Smart Billing",
				desc: "Automated CDR processing and real-time billing calculations"
			},
			{
				icon: "📊",
				title: "Rate Plans",
				desc: "Flexible voice, data, and SMS rate configurations"
			},
			{
				icon: "📄",
				title: "PDF Invoices",
				desc: "Professional invoices generated instantly"
			},
			{
				icon: "🔒",
				title: "Secure Access",
				desc: "Role-based authentication for admins and customers"
			}
		];
		head("1uha8ag", $$renderer, ($$renderer) => {
			$$renderer.title(($$renderer) => {
				$$renderer.push(`<title>FMRZ — Telecom Billing System</title>`);
			});
			$$renderer.push(`<meta name="description" content="FMRZ Telecom Billing Operations Platform — Manage customers, rate plans, contracts, and invoices."/>`);
		});
		$$renderer.push(`<section class="hero svelte-1uha8ag"><div class="hero-bg svelte-1uha8ag"><div class="hero-glow svelte-1uha8ag"></div> <div class="hero-grid svelte-1uha8ag"></div></div> <div class="container hero-content svelte-1uha8ag"><div class="hero-text animate-fade svelte-1uha8ag"><span class="hero-badge svelte-1uha8ag">Telecom Billing Platform</span> <h1 class="svelte-1uha8ag">Powering Your<br/><span class="text-gradient svelte-1uha8ag">Telecom Operations</span></h1> <p class="hero-desc svelte-1uha8ag">Complete billing management system for telecom operators.
        Customer management, CDR processing, automated billing, and invoice generation.</p> <div class="hero-actions svelte-1uha8ag"><a href="/packages" class="btn btn-primary btn-lg svelte-1uha8ag">View Packages</a> <a href="/register" class="btn btn-secondary btn-lg svelte-1uha8ag">Get Started</a></div></div> <div class="hero-visual animate-fade svelte-1uha8ag" style="animation-delay: 0.2s;"><div class="hero-card-stack svelte-1uha8ag"><!--[-->`);
		const each_array = ensure_array_like([
			0,
			1,
			2
		]);
		for (let $$index = 0, $$length = each_array.length; $$index < $$length; $$index++) {
			let i = each_array[$$index];
			$$renderer.push(`<div${attr_class("hero-card svelte-1uha8ag", void 0, { "active": currentSlide === i })}${attr_style(`--offset: ${stringify(i)}`)}><div class="hero-card-line svelte-1uha8ag"></div> <div class="hero-card-line short svelte-1uha8ag"></div> <div class="hero-card-dots svelte-1uha8ag"><span class="dot red svelte-1uha8ag"></span> <span class="dot svelte-1uha8ag"></span> <span class="dot svelte-1uha8ag"></span></div></div>`);
		}
		$$renderer.push(`<!--]--></div></div></div></section> <section class="features container svelte-1uha8ag"><h2 class="section-title svelte-1uha8ag">Built for <span class="text-gradient svelte-1uha8ag">Performance</span></h2> <div class="grid-4"><!--[-->`);
		const each_array_1 = ensure_array_like(features);
		for (let i = 0, $$length = each_array_1.length; i < $$length; i++) {
			let feature = each_array_1[i];
			$$renderer.push(`<div class="card feature-card animate-fade svelte-1uha8ag"${attr_style(`animation-delay: ${stringify(i * .1)}s`)}><span class="feature-icon svelte-1uha8ag">${escape_html(feature.icon)}</span> <h3 class="svelte-1uha8ag">${escape_html(feature.title)}</h3> <p class="svelte-1uha8ag">${escape_html(feature.desc)}</p></div>`);
		}
		$$renderer.push(`<!--]--></div></section> <section class="cta-section svelte-1uha8ag"><div class="container"><div class="cta-card card-glass svelte-1uha8ag"><h2 class="svelte-1uha8ag">Ready to get started?</h2> <p class="svelte-1uha8ag">Browse our packages or register for your own billing dashboard.</p> <div class="cta-actions svelte-1uha8ag"><a href="/packages" class="btn btn-primary">Browse Packages</a> <a href="/login" class="btn btn-secondary">Admin Login</a></div></div></div></section>`);
	});
}
//#endregion
export { _page as default };
