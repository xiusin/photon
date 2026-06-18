// ═══════════════════════════════════════════════════════════
// Photon Docs — Alpine.js SPA Router
// Single Page Application: click nav → fetch fragment → inject
// Supports: hash routing, browser back/forward, page caching
// ═══════════════════════════════════════════════════════════

function photonApp() {
  return {
    // ── Theme ──
    theme: localStorage.getItem('photon-theme') || 'dark',
    toggleTheme() {
      // Add transition class for smooth theme change
      document.documentElement.classList.add('theme-transition');
      this.theme = this.theme === 'dark' ? 'light' : 'dark';
      localStorage.setItem('photon-theme', this.theme);
      // Remove transition class after animation completes
      setTimeout(() => {
        document.documentElement.classList.remove('theme-transition');
      }, 400);
    },
    get themeIcon() { return this.theme === 'dark' ? '☀️' : '🌙'; },

    // ── Mobile sidebar ──
    sidebarOpen: false,

    // ── SPA Router state ──
    currentPage: '',
    pageContent: '',
    pageBreadcrumb: '',
    pageTitle: 'Photon Framework',
    loading: false,
    pageTransition: 'idle', // 'enter' | 'leave' | 'idle'
    pageCache: {},     // fetched fragment cache
    _initialized: false,
    _pendingPage: null, // page waiting for transition to complete

    // ── Navigation definition ──
    navSections: [
      { title: '快速开始', items: [
        { label: '概览', page: 'index', icon: '🏠', badge: '' },
      ]},
      { title: '核心模块', items: [
        { label: 'Core · 核心容器', page: 'core', icon: '⚡', badge: 'GA' },
        { label: 'Config · 配置管理', page: 'config', icon: '⚙️', badge: 'GA' },
        { label: 'Web · Web框架', page: 'web', icon: '🌐', badge: 'GA' },
        { label: 'ORM · 对象映射', page: 'orm', icon: '🗄️', badge: 'Beta' },
      ]},
      { title: '中间件', items: [
        { label: 'Cache · 缓存', page: 'cache', icon: '💨', badge: 'GA' },
        { label: 'Lock · 分布式锁', page: 'lock', icon: '🔒', badge: 'GA' },
        { label: 'Pool · 连接池', page: 'pool', icon: '🏊', badge: 'GA' },
        { label: 'Logger · 日志', page: 'logger', icon: '📋', badge: 'GA' },
        { label: 'Queue · 消息队列', page: 'queue', icon: '📨', badge: 'Beta' },
        { label: 'Security · 安全', page: 'security', icon: '🛡️', badge: 'GA' },
      ]},
      { title: '扩展', items: [
        { label: 'Mailer · 邮件', page: 'mailer', icon: '📧', badge: 'Beta' },
        { label: 'Storage · 存储', page: 'storage', icon: '💾', badge: 'Beta' },
        { label: 'CLI · 命令行', page: 'cli', icon: '⌨️', badge: 'Alpha' },
      ]},
      { title: '指南', items: [
        { label: '框架对比', page: 'comparison', icon: '📊', badge: '' },
        { label: '生产实践', page: 'production', icon: '🚀', badge: '' },
        { label: '文档宪法', page: 'constitution', icon: '📜', badge: '' },
      ]},
    ],

    // ── Badge CSS class ──
    badgeClass(badge) {
      if (badge === 'GA') return 'nav-badge-ga';
      if (badge === 'Beta') return 'nav-badge-beta';
      if (badge === 'Alpha') return 'nav-badge-alpha';
      return '';
    },

    // ── Is nav item active? ──
    isActive(page) {
      return this.currentPage === page;
    },

    // ── Navigate to page (SPA) ──
    navigateTo(page, pushState = true) {
      if (!page) page = 'index';
      if (this.currentPage === page && this.pageContent) return;

      this.currentPage = page;
      this.sidebarOpen = false;

      // Store pushState intent for later
      this._pendingPushState = pushState;

      // If this is the first load, skip transition
      if (!this.pageContent) {
        this._loadPage(page);
        return;
      }

      // Start leave transition: fade out current content
      this._pendingPage = page;
      // Reset to idle first to ensure animation restarts cleanly
      // (e.g. if an enter animation is still playing)
      this.pageTransition = 'idle';
      requestAnimationFrame(() => {
        this.pageTransition = 'leave';
      });
    },

    // ── Load page content (after leave transition or first load) ──
    _loadPage(page) {
      this.loading = true;

      // Check cache first
      if (this.pageCache[page]) {
        this._applyPage(this.pageCache[page]);
        this.loading = false;
        if (this._pendingPushState) history.pushState({ page }, '', '#' + page);
        return;
      }

      // Fetch the page fragment
      fetch('pages/' + page + '.html')
        .then(r => {
          if (!r.ok) throw new Error('Not found: ' + page);
          return r.text();
        })
        .then(html => {
          this.pageCache[page] = html;
          this._applyPage(html);
          this.loading = false;
          if (this._pendingPushState) history.pushState({ page }, '', '#' + page);
        })
        .catch(() => {
          this.pageContent = '<div class="hero"><h1>404</h1><p>页面未找到</p></div>';
          this.pageBreadcrumb = '<a href="#index">Photon</a><span class="sep">/</span>404';
          this.pageTitle = '404 — Photon Framework';
          this.loading = false;
          if (this._pendingPushState) history.pushState({ page: '404' }, '', '#' + page);
        });
    },

    // ── Called after leave animation ends ──
    _onLeaveEnd() {
      if (this._pendingPage) {
        const page = this._pendingPage;
        this._pendingPage = null;
        this._loadPage(page);
      }
    },

    // ── Called after enter animation ends ──
    _onEnterEnd() {
      this.pageTransition = 'idle';
    },

    // Parse fragment and apply to view
    _applyPage(html) {
      const titleMatch = html.match(/<!-- title: (.+?) -->/);
      const breadcrumbMatch = html.match(/<!-- breadcrumb: (.+?) -->/);

      let content = html
        .replace(/<!-- title: .+? -->\n?/g, '')
        .replace(/<!-- breadcrumb: .+? -->\n?/g, '');

      this.pageContent = content;
      this.pageBreadcrumb = breadcrumbMatch ? breadcrumbMatch[1] : '<a href="#index">Photon</a>';
      this.pageTitle = titleMatch ? titleMatch[1] : 'Photon Framework';
      document.title = this.pageTitle;

      // Trigger enter transition (use rAF to ensure DOM has updated)
      this.pageTransition = 'idle';
      requestAnimationFrame(() => {
        this.pageTransition = 'enter';
      });

      this.$nextTick(() => {
        // Scroll main content area to top
        const main = document.querySelector('.main-content');
        if (main) main.scrollTop = 0;
        window.scrollTo(0, 0);

        // Intercept all internal hash links inside page content
        const pageBody = document.querySelector('.page-body');
        if (pageBody) {
          pageBody.querySelectorAll('a[href^="#"]').forEach(link => {
            link.removeEventListener('click', this._handleLinkClick);
            link.addEventListener('click', this._handleLinkClick.bind(this));
          });
        }
      });
    },

    // Intercept clicks on hash links within page content
    _handleLinkClick(e) {
      const href = e.currentTarget.getAttribute('href');
      if (href && href.startsWith('#')) {
        const page = href.slice(1);
        if (page && page !== this.currentPage) {
          e.preventDefault();
          this.navigateTo(page);
        }
      }
    },

    // Parse page name from URL hash
    _pageFromHash() {
      return window.location.hash.slice(1) || '';
    },

    // ── Handle browser back/forward ──
    // Both popstate and hashchange cover all browsers
    _onHashChange() {
      const page = this._pageFromHash() || 'index';
      if (page !== this.currentPage) {
        this.navigateTo(page, false);
      }
    },

    // ── Copy code ──
    copyCode(el) {
      const code = el.closest('.code-block').querySelector('.code-body').textContent;
      navigator.clipboard.writeText(code).then(() => {
        el.textContent = '✓ 已复制';
        setTimeout(() => { el.textContent = '复制'; }, 1500);
      });
    },

    // ── Init ──
    init() {
      if (this._initialized) return;
      this._initialized = true;

      // Listen for hash changes (browser back/forward + hash links)
      window.addEventListener('hashchange', () => this._onHashChange());

      // Load initial page from hash or default to index
      const page = this._pageFromHash() || 'index';
      this.navigateTo(page, false);
      history.replaceState({ page }, '', '#' + page);
    },
  };
}
