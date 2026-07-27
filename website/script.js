document.addEventListener("DOMContentLoaded", () => {
  // Random Gradient Background
  const bgGradient = document.getElementById("bg-gradient");
  function switchBackgroundGradient() {
    if (bgGradient) {
      const randomNum = Math.floor(Math.random() * 10); // 0-9
      bgGradient.style.backgroundImage = `url('assets/gradient/gradient${randomNum}.jpg')`;
    }
  }
  switchBackgroundGradient();
  const navItems = document.querySelectorAll(".nav-item[data-page]");
  const pages = document.querySelectorAll(".page");
  const searchInput = document.getElementById("atlas-search");
  const quickActionItems = document.querySelectorAll(".action-item");
  const officialPluginList = document.getElementById("official-plugin-list");
  const officialPluginCatalogUrl =
    "https://raw.githubusercontent.com/Far-Se/tabame/main/resources/plugins.json";

  // Page Switching Logic
  function switchPage(pageId, updateHash = true) {
    const targetNav = document.querySelector(
      `.nav-item[data-page="${pageId}"]`,
    );
    if (!targetNav) return;
    switchBackgroundGradient();

    // Update Title
    document.title = `Tabame | ${pageId.charAt(0).toUpperCase() + pageId.slice(1)}`;

    // Update Navigation
    navItems.forEach((nav) => {
      nav.classList.remove("active");
    });
    targetNav.classList.add("active");

    // Switch Page
    pages.forEach((page) => {
      page.classList.remove("active");
      if (page.id === `${pageId}-page`) {
        page.classList.add("active");
      }
    });

    // Update Hash
    if (updateHash) {
      window.location.hash = pageId;
    }
  }

  navItems.forEach((item) => {
    item.addEventListener("click", () => {
      const targetPage = item.getAttribute("data-page");
      switchPage(targetPage);
    });
  });

  // Handle Initial Load and Hash Change
  const handleHash = () => {
    const hash = window.location.hash.substring(1);
    if (hash) {
      switchPage(hash, false);
    } else {
      // Default page
      switchPage("preview", false);
    }
  };

  window.addEventListener("hashchange", handleHash);
  handleHash();

  // Functional Atlas Search
  if (searchInput) {
    searchInput.addEventListener("input", (e) => {
      const query = e.target.value.toLowerCase().trim();

      if (query === "") {
        resetSearch();
        return;
      }

      // If query starts with #, jump to page
      if (query.startsWith("#")) {
        const pageName = query.substring(1);
        const targetNav = document.querySelector(
          `.nav-item[data-page="${pageName}"]`,
        );
        if (targetNav) {
          targetNav.click();
          searchInput.value = "";
        }
        return;
      }

      // Search in QuickActions (on QuickMenu page)
      quickActionItems.forEach((item) => {
        const text = item.innerText.toLowerCase();
        const tags = (item.getAttribute("data-tags") || "").toLowerCase();
        if (text.includes(query) || tags.includes(query)) {
          item.style.display = "flex";
          // Ensure the parent details is open
          const details = item.closest("details");
          if (details) details.open = true;
        } else {
          item.style.display = "none";
        }
      });

      // Hide empty groups
      document.querySelectorAll(".atlas-group").forEach((group) => {
        const hasVisibleItems = Array.from(
          group.querySelectorAll(".action-item"),
        ).some((item) => item.style.display !== "none");
        group.style.display = hasVisibleItems ? "block" : "none";
      });
    });
  }

  function resetSearch() {
    quickActionItems.forEach((item) => {
      item.style.display = "flex";
    });
    document.querySelectorAll(".atlas-group").forEach((group) => {
      group.style.display = "block";
    });
  }

  function safeExternalUrl(value) {
    try {
      const url = new URL(value);
      return url.protocol === "https:" ? url.href : null;
    } catch {
      return null;
    }
  }

  function renderOfficialPlugins(plugins) {
    if (!officialPluginList) return;

    officialPluginList.replaceChildren();
    const fragment = document.createDocumentFragment();

    plugins.forEach((plugin) => {
      if (!plugin || typeof plugin.name !== "string") return;

      const homepage = safeExternalUrl(plugin.homepage);
      const item = document.createElement(homepage ? "a" : "article");
      item.className = "official-plugin";

      if (homepage) {
        item.href = homepage;
        item.target = "_blank";
        item.rel = "noreferrer";
      }

      const identity = document.createElement("div");
      identity.className = "official-plugin-identity";

      const icon = document.createElement("i");
      icon.className = "fa-solid fa-puzzle-piece";
      icon.setAttribute("aria-hidden", "true");

      const text = document.createElement("div");
      const name = document.createElement("h3");
      name.textContent = plugin.name;
      const description = document.createElement("p");
      description.textContent =
        plugin.description || "Official Tabame Launcher plugin.";
      text.append(name, description);
      identity.append(icon, text);

      const meta = document.createElement("div");
      meta.className = "official-plugin-meta";
      if (plugin.keyword) {
        const keyword = document.createElement("code");
        keyword.textContent = plugin.keyword;
        keyword.title = `Launcher keyword: ${plugin.keyword}`;
        meta.append(keyword);
      }
      if (plugin.runtime) {
        const runtime = document.createElement("span");
        runtime.textContent = plugin.runtime;
        meta.append(runtime);
      }
      if (homepage) {
        const external = document.createElement("i");
        external.className = "fa-solid fa-arrow-up-right-from-square";
        external.setAttribute("aria-label", `Open ${plugin.name} source`);
        meta.append(external);
      }

      item.append(identity, meta);
      fragment.append(item);
    });

    if (fragment.childNodes.length === 0) {
      officialPluginList.innerHTML =
        '<p class="catalog-status">No official plugins are available right now.</p>';
      return;
    }

    officialPluginList.append(fragment);
  }

  async function loadOfficialPlugins() {
    if (!officialPluginList) return;

    try {
      const response = await fetch(officialPluginCatalogUrl, {
        cache: "no-cache",
      });
      if (!response.ok)
        throw new Error(`Registry request failed: ${response.status}`);

      const catalog = await response.json();
      if (!Array.isArray(catalog.plugins))
        throw new Error("Invalid plugin registry");
      catalog.sort((a, b) => a.name.localeCompare(b.name));
      renderOfficialPlugins(catalog.plugins);
    } catch (error) {
      officialPluginList.innerHTML =
        '<p class="catalog-status catalog-status-error"><i class="fa-solid fa-triangle-exclamation"></i> The official plugin catalogue could not be loaded. Please try again later.</p>';
      console.warn("Unable to load official Tabame plugins.", error);
    }
  }

  loadOfficialPlugins();
});
