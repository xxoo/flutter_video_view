{{flutter_js}}
{{flutter_build_config}}
visualViewport.onresize = () => {
	if (Math.round(visualViewport.width) !== 450) {
		document.querySelector('meta[name="viewport"]').content = `user-scalable=no, width=450`;
	}
};
_flutter.loader.load({
	serviceWorkerSettings: {
		serviceWorkerVersion: {{flutter_service_worker_version}}
	},
	config: {
		hostElement: document.body
	}
});