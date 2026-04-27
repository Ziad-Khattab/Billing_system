<script>
  import { fade, fly } from 'svelte/transition';
  
  let { message, type = 'success', duration = 4000, onclose } = $props();
  
  $effect(() => {
    const timer = setTimeout(() => {
      if (onclose) onclose();
    }, duration);
    return () => clearTimeout(timer);
  });
</script>

{#if message}
  <div 
    class="toast {type}" 
    in:fly={{ y: -20, duration: 300 }} 
    out:fade={{ duration: 200 }}
  >
    <div class="toast-icon">
      {#if type === 'success'}
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>
      {:else}
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
      {/if}
    </div>
    <div class="toast-content">{message}</div>
  </div>
{/if}

<style>
  .toast {
    position: fixed;
    top: 2rem;
    left: 50%;
    transform: translateX(-50%);
    z-index: 9999;
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.75rem 1.5rem;
    border-radius: 100px;
    background: rgba(10, 10, 15, 0.9);
    backdrop-filter: blur(16px);
    -webkit-backdrop-filter: blur(16px);
    border: 1px solid rgba(255, 255, 255, 0.1);
    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4), inset 0 1px 1px rgba(255, 255, 255, 0.1);
    min-width: 300px;
  }

  .toast.success {
    color: #10b981;
    border-color: rgba(16, 185, 129, 0.3);
  }

  .toast.error {
    color: #ef4444;
    border-color: rgba(239, 68, 68, 0.3);
  }

  .toast-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  .toast-content {
    font-size: 0.9375rem;
    font-weight: 600;
    letter-spacing: -0.01em;
  }
</style>
