// Fit the embedded CVMFS usage dashboard to its content. The dashboard
// (neurodesk/cvmfs-infrastructure) posts its height whenever it changes.
(function () {
  var ORIGIN = 'https://neurodesk.github.io';
  window.addEventListener('message', function (event) {
    if (event.origin !== ORIGIN) return;
    var d = event.data;
    if (!d || d.type !== 'cvmfs-dashboard:height' || !Number.isFinite(d.height)) return;
    var frame = document.getElementById('cvmfs-dashboard');
    if (!frame || event.source !== frame.contentWindow) return;
    // +2 for the frame's 1px top and bottom border (border-box sizing).
    frame.style.height = Math.ceil(Math.min(Math.max(d.height, 400), 20000)) + 2 + 'px';
  });
})();
