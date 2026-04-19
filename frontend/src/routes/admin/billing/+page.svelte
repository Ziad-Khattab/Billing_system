<!-- The script block is where all the Javascript/TypeScript logic lives in Svelte -->
<script>
  // $state() is a Svelte 5 Rune. It makes variables reactive. 
  // If contractId changes, the UI will automatically update.
  let contractId = $state('');
  
  // Create an empty array to store the billing data retrieved from the server
  let bills = $state([]);

  // async function allows us to use 'await' when making HTTP requests to the backend
  async function loadBills() {
    // Prevent the function from running if the user hasn't typed a contract ID
    if (!contractId) return;
    
    try {
      // fetch() makes an HTTP GET request to the Tomcat Java backend on port 8080.
      // 'credentials: include' ensures session cookies (for authentication) are sent with the request.
      const res = await fetch(`/api/admin/bills?contract_id=${contractId}`, { credentials: 'include' });
      
      // If the backend returns a 200 OK status, parse the JSON response and update our 'bills' array.
      // Because 'bills' uses $state(), updating it here triggers Svelte to re-render the HTML table below.
      if (res.ok) bills = await res.json();
    } catch {
      // If the server is down or network fails, ignore the error silently for now
    }
  }
</script>

<!-- <svelte:head> injects tags directly into the HTML <head>. Used here for the page title. -->
<svelte:head><title>Billing — FMRZ Admin</title></svelte:head>

<!-- The main wrapper using the .container class defined in app.css -->
<div class="container">
  <!-- Page title -->
  <div class="page-header"><h1>Billing & Invoices</h1></div>
  
  <!-- Search bar area: Flexbox is used to put the input and button side-by-side -->
  <div style="display:flex;gap:1rem;margin-bottom:2rem">
    <!-- bind:value={contractId} implements two-way binding. 
         Typing in the box updates the variable, and changing the variable updates the box. -->
    <input class="input" style="width:200px" placeholder="Contract ID" bind:value={contractId} type="number" />
    
    <!-- onclick={loadBills} attaches the click event directly to our async function -->
    <button class="btn btn-primary" onclick={loadBills}>Load Bills</button>
  </div>
  
  <!-- Svelte {#if} logic block: Only show the table if the bills array is not empty -->
  {#if bills.length > 0}
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
          <!-- Use curly braces {} to render the Javascript properties into the HTML -->
          <td>#{b.id}</td>
          <td>{b.billingDate}</td>
          <td>{b.recurringFees} EGP</td>
          <td>{b.oneTimeFees} EGP</td>
          <td>{b.voiceUsage}s</td>
          <td>{b.dataUsage} MB</td>
          <td>{b.smsUsage}</td>
          <td>{b.taxes} EGP</td>
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
