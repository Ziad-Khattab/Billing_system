<script>
  import { base } from '$app/paths';
  import { onMount } from 'svelte';
  import { fade, fly } from 'svelte/transition';
  
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

<div class="container" in:fade>
  <div class="page-header">
    <a href="/profile" class="back-link">
      <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="margin-right: 6px; vertical-align: middle;"><path d="m15 18-6-6 6-6"/></svg>
      Back to Profile
    </a>
    <h1>My <span class="text-gradient">Invoices</span></h1>
    <p class="subtitle">View and download your monthly billing statements</p>
  </div>

  {#if loading}
    <div class="loading-container">
      <div class="loading-spinner"></div>
      <p>Fetching your billing history...</p>
    </div>
  {:else if invoices.length === 0}
    <div class="card empty-state" in:fly={{ y: 20 }}>
      <div class="empty-icon-wrapper">
        <svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--text-muted)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14.5 2 14.5 7.5 20 7.5"/></svg>
      </div>
      <h3>No invoices yet</h3>
      <p>Your billing history will appear here once your first cycle completes.</p>
    </div>
  {:else}
    <div class="table-container card card-static static-table" in:fly={{ y: 30 }}>
      <table class="premium-table">
        <thead>
          <tr>
            <th>Invoice ID</th>
            <th>Billing Date</th>
            <th>Phone Number</th>
            <th class="text-right">Actions</th>
          </tr>
        </thead>
        <tbody>
          {#each invoices as inv, i}
            <tr style="--delay: {i * 0.05}s">
              <td>
                <span class="id-badge">#{inv.id}</span>
              </td>
              <td class="date-cell">
                {new Date(inv.generationDate).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })}
              </td>
              <td>
                <div class="msisdn-pill">{inv.msisdn}</div>
              </td>
              <td class="text-right">
                <button onclick={() => downloadPdf(inv.id)} class="btn-download">
                  <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
                  <span>Download PDF</span>
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
  .page-header { margin-bottom: 3rem; }
  .subtitle { color: var(--text-secondary); margin-top: 0.5rem; }
  
  .back-link { 
    display: inline-flex; align-items: center; margin-bottom: 1.5rem; 
    color: var(--text-muted); font-size: 0.95rem; font-weight: 500;
    text-decoration: none; transition: color 0.2s;
  }
  .back-link:hover { color: var(--red); }
  
  .text-gradient { 
    background: linear-gradient(135deg, var(--red), var(--red-light)); 
    -webkit-background-clip: text; -webkit-text-fill-color: transparent; 
    background-clip: text; 
  }

  /* Premium Static Table */
  .table-container { 
    padding: 0; overflow: hidden; 
    background: rgba(15, 15, 25, 0.4); 
    border: 1px solid rgba(255, 255, 255, 0.05);
    backdrop-filter: blur(20px);
  }
  
  .premium-table { width: 100%; border-collapse: collapse; text-align: left; }
  
  .premium-table thead tr { 
    background: rgba(224, 8, 0, 0.05); 
    border-bottom: 1px solid rgba(224, 8, 0, 0.2); 
  }
  
  .premium-table th { 
    padding: 1.25rem 2rem; color: var(--red-light); 
    font-size: 0.85rem; font-weight: 800; text-transform: uppercase; letter-spacing: 0.05em; 
  }
  
  .premium-table td { padding: 1.5rem 2rem; border-bottom: 1px solid rgba(255, 255, 255, 0.03); color: white; vertical-align: middle; }
  
  /* Disable Hover Scaling & Lighting - Force Static Box */
  .card-static, .static-table { 
    transform: none !important; 
    transition: none !important; 
    filter: none !important;
  }
  
  .static-table tr { 
    transition: none !important; 
    transform: none !important; 
  }
  
  .static-table tr:hover { 
    background: rgba(255, 255, 255, 0.02) !important; 
    filter: none !important; 
    transform: none !important;
  }

  .id-badge { 
    background: rgba(255, 255, 255, 0.05); padding: 4px 12px; border-radius: 6px;
    font-family: 'JetBrains Mono', monospace; font-weight: 700; color: #94a3b8;
  }
  
  .date-cell { font-weight: 600; color: #e2e8f0; }
  
  .msisdn-pill {
    display: inline-block; padding: 6px 14px; border-radius: 100px;
    background: rgba(224, 8, 0, 0.1); border: 1px solid rgba(224, 8, 0, 0.2);
    color: var(--red-light); font-weight: 800; font-size: 0.95rem;
  }

  .text-right { text-align: right; }

  .btn-download {
    background: rgba(255, 255, 255, 0.05); border: 1px solid rgba(255, 255, 255, 0.1);
    color: white; padding: 10px 20px; border-radius: 12px; cursor: pointer;
    display: inline-flex; align-items: center; gap: 10px; font-weight: 700; font-size: 0.9rem;
    transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  }
  
  .btn-download:hover { 
    background: var(--red); border-color: var(--red); 
    transform: translateY(-2px); box-shadow: 0 10px 20px rgba(224, 8, 0, 0.3);
  }

  /* Empty State */
  .empty-state { text-align: center; padding: 6rem 2rem; background: rgba(15, 15, 25, 0.3); }
  .empty-icon-wrapper { margin-bottom: 1.5rem; opacity: 0.4; }
  .empty-state h3 { font-size: 1.5rem; font-weight: 800; margin-bottom: 0.75rem; }
  .empty-state p { color: var(--text-muted); font-size: 1.1rem; }

  .loading-container { text-align: center; padding: 8rem 0; color: var(--text-secondary); }
  .loading-spinner { 
    width: 40px; height: 40px; border: 3px solid rgba(224, 8, 0, 0.1); 
    border-top-color: var(--red); border-radius: 50%; margin: 0 auto 1.5rem;
    animation: spin 1s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
</style>
