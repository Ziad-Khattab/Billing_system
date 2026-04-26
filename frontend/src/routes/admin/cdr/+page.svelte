<script>
  let cdrs = $state([]);
  let search = $state('');
  let loading = $state(true);
  let importing = $state(false);
  let page = $state(0);
  const limit = 50;

  async function loadCDRs() {
    loading = true;
    try {
      const offset = page * limit;
      const res = await fetch(`/api/admin/cdr?limit=${limit}&offset=${offset}`, { credentials: 'include' });
      if (res.ok) cdrs = await res.json();
    } catch (e) {
      console.error(e);
    } finally {
      loading = false;
    }
  }

  function nextPage() { page++; loadCDRs(); }
  function prevPage() { if (page > 0) { page--; loadCDRs(); } }

  async function importCDRs() {
    importing = true;
    try {
      const res = await fetch('/api/admin/cdr', { method: 'POST', credentials: 'include' });
      if (res.ok) {
        page = 0; 
        await loadCDRs();
      }
    } catch (e) {
      console.error(e);
    } finally {
      importing = false;
    }
  }

  let filteredCDRs = $derived(
    search ? cdrs.filter(c => c.msisdn.includes(search) || c.destination.includes(search)) : cdrs
  );

  function formatDuration(s) {
    if (!s) return '0s';
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const rs = s % 60;
    return (h > 0 ? h + 'h ' : '') + (m > 0 ? m + 'm ' : '') + (rs + 's');
  }

  $effect(() => { loadCDRs(); });
</script>

<svelte:head><title>Call Explorer — FMRZ</title></svelte:head>

<div class="container">
  <div class="page-header">
    <div class="header-main">
      <h1>Call <span class="text-gradient">Explorer</span></h1>
      <button class="btn-import" onclick={importCDRs} disabled={importing}>
        {#if importing}
          <div class="mini-spinner"></div> Processing...
        {:else}
          <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
          Import & Rate New CDRs
        {/if}
      </button>
    </div>
    <p class="text-muted">Analyze and audit call detail records across the network</p>
  </div>

  <div class="search-bar animate-fade">
    <div class="input-group">
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
      <input type="text" bind:value={search} placeholder="Search by phone number..." />
    </div>
  </div>

  <div class="table-card card card-static animate-fade" style="animation-delay: 0.1s">
    <div class="table-wrapper">
      {#if loading}
        <div class="loading-state">
          <div class="spinner"></div>
          <p>Loading Call Records...</p>
        </div>
      {:else if filteredCDRs.length === 0}
        <div class="empty-state">
          <p>No call records found matching your search.</p>
        </div>
      {:else}
        <table>
          <thead>
            <tr>
              <th>ID</th>
              <th>MSISDN</th>
              <th>Destination</th>
              <th>Duration</th>
              <th>Type</th>
              <th>Timestamp</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {#each filteredCDRs as cdr}
              <tr>
                <td><span class="id-badge">#{cdr.id}</span></td>
                <td><span class="phone-num">{cdr.msisdn}</span></td>
                <td><span class="phone-num">{cdr.destination || '—'}</span></td>
                <td><span class="duration">{formatDuration(cdr.duration)}</span></td>
                <td>
                  <span class="badge badge-customer">
                    {cdr.type == 1 ? 'Voice' : cdr.type == 2 ? 'Data' : 'SMS'}
                  </span>
                </td>
                <td class="text-muted">{new Date(cdr.timestamp).toLocaleString()}</td>
                <td>
                  <span class="badge {cdr.rated ? 'badge-admin' : 'badge-customer'}">
                    {cdr.rated ? 'Rated' : 'Pending'}
                  </span>
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
        
        <div class="pagination">
          <button class="btn-page" onclick={prevPage} disabled={page === 0}>
            Previous 50
          </button>
          <span class="page-info">Page {page + 1}</span>
          <button class="btn-page" onclick={nextPage} disabled={cdrs.length < limit}>
            Next 50
          </button>
        </div>
      {/if}
    </div>
  </div>
</div>

<style>
  .text-gradient { background: linear-gradient(135deg, var(--red), var(--red-light)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
  .header-main { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem; }
  .btn-import { display: flex; align-items: center; gap: 0.5rem; background: var(--red); color: white; border: none; padding: 0.8rem 1.5rem; border-radius: 12px; font-weight: 600; cursor: pointer; transition: all 0.3s; box-shadow: 0 4px 15px rgba(224, 8, 0, 0.3); }
  .btn-import:hover:not(:disabled) { background: var(--red-light); transform: translateY(-2px); box-shadow: 0 6px 20px rgba(224, 8, 0, 0.4); }
  .btn-import:disabled { opacity: 0.6; cursor: not-allowed; }

  .mini-spinner { width: 16px; height: 16px; border: 2px solid rgba(255, 255, 255, 0.3); border-top-color: white; border-radius: 50%; animation: spin 0.8s linear infinite; }

  .search-bar { margin-bottom: 2rem; max-width: 400px; }
  .input-group { position: relative; display: flex; align-items: center; }
  .input-group svg { position: absolute; left: 1rem; color: var(--text-muted); }
  .input-group input { width: 100%; padding: 0.8rem 1rem 0.8rem 3rem; background: rgba(255, 255, 255, 0.05); border: 1px solid var(--border); border-radius: 12px; color: white; transition: all 0.3s; }
  .input-group input:focus { outline: none; border-color: var(--red); box-shadow: 0 0 15px rgba(224, 8, 0, 0.2); background: rgba(255, 255, 255, 0.08); }

  .table-card { 
    padding: 0; 
    overflow: hidden; 
    border-radius: 20px; 
    border: 1px solid var(--border);
    background: var(--bg-card);
  }
  .table-card .table-wrapper {
    border: none;
    background: transparent;
    margin-top: 0;
  }
  .id-badge { background: rgba(255, 255, 255, 0.05); padding: 0.2rem 0.5rem; border-radius: 6px; font-size: 0.8rem; color: var(--text-muted); }
  .phone-num { font-family: 'JetBrains Mono', monospace; font-weight: 600; color: #3B82F6; }
  .duration { font-weight: 700; color: #F59E0B; }
  .cost { font-weight: 700; color: #22C55E; }

  .loading-state, .empty-state { padding: 4rem; text-align: center; color: var(--text-muted); }
  .spinner { width: 40px; height: 40px; border: 4px solid rgba(224, 8, 0, 0.1); border-top-color: var(--red); border-radius: 50%; animation: spin 1s linear infinite; margin: 0 auto 1rem; }
  
  @keyframes spin { to { transform: rotate(360deg); } }

  .badge-roaming { background: rgba(168, 85, 247, 0.1); color: #A855F7; border: 1px solid rgba(168, 85, 247, 0.2); }

  .pagination { display: flex; align-items: center; justify-content: center; gap: 2rem; padding: 1.5rem; border-top: 1px solid var(--border); background: rgba(255, 255, 255, 0.02); }
  .btn-page { background: rgba(255, 255, 255, 0.05); color: white; border: 1px solid var(--border); padding: 0.5rem 1rem; border-radius: 8px; font-weight: 600; cursor: pointer; transition: all 0.2s; }
  .btn-page:hover:not(:disabled) { background: rgba(255, 255, 255, 0.1); border-color: var(--red); }
  .btn-page:disabled { opacity: 0.4; cursor: not-allowed; }
  .page-info { font-weight: 600; color: var(--text-muted); font-size: 0.9rem; }
</style>
