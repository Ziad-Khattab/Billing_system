<script>
  import { onMount } from 'svelte';
  import { fade } from 'svelte/transition';
  import { showToast } from '$lib/toast.svelte.js';

  let cdrs = $state([]);
  let loading = $state(true);
  let importing = $state(false);
  let uploading = $state(false);
  let generating = $state(false);
  let search = $state('');
  
  // Pagination
  let page = $state(0);
  let limit = $state(50);
  let total = $state(0);

  const totalPages = $derived(Math.ceil(total / limit));

  const loadCDRs = async () => {
    loading = true;
    try {
      const offset = page * limit;
      const res = await fetch(`/api/admin/cdr?limit=${limit}&offset=${offset}&search=${search}`, { credentials: 'include' });
      if (res.ok) {
        const result = await res.json();
        cdrs = result.data || [];
        total = result.total || 0;
      }
    } catch (err) {
      console.error(err);
    } finally {
      loading = false;
    }
  };

  const uploadCDR = async (e) => {
    const file = e.target.files[0];
    if (!file) return;

    uploading = true;
    const formData = new FormData();
    formData.append('file', file);

    try {
      const res = await fetch('/api/admin/cdr-upload', { method: 'POST', body: formData, credentials: 'include' });
      if (res.ok) {
        showToast('CDR file uploaded and parsed successfully');
        page = 0;
        await loadCDRs();
      } else {
        showToast('Failed to upload CDR file', 'error');
      }
    } catch (err) {
      showToast('Error uploading file', 'error');
    } finally {
      uploading = false;
    }
  };

  const importCDRs = async () => {
    importing = true;
    try {
      const res = await fetch('/api/admin/cdr', { method: 'POST', credentials: 'include' });
      const data = await res.json();
      if (res.ok) {
        showToast(`Processing complete! ${data.message || 'Records imported'}`);
        page = 0;
        await loadCDRs();
      } else {
        showToast(data.error || 'Import failed', 'error');
      }
    } catch (err) {
      showToast('Network error during import', 'error');
    } finally {
      importing = false;
    }
  };

  const generateSamples = async () => {
    generating = true;
    try {
      const res = await fetch('/api/admin/cdr-generate', { method: 'POST', credentials: 'include' });
      if (res.ok) {
        showToast('100 Fresh CDR records generated successfully');
        page = 0;
        await loadCDRs();
      }
    } catch (err) {
      showToast('Failed to generate samples', 'error');
    } finally {
      generating = false;
    }
  };

  // Smart Formatter: Logic updated to use the "Gold Standard" (Bytes/Seconds)
  const formatUsage = (value, type) => {
    if (!value) return '0';
    const t = String(type || '').toLowerCase();
    
    if (t === 'voice' || t.includes('call') || t.includes('min')) {
      // Value is in Seconds
      if (value >= 60) return (value / 60).toFixed(1) + ' min';
      return value + ' sec';
    }

    if (t === 'data' || t.includes('internet') || t.includes('gb') || t.includes('mb')) {
      // Value is in Bytes
      if (value >= 1073741824) return (value / 1073741824).toFixed(2) + ' GB';
      if (value >= 1048576) return (value / 1048576).toFixed(1) + ' MB';
      if (value >= 1024) return (value / 1024).toFixed(1) + ' KB';
      return value + ' B';
    }

    if (t === 'sms') return value + ' SMS';
    
    return value;
  };

  const getTypeInfo = (serviceId, ratedType, destination, serviceType) => {
    const mapping = {
      'voice': { label: 'Voice', class: 'badge-voice', icon: 'M12 18.5a6.5 6.5 0 1 0-7-7 1 1 0 0 1-1-1 1 1 0 0 1 1-1 8.5 8.5 0 1 1 9 9 1 1 0 0 1-1-1 1 1 0 0 1 1-1zM5.5 10.5A2.5 2.5 0 1 0 8 13a1 1 0 0 1 1 1 1 1 0 0 1-1 1 4.5 4.5 0 1 1 5-5 1 1 0 0 1 1 1 1 1 0 0 1-1 1z' },
      'data': { label: 'Data', class: 'badge-data', icon: 'M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5' },
      'sms': { label: 'SMS', class: 'badge-sms', icon: 'M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z' }
    };

    const t = String(serviceType || '').toLowerCase();
    if (mapping[t]) return mapping[t];

    const typeStr = String(ratedType || '').toLowerCase();
    if (typeStr.includes('gift') || typeStr.includes('welcome')) {
      return { label: 'Reward', class: 'badge-gift', icon: 'M20 12v10H4V12M2 7h20v5H2zM12 22V7M12 7H7.5a2.5 2.5 0 0 1 0-5C11 2 12 7 12 7zM12 7h4.5a2.5 2.5 0 0 0 0-5C13 2 12 7 12 7z' };
    }

    if (serviceId === 1 || typeStr.includes('voice')) return mapping.voice;
    if (serviceId === 2 || typeStr.includes('data')) return mapping.data;
    if (serviceId === 3 || typeStr.includes('sms')) return mapping.sms;
    return { label: 'Service', class: 'badge-secondary', icon: 'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z' };
  };

  const formatDate = (ts) => {
    if (!ts) return '—';
    return new Date(ts).toLocaleString();
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
      <input type="text" bind:value={search} oninput={() => {page=0; loadCDRs();}} placeholder="Search MSISDN or Destination..." />
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
        {#if cdrs.length === 0}
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
              {#each cdrs as cdr}
                {@const typeInfo = getTypeInfo(cdr.service_id, cdr.type, cdr.destination, cdr.service_type)}
                <tr transition:fade={{duration: 200}}>
                  <td class="font-mono text-dim">#{cdr.id}</td>
                  <td class="font-bold">{cdr.msisdn}</td>
                  <td class="text-dim">{cdr.destination}</td>
                  <td class="usage-cell">
                    <span class="usage-value">{formatUsage(cdr.duration, typeInfo.label)}</span>
                  </td>
                  <td>
                    <div class="badge {typeInfo.class}">
                      <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d={typeInfo.icon}/></svg>
                      {cdr.type || typeInfo.label}
                    </div>
                  </td>
                  <td class="text-dim text-sm">{formatDate(cdr.timestamp)}</td>
                  <td>
                    <span class="status-indicator {cdr.rated ? 'status-rated' : 'status-pending'}">
                      {cdr.rated ? 'Rated' : 'Pending'}
                    </span>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
          
          <div class="pagination">
             <button disabled={page === 0} onclick={() => {page--; loadCDRs();}}>Prev</button>
             <span>Page {page + 1} of {totalPages || 1}</span>
             <button disabled={(page + 1) * limit >= total} onclick={() => {page++; loadCDRs();}}>Next</button>
             <span class="total-count">Total: {total} records</span>
          </div>
        {/if}
      {/if}
    </div>
  </div>
</div>

<style>
  .container { max-width: 1200px; margin: 0 auto; padding: 2rem 1rem; }
  .page-header { margin-bottom: 2.5rem; }
  .header-main { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem; }
  h1 { font-size: 2.5rem; font-weight: 800; letter-spacing: -0.02em; }
  .text-gradient { background: linear-gradient(135deg, #FF3E00, #FF8A00); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
  .header-actions { display: flex; gap: 0.75rem; }
  .btn-secondary { display: flex; align-items: center; gap: 0.5rem; padding: 0.6rem 1.25rem; background: rgba(255, 255, 255, 0.05); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 12px; color: white; font-weight: 600; cursor: pointer; transition: all 0.2s; }
  .btn-secondary:hover:not(:disabled) { background: rgba(255, 255, 255, 0.1); border-color: rgba(255, 255, 255, 0.2); transform: translateY(-1px); }
  .btn-import { display: flex; align-items: center; gap: 0.5rem; padding: 0.6rem 1.5rem; background: linear-gradient(135deg, #FF3E00, #FF8A00); border: none; border-radius: 12px; color: white; font-weight: 700; cursor: pointer; transition: all 0.2s; box-shadow: 0 4px 15px rgba(255, 62, 0, 0.3); }
  .btn-import:hover:not(:disabled) { transform: translateY(-2px); box-shadow: 0 6px 20px rgba(255, 62, 0, 0.4); }
  .btn-import:disabled { opacity: 0.6; cursor: not-allowed; }
  .search-bar { margin-bottom: 2rem; }
  .input-group { position: relative; max-width: 500px; }
  .input-group svg { position: absolute; left: 1rem; top: 50%; transform: translateY(-50%); color: #666; }
  .input-group input { width: 100%; padding: 0.8rem 1rem 0.8rem 3rem; background: rgba(255, 255, 255, 0.05); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 14px; color: white; font-size: 1rem; transition: all 0.2s; }
  .input-group input:focus { outline: none; border-color: #FF3E00; background: rgba(255, 255, 255, 0.08); box-shadow: 0 0 0 4px rgba(255, 62, 0, 0.1); }
  .table-wrapper { background: rgba(255, 255, 255, 0.03); border: 1px solid rgba(255, 255, 255, 0.08); border-radius: 20px; overflow: hidden; backdrop-filter: blur(10px); }
  table { width: 100%; border-collapse: collapse; text-align: left; }
  th { padding: 1.25rem 1.5rem; background: rgba(255, 255, 255, 0.02); color: #888; font-weight: 600; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.05em; border-bottom: 1px solid rgba(255, 255, 255, 0.08); }
  td { padding: 1.25rem 1.5rem; border-bottom: 1px solid rgba(255, 255, 255, 0.04); }
  tr:hover td { background: rgba(255, 255, 255, 0.02); }
  .font-mono { font-family: 'JetBrains Mono', monospace; letter-spacing: -0.02em; }
  .text-dim { color: #888; }
  .text-sm { font-size: 0.9rem; }
  .usage-value { font-weight: 700; color: #fff; }
  .badge { display: inline-flex; align-items: center; gap: 0.4rem; padding: 0.35rem 0.75rem; border-radius: 8px; font-size: 0.8rem; font-weight: 600; }
  .badge-voice { background: rgba(59, 130, 246, 0.15); color: #60A5FA; }
  .badge-data { background: rgba(168, 85, 247, 0.15); color: #C084FC; }
  .badge-sms { background: rgba(34, 197, 94, 0.15); color: #4ADE80; }
  .badge-gift { background: rgba(245, 158, 11, 0.15); color: #FBBF24; }
  .badge-secondary { background: rgba(255, 255, 255, 0.1); color: #aaa; }
  .status-indicator { display: inline-flex; align-items: center; gap: 0.4rem; font-size: 0.8rem; font-weight: 600; }
  .status-indicator::before { content: ''; width: 6px; height: 6px; border-radius: 50%; }
  .status-rated { color: #22C55E; }
  .status-rated::before { background: #22C55E; box-shadow: 0 0 8px #22C55E; }
  .status-pending { color: #F59E0B; }
  .status-pending::before { background: #F59E0B; }
  .pagination { display: flex; align-items: center; gap: 1rem; padding: 1.5rem; background: rgba(255, 255, 255, 0.02); border-top: 1px solid rgba(255, 255, 255, 0.08); }
  .pagination button { padding: 0.5rem 1rem; background: rgba(255, 255, 255, 0.05); border: 1px solid rgba(255, 255, 255, 0.1); border-radius: 8px; color: white; cursor: pointer; transition: all 0.2s; }
  .pagination button:hover:not(:disabled) { background: rgba(255, 255, 255, 0.1); border-color: #FF3E00; }
  .pagination button:disabled { opacity: 0.5; cursor: not-allowed; }
  .total-count { margin-left: auto; color: #666; font-size: 0.9rem; }
  .loading-state, .empty-state { padding: 4rem; text-align: center; color: #888; }
  .spinner, .mini-spinner { border: 2px solid rgba(255, 255, 255, 0.1); border-top-color: #FF3E00; border-radius: 50%; animation: spin 0.8s linear infinite; }
  .spinner { width: 30px; height: 30px; margin: 0 auto 1rem; }
  .mini-spinner { width: 16px; height: 16px; }
  @keyframes spin { to { transform: rotate(360deg); } }
  @keyframes fade { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
  .animate-fade { animation: fade 0.4s ease forwards; }
</style>