const THEME_STYLE = `
	:root {
		--Bbsmc-usp-bg: #27292e;
		--Bbsmc-usp-surface: #34363c;
		--Bbsmc-usp-divider: #34363c;
		--Bbsmc-usp-text: #b0bac5;
		--Bbsmc-usp-contrast: #ffffff;
		--Bbsmc-usp-brand: #1bd96a;
		--Bbsmc-usp-link: #4f9cff;
		--Bbsmc-usp-accent-contrast: #000000;
		--Bbsmc-usp-shadow: rgba(0, 0, 0, 0.1) 0 4px 6px -1px,
			rgba(0, 0, 0, 0.06) 0 2px 4px -1px;
		color-scheme: dark;
	}

	#qc-cmp2-usp {
		outline: none !important;
		background: var(--Bbsmc-usp-bg) !important;
		border: 1px solid var(--Bbsmc-usp-divider) !important;
		border-radius: 1rem !important;
		box-shadow: var(--Bbsmc-usp-shadow) !important;
		color: var(--Bbsmc-usp-text) !important;
		font-family: Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Roboto,
			Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', sans-serif !important;
		max-width: 660px;
	}

	#qc-cmp2-usp .qc-usp-ui-content,
	#qc-cmp2-usp .qc-usp-ui-form-content,
	#qc-cmp2-usp .qc-usp-container {
		background: transparent !important;
	}

	#qc-cmp2-usp .qc-usp-container {
		margin-bottom: 12px;
	}

	#qc-cmp2-usp p,
	#qc-cmp2-usp label,
	#qc-cmp2-usp .qc-usp-action-description {
		color: var(--Bbsmc-usp-text) !important;
		font-family: inherit !important;
	}

	#qc-cmp2-usp .qc-usp-title,
	#qc-cmp2-usp .qc-cmp2-list-item-title {
		color: var(--Bbsmc-usp-contrast) !important;
		font-family: inherit !important;
		font-weight: 700 !important;
	}

	#qc-cmp2-usp .qc-usp-title {
		font-size: 1.25rem !important;
	}

	#qc-cmp2-usp a,
	#qc-cmp2-usp .qc-usp-alt-action {
		color: var(--Bbsmc-usp-link) !important;
	}

	#qc-cmp2-usp .qc-cmp2-list-item {
		background: var(--Bbsmc-usp-surface) !important;
		border: 1px solid var(--Bbsmc-usp-divider) !important;
		border-radius: 0.75rem !important;
	}

	#qc-cmp2-usp .qc-cmp2-list-item-header {
		background: transparent !important;
		border: 0 !important;
		color: var(--Bbsmc-usp-contrast) !important;
	}

	#qc-cmp2-usp .qc-cmp2-list-item-header svg {
		color: var(--Bbsmc-usp-text) !important;
	}

	#qc-cmp2-usp .qc-cmp2-toggle {
		background: var(--Bbsmc-usp-bg) !important;
		border-color: var(--Bbsmc-usp-divider) !important;
	}

	#qc-cmp2-usp .qc-cmp2-toggle .toggle {
		background: var(--Bbsmc-usp-contrast) !important;
	}

	#qc-cmp2-usp .qc-cmp2-toggle .text {
		color: var(--Bbsmc-usp-contrast) !important;
	}

	#qc-cmp2-usp .qc-cmp2-toggle[aria-checked='true'] {
		background: var(--Bbsmc-usp-brand) !important;
		border-color: var(--Bbsmc-usp-brand) !important;
	}

	#qc-cmp2-usp .qc-cmp2-toggle[aria-checked='true'] .text {
		color: var(--Bbsmc-usp-accent-contrast) !important;
	}

	#qc-cmp2-usp button[mode='primary'] {
		background: var(--Bbsmc-usp-brand) !important;
		border: 0 !important;
		border-radius: 0.75rem !important;
		color: var(--Bbsmc-usp-accent-contrast) !important;
		font-family: inherit !important;
		font-weight: 700 !important;
	}

	#qc-cmp2-usp .qc-usp-close-icon {
		border: 0 !important;
		background: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M18 6 6 18'/%3E%3Cpath d='m6 6 12 12'/%3E%3C/svg%3E")
			center / 1.5rem 1.5rem no-repeat;
	}

	#qc-cmp2-usp a:focus-visible,
	#qc-cmp2-usp button:focus-visible {
		outline: 2px solid var(--Bbsmc-usp-brand) !important;
		outline-offset: 2px !important;
	}

	#qc-cmp2-usp .qc-usp-ui-content {
		max-width: 100% !important;
	}

	#qc-cmp2-usp .qc-usp-ui-content .qc-usp-ui-form-content {
		border: 1px solid transparent !important;
		padding: 0 !important;
	}
`

const RAIL_STYLE = `
	html.Bbsmc-ads-consent-preferences #Bbsmc-rail-1 {
		display: none !important;
	}
`

const OVERLAY_STYLE = `
	html.Bbsmc-ads-consent-overlay:not(.Bbsmc-ads-consent-fallback):not(.Bbsmc-ads-consent-preferences) #qc-cmp2-main,
	html.Bbsmc-ads-consent-preferences:not(.Bbsmc-ads-consent-preferences-visible) #qc-cmp2-main {
		display: none !important;
	}

	#qc-cmp2-usp .qc-usp-close-icon {
		display: none !important;
	}
`

function installStyle(id, css) {
	if (document.getElementById(id)) return

	const style = document.createElement('style')
	style.id = id
	style.textContent = css
	document.documentElement.appendChild(style)
}

function installConsentStyles() {
	installStyle('Bbsmc-ads-consent-theme-style', THEME_STYLE)
	installStyle('Bbsmc-ads-rail-style', RAIL_STYLE)
	installStyle('Bbsmc-ads-consent-overlay-style', OVERLAY_STYLE)
}
