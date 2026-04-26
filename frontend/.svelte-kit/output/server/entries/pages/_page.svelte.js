import { h as head, d as ensure_array_like, b as attr_class, f as attr_style, e as escape_html, i as stringify } from "../../chunks/renderer.js";
function html(value) {
  var html2 = String(value ?? "");
  var open = "<!---->";
  return open + html2 + "<!---->";
}
function _page($$renderer, $$props) {
  $$renderer.component(($$renderer2) => {
    let currentSlide = 0;
    const features = [
      {
        icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect width="16" height="20" x="4" y="2" rx="2" ry="2"/><line x1="12" x2="12.01" y1="18" y2="18"/><line x1="8" x2="16" y1="6" y2="6"/><line x1="8" x2="16" y1="10" y2="10"/><line x1="8" x2="16" y1="14" y2="14"/></svg>`,
        title: "Smart Billing",
        desc: "Automated CDR processing and real-time billing calculations"
      },
      {
        icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><line x1="12" x2="12" y1="20" y2="10"/><line x1="18" x2="18" y1="20" y2="4"/><line x1="6" x2="6" y1="20" y2="16"/></svg>`,
        title: "Rate Plans",
        desc: "Flexible voice, data, and SMS rate configurations"
      },
      {
        icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/><line x1="16" x2="8" y1="13" y2="13"/><line x1="16" x2="8" y1="17" y2="17"/><line x1="10" x2="8" y1="9" y2="9"/></svg>`,
        title: "PDF Invoices",
        desc: "Professional invoices generated instantly"
      },
      {
        icon: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/></svg>`,
        title: "Secure Access",
        desc: "Role-based authentication for admins and customers"
      }
    ];
    head("1uha8ag", $$renderer2, ($$renderer3) => {
      $$renderer3.title(($$renderer4) => {
        $$renderer4.push(`<title>FMRZ — Telecom Billing System</title>`);
      });
      $$renderer3.push(`<meta name="description" content="FMRZ Telecom Billing Operations Platform — Manage customers, rate plans, contracts, and invoices."/>`);
    });
    $$renderer2.push(`<section class="hero svelte-1uha8ag"><div class="container hero-content svelte-1uha8ag"><div class="hero-text animate-fade svelte-1uha8ag"><span class="hero-badge svelte-1uha8ag">Telecom Billing Platform</span> <h1 class="svelte-1uha8ag">Powering Your<br/><span class="text-gradient svelte-1uha8ag">Telecom Operations</span></h1> <p class="hero-desc svelte-1uha8ag">Complete billing management system for telecom operators.
        Customer management, CDR processing, automated billing, and invoice generation.</p> <div class="hero-actions svelte-1uha8ag"><a href="packages" class="btn btn-primary btn-lg svelte-1uha8ag">View Packages</a> `);
    {
      $$renderer2.push("<!--[-1-->");
      $$renderer2.push(`<a href="register" class="btn btn-secondary btn-lg svelte-1uha8ag">Get Started</a>`);
    }
    $$renderer2.push(`<!--]--></div></div> <div class="hero-visual animate-fade svelte-1uha8ag" style="animation-delay: 0.2s;"><div class="hero-card-stack svelte-1uha8ag"><!--[-->`);
    const each_array = ensure_array_like([0, 1, 2]);
    for (let $$index = 0, $$length = each_array.length; $$index < $$length; $$index++) {
      let i = each_array[$$index];
      $$renderer2.push(`<div${attr_class("hero-card card svelte-1uha8ag", void 0, { "active": currentSlide === i })}${attr_style(`--offset: ${stringify((i - currentSlide + 3) % 3)}`)}><div class="hero-card-header svelte-1uha8ag"><div class="hero-avatar svelte-1uha8ag">`);
      if (i === 0) {
        $$renderer2.push("<!--[0-->");
        $$renderer2.push(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:20px;height:20px;"><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"></path><circle cx="12" cy="7" r="4"></circle></svg>`);
      } else if (i === 1) {
        $$renderer2.push("<!--[1-->");
        $$renderer2.push(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:20px;height:20px;"><rect width="20" height="14" x="2" y="7" rx="2" ry="2"></rect><path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"></path></svg>`);
      } else {
        $$renderer2.push("<!--[-1-->");
        $$renderer2.push(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="width:20px;height:20px;"><path d="M6 4h12l4 6-10 11L2 10Z"></path><path d="M2 10h20"></path><path d="M6 4l6 6 6-6"></path><path d="M8 10l4 11"></path><path d="M16 10l-4 11"></path></svg>`);
      }
      $$renderer2.push(`<!--]--></div> <div class="hero-header-lines svelte-1uha8ag"><div class="hero-card-line svelte-1uha8ag"></div> <div class="hero-card-line short svelte-1uha8ag"></div></div></div> <div class="hero-card-dots svelte-1uha8ag"><span${attr_class("dot svelte-1uha8ag", void 0, { "red": i === 0 })}></span> <span${attr_class("dot svelte-1uha8ag", void 0, { "red": i === 1 })}></span> <span${attr_class("dot svelte-1uha8ag", void 0, { "red": i === 2 })}></span></div></div>`);
    }
    $$renderer2.push(`<!--]--></div></div></div></section> <section class="features container svelte-1uha8ag"><h2 class="section-title svelte-1uha8ag">Built for <span class="text-gradient svelte-1uha8ag">Performance</span></h2> <div class="grid-4"><!--[-->`);
    const each_array_1 = ensure_array_like(features);
    for (let i = 0, $$length = each_array_1.length; i < $$length; i++) {
      let feature = each_array_1[i];
      $$renderer2.push(`<div class="card feature-card animate-fade svelte-1uha8ag"${attr_style(`animation-delay: ${stringify(i * 0.1)}s`)}><span class="feature-icon svelte-1uha8ag">${html(feature.icon)}</span> <h3 class="svelte-1uha8ag">${escape_html(feature.title)}</h3> <p class="svelte-1uha8ag">${escape_html(feature.desc)}</p></div>`);
    }
    $$renderer2.push(`<!--]--></div></section> <section class="cta-section svelte-1uha8ag"><div class="container"><div class="cta-card card-glass svelte-1uha8ag"><h2 class="svelte-1uha8ag">Ready to get started?</h2> <p class="svelte-1uha8ag">Browse our packages or register for your own billing dashboard.</p> <div class="cta-actions svelte-1uha8ag"><a href="packages" class="btn btn-primary">Browse Packages</a> `);
    {
      $$renderer2.push("<!--[-1-->");
      $$renderer2.push(`<a href="login" class="btn btn-secondary">Login</a>`);
    }
    $$renderer2.push(`<!--]--></div></div></div></section>`);
  });
}
export {
  _page as default
};
