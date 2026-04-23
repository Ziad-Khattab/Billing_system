<script>
	import './layout.css';
	import '../app.css';
	import { page } from '$app/stores';

	/** @type {{ children: import('svelte').Snippet }} */
	let { children } = $props();

	let user = $state(null);
	let navOpen = $state(false);

	async function checkAuth() {
		try {
			const res = await fetch('/api/auth/me', { credentials: 'include' });

			if (res.ok) user = await res.json(); else user = null;
		} catch {
			user = null;
		}
	}

	async function logout() {
		await fetch('/api/auth/logout', { method: 'POST', credentials: 'include' });
		user = null;
		window.location.href = '/';
	}

	$effect(() => {
		checkAuth();
	});
</script>

<div class="app">
	<nav class="navbar">
		<div class="nav-inner container">
			<a href="/" class="nav-brand"><img src="/eand_logo.svg" alt="e&" class="nav-logo" style="height: 40px;" /></a>

			<button
				class="nav-toggle"
				onclick={() => navOpen = !navOpen}
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
					class:active={$page.url.pathname === '/packages'}
				>Packages</a>

				{#if user && user.role === 'admin'}
					<a
						href="/admin"
						class="nav-link"
						class:active={$page.url.pathname === '/admin'}
					>Dashboard</a>

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
				{:else if user && user.role === 'customer'}
					<a
						href="/dashboard"
						class="nav-link"
						class:active={$page.url.pathname === '/dashboard'}
					>Dashboard</a>

					<a
						href="/dashboard/invoices"
						class="nav-link"
						class:active={$page.url.pathname.startsWith('/dashboard/invoices')}
					>Invoices</a>
				{/if}

				<div class="nav-spacer"></div>

				{#if user}
					<span class="nav-user">
						<span
							class="badge {user.role === 'admin' ? 'badge-admin' : 'badge-customer'}"
						>{user.role}</span>

						{user.fullName}
					</span>

					<button class="btn btn-ghost" onclick={logout}>Logout</button>
				{:else}
					<a href="/login" class="btn btn-ghost">Login</a>
					<a href="/register" class="btn btn-primary">Register</a>
				{/if}
			</div>
		</div>
	</nav>

	<main class="main-content">{@render children()}</main>
	<footer class="footer"><div class="container"><p>© 2026 FMRZ Telecom Billing — ITI Project</p></div></footer>
</div>

<style>
	.app {
		display: flex;
		flex-direction: column;
		min-height: 100vh;
	}

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
		color: var(--red-light);
		background: rgba(224, 8, 0, 0.12);
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
</style>
