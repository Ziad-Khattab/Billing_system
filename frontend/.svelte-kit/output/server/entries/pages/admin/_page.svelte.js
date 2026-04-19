import { V as escape_html, o as head } from "../../../chunks/dev.js";
//#region src/routes/admin/+page.svelte
function _page($$renderer, $$props) {
	$$renderer.component(($$renderer) => {
		let stats = {
			customers: 0,
			contracts: 0,
			invoices: 0
		};
		head("1jef3w8", $$renderer, ($$renderer) => {
			$$renderer.title(($$renderer) => {
				$$renderer.push(`<title>Admin Dashboard — FMRZ</title>`);
			});
		});
		$$renderer.push(`<div class="container"><div class="page-header"><h1>Admin <span class="text-gradient svelte-1jef3w8">Dashboard</span></h1></div> <div class="grid-4"><div class="stat-card animate-fade"><span class="stat-label">Customers</span> <span class="stat-value">${escape_html(stats.customers)}</span></div> <div class="stat-card animate-fade" style="animation-delay: 0.1s"><span class="stat-label">Contracts</span> <span class="stat-value">${escape_html(stats.contracts)}</span></div> <div class="stat-card animate-fade" style="animation-delay: 0.2s"><span class="stat-label">Invoices</span> <span class="stat-value">${escape_html(stats.invoices)}</span></div> <div class="stat-card animate-fade" style="animation-delay: 0.3s"><span class="stat-label">System Status</span> <span class="stat-value" style="font-size: 1.5rem;">🟢 Online</span></div></div> <div class="quick-actions svelte-1jef3w8"><h2 class="svelte-1jef3w8">Quick Actions</h2> <div class="grid-3"><a href="/admin/customers" class="action-card card svelte-1jef3w8"><span class="action-icon svelte-1jef3w8">👥</span> <h3 class="svelte-1jef3w8">Manage Customers</h3> <p class="svelte-1jef3w8">Add, search, and edit customer profiles</p></a> <a href="/admin/contracts" class="action-card card svelte-1jef3w8"><span class="action-icon svelte-1jef3w8">📋</span> <h3 class="svelte-1jef3w8">Contracts</h3> <p class="svelte-1jef3w8">View and manage service contracts</p></a> <a href="/admin/billing" class="action-card card svelte-1jef3w8"><span class="action-icon svelte-1jef3w8">💰</span> <h3 class="svelte-1jef3w8">Billing &amp; Invoices</h3> <p class="svelte-1jef3w8">Generate bills and download invoices</p></a></div></div></div>`);
	});
}
//#endregion
export { _page as default };
