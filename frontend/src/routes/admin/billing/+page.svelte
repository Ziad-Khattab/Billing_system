<!-- The script block is where all the Javascript/TypeScript logic lives in Svelte -->
<script>
  // $state() is a Svelte 5 Rune. It makes variables reactive. 
  // If contractId changes, the UI will automatically update.
  let contractId = $state('');
  
  // Create an empty array to store the billing data retrieved from the server
  let bills = $state([]);
  let loading = $state(false);

  async function loadBills() {
    if (!contractId) return;
    loading = true;
    try {
      const res = await fetch(`/api/admin/bills?contract_id=${contractId}`, { credentials: 'include' });
      if (res.ok) bills = await res.json();
    } catch {
    } finally {
      loading = false;
    }
  }
</script>

<!-- <svelte:head> injects tags directly into the HTML <head>. Used here for the page title. -->
<svelte:head><title>Billing — FMRZ Admin</title></svelte:head>

<!-- The main wrapper using the .container class defined in app.css -->
<div class="container">
  <!-- Page title -->
  <div class="page-header">
    <h1>Billing & <span class="text-gradient">Invoices</span></h1>
    <p class="text-muted">Track and audit historical billing records across the network</p>
  </div>
  
  <div class="search-bar animate-fade">
    <div style="display:flex;gap:1rem;margin-bottom:2rem">
      <input class="input" style="width:200px" placeholder="Enter Contract ID..." bind:value={contractId} type="number" />
      <button class="btn btn-primary" onclick={loadBills}>Load Bills</button>
    </div>
  </div>
  
  {#if loading}
    <div class="card" style="text-align:center;padding:4rem;">
      <div class="spinner" style="margin: 0 auto 1rem;"></div>
      <p style="color:var(--text-muted)">Fetching Billing Records...</p>
    </div>
  {:else if bills.length > 0}
  <div class="table-wrapper">
    <table>
      <thead>
        <tr>
          <th>Bill ID</th><th>Date</th><th>Recurring</th><th>One-time</th>
          <th>Voice</th><th>Data</th><th>SMS</th><th>Tax</th>
        </tr>
      </thead>
      <tbody>
        <!-- Svelte {#each} loop: Iterates over the 'bills' array. 'b' represents each bill object -->
        {#each bills as b}
        <tr>
          <td><span class="id-badge">#{b.id}</span></td>
          <td class="text-muted">{b.billingDate}</td>
          <td><span class="amount-num">{b.recurringFees} EGP</span></td>
          <td><span class="amount-num">{b.oneTimeFees} EGP</span></td>
          <td><span class="duration-num">{b.voiceUsage}s</span></td>
          <td><span class="duration-num">{b.dataUsage} MB</span></td>
          <td><span class="duration-num">{b.smsUsage}</span></td>
          <td><span class="amount-num">{b.taxes} EGP</span></td>
        </tr>
        {/each}
      </tbody>
    </table>
  </div>
  <!-- Svelte {:else} block: What to show if the bills array IS empty -->
  {:else}
  <div class="card" style="text-align:center;padding:3rem;color:var(--text-muted)">
    Enter a contract ID and click "Load Bills" to view billing data
  </div>
  {/if} <!-- Close the if statement -->
</div>
