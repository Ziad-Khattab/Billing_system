

export const index = 2;
let component_cache;
export const component = async () => component_cache ??= (await import('../entries/pages/_page.svelte.js')).default;
export const imports = ["_app/immutable/nodes/2.DDRaXunC.js","_app/immutable/chunks/BtdNFNN8.js","_app/immutable/chunks/D9FQP20W.js"];
export const stylesheets = ["_app/immutable/assets/2.DEsQ2eZ8.css"];
export const fonts = [];
