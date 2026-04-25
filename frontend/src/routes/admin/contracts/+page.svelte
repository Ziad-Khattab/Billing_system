<script>
  let contracts = $state([]);
  $effect(() => {
    fetch('/api/admin/contracts', { credentials: 'include' })
      .then(r => r.ok ? r.json() : []).then(d => contracts = d).catch(() => {});
  });
</script>
<svelte:head><title>Contracts — FMRZ Admin</title></svelte:head>
<div class="container">
  <div class="page-header">
    <h1>Service <span class="text-gradient">Contracts</span></h1>
    <p class="text-muted">Manage and provision phone lines across the subscriber base</p>
  </div>

  <div class="table-wrapper animate-fade"><table>
    <thead><tr><th>ID</th><th>MSISDN</th><th>Customer</th><th>Plan</th><th>Status</th><th>Credit</th></tr></thead>
    <tbody>{#each contracts as c}<tr>
      <td><span class="id-badge">#{c.id}</span></td>
      <td><span class="phone-num">{c.msisdn}</span></td>
      <td style="font-weight:600">{c.customerName||'—'}</td>
      <td><span class="badge badge-customer">{c.rateplanName||'—'}</span></td>
      <td><span class="badge badge-{c.status}">{c.status}</span></td>
      <td>
        <span class="amount-num" style={c.availableCredit < 0 ? 'color: #ef4444' : ''}>
          {c.availableCredit} EGP
        </span>
      </td>
    </tr>{/each}</tbody>
  </table></div>
</div>
