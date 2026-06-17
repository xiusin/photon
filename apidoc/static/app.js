// ═══════════════════════════════════════════════════════════════════════════
// app.js — Photon API Docs · Fluent UI Web Components Interaction Layer
//
// All interactions follow Fluent UI patterns:
// - Event delegation over inline handlers
// - fluent-dialog for confirmations (no alert/confirm)
// - Toast notifications for feedback
// - Semantic HTML + ARIA where applicable
// ═══════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════
// 1. STATE
// ═══════════════════════════════════════════════════════════════════════════

const state = {
  entries: [],
  activeId: null,
  searchTerm: '',
  pendingDeleteId: null,
  darkMode: false,
}

// ═══════════════════════════════════════════════════════════════════════════
// 2. ICONS — Fluent UI System Icons (16px)
// ═══════════════════════════════════════════════════════════════════════════

const Icons = {
  lock: `<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M8 1a3 3 0 0 0-3 3v2H4a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V7a1 1 0 0 0-1-1h-1V4a3 3 0 0 0-3-3zm2 5V4a2 2 0 1 0-4 0v2h4z"/></svg>`,
  unlock: `<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M8 1a3 3 0 0 0-3 3v1H4a1 1 0 0 0-1 1v7a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V6a1 1 0 0 0-1-1H6V4a2 2 0 1 1 4 0h1a3 3 0 0 0-3-3z"/></svg>`,
  trash: `<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M6.5 1a.5.5 0 0 0-.5.5V2H3a1 1 0 0 0 0 1h10a1 1 0 0 0 0-1h-3v-.5a.5.5 0 0 0-.5-.5h-3zM4.146 4l.812 9.063A1 1 0 0 0 5.95 14h4.1a1 1 0 0 0 .992-.937L11.854 4H4.146z"/></svg>`,
  chart: `<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M2 2v12h12V2H2zm1 1h10v10H3V3zm2 2v6h1V6H5zm3 1v4h1V7H8zm3 2v2h1V9h-1z"/></svg>`,
  clock: `<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1zm0 1a6 6 0 1 1 0 12A6 6 0 0 1 8 2zm-.5 2v4.5l3 2 .5-.87-2.5-1.63V4h-1z"/></svg>`,
  pin: `<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M9.828.722a.5.5 0 0 1 .354.146l4.95 4.95a.5.5 0 0 1-.707.707L9.828 1.88 7.293 4.415l3.182 3.182-1.414 1.414-3.182-3.182-2.828 2.829 3.182 3.182-1.414 1.414-3.182-3.182-.707.707a.5.5 0 0 1-.707 0l-.707-.707a.5.5 0 0 1 0-.707l.707-.708-1.414-1.414 1.414-1.414 1.414 1.414 2.829-2.828-1.414-1.414 1.414-1.414 1.414 1.414L9.122.722a.5.5 0 0 1 .706 0z"/></svg>`,
  package: `<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M8 1l7 4v6l-7 4-7-4V5l7-4zm0 1.15L2.5 5.38 8 8.15l5.5-2.77L8 2.15zM1.5 5.88v4.74L7.5 13.4V8.65L1.5 5.88zm7 7.52l6-2.78V5.88l-6 2.77v4.75z"/></svg>`,
  mail: `<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M2 3a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V4a1 1 0 0 0-1-1H2zm1 1h10l-5 4-5-4zm-1 .5v7l4-3.5L2 4.5zm6 3.5l4 3.5V4.5L8 8z"/></svg>`,
  attach: `<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M4.5 3a2.5 2.5 0 0 1 5 0v7a1.5 1.5 0 0 1-3 0V4a.5.5 0 0 1 1 0v6a.5.5 0 0 0 1 0V3a1.5 1.5 0 0 0-3 0v7a2.5 2.5 0 0 0 5 0V4"/></svg>`,
  chevronDown: `<svg class="group-chevron" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><polyline points="5 6 8 9 11 6"/></svg>`,
}

// ═══════════════════════════════════════════════════════════════════════════
// 3. INITIALIZATION
// ═══════════════════════════════════════════════════════════════════════════

document.addEventListener('DOMContentLoaded', () => {
  // Restore theme preference
  const savedTheme = localStorage.getItem('photon-apidoc-theme')
  if (savedTheme === 'dark') {
    state.darkMode = true
    document.documentElement.classList.add('dark')
  }

  // Bind search
  const searchInput = document.getElementById('searchInput')
  searchInput.addEventListener('input', (e) => {
    state.searchTerm = (e.target.value || '').toLowerCase()
    renderSidebar()
  })

  // Bind command bar buttons
  document.getElementById('refreshBtn').addEventListener('click', loadEntries)
  document.getElementById('exportBtn').addEventListener('click', exportOpenAPI)
  document.getElementById('emptyRefreshBtn').addEventListener('click', loadEntries)
  document.getElementById('themeToggleBtn').addEventListener('click', toggleTheme)

  // Bind delete dialog buttons
  document.getElementById('deleteCancelBtn').addEventListener('click', closeDeleteDialog)
  document.getElementById('deleteConfirmBtn').addEventListener('click', confirmDelete)

  // Delegate click events for dynamically rendered content
  document.getElementById('sidebarGroups').addEventListener('click', handleSidebarClick)
  document.getElementById('detailView').addEventListener('click', handleDetailClick)
  document.getElementById('detailView').addEventListener('focusout', handleDetailEdit)

  // Initial load
  loadEntries()
})

// ═══════════════════════════════════════════════════════════════════════════
// 4. API LAYER
// ═══════════════════════════════════════════════════════════════════════════

async function loadEntries() {
  try {
    const res = await fetch('/__docs/api/entries')
    const data = await res.json()
    state.entries = data.data || []
    renderSidebar()

    if (state.activeId) {
      const found = state.entries.find(e => e.id === state.activeId)
      if (found) {
        renderDetail(state.activeId)
      } else {
        state.activeId = null
        showEmpty()
      }
    } else if (state.entries.length > 0) {
      state.activeId = state.entries[0].id
      renderDetail(state.activeId)
      renderSidebar()
    } else {
      showEmpty()
    }
  } catch (err) {
    toast('加载失败: ' + err.message, 'error')
  }
}

async function updateEntry(id, changes) {
  try {
    const res = await fetch('/__docs/api/entries/' + encodeURIComponent(id), {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(changes),
    })
    const data = await res.json()
    if (data.code !== 0) throw new Error(data.msg || data.message || '未知错误')
    toast('已保存', 'success')
    await loadEntries()
  } catch (err) {
    toast('保存失败: ' + err.message, 'error')
  }
}

async function deleteEntryById(id) {
  try {
    const res = await fetch('/__docs/api/entries/' + encodeURIComponent(id), {
      method: 'DELETE',
    })
    const data = await res.json()
    if (data.code !== 0) throw new Error(data.msg || data.message || '未知错误')
    toast('已删除', 'success')
    if (state.activeId === id) {
      state.activeId = null
      showEmpty()
    }
    await loadEntries()
  } catch (err) {
    toast('删除失败: ' + err.message, 'error')
  }
}

async function exportOpenAPI() {
  try {
    const res = await fetch('/__docs/api/export')
    const text = await res.text()
    // Download as file
    const blob = new Blob([text], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'openapi.json'
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
    toast('OpenAPI 规范已导出', 'success')
  } catch (err) {
    toast('导出失败: ' + err.message, 'error')
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 5. SIDEBAR RENDERING
// ═══════════════════════════════════════════════════════════════════════════

function renderSidebar() {
  const container = document.getElementById('sidebarGroups')

  // Filter entries
  const filtered = state.searchTerm
    ? state.entries.filter(e =>
        e.path.toLowerCase().includes(state.searchTerm) ||
        e.method.toLowerCase().includes(state.searchTerm) ||
        (e.summary || '').toLowerCase().includes(state.searchTerm))
    : state.entries

  // Group by group name
  const groups = {}
  for (const e of filtered) {
    const g = e.group || 'default'
    if (!groups[g]) groups[g] = []
    groups[g].push(e)
  }

  if (Object.keys(groups).length === 0) {
    container.innerHTML = `<div class="empty-hint" style="padding:20px;text-align:center;">${
      state.searchTerm ? '无匹配结果' : '暂无数据'
    }</div>`
    return
  }

  let html = ''
  for (const [groupName, entries] of Object.entries(groups)) {
    html += `<div class="group-section" data-group="${escapeAttr(groupName)}">
      <div class="group-header" data-action="toggle-group">
        ${Icons.chevronDown}
        <span class="group-header-text">${escapeHtml(groupName)}</span>
        <span class="group-count-badge">${entries.length}</span>
      </div>
      <div class="group-routes">`

    for (const e of entries) {
      const isActive = e.id === state.activeId
      const lockIcon = e.locked
        ? `<span class="route-lock-icon locked">${Icons.lock}</span>`
        : `<span class="route-lock-icon">${Icons.lock}</span>`

      html += `<div class="route-item${isActive ? ' active' : ''}" data-action="select-route" data-route-id="${escapeAttr(e.id)}">
        <span class="method-badge ${e.method.toLowerCase()}">${e.method}</span>
        <span class="route-path">${escapeHtml(e.path)}</span>
        ${lockIcon}
      </div>`
    }

    html += '</div></div>'
  }

  container.innerHTML = html
}

// ═══════════════════════════════════════════════════════════════════════════
// 6. DETAIL RENDERING
// ═══════════════════════════════════════════════════════════════════════════

function renderDetail(id) {
  const entry = state.entries.find(e => e.id === id)
  if (!entry) { showEmpty(); return }

  document.getElementById('emptyState').style.display = 'none'
  const dv = document.getElementById('detailView')
  dv.style.display = 'block'

  // Update breadcrumb
  document.getElementById('breadcrumbCurrent').textContent = entry.summary || entry.path

  const lockIcon = entry.locked ? Icons.lock : Icons.unlock
  const lockBtnAppearance = entry.locked ? 'accent' : 'outline'
  const lockBtnLabel = entry.locked ? '解锁' : '锁定'

  let html = ''

  // ── Overview Card ──
  html += `<fluent-card class="overview-card">
    <div class="card-body">
      <div class="route-method-path">
        <span class="method-badge ${entry.method.toLowerCase()} big-badge">${entry.method}</span>
        <h2>${escapeHtml(entry.path)}</h2>
      </div>

      <div class="editable-field">
        <span class="field-label">摘要</span>
        <div class="field-value" contenteditable="true" data-field="summary" data-entry-id="${escapeAttr(entry.id)}">${escapeHtml(entry.summary || '')}</div>
      </div>

      <div class="editable-field">
        <span class="field-label">分组</span>
        <div class="field-value" contenteditable="true" data-field="group" data-entry-id="${escapeAttr(entry.id)}">${escapeHtml(entry.group || '')}</div>
      </div>

      <div class="route-info">
        <span class="route-info-item">${Icons.chart} 请求: <strong>${entry.hit_count || 0}</strong></span>
        <span class="route-info-item">${Icons.clock} 首次: <strong>${fmtTime(entry.first_seen)}</strong></span>
        <span class="route-info-item">${Icons.clock} 最近: <strong>${fmtTime(entry.last_seen)}</strong></span>
      </div>

      <div class="overview-actions">
        <fluent-button appearance="${lockBtnAppearance}" size="small" data-action="toggle-lock" data-entry-id="${escapeAttr(entry.id)}" title="${lockBtnLabel}">
          ${lockIcon} ${lockBtnLabel}
        </fluent-button>
        <fluent-button appearance="outline" size="small" data-action="delete-entry" data-entry-id="${escapeAttr(entry.id)}">
          ${Icons.trash} 删除
        </fluent-button>
      </div>
    </div>
  </fluent-card>`

  // ── Parameters Section ──
  const params = entry.parameters || []
  html += renderSectionCard(
    Icons.pin + ' 请求参数',
    params.length,
    params.length === 0
      ? '<div class="empty-hint">暂未捕获到参数</div>'
      : renderParamTable([
          { label: '名称',   render: p => `<span class="param-name">${escapeHtml(p.name)}</span>` },
          { label: '位置',   render: p => `<span class="param-type">${escapeHtml(p.location)}</span>` },
          { label: '类型',   render: p => `<span class="param-type">${escapeHtml(p.type || 'string')}</span>` },
          { label: '必需',   render: p => `<span class="param-required ${p.required ? 'yes' : 'no'}">${p.required ? '是' : '否'}</span>` },
          { label: '说明',   render: p => `<div class="param-desc"><input type="text" value="${escapeAttr(p.description || '')}" placeholder="..." data-action="edit-param-desc" data-entry-id="${escapeAttr(entry.id)}" data-param-location="${escapeAttr(p.location)}" data-param-name="${escapeAttr(p.name)}" /></div>` },
          { label: '示例',   render: p => `<span class="param-example">${escapeHtml(formatExamples(p.examples || p.example))}</span>` },
          { label: '',       render: p => `<span class="param-lock${p.locked ? ' locked' : ''}" data-action="toggle-param-lock" data-entry-id="${escapeAttr(entry.id)}" data-param-location="${escapeAttr(p.location)}" data-param-name="${escapeAttr(p.name)}">${p.locked ? Icons.lock : Icons.unlock}</span>` },
        ], params),
    params.length
  )

  // ── Headers Section ──
  const headers = entry.headers || []
  html += renderSectionCard(
    Icons.attach + ' 请求头',
    headers.length,
    headers.length === 0
      ? '<div class="empty-hint">仅显示非标准请求头</div>'
      : renderParamTable([
          { label: '名称', render: h => `<span class="param-name">${escapeHtml(h.name)}</span>` },
          { label: '示例', render: h => `<span class="param-example">${escapeHtml(h.value_sample || h.value || '-')}</span>` },
          { label: '',     render: h => `<span class="param-lock${h.locked ? ' locked' : ''}" data-action="toggle-header-lock" data-entry-id="${escapeAttr(entry.id)}" data-header-name="${escapeAttr(h.name)}">${h.locked ? Icons.lock : Icons.unlock}</span>` },
        ], headers),
    headers.length
  )

  // ── Request Body Section ──
  const reqBody = entry.request_body || {}
  const reqProps = reqBody.properties || {}
  const reqArr = Object.entries(reqProps)
  let reqHtml = ''
  if (reqArr.length > 0) {
    reqHtml += renderParamTable([
      { label: '属性', render: (_, k) => `<span class="param-name">${escapeHtml(k)}</span>` },
      { label: '类型', render: (_, k, p) => `<span class="param-type">${escapeHtml(p.type || p.type_ || 'string')}</span>` },
      { label: '说明', render: (_, k, p) => `<div class="param-desc"><input type="text" value="${escapeAttr(p.description || '')}" placeholder="..." /></div>` },
      { label: '示例', render: (_, k, p) => `<span class="param-example">${escapeHtml(formatExamples(p.examples || p.example))}</span>` },
    ], reqArr.map(([k, p]) => ({ name: k, ...p })))
  }
  if (reqBody.example) {
    reqHtml += `<pre class="json-block">${highlightJson(reqBody.example)}</pre>`
  }
  html += renderSectionCard(
    Icons.package + ' 请求体' + (reqBody.content_type ? ` (${reqBody.content_type})` : ''),
    reqArr.length + (reqBody.example ? 1 : 0),
    reqArr.length === 0 && !reqBody.example
      ? '<div class="empty-hint">无请求体数据</div>'
      : reqHtml,
    reqArr.length + (reqBody.example ? 1 : 0)
  )

  // ── Response Section ──
  const resp = entry.response || {}
  const respProps = resp.properties || []
  let respHtml = ''

  if (resp.status_code) {
    const sc = resp.status_code
    const badgeClass = sc < 300 ? 'success' : (sc < 500 ? 'warning' : 'error')
    respHtml += `<div style="padding:var(--space-sm) var(--space-lg);border-bottom:1px solid var(--stroke-subtle);">
      <span class="status-badge ${badgeClass}">${sc}</span>
    </div>`
  }

  if (respProps.length > 0) {
    respHtml += renderParamTable([
      { label: '路径', render: p => `<span class="param-name">${escapeHtml(p.path)}</span>` },
      { label: '类型', render: p => `<span class="param-type">${escapeHtml(p.type || p.type_ || 'string')}${p.nullable ? '?' : ''}</span>` },
      { label: '原始', render: p => `<span class="param-example">${escapeHtml(p.original_type || '')}</span>` },
      { label: '说明', render: p => `<div class="param-desc"><input type="text" value="${escapeAttr(p.description || '')}" placeholder="..." data-action="edit-resp-prop-desc" data-entry-id="${escapeAttr(entry.id)}" data-resp-path="${escapeAttr(p.path)}" /></div>` },
      { label: '示例', render: p => `<span class="param-example">${escapeHtml(formatExamples(p.examples || p.example))}</span>` },
      { label: '',     render: p => `<span class="param-lock${p.locked ? ' locked' : ''}" data-action="toggle-resp-prop-lock" data-entry-id="${escapeAttr(entry.id)}" data-resp-path="${escapeAttr(p.path)}">${p.locked ? Icons.lock : Icons.unlock}</span>` },
    ], respProps)
  }

  if (resp.body_sample) {
    let pretty = resp.body_sample
    try { pretty = JSON.stringify(JSON.parse(resp.body_sample), null, 2) } catch {}
    respHtml += `<pre class="json-block">${highlightJson(pretty)}</pre>`
  }

  html += renderSectionCard(
    Icons.mail + ' 响应',
    respProps.length + (resp.body_sample ? 1 : 0),
    respProps.length === 0 && !resp.body_sample
      ? '<div class="empty-hint">无响应数据</div>'
      : respHtml,
    respProps.length + (resp.body_sample ? 1 : 0)
  )

  dv.innerHTML = html
}

// ═══════════════════════════════════════════════════════════════════════════
// 7. COMPONENT BUILDERS
// ═══════════════════════════════════════════════════════════════════════════

function renderSectionCard(title, count, bodyHtml, totalCount) {
  const isCollapsed = totalCount === 0 ? ' collapsed' : ''
  return `<fluent-card class="section-card">
    <div class="section-header" data-action="toggle-section">
      <span class="section-header-title">${title}</span>
      <span class="section-header-count">${count}</span>
    </div>
    <div class="section-body${isCollapsed}">${bodyHtml}</div>
  </fluent-card>`
}

function renderParamTable(columns, rows) {
  let html = `<table class="param-table"><thead><tr>`
  for (const col of columns) {
    html += `<th>${col.label}</th>`
  }
  html += '</tr></thead><tbody>'

  for (const row of rows) {
    html += '<tr>'
    for (const col of columns) {
      // col.render can take (row, key, fullRow) depending on context
      const val = col.render(row, row.name, row)
      html += `<td>${val}</td>`
    }
    html += '</tr>'
  }

  html += '</tbody></table>'
  return html
}

// ═══════════════════════════════════════════════════════════════════════════
// 8. EVENT HANDLERS (Delegation Pattern)
// ═══════════════════════════════════════════════════════════════════════════

function handleSidebarClick(e) {
  // Group toggle
  const groupHeader = e.target.closest('[data-action="toggle-group"]')
  if (groupHeader) {
    const chevron = groupHeader.querySelector('.group-chevron')
    const routes = groupHeader.nextElementSibling
    chevron.classList.toggle('collapsed')
    routes.classList.toggle('collapsed')
    return
  }

  // Route select
  const routeItem = e.target.closest('[data-action="select-route"]')
  if (routeItem) {
    const id = routeItem.dataset.routeId
    state.activeId = id
    renderSidebar()
    renderDetail(id)
    return
  }
}

function handleDetailClick(e) {
  const target = e.target.closest('[data-action]')
  if (!target) return

  const action = target.dataset.action

  switch (action) {
    case 'toggle-lock': {
      const id = target.dataset.entryId
      const entry = state.entries.find(x => x.id === id)
      if (entry) updateEntry(id, { locked: !entry.locked })
      break
    }
    case 'delete-entry': {
      const id = target.dataset.entryId
      openDeleteDialog(id)
      break
    }
    case 'toggle-section': {
      const body = target.nextElementSibling
      if (body) body.classList.toggle('collapsed')
      break
    }
    case 'toggle-param-lock': {
      const id = target.dataset.entryId
      const location = target.dataset.paramLocation
      const name = target.dataset.paramName
      updateEntry(id, { toggleParamLock: { location, name } })
      break
    }
    case 'toggle-header-lock': {
      const id = target.dataset.entryId
      const name = target.dataset.headerName
      updateEntry(id, { toggleHeaderLock: { name } })
      break
    }
    case 'toggle-resp-prop-lock': {
      const id = target.dataset.entryId
      const path = target.dataset.respPath
      updateEntry(id, { toggleRespPropLock: { path } })
      break
    }
  }
}

function handleDetailEdit(e) {
  const target = e.target.closest('[data-field]')
  if (!target) return

  const field = target.dataset.field
  const entryId = target.dataset.entryId
  const value = target.textContent.trim()

  if (field === 'summary') {
    updateEntry(entryId, { summary: value })
  } else if (field === 'group') {
    updateEntry(entryId, { group: value })
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 9. DELETE DIALOG (Fluent UI Dialog — no confirm())
// ═══════════════════════════════════════════════════════════════════════════

function openDeleteDialog(id) {
  state.pendingDeleteId = id
  const dialog = document.getElementById('deleteDialog')
  if (dialog && dialog.showModal) {
    dialog.showModal()
  }
}

function closeDeleteDialog() {
  state.pendingDeleteId = null
  const dialog = document.getElementById('deleteDialog')
  if (dialog && dialog.close) {
    dialog.close()
  }
}

function confirmDelete() {
  const id = state.pendingDeleteId
  closeDeleteDialog()
  if (id) {
    deleteEntryById(id)
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 10. THEME TOGGLE
// ═══════════════════════════════════════════════════════════════════════════

function toggleTheme() {
  state.darkMode = !state.darkMode
  document.documentElement.classList.toggle('dark', state.darkMode)
  localStorage.setItem('photon-apidoc-theme', state.darkMode ? 'dark' : 'light')
}

// ═══════════════════════════════════════════════════════════════════════════
// 11. EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════════

function showEmpty() {
  document.getElementById('emptyState').style.display = 'flex'
  document.getElementById('detailView').style.display = 'none'
  document.getElementById('breadcrumbCurrent').textContent = ''
}

// ═══════════════════════════════════════════════════════════════════════════
// 12. TOAST NOTIFICATION (Fluent UI Notification Bar)
// ═══════════════════════════════════════════════════════════════════════════

function toast(msg, type = 'info') {
  const container = document.getElementById('toastProvider')
  const el = document.createElement('div')
  el.className = 'toast ' + type
  el.textContent = msg
  container.appendChild(el)

  setTimeout(() => {
    el.style.opacity = '0'
    el.style.transition = 'opacity 150ms ease'
    setTimeout(() => el.remove(), 150)
  }, 3000)
}

// ═══════════════════════════════════════════════════════════════════════════
// 13. JSON SYNTAX HIGHLIGHTING
// ═══════════════════════════════════════════════════════════════════════════

function highlightJson(str) {
  if (!str) return ''
  const escaped = str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')

  let result = ''
  let i = 0
  while (i < escaped.length) {
    const ch = escaped[i]
    if (ch === '"') {
      let j = i + 1, strContent = '"'
      while (j < escaped.length) {
        const c = escaped[j]
        strContent += c
        if (c === '\\' && j + 1 < escaped.length) {
          strContent += escaped[j + 1]
          j += 2
          continue
        }
        if (c === '"') { j++; break }
        j++
      }
      const raw = strContent
      let ahead = escaped.slice(j).trimStart()
      if (ahead.startsWith(':')) {
        result += '<span class="jk">' + raw + '</span>'
      } else {
        result += '<span class="js">' + raw + '</span>'
      }
      i = j
    } else if (ch === '-' || (ch >= '0' && ch <= '9')) {
      let j = i
      while (j < escaped.length && (escaped[j] === '-' || escaped[j] === '.' || (escaped[j] >= '0' && escaped[j] <= '9') || escaped[j] === 'e' || escaped[j] === 'E' || escaped[j] === '+')) j++
      result += '<span class="jn">' + escaped.slice(i, j) + '</span>'
      i = j
    } else if (escaped.slice(i, i + 4) === 'true') {
      result += '<span class="jb">true</span>'; i += 4
    } else if (escaped.slice(i, i + 5) === 'false') {
      result += '<span class="jb">false</span>'; i += 5
    } else if (escaped.slice(i, i + 4) === 'null') {
      result += '<span class="jnull">null</span>'; i += 4
    } else {
      result += ch; i++
    }
  }
  return result
}

// ═══════════════════════════════════════════════════════════════════════════
// 14. UTILITIES
// ═══════════════════════════════════════════════════════════════════════════

function escapeHtml(str) {
  if (!str) return ''
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function escapeAttr(str) {
  if (!str) return ''
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

function fmtTime(ts) {
  if (!ts || ts === 0) return '-'
  return new Date(ts).toLocaleString('zh-CN', { hour12: false })
}

function formatExamples(examples) {
  if (!examples) return '-'
  if (Array.isArray(examples)) return examples.join(', ') || '-'
  return String(examples)
}
