<script>
	import '../app.css';
	import { page } from '$app/stores';
	import Toast from '$lib/components/Toast.svelte';
	import { authState, checkAuth, logout } from '$lib/auth.svelte.js';
	import { toastState, hideToast } from '$lib/toast.svelte.js';

	/** @type {{ children: import('svelte').Snippet }} */
	let { children } = $props();

	let navOpen = $state(false);

	$effect(() => {
		checkAuth();
	});

	// Global Security Guard
	$effect(() => {
		if (authState.initialized && $page.url.pathname.startsWith('/admin')) {
			if (!authState.user || authState.user.role !== 'admin') {
				window.location.href = `/login?returnTo=${$page.url.pathname}`;
			}
		}
	});
</script>

<div class="app">
	<nav class="navbar">
		<div class="nav-inner container">
			<a href="/" class="nav-brand" aria-label="Home">
				<img src="/red-logo.png" alt="FMRZ" class="nav-logo" style="height: 40px;" />
			</a>

			<button
				class="nav-toggle"
				onclick={() => navOpen = !navOpen}
				aria-label={navOpen ? 'Close navigation' : 'Open navigation'}
				aria-expanded={navOpen}
			><span></span><span></span><span></span></button>

			<div class="nav-links" class:open={navOpen}>
				<a
					href="/"
					class="nav-link"
					class:active={$page.url.pathname === '/'}
				>Home</a>

				<a
					href="/packages"
					class="nav-link"
					class:active={$page.url.pathname.startsWith('/packages')}
				>Packages</a>

				{#if authState.user && authState.user.role === 'admin'}
					<a
						href="/admin"
						class="nav-link"
						class:active={$page.url.pathname === '/admin'}
					>Admin Panel</a>

					<a
						href="/admin/customers"
						class="nav-link"
						class:active={$page.url.pathname.startsWith('/admin/customers')}
					>Customers</a>

					<a
						href="/admin/contracts"
						class="nav-link"
						class:active={$page.url.pathname.startsWith('/admin/contracts')}
					>Contracts</a>

					<a
						href="/admin/billing"
						class="nav-link"
						class:active={$page.url.pathname.startsWith('/admin/billing')}
					>Billing</a>
				{:else if authState.user && authState.user.role === 'customer'}
					<a
						href="/profile"
						class="nav-link"
						class:active={$page.url.pathname === '/profile' || ($page.url.pathname.startsWith('/profile') && !$page.url.pathname.includes('/invoices'))}
					>Profile</a>

					<a
						href="/profile/invoices"
						class="nav-link"
						class:active={$page.url.pathname.startsWith('/profile/invoices')}
					>My Invoices</a>
				{/if}

				<div class="nav-spacer"></div>

				{#if authState.user}
					<button class="btn btn-ghost" onclick={logout} style="margin-right: 0.5rem;">Logout</button>
					
					<span class="nav-user">
						<span
							class="badge {authState.user.role === 'admin' ? 'badge-admin' : 'badge-customer'}"
						>{authState.user.role}</span>

						{authState.user.name || authState.user.username}
					</span>
				{:else}
					<a href="/login" class="btn btn-ghost">Login</a>
					<a href="/register" class="btn btn-primary">Register</a>
				{/if}
			</div>
		</div>
	</nav>

	<main class="main-content">
		{#if $page.url.pathname.startsWith('/admin') && !authState.initialized}
			<div class="verify-screen">
				<div class="spinner"></div>
				<p>Verifying Security Credentials...</p>
			</div>
		{:else}
			{@render children()}
		{/if}
	</main>
	<footer class="footer"><div class="container"><p>© 2026 FMRZ Telecom Billing — ITI Project</p></div></footer>

	{#if toastState.message}
		<Toast 
			message={toastState.message} 
			type={toastState.type} 
			onclose={hideToast}
		/>
	{/if}
</div>

<style>
	.navbar {
		position: sticky;
		top: 0;
		z-index: 100;
		background: rgba(10, 10, 15, 0.85);
		backdrop-filter: blur(20px);
		-webkit-backdrop-filter: blur(20px);
		border-bottom: 1px solid var(--border);
	}

	.nav-inner {
		display: flex;
		align-items: center;
		height: 64px;
		gap: 1rem;
	}

	.nav-brand {
		display: flex;
		align-items: center;
	}

	.nav-logo {
		height: 44px;
		width: auto;
	}

	.nav-links {
		display: flex;
		align-items: center;
		gap: 0.25rem;
		flex: 1;
	}

	.nav-link {
		padding: 0.5rem 1rem;
		border-radius: var(--radius-sm);
		font-size: 0.9375rem;
		font-weight: 600;
		letter-spacing: -0.01em;
		color: var(--text-secondary);
		transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1);
	}

	.nav-link:hover {
		color: var(--text-primary);
		background: rgba(255, 255, 255, 0.05);
		transform: translateY(-1px);
	}

	.nav-link.active {
		color: #f59e0b; /* Premium Gold */
		background: rgba(245, 158, 11, 0.12);
	}

	.nav-spacer {
		flex: 1;
	}

	.nav-user {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		font-size: 0.85rem;
		color: var(--text-secondary);
		margin-right: 0.5rem;
	}

	.nav-toggle {
		display: none;
		flex-direction: column;
		gap: 4px;
		background: none;
		border: none;
		cursor: pointer;
		padding: 0.5rem;
	}

	.nav-toggle span {
		width: 20px;
		height: 2px;
		background: var(--text-secondary);
		border-radius: 1px;
		transition: all 0.3s;
	}

	.main-content {
		flex: 1;
		padding: 2rem 0;
	}

	.footer {
		border-top: 1px solid var(--border);
		padding: 1.5rem 0;
		text-align: center;
		font-size: 0.8rem;
		color: var(--text-muted);
	}

	@media (max-width: 768px) {
		.nav-toggle {
			display: flex;
		}
		.nav-links {
			display: none;
			position: absolute;
			top: 64px;
			left: 0;
			right: 0;
			flex-direction: column;
			background: var(--bg-secondary);
			padding: 1rem;
			border-bottom: 1px solid var(--border);
		}
		.nav-links.open {
			display: flex;
		}
		.nav-spacer {
			display: none;
		}
	}
	.verify-screen {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		min-height: 60vh;
		gap: 1.5rem;
		color: var(--text-secondary);
	}
	.spinner {
		width: 40px;
		height: 40px;
		border: 3px solid rgba(255, 255, 255, 0.05);
		border-top-color: var(--red);
		border-radius: 50%;
		animation: spin 1s linear infinite;
	}
	@keyframes spin { to { transform: rotate(360deg); } }
</style>
