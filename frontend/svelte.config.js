import adapter from '@sveltejs/adapter-static';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	kit: {
		// adapter-static will generate a pure HTML/JS build
		adapter: adapter({
			pages: '../src/main/webapp',
			assets: '../src/main/webapp',
			fallback: 'index.html', // Enable SPA mode
			precompress: false,
			strict: true
		}),
		paths: {
			base: ""
		}
	}
};

export default config;
