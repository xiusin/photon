// app.js — Photon API 文档前端
// 纯 Vanilla JS，无框架依赖。shadcn/ui 风格设计。
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
  document.getElementById('searchInput').addEventListener('input', (e) => {
    searchTerm = e.target.value.toLowerCase()
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

  // Group by
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
        <span class="group-badge">${entries.length}</span>
      </div>
      <div class="group-routes">`
    for (const e of entries) {
      const isActive = e.id === activeId
      const lockClass = e.locked ? ' locked' : ''
      html += `<div class="route-item${isActive ? ' active' : ''}" onclick="selectRoute('${escapeStr(e.id)}')">
        <span class="method-badge ${e.method.toLowerCase()}">${e.method}</span>
        <span class="route-path">${e.path}</span>
        <span class="route-lock${lockClass}">${e.locked ? '🔒' : ''}</span>
      </div>`
    }
    html += `</div></div>`
  }

  if (!html) {
    html = '<div style="padding:24px;text-align:center;color:hsl(var(--muted-foreground));font-size:13px;">' +
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
  html += `<div class="overview-card">
    <div class="route-method-path">
      <span class="method-badge ${entry.method.toLowerCase()} big-badge">${entry.method}</span>
      <h2>${escapeHtml(entry.path)}</h2>
    </div>
    <div class="editable-field">
      <span class="field-label">摘要</span>
      <div class="field-value" contenteditable="true"
           onblur="onEditSummary('${escapeStr(entry.id)}', this)"
           onkeydown="if(event.key==='Enter'){this.blur();event.preventDefault()}">${escapeHtml(entry.summary || '')}</div>
      <button class="lock-btn${entry.locked?' locked':''}" onclick="toggleLock('${escapeStr(entry.id)}')" title="锁定/解锁">${entry.locked ? '🔒' : '🔓'}</button>
    </div>
    <div class="editable-field">
      <span class="field-label">分组</span>
      <div class="field-value" contenteditable="true"
           onblur="onEditGroup('${escapeStr(entry.id)}', this)"
           onkeydown="if(event.key==='Enter'){this.blur();event.preventDefault()}">${escapeHtml(entry.group || '')}</div>
    </div>
    <div class="route-info">
      <span>📊 请求次数: <strong>${entry.hit_count || 0}</strong></span>
      <span>🕐 首次: <strong>${fmtTime(entry.first_seen)}</strong></span>
      <span>🕐 最近: <strong>${fmtTime(entry.last_seen)}</strong></span>
    </div>
    <div style="margin-top:12px;display:flex;gap:8px;">
      <button class="btn btn-destructive btn-sm" onclick="deleteEntry('${escapeStr(entry.id)}')">🗑 删除</button>
    </div>
  </div>`

  // -- Parameters --
  const params = entry.parameters || []
  html += `<div class="section-card">
    <div class="section-header" onclick="this.nextElementSibling.classList.toggle('collapsed')">
      <h3>📌 请求参数</h3>
      <span class="section-count">${params.length}</span>
    </div>
    <div class="section-body${params.length===0?' collapsed':''}">`
  if (params.length === 0) {
    html += '<div style="padding:16px;color:hsl(var(--muted-foreground));font-size:13px;">暂未捕获到参数</div>'
  } else {
    html += `<table class="param-table">
      <thead><tr>
        <th>名称</th><th>位置</th><th>类型</th><th>必需</th><th>描述</th><th>示例</th><th></th>
      </tr></thead><tbody>`
    for (const p of params) {
      html += `<tr>
        <td class="param-name">${escapeHtml(p.name)}</td>
        <td><span style="font-family:'SF Mono',monospace;font-size:12px;">${p.location}</span></td>
        <td class="param-type">${p.type_ || 'string'}</td>
        <td class="param-required ${p.required?'yes':'no'}">${p.required ? '是' : '否'}</td>
        <td class="param-desc">
          <input type="text" value="${escapeHtml(p.description || '')}"
                 onblur="onEditParam('${escapeStr(entry.id)}','${p.location}','${escapeStr(p.name)}','description',this.value)"
                 placeholder="参数说明..." />
        </td>
        <td class="param-example">${escapeHtml(p.example || '-')}</td>
        <td>
          <span class="param-lock${p.locked?' locked':''}"
                onclick="toggleParamLock('${escapeStr(entry.id)}','${p.location}','${escapeStr(p.name)}')"
                title="锁定参数">${p.locked ? '🔒' : '🔓'}</span>
        </td>
      </tr>`
    }
    html += '</tbody></table>'
  }
  html += `</div></div>`

  // -- Headers --
  const headers = entry.headers || []
  html += `<div class="section-card">
    <div class="section-header" onclick="this.nextElementSibling.classList.toggle('collapsed')">
      <h3>📎 请求头</h3>
      <span class="section-count">${headers.length}</span>
    </div>
    <div class="section-body${headers.length===0?' collapsed':''}">`
  if (headers.length === 0) {
    html += '<div style="padding:16px;color:hsl(var(--muted-foreground));font-size:13px;">仅显示非标准请求头</div>'
  } else {
    html += `<table class="param-table">
      <thead><tr><th>名称</th><th>示例值</th><th></th></tr></thead><tbody>`
    for (const h of headers) {
      html += `<tr>
        <td class="param-name">${escapeHtml(h.name)}</td>
        <td class="param-example">${escapeHtml(h.value || '-')}</td>
        <td><span class="param-lock${h.locked?' locked':''}"
                  onclick="toggleHeaderLock('${escapeStr(entry.id)}','${escapeStr(h.name)}')">${h.locked ? '🔒' : '🔓'}</span></td>
      </tr>`
    }
    html += '</tbody></table>'
  }
  html += `</div></div>`

  // -- Request Body --
  const reqBody = entry.request_body || {}
  const reqProps = reqBody.properties || {}
  const reqPropArr = Object.entries(reqProps)
  html += `<div class="section-card">
    <div class="section-header" onclick="this.nextElementSibling.classList.toggle('collapsed')">
      <h3>📦 请求体 ${reqBody.content_type ? '(' + reqBody.content_type + ')' : ''}</h3>
      <span class="section-count">${reqPropArr.length}</span>
    </div>
    <div class="section-body${reqPropArr.length===0?' collapsed':''}">`
  if (reqPropArr.length === 0 && !reqBody.example) {
    html += '<div style="padding:16px;color:hsl(var(--muted-foreground));font-size:13px;">无请求体数据</div>'
  } else {
    if (reqPropArr.length > 0) {
      html += `<table class="param-table">
        <thead><tr><th>属性</th><th>类型</th><th>描述</th><th>示例</th></tr></thead><tbody>`
      for (const [key, prop] of reqPropArr) {
        html += `<tr>
          <td class="param-name">${escapeHtml(key)}</td>
          <td class="param-type">${prop.type_ || 'string'}</td>
          <td class="param-desc"><input type="text" value="${escapeHtml(prop.description||'')}" placeholder="描述..." /></td>
          <td class="param-example">${escapeHtml(prop.example||'-')}</td>
        </tr>`
      }
      html += '</tbody></table>'
    }
    if (reqBody.example) {
      html += `<pre class="json-block">${escapeHtml(reqBody.example)}</pre>`
    }
  }
  html += `</div></div>`

  // -- Response --
  const resp = entry.response || {}
  const respProps = resp.properties || []
  html += `<div class="section-card">
    <div class="section-header" onclick="this.nextElementSibling.classList.toggle('collapsed')">
      <h3>📬 响应</h3>
      <span class="section-count">${resp.status_code || ''} ${respProps.length} 个属性</span>
    </div>
    <div class="section-body${respProps.length===0 && !resp.raw_body?' collapsed':''}">`
  if (resp.status_code) {
    const statusClass = resp.status_code < 300 ? 'success' : (resp.status_code < 500 ? 'warning' : 'error')
    html += `<div style="padding:12px 16px;border-bottom:1px solid hsl(var(--border));">
      <span class="status-badge ${statusClass}">${resp.status_code}</span>
    </div>`
  }
  if (respProps.length > 0) {
    html += `<table class="param-table">
      <thead><tr><th>属性路径</th><th>类型</th><th>原始类型</th><th>描述</th><th>示例</th><th></th></tr></thead><tbody>`
    for (const p of respProps) {
      html += `<tr>
        <td class="param-name">${escapeHtml(p.path)}</td>
        <td class="param-type">${p.type_ || 'string'}${p.nullable?'?':''}</td>
        <td style="font-size:11px;color:hsl(var(--muted-foreground))">${p.original_type||''}</td>
        <td class="param-desc">
          <input type="text" value="${escapeHtml(p.description||'')}"
                 onblur="onEditRespProp('${escapeStr(entry.id)}','${escapeStr(p.path)}','description',this.value)"
                 placeholder="属性说明..." />
        </td>
        <td class="param-example">${escapeHtml(p.example||'-')}</td>
        <td><span class="param-lock${p.locked?' locked':''}"
                  onclick="toggleRespPropLock('${escapeStr(entry.id)}','${escapeStr(p.path)}')">${p.locked ? '🔒' : '🔓'}</span></td>
      </tr>`
    }
    html += '</tbody></table>'
  }
  if (resp.raw_body) {
    html += `<pre class="json-block" style="margin:8px;">${escapeHtml(formatJson(resp.raw_body))}</pre>`
  }
  html += `</div></div>`

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
