<script>
  import { fade, fly } from 'svelte/transition';
  
  let { show = $bindable(), title, subtitle, children, onclose, type = 'default' } = $props();

  function close() {
    show = false;
    if (onclose) onclose();
  }
</script>

{#if show}
  <div class="modal-overlay" transition:fade onclick={close} role="button" tabindex="0" onkeydown={(e) => e.key === 'Escape' && close()}>
    <div 
      class="modal {type === 'admin' ? 'modal-admin' : ''}" 
      onclick={(e) => e.stopPropagation()} 
      in:fly={{ y: 30, duration: 500 }} 
      out:fade={{ duration: 200 }}
    >
      <button class="close-btn" onclick={close} aria-label="Close modal">
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
      </button>

      {#if title}
        <div class="modal-header">
          <h2 class="text-gradient">{title}</h2>
          {#if subtitle}
            <p class="text-muted">{subtitle}</p>
          {/if}
        </div>
      {/if}

      <div class="modal-content">
        {@render children()}
      </div>
    </div>
  </div>
{/if}

<style>
  .modal-overlay {
    position: fixed;
    inset: 0;
    background: rgba(5, 5, 10, 0.85);
    backdrop-filter: blur(25px);
    -webkit-backdrop-filter: blur(25px);
    z-index: 2000;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 1.5rem;
  }

  .modal {
    width: 100%;
    max-width: 500px;
    background: rgba(15, 15, 25, 0.85);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 28px;
    padding: 2.5rem;
    position: relative;
    box-shadow: 0 40px 100px rgba(0, 0, 0, 0.7), inset 0 1px 1px rgba(255, 255, 255, 0.1);
  }

  .modal-admin {
    border: 1px solid var(--red);
    box-shadow: 0 0 50px rgba(224, 8, 0, 0.15), 0 40px 100px rgba(0, 0, 0, 0.7);
  }

  .close-btn {
    position: absolute;
    top: 1.5rem;
    right: 1.5rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 255, 255, 0.1);
    color: var(--text-secondary);
    width: 36px;
    height: 36px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    transition: all 0.3s;
  }

  .close-btn:hover {
    background: rgba(224, 8, 0, 0.2);
    border-color: var(--red);
    color: white;
    transform: rotate(90deg);
  }

  .modal-header {
    margin-bottom: 2rem;
  }

  .modal-header h2 {
    font-size: 1.8rem;
    font-weight: 800;
    margin-bottom: 0.5rem;
    letter-spacing: -0.03em;
  }

  .modal-header p {
    font-size: 0.9375rem;
  }

  .text-gradient {
    background: linear-gradient(135deg, #fff 30%, #94a3b8 100%);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
  }
</style>
