// Mobile menu toggle
(function () {
  var btn = document.querySelector('.menu-toggle');
  var nav = document.getElementById('main-nav');
  if (!btn || !nav) return;
  btn.addEventListener('click', function () {
    var open = nav.classList.toggle('open');
    btn.setAttribute('aria-expanded', open ? 'true' : 'false');
  });
})();
