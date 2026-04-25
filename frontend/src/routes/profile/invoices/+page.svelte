<script>
  import { base } from '$app/paths';
  import { onMount } from 'svelte';
  
  let invoices = $state([]);
  let loading = $state(true);

  async function loadInvoices() {
    try {
      const res = await fetch('/api/customer/invoices', { credentials: 'include' });
      if (res.ok) {
        invoices = await res.json();
      }
    } catch {}
    loading = false;
  }

  function downloadPdf(id) {
    window.location.href = `/api/customer/invoices/download?id=${id}`;
  }

  onMount(loadInvoices);
</script>

<svelte:head><title>My Invoices — FMRZ</title></svelte:head>

<div class="container animate-fade">
  <div class="page-header">
    <a href="/profile" class="back-link">← Back to Profile</a>
    <h1>My <span class="text-gradient">Invoices</span></h1>
  </div>

  {#if loading}
    <div class="loading">Loading your billing history...</div>
  {:else if invoices.length === 0}
    <div class="card empty-state">
      <div class="empty-icon">📂</div>
      <h3>No invoices yet</h3>
      <p>Your billing history will appear here once your first bill is generated.</p>
    </div>
  {:else}
    <div class="table-wrapper card">
      <table>
        <thead>
          <tr>
            <th>Invoice ID</th>
            <th>Billing Date</th>
            <th>Phone Number</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {#each invoices as inv}
            <tr>
              <td>#{inv.id}</td>
              <td>{new Date(inv.generationDate).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })}</td>
              <td style="font-weight: 600;">{inv.msisdn}</td>
              <td>
                <button onclick={() => downloadPdf(inv.id)} class="btn btn-secondary btn-sm">
                  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="margin-right: 6px;"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
                  Download PDF
                </button>
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}
</div>

<style>
  .back-link { display: block; margin-bottom: 1rem; color: var(--text-muted); font-size: 0.9rem; text-decoration: none; }
  .back-link:hover { color: var(--red); }
  .text-gradient { background: linear-gradient(135deg, var(--red), var(--red-light)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
  
  .empty-state { text-align: center; padding: 5rem 2rem; }
  .empty-icon { font-size: 3rem; margin-bottom: 1rem; opacity: 0.5; }
  .empty-state h3 { font-size: 1.25rem; margin-bottom: 0.5rem; }
  .empty-state p { color: var(--text-muted); }

  .loading { text-align: center; padding: 4rem; color: var(--text-muted); }

  .btn-sm { padding: 0.4rem 0.8rem; font-size: 0.8rem; display: inline-flex; align-items: center; }
  
  table td { padding: 1rem; }
</style>
