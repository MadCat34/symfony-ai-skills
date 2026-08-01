---
title: Symfony AI Agent Skills
description: Eight SKILL.md files and nine end-to-end recipes that package Symfony AI for Claude Code, Gemini CLI and Codex.
hide:
  - navigation
  - toc
home_page: true
---

<script>document.body.classList.add('home-page');</script>
{% include "home.html" %}
<script>
(function() {
  function initReveal() {
    var targets = document.querySelectorAll('[data-reveal]');
    if (!targets.length) { return; }
    if (!('IntersectionObserver' in window)) {
      targets.forEach(function(el) { el.classList.add('is-visible'); });
      return;
    }
    var obs = new IntersectionObserver(function(entries) {
      entries.forEach(function(e) {
        if (e.isIntersecting) {
          e.target.classList.add('is-visible');
          obs.unobserve(e.target);
        }
      });
    }, { threshold: 0.2 });
    targets.forEach(function(el) { obs.observe(el); });
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initReveal);
  } else {
    initReveal();
  }
})();
</script>
