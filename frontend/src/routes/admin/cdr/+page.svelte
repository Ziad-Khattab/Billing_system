<script>
  let cdrs = $state([]);
  let total = $state(0);
  let search = $state('');
  let loading = $state(true);
  let importing = $state(false);
  let page = $state(0);
  let limit = $state(50);
  let jumpPage = $state(1);

  const totalPages = $derived(Math.ceil(total / limit));

  async function loadCDRs() {
    loading = true;
    try {
      const offset = page * limit;
      const res = await fetch(`/api/admin/cdr?limit=${limit}&offset=${offset}`, { credentials: 'include' });
      if (res.ok) {
        const result = await res.json();
        cdrs = result.data || [];
        total = result.total || 0;
        jumpPage = page + 1;
      }
    } catch (e) {
      console.error(e);
    } finally {
      loading = false;
    }
  }

  function nextPage() { 
    if ((page + 1) * limit < total) {
      page++; 
      loadCDRs(); 
    }
  }
  function prevPage() { if (page > 0) { page--; loadCDRs(); } }

  function goToPage() {
    const target = Math.max(1, Math.min(jumpPage, totalPages));
    page = target - 1;
    loadCDRs();
  }

  function handleLimitChange(e) {
    limit = parseInt(e.target.value);
    page = 0;
    loadCDRs();
  }

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
          search ? cdrs.filter(c => c.msisdn.includes(search) || (c.destination && c.destination.includes(search))) : cdrs
  );

  // Formatter: Logic updated because API sends MB
  // Smart Formatter: Logic updated to handle legacy SMS records and dynamic usage
  function formatUsage(value, type, destination) {
    if (value === 0) return '0';
    if (!value) return '—';

    // Smart Correction for legacy records: If type is Data (2) but usage is 1 and destination is numeric, treat as SMS
    const isLegacySMS = type === 'data' && value === 1 && destination && /^\d+$/.test(destination.replace(/[+]/g, ''));
    const effectiveType = isLegacySMS ? 'sms' : type;

    switch (effectiveType) {
      case 'voice':
        const h = Math.floor(value / 3600);
        const m = Math.floor((value % 3600) / 60);
        const s = value % 60;
        return `${h > 0 ? h + 'h ' : ''}${m > 0 ? m + 'm ' : ''}${s}s`;

      case 'data':
        if (value >= 1024) return (value / 1024).toFixed(2) + ' GB';
        return value.toFixed(2) + ' MB';

      case 'sms':
        return value + ' SMS';

      default:
        return value;
    }
  }

  const getTypeInfo = (type, value, destination) => {
    // If it's a legacy number ID
    if (type === 1 || type === '1') return { label: 'Voice', class: 'badge-voice' };
    if (type === 2 || type === '2') {
      const isLegacySMS = value === 1 && destination && /^\d+$/.test(destination.replace(/[+]/g, ''));
      return isLegacySMS ? { label: 'SMS', class: 'badge-sms' } : { label: 'Data', class: 'badge-data' };
    }
    if (type === 3 || type === '3') return { label: 'SMS', class: 'badge-sms' };

    // New Smart Rating String Labels
    const typeStr = String(type || '').toLowerCase();
    
    if (typeStr.includes('voice')) return { label: type, class: 'badge-voice' };
    if (typeStr.includes('data')) return { label: type, class: 'badge-data' };
    if (typeStr.includes('sms')) return { label: type, class: 'badge-sms' };
    if (typeStr.includes('bonus') || typeStr.includes('free')) return { label: type, class: 'badge-units' };
    if (typeStr.includes('overage')) return { label: 'Overage', class: 'badge-error' };
    
    return { label: type || 'Other', class: 'badge-secondary' };
  };

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
    <p class="text-muted">Analyze and audit network usage records</p>
  </div>

  <div class="search-bar animate-fade">
    <div class="input-group">
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
      <input type="text" bind:value={search} placeholder="Search MSISDN or Destination..." />
    </div>
  </div>

  <div class="animate-fade" style="animation-delay: 0.1s">
    <div class="table-wrapper">
      {#if loading}
        <div class="loading-state">
          <div class="spinner"></div>
          <p>Loading records...</p>
        </div>
      {:else}
        {#if filteredCDRs.length === 0}
          <div class="empty-state">
            <p>No records found matching your search.</p>
          </div>
        {:else}
          <table>
            <thead>
            <tr>
              <th>ID</th>
              <th>MSISDN</th>
              <th>Destination</th>
              <th>Usage</th>
              <th>Type</th>
              <th>Timestamp</th>
              <th>Status</th>
            </tr>
            </thead>
            <tbody>
            {#each filteredCDRs as cdr}
              {@const typeInfo = getTypeInfo(cdr.type, cdr.duration, cdr.destination)}
              <tr>
                <td><span class="id-badge">#{cdr.id}</span></td>
                <td><span class="phone-num">{cdr.msisdn}</span></td>
                <td><span class="phone-num">{cdr.destination || '—'}</span></td>
                <td><span class="usage-text">{formatUsage(cdr.duration, cdr.type, cdr.destination)}</span></td>
                <td>
                    <span class="badge {typeInfo.class} badge-base">
                      {typeInfo.label}
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
        {/if}

        <div class="pagination">
          <div class="pagination-controls">
            <button class="btn-page" onclick={prevPage} disabled={page === 0}>
              Previous
            </button>
            
            <div class="page-jump">
              <span>Page</span>
              <input type="number" bind:value={jumpPage} min="1" max={totalPages} class="input-jump" />
              <span>of {totalPages}</span>
              <button class="btn-go" onclick={goToPage}>Go</button>
            </div>

            <button class="btn-page" onclick={nextPage} disabled={(page + 1) * limit >= total}>
              Next
            </button>
          </div>

          <div class="pagination-settings">
            <span>Rows per page:</span>
            <select bind:value={limit} onchange={handleLimitChange} class="select-limit">
              <option value="10">10</option>
              <option value="25">25</option>
              <option value="50">50</option>
              <option value="100">100</option>
            </select>
            <span class="total-info">Total: {total} records</span>
          </div>
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
  .input-group input:focus { outline: none; border-color: var(--red); box-shadow: 0 0 15px rgba(224, 8, 0, 0.2); }

  .id-badge { background: rgba(255, 255, 255, 0.05); padding: 0.2rem 0.5rem; border-radius: 6px; font-size: 0.8rem; color: var(--text-muted); }
  .phone-num { font-family: 'JetBrains Mono', monospace; font-weight: 600; color: #3B82F6; }

  .usage-text { font-family: 'JetBrains Mono', monospace; font-weight: 700; color: #F59E0B; }

  .badge-base { border-left: 3px solid transparent; }
  .badge-voice { border-left-color: #3B82F6; color: #3B82F6; background: rgba(59, 130, 246, 0.1); }
  .badge-data { border-left-color: #22C55E; color: #22C55E; background: rgba(34, 197, 94, 0.1); }
  .badge-sms { border-left-color: #A855F7; color: #A855F7; background: rgba(168, 85, 247, 0.1); }
  .badge-units { border-left-color: #F59E0B; color: #F59E0B; background: rgba(245, 158, 11, 0.1); }
  .badge-error { border-left-color: #EF4444; color: #EF4444; background: rgba(239, 68, 68, 0.1); }
  .badge-secondary { border-left-color: #9CA3AF; color: #9CA3AF; background: rgba(156, 163, 175, 0.1); }

  .loading-state, .empty-state { padding: 4rem; text-align: center; color: var(--text-muted); }
  .spinner { width: 40px; height: 40px; border: 4px solid rgba(224, 8, 0, 0.1); border-top-color: var(--red); border-radius: 50%; animation: spin 1s linear infinite; margin: 0 auto 1rem; }

  @keyframes spin { to { transform: rotate(360deg); } }

  .pagination { display: flex; flex-direction: column; align-items: center; gap: 1rem; padding: 1.5rem; border-top: 1px solid var(--border); background: rgba(255, 255, 255, 0.02); }
  .pagination-controls { display: flex; align-items: center; gap: 1.5rem; }
  .pagination-settings { display: flex; align-items: center; gap: 1rem; font-size: 0.85rem; color: var(--text-muted); }
  
  .page-jump { display: flex; align-items: center; gap: 0.5rem; font-weight: 600; color: var(--text-muted); font-size: 0.9rem; }
  .input-jump { width: 60px; padding: 0.3rem 0.5rem; background: rgba(255, 255, 255, 0.05); border: 1px solid var(--border); border-radius: 6px; color: white; text-align: center; }
  .btn-go { background: var(--red); color: white; border: none; padding: 0.3rem 0.8rem; border-radius: 6px; font-weight: 600; cursor: pointer; transition: 0.2s; }
  .btn-go:hover { background: var(--red-light); }

  .select-limit { background: rgba(255, 255, 255, 0.05); color: white; border: 1px solid var(--border); border-radius: 6px; padding: 0.2rem 0.5rem; outline: none; }
  .select-limit:focus { border-color: var(--red); }
  .total-info { margin-left: 1rem; font-style: italic; }

  .btn-page { background: rgba(255, 255, 255, 0.05); color: white; border: 1px solid var(--border); padding: 0.5rem 1rem; border-radius: 8px; font-weight: 600; cursor: pointer; transition: all 0.2s; }
  .btn-page:hover:not(:disabled) { background: rgba(255, 255, 255, 0.1); border-color: var(--red); }
  .btn-page:disabled { opacity: 0.4; cursor: not-allowed; }
</style>