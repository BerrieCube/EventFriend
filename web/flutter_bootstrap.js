{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load();

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("offline_sw.js").catch((e) => console.warn("Offline-modus niet beschikbaar", e));
  });
}
