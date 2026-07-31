---
title: Symfony AI Agent Skills
description: Eight SKILL.md files and nine end-to-end recipes that package Symfony AI for Claude Code, Gemini CLI and Codex.
hide:
  - navigation
  - toc
home_page: true
---

<script>document.body.classList.add('home-page');</script>
<script>
(function() {
  if (!('IntersectionObserver' in window)) {
    document.querySelectorAll('.hero__orbit').forEach(function(el) { el.classList.add('in-view'); });
    return;
  }
  var obs = new IntersectionObserver(function(entries) {
    entries.forEach(function(e) {
      if (e.isIntersecting) {
        e.target.classList.add('in-view');
        obs.unobserve(e.target);
      }
    });
  }, { threshold: 0.2 });
  document.querySelectorAll('.hero__orbit').forEach(function(el) { obs.observe(el); });
})();
</script>
{% include "home.html" %}