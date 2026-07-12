(function () {
  const siteHeader = document.querySelector(".site-header");
  const compactHeaderQuery = window.matchMedia("(max-width: 680px)");
  let isCompact = false;
  let ticking = false;

  const updateMobileHeader = () => {
    if (!siteHeader) return;
    const shouldCompact = compactHeaderQuery.matches && window.scrollY > (isCompact ? 36 : 72);
    if (shouldCompact !== isCompact) {
      isCompact = shouldCompact;
      siteHeader.classList.toggle("is-mobile-compact", isCompact);
    }
    ticking = false;
  };

  const requestHeaderUpdate = () => {
    if (ticking) return;
    ticking = true;
    window.requestAnimationFrame(updateMobileHeader);
  };

  updateMobileHeader();
  window.addEventListener("scroll", requestHeaderUpdate, { passive: true });
  compactHeaderQuery.addEventListener?.("change", requestHeaderUpdate);
})();
