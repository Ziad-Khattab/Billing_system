<script>
  import Modal from './Modal.svelte';
  
  let { show = $bindable(), title, message, onconfirm, loading = false, type = 'default' } = $props();

  function handleConfirm() {
    if (onconfirm) onconfirm();
  }
</script>

<Modal bind:show={show} {title} {type}>
  <div class="confirm-body">
    <p class="message">{message}</p>
    
    <div class="actions">
      <button class="btn btn-secondary" onclick={() => show = false} disabled={loading}>Cancel</button>
      <button class="btn btn-primary" onclick={handleConfirm} disabled={loading}>
        {#if loading}
          <div class="mini-spinner"></div> Processing...
        {:else}
          Confirm Action
        {/if}
      </button>
    </div>
  </div>
</Modal>

<style>
  .confirm-body {
    text-align: left;
  }
  .message {
    font-size: 1.1rem;
    color: var(--text-secondary);
    line-height: 1.6;
    margin-bottom: 2.5rem;
  }
  .actions {
    display: flex;
    gap: 1rem;
    justify-content: flex-end;
  }
  .actions button {
    min-width: 120px;
  }
  .mini-spinner {
    width: 14px;
    height: 14px;
    border: 2px solid rgba(255, 255, 255, 0.3);
    border-top-color: white;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
    display: inline-block;
    margin-right: 8px;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
</style>
