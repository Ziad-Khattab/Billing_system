

export const index = 5;
let component_cache;
export const component = async () => component_cache ??= (await import('../entries/pages/admin/contracts/_page.svelte.js')).default;
export const imports = ["_app/immutable/nodes/5.DKI9SIgn.js","_app/immutable/chunks/m3_Lzi_o.js","_app/immutable/chunks/CV7MmNJi.js","_app/immutable/chunks/BKtiSnKr.js","_app/immutable/chunks/dAu5spLh.js","_app/immutable/chunks/BBwEEXL4.js"];
export const stylesheets = [];
export const fonts = [];
