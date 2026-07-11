(function () {
  const siteHeader = document.querySelector(".site-header");
  const compactHeaderQuery = window.matchMedia("(max-width: 680px)");
  const updateMobileHeader = () => {
    if (!siteHeader) return;
    siteHeader.classList.toggle(
      "is-mobile-compact",
      compactHeaderQuery.matches && window.scrollY > 72
    );
  };

  updateMobileHeader();
  window.addEventListener("scroll", updateMobileHeader, { passive: true });
  compactHeaderQuery.addEventListener?.("change", updateMobileHeader);
})();
