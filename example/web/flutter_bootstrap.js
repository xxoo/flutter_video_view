{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load({
	serviceWorkerSettings: {
		serviceWorkerVersion: {{flutter_service_worker_version}}
	},
	config: {
		hostElement: document.body
	}
});