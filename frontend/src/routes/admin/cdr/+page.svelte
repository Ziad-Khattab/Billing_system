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

  let generating = $state(false);
  let uploading = $state(false);

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

  async function generateSamples() {
    generating = true;
    try {
      const res = await fetch('/api/admin/cdr-generate', { method: 'POST', credentials: 'include' });
      const data = await res.json();
      if (res.ok) {
        alert(data.message || 'Samples generated successfully!');
      } else {
        alert('Generation failed: ' + (data.error || data.message));
      }
    } catch (e) {
      console.error(e);
      alert('Error connecting to server');
    } finally {
      generating = false;
    }
  }

  async function uploadCDR(event) {
    const file = event.target.files[0];
    if (!file) return;

    const formData = new FormData();
    formData.append('file', file);

    uploading = true;
    try {
      const res = await fetch('/api/admin/cdr-upload', { 
        method: 'POST', 
        body: formData,
        credentials: 'include'
      });
      const data = await res.json();
      if (res.ok) {
        alert('File uploaded successfully! You can now click "Import" to process it.');
      } else {
        alert('Upload failed: ' + (data.error || data.message));
      }
    } catch (e) {
      console.error(e);
      alert('Error during upload');
    } finally {
      uploading = false;
      event.target.value = ''; // Reset input
    }
  }

  let filteredCDRs = $derived(
          search ? cdrs.filter(c => c.msisdn.includes(search) || (c.destination && c.destination.includes(search))) : cdrs
  );

  // Formatter: Logic updated because API sends MB
  // Smart Formatter: Logic updated to handle legacy SMS records and dynamic usage
  function formatUsage(value, serviceId, type, destination, serviceType) {
    if (value === 0 && (serviceType === 'data' || String(destination).toLowerCase() === 'internet')) return '0 MB';
    if (value === 0) return '0';
    if (!value) return '—';

    // Prioritize Service Type from DB
    let effectiveType = serviceType || 'other';
    
    if (effectiveType === 'other') {
      // Fallback to legacy logic if serviceType is missing
      if (serviceId === 1) effectiveType = 'voice';
      else if (serviceId === 2) effectiveType = 'data';
      else if (serviceId === 3) effectiveType = 'sms';
      else {
        const typeStr = String(type || '').toLowerCase();
        const destStr = String(destination || '').toLowerCase();
        if (typeStr.includes('voice') || typeStr.includes('call')) effectiveType = 'voice';
        else if (typeStr.includes('data') || typeStr.includes('internet') || destStr === 'internet') effectiveType = 'data';
        else if (typeStr.includes('sms')) effectiveType = 'sms';
      }
    }

    switch (effectiveType) {
      case 'voice':
        const mins = (value / 60).toFixed(1);
        return `${mins} min`;

      case 'data':
        if (value >= 1024) return (value / 1024).toFixed(2) + ' GB';
        return value.toFixed(1) + ' MB';

      case 'sms':
        return value + ' SMS';

      default:
        return value;
    }
  }

  const getTypeInfo = (serviceId, ratedType, destination, serviceType) => {
    // Standardized Mapping
    const mapping = {
      'voice': { label: 'Voice', class: 'badge-voice', icon: 'M12 18.5a6.5 6.5 0 1 0-7-7 1 1 0 0 1-1-1 1 1 0 0 1 1-1 8.5 8.5 0 1 1 9 9 1 1 0 0 1-1-1 1 1 0 0 1 1-1zM5.5 10.5A2.5 2.5 0 1 0 8 13a1 1 0 0 1 1 1 1 1 0 0 1-1 1 4.5 4.5 0 1 1 5-5 1 1 0 0 1 1 1 1 1 0 0 1-1 1z' },
      'data': { label: 'Data', class: 'badge-data', icon: 'M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5' },
      'sms': { label: 'SMS', class: 'badge-sms', icon: 'M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z' }
    };

    if (mapping[serviceType]) return mapping[serviceType];

    // Fallbacks
    const typeStr = String(ratedType || '').toLowerCase();
    if (typeStr.includes('gift') || typeStr.includes('welcome')) {
      return { 
        label: 'Reward', 
        class: 'badge-gift', 
        icon: 'M20 12v10H4V12M2 7h20v5H2zM12 22V7M12 7H7.5a2.5 2.5 0 0 1 0-5C11 2 12 7 12 7zM12 7h4.5a2.5 2.5 0 0 0 0-5C13 2 12 7 12 7z' 
      };
    }

    if (serviceId === 1 || typeStr.includes('voice')) return mapping.voice;
    if (serviceId === 2 || typeStr.includes('data')) return mapping.data;
    if (serviceId === 3 || typeStr.includes('sms')) return mapping.sms;
    
    return { label: 'Service', class: 'badge-secondary', icon: 'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z' };
  };

  $effect(() => { loadCDRs(); });
</script>

<svelte:head><title>Call Explorer — FMRZ</title></svelte:head>

<div class="container">
  <div class="page-header">
    <div class="header-main">
      <h1>Call <span class="text-gradient">Explorer</span></h1>
      <div class="header-actions">
        <label class="btn-secondary" style="cursor: pointer;">
          <input type="file" accept=".csv" onchange={uploadCDR} style="display: none;" disabled={uploading}/>
          {#if uploading}
            <div class="mini-spinner color-red"></div> Uploading...
          {:else}
            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
            Upload CSV
          {/if}
        </label>

        <button class="btn-secondary" onclick={generateSamples} disabled={generating}>
          {#if generating}
            <div class="mini-spinner color-red"></div> Generating...
          {:else}
            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/></svg>
            Generate Samples
          {/if}
        </button>

        <button class="btn-import" onclick={importCDRs} disabled={importing}>
          {#if importing}
            <div class="mini-spinner"></div> Processing...
          {:else}
            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m12 19 7-7 3 3-7 7-3-3Z"/><path d="m18 13-1.5-7.5L2 2l3.5 14.5L13 18l5-5Z"/><path d="m2 2 7.586 7.586"/><circle cx="11" cy="11" r="2"/></svg>
            Import & Rate
          {/if}
        </button>
      </div>
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
              {@const typeInfo = getTypeInfo(cdr.service_id, cdr.type, cdr.destination, cdr.service_type)}
              <tr>
                <td><span class="id-badge">#{cdr.id}</span></td>
                <td><span class="phone-num">{cdr.msisdn}</span></td>
                <td><span class="phone-num">{cdr.destination || '—'}</span></td>
                <td><span class="usage-text">{formatUsage(cdr.duration, cdr.service_id, cdr.type, cdr.destination, cdr.service_type)}</span></td>
                <td>
                    <div style="display:flex; align-items:center; gap:8px">
                      <div class="icon-box {typeInfo.class}">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d={typeInfo.icon}/></svg>
                      </div>
                      <div style="display:flex; flex-direction:column">
                        <span class="type-label">{typeInfo.label}</span>
                        <span class="type-subtext">{cdr.type || 'System Record'}</span>
                      </div>
                    </div>
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

  .header-actions { display: flex; gap: 0.75rem; align-items: center; }
  .btn-secondary { display: flex; align-items: center; gap: 0.5rem; background: rgba(255, 255, 255, 0.05); color: white; border: 1px solid var(--border); padding: 0.8rem 1.2rem; border-radius: 12px; font-weight: 600; cursor: pointer; transition: all 0.3s; }
  .btn-secondary:hover:not(:disabled) { background: rgba(255, 255, 255, 0.1); border-color: var(--red); }
  .btn-secondary:disabled { opacity: 0.6; cursor: not-allowed; }

  .btn-import { display: flex; align-items: center; gap: 0.5rem; background: var(--red); color: white; border: none; padding: 0.8rem 1.5rem; border-radius: 12px; font-weight: 600; cursor: pointer; transition: all 0.3s; box-shadow: 0 4px 15px rgba(224, 8, 0, 0.3); }
  .btn-import:hover:not(:disabled) { background: var(--red-light); transform: translateY(-2px); box-shadow: 0 6px 20px rgba(224, 8, 0, 0.4); }
  .btn-import:disabled { opacity: 0.6; cursor: not-allowed; }

  .mini-spinner { width: 16px; height: 16px; border: 2px solid rgba(255, 255, 255, 0.3); border-top-color: white; border-radius: 50%; animation: spin 0.8s linear infinite; }
  .mini-spinner.color-red { border-top-color: var(--red); }

  .search-bar { margin-bottom: 2rem; max-width: 400px; }
  .input-group { position: relative; display: flex; align-items: center; }
  .input-group svg { position: absolute; left: 1rem; color: var(--text-muted); }
  .input-group input { width: 100%; padding: 0.8rem 1rem 0.8rem 3rem; background: rgba(255, 255, 255, 0.05); border: 1px solid var(--border); border-radius: 12px; color: white; transition: all 0.3s; }
  .input-group input:focus { outline: none; border-color: var(--red); box-shadow: 0 0 15px rgba(224, 8, 0, 0.2); }

  .id-badge { background: rgba(255, 255, 255, 0.05); padding: 0.2rem 0.5rem; border-radius: 6px; font-size: 0.8rem; color: var(--text-muted); }
  .phone-num { font-family: 'JetBrains Mono', monospace; font-weight: 600; color: #3B82F6; }

  .usage-text { font-family: 'JetBrains Mono', monospace; font-weight: 700; color: #F59E0B; }

  .badge-secondary { border-left-color: #9CA3AF; color: #9CA3AF; background: rgba(156, 163, 175, 0.1); }

  .icon-box { width: 32px; height: 32px; border-radius: 8px; display: flex; align-items: center; justify-content: center; flex-shrink: 0; }
  .icon-box svg { width: 18px; height: 18px; }
  .icon-box.badge-voice { background: rgba(59, 130, 246, 0.1); color: #3B82F6; }
  .icon-box.badge-data { background: rgba(34, 197, 94, 0.1); color: #22C55E; }
  .icon-box.badge-sms { background: rgba(245, 158, 11, 0.1); color: #F59E0B; }
  .icon-box.badge-gift { background: rgba(168, 85, 247, 0.15); color: #A855F7; border: 1px solid rgba(168, 85, 247, 0.3); }
  .icon-box.badge-secondary { background: rgba(156, 163, 175, 0.1); color: #9CA3AF; }

  .type-label { font-weight: 700; font-size: 0.85rem; color: #FFFFFF; }
  .type-subtext { font-size: 0.65rem; color: var(--text-muted); font-weight: 600; text-transform: uppercase; letter-spacing: 0.02em; }

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