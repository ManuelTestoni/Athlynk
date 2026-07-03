/* Athlynk — shared CSRF token accessor.
   base.html emits <meta name="csrf-token" content="{{ csrf_token }}">; read that
   instead of re-parsing the csrftoken cookie in every module. */
window.csrfToken = function () {
  return document.querySelector('meta[name="csrf-token"]')?.content || '';
};
