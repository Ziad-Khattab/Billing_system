import { h as head, e as escape_html } from "../../../chunks/renderer.js";
import "@sveltejs/kit/internal";
import "../../../chunks/exports.js";
import "../../../chunks/utils.js";
import "@sveltejs/kit/internal/server";
import "../../../chunks/root.js";
import "../../../chunks/state.svelte.js";
function _page($$renderer, $$props) {
  $$renderer.component(($$renderer2) => {
    let stats = { customers: 0, contracts: 0, invoices: 0 };
    head("1jef3w8", $$renderer2, ($$renderer3) => {
      $$renderer3.title(($$renderer4) => {
        $$renderer4.push(`<title>Admin Dashboard — FMRZ</title>`);
      });
    });
    $$renderer2.push(`<div class="container svelte-1jef3w8"><div class="page-header svelte-1jef3w8"><h1 class="svelte-1jef3w8">Admin <span class="text-gradient svelte-1jef3w8">Dashboard</span></h1></div> <div class="grid-4 svelte-1jef3w8"><div class="stat-card animate-fade svelte-1jef3w8"><span class="stat-label svelte-1jef3w8">Customers</span> <span class="stat-value svelte-1jef3w8">${escape_html(stats.customers)}</span></div> <div class="stat-card animate-fade svelte-1jef3w8" style="animation-delay: 0.1s"><span class="stat-label svelte-1jef3w8">Contracts</span> <span class="stat-value svelte-1jef3w8">${escape_html(stats.contracts)}</span></div> <div class="stat-card animate-fade svelte-1jef3w8" style="animation-delay: 0.2s"><span class="stat-label svelte-1jef3w8">Invoices</span> <span class="stat-value svelte-1jef3w8">${escape_html(stats.invoices)}</span></div> <div class="stat-card animate-fade svelte-1jef3w8" style="animation-delay: 0.3s"><span class="stat-label svelte-1jef3w8">System Status</span> <div class="status-indicator svelte-1jef3w8"><span class="status-dot svelte-1jef3w8"></span> <span class="status-text svelte-1jef3w8">Online</span></div></div></div> <div class="quick-actions svelte-1jef3w8"><h2 class="svelte-1jef3w8">Quick Actions</h2> <div class="grid-3 svelte-1jef3w8"><a href="/admin/customers" class="action-card card svelte-1jef3w8"><div class="action-icon svelte-1jef3w8"><svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="svelte-1jef3w8"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" class="svelte-1jef3w8"></path><circle cx="9" cy="7" r="4" class="svelte-1jef3w8"></circle><path d="M22 21v-2a4 4 0 0 0-3-3.87" class="svelte-1jef3w8"></path><path d="M16 3.13a4 4 0 0 1 0 7.75" class="svelte-1jef3w8"></path></svg></div> <h3 class="svelte-1jef3w8">Manage Customers</h3> <p class="svelte-1jef3w8">Add, search, and edit customer profiles</p></a> <a href="/admin/contracts" class="action-card card svelte-1jef3w8"><div class="action-icon svelte-1jef3w8"><svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="svelte-1jef3w8"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z" class="svelte-1jef3w8"></path><path d="M14 2v4a2 2 0 0 0 2 2h4" class="svelte-1jef3w8"></path><path d="M10 9H8" class="svelte-1jef3w8"></path><path d="M16 13H8" class="svelte-1jef3w8"></path><path d="M16 17H8" class="svelte-1jef3w8"></path></svg></div> <h3 class="svelte-1jef3w8">Contracts</h3> <p class="svelte-1jef3w8">View and manage service contracts</p></a> <a href="/admin/billing" class="action-card card svelte-1jef3w8"><div class="action-icon svelte-1jef3w8"><svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="svelte-1jef3w8"><line x1="12" y1="1" x2="12" y2="23" class="svelte-1jef3w8"></line><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6" class="svelte-1jef3w8"></path></svg></div> <h3 class="svelte-1jef3w8">Billing &amp; Invoices</h3> <p class="svelte-1jef3w8">Generate bills and download invoices</p></a></div></div></div>`);
  });
}
export {
  _page as default
};
