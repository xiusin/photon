// app.js — Photon API 文档前端
// 纯 Vanilla JS，Fluent UI Web Components 风格
// 功能：侧边栏分组、搜索、详情编辑、锁定、导出

// ══════════════════════════════════════
// State
// ══════════════════════════════════════

let allEntries = []
let activeId = null
let searchTerm = ''

// ══════════════════════════════════════
// Initialization
// ══════════════════════════════════════

document.addEventListener('DOMContentLoaded', () => {
  loadEntries()
  const searchEl = document.getElementById('searchInput')
  searchEl.addEventListener('input', (e) => {
    searchTerm = (e.target.value || e.detail?.value || '').toLowerCase()
    renderSidebar()
  })
})

// ══════════════════════════════════════
// API Calls
// ══════════════════════════════════════

async function loadEntries() {
  try {
    const res = await fetch('/__docs/api/entries')
    const data = await res.json()
    allEntries = data.data || []
    renderSidebar()
    if (activeId) {
      const stillExists = allEntries.find(e => e.id === activeId)
      if (stillExists) renderDetail(activeId)
      else { activeId = null; showEmpty() }
    } else if (allEntries.length > 0) {
      activeId = allEntries[0].id
      renderDetail(activeId)
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
      body: JSON.stringify(changes)
    })
    const data = await res.json()
    if (data.code !== 0) throw new Error(data.message)
    toast('保存成功', 'success')
    await loadEntries()
  } catch (err) {
    toast('保存失败: ' + err.message, 'error')
  }
}

async function deleteEntry(id) {
  if (!confirm('确认删除此条目?')) return
  try {
    const res = await fetch('/__docs/api/entries/' + encodeURIComponent(id), {
      method: 'DELETE'
    })
    const data = await res.json()
    if (data.code !== 0) throw new Error(data.message)
    toast('已删除', 'success')
    if (activeId === id) { activeId = null; showEmpty() }
    await loadEntries()
  } catch (err) {
    toast('删除失败: ' + err.message, 'error')
  }
}

// ══════════════════════════════════════
// SVG Icon helpers (no emoji)
// ══════════════════════════════════════

const ICONS = {
  lock: '<svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14"><path d="M8 1a3 3 0 0 0-3 3v2H4a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V7a1 1 0 0 0-1-1h-1V4a3 3 0 0 0-3-3zm2 5V4a2 2 0 1 0-4 0v2h4z"/></svg>',
  unlock: '<svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14"><path d="M8 1a3 3 0 0 0-3 3v1H4a1 1 0 0 0-1 1v7a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V6a1 1 0 0 0-1-1H6V4a2 2 0 1 1 4 0h1a3 3 0 0 0-3-3z"/></svg>',
  trash: '<svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14"><path d="M6.5 1a.5.5 0 0 0-.5.5V2H3a1 1 0 0 0 0 1h10a1 1 0 0 0 0-1h-3v-.5a.5.5 0 0 0-.5-.5h-3zM4.146 4l.812 9.063A1 1 0 0 0 5.95 14h4.1a1 1 0 0 0 .992-.937L11.854 4H4.146z"/></svg>',
  chart: '<svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14"><path d="M2 2v12h12V2H2zm1 1h10v10H3V3zm2 2v6h1V6H5zm3 1v5h1V7H8zm3 2v3h1V9h-1z"/></svg>',
  clock: '<svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14"><path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1zm0 1a6 6 0 1 1 0 12A6 6 0 0 1 8 2zm-.5 2v4.5l3 2 .5-.87-2.5-1.63V4h-1z"/></svg>',
  pin: '<svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14"><path d="M9.828.722a.5.5 0 0 1 .354.146l4.95 4.95a.5.5 0 0 1-.707.707L9.828 1.88 7.293 4.415l3.182 3.182-1.414 1.414-3.182-3.182-2.828 2.829 3.182 3.182-1.414 1.414-3.182-3.182-.707.707a.5.5 0 0 1-.707 0l-.707-.707a.5.5 0 0 1 0-.707l.707-.708-1.414-1.414 1.414-1.414 1.414 1.414 2.829-2.828-1.414-1.414 1.414-1.414 1.414 1.414L9.122.722a.5.5 0 0 1 .706 0z"/></svg>',
  package: '<svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14"><path d="M8 1l7 4v6l-7 4-7-4V5l7-4zm0 1.15L2.5 5.38 8 8.15l5.5-2.77L8 2.15zM1.5 5.88v4.74L7.5 13.4V8.65L1.5 5.88zm7 7.52l6-2.78V5.88l-6 2.77v4.75z"/></svg>',
  mail: '<svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14"><path d="M2 3a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V4a1 1 0 0 0-1-1H2zm1 1h10l-5 4-5-4zm-1 .5v7l4-3.5L2 4.5zm6 3.5l4 3.5V4.5L8 8z"/></svg>',
  attach: '<svg viewBox="0 0 16 16" fill="currentColor" width="14" height="14"><path d="M4.5 3a2.5 2.5 0 0 1 5 0v7a1.5 1.5 0 0 1-3 0V4a.5.5 0 0 1 1 0v6a.5.5 0 0 0 1 0V3a1.5 1.5 0 0 0-3 0v7a2.5 2.5 0 0 0 5 0V4"/></svg>',
}

// ══════════════════════════════════════
// Sidebar Rendering
// ══════════════════════════════════════

function renderSidebar() {
  const container = document.getElementById('sidebarGroups')
  const filtered = searchTerm
    ? allEntries.filter(e =>
        e.path.toLowerCase().includes(searchTerm) ||
        e.method.toLowerCase().includes(searchTerm) ||
        (e.summary || '').toLowerCase().includes(searchTerm) ||
        e.id.toLowerCase().includes(searchTerm))
    : allEntries

  const groups = {}
  for (const e of filtered) {
    const g = e.group || 'default'
    if (!groups[g]) groups[g] = []
    groups[g].push(e)
  }

  let html = ''
  for (const [groupName, entries] of Object.entries(groups)) {
    html += `<div class="group-section">
      <div class="group-header" onclick="toggleGroup(this)">
        <svg class="chevron" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <polyline points="9 18 15 12 9 6"></polyline>
        </svg>
        ${groupName}
        <fluent-badge size="small" color="informative">${entries.length}</fluent-badge>
      </div>
      <div class="group-routes">`
    for (const e of entries) {
      const isActive = e.id === activeId
      const lockIcon = e.locked ? `<span class="route-lock locked">${ICONS.lock}</span>` : ''
      html += `<div class="route-item${isActive ? ' active' : ''}" onclick="selectRoute('${escapeStr(e.id)}')">
        <span class="method-badge ${e.method.toLowerCase()}">${e.method}</span>
        <span class="route-path">${e.path}</span>
        ${lockIcon}
      </div>`
    }
    html += `</div></div>`
  }

  if (!html) {
    html = '<div style="padding:24px;text-align:center;color:var(--neutral-foreground-hint);font-size:13px;">' +
      (searchTerm ? '无匹配路由' : '暂无数据') + '</div>'
  }

  container.innerHTML = html
}

function toggleGroup(el) {
  el.querySelector('.chevron').classList.toggle('collapsed')
  el.nextElementSibling.classList.toggle('collapsed')
}

function selectRoute(id) {
  activeId = id
  renderSidebar()
  renderDetail(id)
}

// ══════════════════════════════════════
// Detail Rendering
// ══════════════════════════════════════

function renderDetail(id) {
  const entry = allEntries.find(e => e.id === id)
  if (!entry) { showEmpty(); return }

  document.getElementById('emptyState').style.display = 'none'
  const dv = document.getElementById('detailView')
  dv.style.display = 'block'
  document.getElementById('headerTitle').textContent = (entry.summary || entry.path)

  let html = ''

  // -- Overview Card --
  const lockIcon = entry.locked ? ICONS.lock : ICONS.unlock
  html += `<fluent-card class="overview-card">
    <div class="card-body">
      <div class="route-method-path">
        <span class="method-badge ${entry.method.toLowerCase()} big-badge">${entry.method}</span>
        <h2>${escapeHtml(entry.path)}</h2>
      </div>
      <div class="editable-field">
        <span class="field-label">摘要</span>
        <div class="field-value" contenteditable="true"
             onblur="onEditSummary('${escapeStr(entry.id)}', this)"
             onkeydown="if(event.key==='Enter'){this.blur();event.preventDefault()}">${escapeHtml(entry.summary || '')}</div>
        <fluent-button class="lock-btn${entry.locked?' locked':''}" appearance="${entry.locked?'accent':'outline'}" size="small" onclick="toggleLock('${escapeStr(entry.id)}')" title="锁定/解锁">${lockIcon}</fluent-button>
      </div>
      <div class="editable-field">
        <span class="field-label">分组</span>
        <div class="field-value" contenteditable="true"
             onblur="onEditGroup('${escapeStr(entry.id)}', this)"
             onkeydown="if(event.key==='Enter'){this.blur();event.preventDefault()}">${escapeHtml(entry.group || '')}</div>
      </div>
      <div class="route-info">
        <span>${ICONS.chart} 请求次数: <strong>${entry.hit_count || 0}</strong></span>
        <span>${ICONS.clock} 首次: <strong>${fmtTime(entry.first_seen)}</strong></span>
        <span>${ICONS.clock} 最近: <strong>${fmtTime(entry.last_seen)}</strong></span>
      </div>
      <div style="margin-top:12px;display:flex;gap:8px;">
        <fluent-button appearance="outline" size="small" onclick="deleteEntry('${escapeStr(entry.id)}')">${ICONS.trash} 删除</fluent-button>
      </div>
    </div>
  </fluent-card>`

  // -- Parameters (fixed: p.type_ -> p.type, p.example -> p.examples) --
  const params = entry.parameters || []
  html += `<fluent-card class="section-card">
    <div class="section-header" onclick="this.nextElementSibling.classList.toggle('collapsed')">
      <h3>${ICONS.pin} 请求参数</h3>
      <fluent-badge size="small" color="informative">${params.length}</fluent-badge>
    </div>
    <div class="section-body${params.length===0?' collapsed':''}">`
  if (params.length === 0) {
    html += '<div style="padding:16px;color:var(--neutral-foreground-hint);font-size:13px;">暂未捕获到参数</div>'
  } else {
    html += `<table class="param-table">
      <thead><tr>
        <th>名称</th><th>位置</th><th>类型</th><th>必需</th><th>描述</th><th>示例</th><th></th>
      </tr></thead><tbody>`
    for (const p of params) {
      const pLock = p.locked ? ICONS.lock : ICONS.unlock
      html += `<tr>
        <td class="param-name">${escapeHtml(p.name)}</td>
        <td><span class="mono-sm">${p.location}</span></td>
        <td class="param-type">${p.type || 'string'}</td>
        <td class="param-required ${p.required?'yes':'no'}">${p.required ? '是' : '否'}</td>
        <td class="param-desc">
          <input type="text" value="${escapeHtml(p.description || '')}"
                 onblur="onEditParam('${escapeStr(entry.id)}','${p.location}','${escapeStr(p.name)}','description',this.value)"
                 placeholder="参数说明..." />
        </td>
        <td class="param-example">${escapeHtml(p.examples || p.example || '-')}</td>
        <td>
          <span class="param-lock${p.locked?' locked':''}"
                onclick="toggleParamLock('${escapeStr(entry.id)}','${p.location}','${escapeStr(p.name)}')"
                title="锁定参数">${pLock}</span>
        </td>
      </tr>`
    }
    html += '</tbody></table>'
  }
  html += `</div></fluent-card>`

  // -- Headers (fixed: h.value -> h.value_sample) --
  const headers = entry.headers || []
  html += `<fluent-card class="section-card">
    <div class="section-header" onclick="this.nextElementSibling.classList.toggle('collapsed')">
      <h3>${ICONS.attach} 请求头</h3>
      <fluent-badge size="small" color="informative">${headers.length}</fluent-badge>
    </div>
    <div class="section-body${headers.length===0?' collapsed':''}">`
  if (headers.length === 0) {
    html += '<div style="padding:16px;color:var(--neutral-foreground-hint);font-size:13px;">仅显示非标准请求头</div>'
  } else {
    html += `<table class="param-table">
      <thead><tr><th>名称</th><th>示例值</th><th></th></tr></thead><tbody>`
    for (const h of headers) {
      const hLock = h.locked ? ICONS.lock : ICONS.unlock
      html += `<tr>
        <td class="param-name">${escapeHtml(h.name)}</td>
        <td class="param-example">${escapeHtml(h.value_sample || h.value || '-')}</td>
        <td><span class="param-lock${h.locked?' locked':''}"
                  onclick="toggleHeaderLock('${escapeStr(entry.id)}','${escapeStr(h.name)}')">${hLock}</span></td>
      </tr>`
    }
    html += '</tbody></table>'
  }
  html += `</div></fluent-card>`

  // -- Request Body --
  const reqBody = entry.request_body || {}
  const reqProps = reqBody.properties || {}
  const reqPropArr = Object.entries(reqProps)
  html += `<fluent-card class="section-card">
    <div class="section-header" onclick="this.nextElementSibling.classList.toggle('collapsed')">
      <h3>${ICONS.package} 请求体 ${reqBody.content_type ? '(' + reqBody.content_type + ')' : ''}</h3>
      <fluent-badge size="small" color="informative">${reqPropArr.length}</fluent-badge>
    </div>
    <div class="section-body${reqPropArr.length===0?' collapsed':''}">`
  if (reqPropArr.length === 0 && !reqBody.example) {
    html += '<div style="padding:16px;color:var(--neutral-foreground-hint);font-size:13px;">无请求体数据</div>'
  } else {
    if (reqPropArr.length > 0) {
      html += `<table class="param-table">
        <thead><tr><th>属性</th><th>类型</th><th>描述</th><th>示例</th></tr></thead><tbody>`
      for (const [key, prop] of reqPropArr) {
        html += `<tr>
          <td class="param-name">${escapeHtml(key)}</td>
          <td class="param-type">${prop.type || prop.type_ || 'string'}</td>
          <td class="param-desc"><input type="text" value="${escapeHtml(prop.description||'')}" placeholder="描述..." /></td>
          <td class="param-example">${escapeHtml(prop.examples || prop.example || '-')}</td>
        </tr>`
      }
      html += '</tbody></table>'
    }
    if (reqBody.example) {
      html += `<pre class="json-block">${escapeHtml(reqBody.example)}</pre>`
    }
  }
  html += `</div></fluent-card>`

  // -- Response (fixed: resp.raw_body -> resp.body_sample, p.type_ -> p.type) --
  const resp = entry.response || {}
  const respProps = resp.properties || []
  html += `<fluent-card class="section-card">
    <div class="section-header" onclick="this.nextElementSibling.classList.toggle('collapsed')">
      <h3>${ICONS.mail} 响应</h3>
      <fluent-badge size="small" color="informative">${resp.status_code || ''} ${respProps.length} 个属性</fluent-badge>
    </div>
    <div class="section-body${respProps.length===0 && !resp.body_sample?' collapsed':''}">`
  if (resp.status_code) {
    const statusColor = resp.status_code < 300 ? 'success' : (resp.status_code < 500 ? 'warning' : 'danger')
    html += `<div style="padding:12px 16px;border-bottom:1px solid var(--neutral-stroke-divider-rest);">
      <fluent-badge color="${statusColor}" size="medium">${resp.status_code}</fluent-badge>
    </div>`
  }
  if (respProps.length > 0) {
    html += `<table class="param-table">
      <thead><tr><th>属性路径</th><th>类型</th><th>原始类型</th><th>描述</th><th>示例</th><th></th></tr></thead><tbody>`
    for (const p of respProps) {
      const rLock = p.locked ? ICONS.lock : ICONS.unlock
      html += `<tr>
        <td class="param-name">${escapeHtml(p.path)}</td>
        <td class="param-type">${p.type || p.type_ || 'string'}${p.nullable?'?':''}</td>
        <td class="mono-sm muted">${p.original_type||''}</td>
        <td class="param-desc">
          <input type="text" value="${escapeHtml(p.description||'')}"
                 onblur="onEditRespProp('${escapeStr(entry.id)}','${escapeStr(p.path)}','description',this.value)"
                 placeholder="属性说明..." />
        </td>
        <td class="param-example">${escapeHtml(p.examples || p.example || '-')}</td>
        <td><span class="param-lock${p.locked?' locked':''}"
                  onclick="toggleRespPropLock('${escapeStr(entry.id)}','${escapeStr(p.path)}')">${rLock}</span></td>
      </tr>`
    }
    html += '</tbody></table>'
  }
  if (resp.body_sample) {
    html += `<pre class="json-block" style="margin:8px;">${escapeHtml(formatJson(resp.body_sample))}</pre>`
  }
  html += `</div></fluent-card>`

  dv.innerHTML = html
}

function showEmpty() {
  document.getElementById('emptyState').style.display = 'flex'
  document.getElementById('detailView').style.display = 'none'
  document.getElementById('headerTitle').textContent = 'API 文档管理器'
}

// ══════════════════════════════════════
// Edit Handlers
// ══════════════════════════════════════

function onEditSummary(id, el) {
  updateEntry(id, { summary: el.textContent.trim() })
}

function onEditGroup(id, el) {
  updateEntry(id, { group: el.textContent.trim() })
}

function toggleLock(id) {
  const entry = allEntries.find(e => e.id === id)
  if (!entry) return
  updateEntry(id, { locked: !entry.locked })
}

function onEditParam(id, location, name, field, value) {
  updateEntry(id, { editParam: { location, name, field, value } })
}

function toggleParamLock(id, location, name) {
  updateEntry(id, { toggleParamLock: { location, name } })
}

function toggleHeaderLock(id, name) {
  updateEntry(id, { toggleHeaderLock: { name } })
}

function onEditRespProp(id, path, field, value) {
  updateEntry(id, { editRespProp: { path, field, value } })
}

function toggleRespPropLock(id, path) {
  updateEntry(id, { toggleRespPropLock: { path } })
}

// ══════════════════════════════════════
// Theme
// ══════════════════════════════════════

function toggleTheme() {
  document.documentElement.classList.toggle('dark')
}

// ══════════════════════════════════════
// Utilities
// ══════════════════════════════════════

function toast(msg, type = 'info') {
  const container = document.getElementById('toastContainer')
  const t = document.createElement('div')
  t.className = 'toast ' + type
  t.textContent = msg
  container.appendChild(t)
  setTimeout(() => { t.style.opacity = '0'; t.style.transition = 'opacity 0.3s'; setTimeout(() => t.remove(), 300) }, 2500)
}

function escapeHtml(str) {
  if (!str) return ''
  const div = document.createElement('div')
  div.textContent = str
  return div.innerHTML
}

function escapeStr(str) {
  if (!str) return ''
  return str.replace(/'/g, "\\'").replace(/"/g, "&quot;")
}

function fmtTime(ts) {
  if (!ts || ts === 0) return '-'
  const d = new Date(ts)
  return d.toLocaleString('zh-CN', { hour12: false })
}

function formatJson(str) {
  if (!str) return ''
  try {
    return JSON.stringify(JSON.parse(str), null, 2)
  } catch { return str }
}