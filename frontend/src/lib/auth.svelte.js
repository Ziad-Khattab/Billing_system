export const authState = $state({
    user: null,
    initialized: false
});

export async function checkAuth() {
    try {
        const res = await fetch('/api/auth/me', { credentials: 'include' });
        if (res.ok) {
            authState.user = await res.json();
        } else {
            authState.user = null;
        }
    } catch (e) {
        authState.user = null;
    } finally {
        authState.initialized = true;
    }
}

export async function logout() {
    await fetch('/api/auth/logout', { method: 'POST', credentials: 'include' });
    authState.user = null;
    window.location.href = '/';
}
