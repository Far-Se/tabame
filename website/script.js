document.addEventListener('DOMContentLoaded', () => {
    // Random Gradient Background
    const bgGradient = document.getElementById('bg-gradient');
    function switchBackgroundGradient() {
        if (bgGradient) {
            const randomNum = Math.floor(Math.random() * 10); // 0-9
            bgGradient.style.backgroundImage = `url('assets/gradient/gradient${randomNum}.jpg')`;
        }
    }
    switchBackgroundGradient();
    const navItems = document.querySelectorAll('.nav-item[data-page]');
    const pages = document.querySelectorAll('.page');
    const searchInput = document.getElementById('atlas-search');
    const quickActionItems = document.querySelectorAll('.action-item');

    // Page Switching Logic
    function switchPage(pageId, updateHash = true) {
        const targetNav = document.querySelector(`.nav-item[data-page="${pageId}"]`);
        if (!targetNav) return;
        switchBackgroundGradient();

        // Update Title
        document.title = `Tabame | ${pageId.charAt(0).toUpperCase() + pageId.slice(1)}`;

        // Update Navigation
        navItems.forEach(nav => nav.classList.remove('active'));
        targetNav.classList.add('active');

        // Switch Page
        pages.forEach(page => {
            page.classList.remove('active');
            if (page.id === `${pageId}-page`) {
                page.classList.add('active');
            }
        });

        // Update Hash
        if (updateHash) {
            window.location.hash = pageId;
        }
    }

    navItems.forEach(item => {
        item.addEventListener('click', () => {
            const targetPage = item.getAttribute('data-page');
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
            switchPage('quickmenu', false);
        }
    };

    window.addEventListener('hashchange', handleHash);
    handleHash();

    // Functional Atlas Search
    if (searchInput) {
        searchInput.addEventListener('input', (e) => {
            const query = e.target.value.toLowerCase().trim();

            if (query === '') {
                resetSearch();
                return;
            }

            // If query starts with #, jump to page
            if (query.startsWith('#')) {
                const pageName = query.substring(1);
                const targetNav = document.querySelector(`.nav-item[data-page="${pageName}"]`);
                if (targetNav) {
                    targetNav.click();
                    searchInput.value = '';
                }
                return;
            }

            // Search in QuickActions (on QuickMenu page)
            quickActionItems.forEach(item => {
                const text = item.innerText.toLowerCase();
                const tags = (item.getAttribute('data-tags') || '').toLowerCase();
                if (text.includes(query) || tags.includes(query)) {
                    item.style.display = 'flex';
                    // Ensure the parent details is open
                    const details = item.closest('details');
                    if (details) details.open = true;
                } else {
                    item.style.display = 'none';
                }
            });

            // Hide empty groups
            document.querySelectorAll('.atlas-group').forEach(group => {
                const hasVisibleItems = Array.from(group.querySelectorAll('.action-item'))
                    .some(item => item.style.display !== 'none');
                group.style.display = hasVisibleItems ? 'block' : 'none';
            });
        });
    }

    function resetSearch() {
        quickActionItems.forEach(item => item.style.display = 'flex');
        document.querySelectorAll('.atlas-group').forEach(group => group.style.display = 'block');
    }
});
