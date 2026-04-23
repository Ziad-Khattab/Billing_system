<script>
  let contracts = $state([]);
  $effect(() => {
    fetch('/api/admin/contracts', { credentials: 'include' })
      .then(r => r.ok ? r.json() : []).then(d => contracts = d).catch(() => {});
  });
</script>
<svelte:head><title>Contracts — FMRZ Admin</title></svelte:head>
<div class="container">
  <div class="page-header"><h1>Contracts</h1></div>
  <div class="table-wrapper"><table>
    <thead><tr><th>ID</th><th>MSISDN</th><th>Customer</th><th>Plan</th><th>Status</th><th>Credit</th></tr></thead>
    <tbody>{#each contracts as c}<tr>
      <td>#{c.id}</td>
      <td style="font-weight:600">{c.msisdn}</td>
      <td>{c.customerName||'—'}</td>
      <td>{c.rateplanName||'—'}</td>
      <td><span class="badge badge-{c.status}">{c.status}</span></td>
      <td>{c.availableCredit} EGP</td>
    </tr>{/each}</tbody>
  </table></div>
</div>
