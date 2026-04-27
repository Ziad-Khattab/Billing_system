export const toastState = $state({
    message: null,
    type: 'success'
});

export function showToast(message, type = 'success') {
    toastState.message = message;
    toastState.type = type;
}

export function hideToast() {
    toastState.message = null;
}
