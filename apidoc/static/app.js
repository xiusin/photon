// app.js — Photon API Docs · Fluent UI Web Components
// 功能：侧边栏分组、搜索、详情编辑、锁定、导出

// ══════════════════════════════════════
// State
// ══════════════════════════════════════

let allEntries = []
let activeId = null
let searchTerm = ''

// ══════════════════════════════════════
// Init
// ══════════════════════════════════════

document.addEventListener('DOMContentLoaded', () => {
  loadEntries()
  document.getElementById('searchInput').addEventListener('input', (e) => {
    searchTerm = (e.target.value || e.detail?.value || '').toLowerCase()
    renderSidebar()
  })
})

// ══════════════════════════════════════
// API
// ══════════════════════════════════════

async function loadEntries() {
  try {
    const res = await fetch('/__docs/api/entries')
    const data = await res.json()
    allEntries = data.data || []
    renderSidebar()
    if (activeId) {
      const found = allEntries.find(e => e.id === activeId)
      if (found) renderDetail(activeId)
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
    toast('已保存', 'success')
    await loadEntries()
  } catch (err) {
    toast('保存失败: ' + err.message, 'error')
  }
}

async function deleteEntry(id) {
  if (!confirm('确认删除此条目？')) return
  try {
    const res = await fetch('/__docs/api/entries/' + encodeURIComponent(id), { method: 'DELETE' })
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
// Icons — 12px SVG, Fluent UI style
// ══════════════════════════════════════

const I = {
  // lock (key)
  lock: '<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M8 1a3 3 0 0 0-3 3v2H4a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V7a1 1 0 0 0-1-1h-1V4a3 3 0 0 0-3-3zm2 5V4a2 2 0 1 0-4 0v2h4z"/></svg>',
  // unlock
  unlock: '<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M8 1a3 3 0 0 0-3 3v1H4a1 1 0 0 0-1 1v7a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V6a1 1 0 0 0-1-1H6V4a2 2 0 1 1 4 0h1a3 3 0 0 0-3-3z"/></svg>',
  // trash
  trash: '<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M6.5 1a.5.5 0 0 0-.5.5V2H3a1 1 0 0 0 0 1h10a1 1 0 0 0 0-1h-3v-.5a.5.5 0 0 0-.5-.5h-3zM4.146 4l.812 9.063A1 1 0 0 0 5.95 14h4.1a1 1 0 0 0 .992-.937L11.854 4H4.146z"/></svg>',
  // chart
  chart: '<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M2 2v12h12V2H2zm1 1h10v10H3V3zm2 2v6h1V6H5zm3 1v4h1V7H8zm3 2v2h1V9h-1z"/></svg>',
  // clock
  clock: '<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1zm0 1a6 6 0 1 1 0 12A6 6 0 0 1 8 2zm-.5 2v4.5l3 2 .5-.87-2.5-1.63V4h-1z"/></svg>',
  // pin / anchor
  pin: '<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M9.828.722a.5.5 0 0 1 .354.146l4.95 4.95a.5.5 0 0 1-.707.707L9.828 1.88 7.293 4.415l3.182 3.182-1.414 1.414-3.182-3.182-2.828 2.829 3.182 3.182-1.414 1.414-3.182-3.182-.707.707a.5.5 0 0 1-.707 0l-.707-.707a.5.5 0 0 1 0-.707l.707-.708-1.414-1.414 1.414-1.414 1.414 1.414 2.829-2.828-1.414-1.414 1.414-1.414 1.414 1.414L9.122.722a.5.5 0 0 1 .706 0z"/></svg>',
  // package
  package: '<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M8 1l7 4v6l-7 4-7-4V5l7-4zm0 1.15L2.5 5.38 8 8.15l5.5-2.77L8 2.15zM1.5 5.88v4.74L7.5 13.4V8.65L1.5 5.88zm7 7.52l6-2.78V5.88l-6 2.77v4.75z"/></svg>',
  // mail / response
  mail: '<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M2 3a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V4a1 1 0 0 0-1-1H2zm1 1h10l-5 4-5-4zm-1 .5v7l4-3.5L2 4.5zm6 3.5l4 3.5V4.5L8 8z"/></svg>',
  // attach
  attach: '<svg viewBox="0 0 16 16" fill="currentColor" width="12" height="12"><path d="M4.5 3a2.5 2.5 0 0 1 5 0v7a1.5 1.5 0 0 1-3 0V4a.5.5 0 0 1 1 0v6a.5.5 0 0 0 1 0V3a1.5 1.5 0 0 0-3 0v7a2.5 2.5 0 0 0 5 0V4"/></svg>',
}

// ══════════════════════════════════════
// JSON Syntax Highlighting
// ══════════════════════════════════════

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
      // read string
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
      // peek ahead: if followed by whitespace+colon, it's a key
      let ahead = escaped.slice(j).trimStart()
      if (ahead.startsWith(':')) {
        // key
        result += '<span class="jk">' + raw + '</span>'
      } else {
        // string value
        result += '<span class="js">' + raw + '</span>'
      }
      i = j
    } else if (ch === '-' || (ch >= '0' && ch <= '9')) {
      // number
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

// ══════════════════════════════════════
// Sidebar
// ══════════════════════════════════════

function renderSidebar() {
  const container = document.getElementById('sidebarGroups')
  const filtered = searchTerm
    ? allEntries.filter(e =>
        e.path.toLowerCase().includes(searchTerm) ||
        e.method.toLowerCase().includes(searchTerm) ||
        (e.summary || '').toLowerCase().includes(searchTerm))
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
        <svg class="chevron" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2">
          <polyline points="6 4 10 8 6 12"/>
        </svg>
        ${escapeHtml(groupName)}
        <fluent-badge size="small" color="informative">${entries.length}</fluent-badge>
      </div>
      <div class="group-routes">`
    for (const e of entries) {
      const active = e.id === activeId
      const lock = e.locked ? `<span class="route-lock locked">${I.lock}</span>` : ''
      html += `<div class="route-item${active ? ' active' : ''}" onclick="selectRoute('${escapeStr(e.id)}')">
        <span class="method-badge ${e.method.toLowerCase()}">${e.method}</span>
        <span class="route-path">${escapeHtml(e.path)}</span>
        ${lock}
      </div>`
    }
    html += '</div></div>'
  }

  if (!html) {
    html = '<div style="padding:20px;text-align:center;font-size:12px;color:var(--fg-hint);">'
      + (searchTerm ? '无匹配结果' : '暂无数据') + '</div>'
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
// Detail
// ══════════════════════════════════════

function renderDetail(id) {
  const entry = allEntries.find(e => e.id === id)
  if (!entry) { showEmpty(); return }

  document.getElementById('emptyState').style.display = 'none'
  const dv = document.getElementById('detailView')
  dv.style.display = 'block'
  document.getElementById('headerTitle').textContent = entry.summary || entry.path

  let html = ''

  // Overview card
  const lockIcon = entry.locked ? I.lock : I.unlock
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
        <fluent-button class="lock-btn${entry.locked?' locked':''}" appearance="${entry.locked?'accent':'outline'}" size="small" onclick="toggleLock('${escapeStr(entry.id)}')" title="锁定">${lockIcon}</fluent-button>
      </div>
      <div class="editable-field">
        <span class="field-label">分组</span>
        <div class="field-value" contenteditable="true"
             onblur="onEditGroup('${escapeStr(entry.id)}', this)"
             onkeydown="if(event.key==='Enter'){this.blur();event.preventDefault()}">${escapeHtml(entry.group || '')}</div>
      </div>
      <div class="route-info">
        <span>${I.chart} 请求: <strong>${entry.hit_count || 0}</strong></span>
        <span>${I.clock} 首次: <strong>${fmtTime(entry.first_seen)}</strong></span>
        <span>${I.clock} 最近: <strong>${fmtTime(entry.last_seen)}</strong></span>
      </div>
      <div style="margin-top:12px;display:flex;gap:6px;">
        <fluent-button appearance="outline" size="small" onclick="deleteEntry('${escapeStr(entry.id)}')">${I.trash} 删除</fluent-button>
      </div>
    </div>
  </fluent-card>`

  // Parameters
  const params = entry.parameters || []
  html += sectionCard(I.pin + ' 请求参数', params.length, params.length === 0 ? '<div class="empty-hint">暂未捕获到参数</div>' : paramTable([
    ['名称', 'location', p => escapeHtml(p.name)],
    ['位置', 'location', p => `<span class="mono-sm">${p.location}</span>`],
    ['类型', 'type', p => `<span class="param-type">${p.type || 'string'}</span>`],
    ['必需', 'required', p => `<span class="param-required ${p.required?'yes':'no'}">${p.required?'是':'否'}</span>`],
    ['说明', 'description', p => `<input type="text" value="${escapeHtml(p.description||'')}" placeholder="..." onblur="onEditParam('${escapeStr(entry.id)}','${p.location}','${escapeStr(p.name)}','description',this.value)" />`],
    ['示例', 'examples', p => `<span class="mono-sm" style="color:var(--fg-hint)">${escapeHtml(p.examples||p.example||'-')}</span>`],
    ['锁', 'locked', p => `<span class="param-lock${p.locked?' locked':''}" onclick="toggleParamLock('${escapeStr(entry.id)}','${p.location}','${escapeStr(p.name)}')">${p.locked?I.lock:I.unlock}</span>`],
  ], params), params.length)

  // Headers
  const headers = entry.headers || []
  html += sectionCard(I.attach + ' 请求头', headers.length, headers.length === 0 ? '<div class="empty-hint">仅显示非标准请求头</div>' : paramTable([
    ['名称', 'name', h => escapeHtml(h.name)],
    ['示例', 'value_sample', h => `<span class="mono-sm" style="color:var(--fg-hint)">${escapeHtml(h.value_sample||h.value||'-')}</span>`],
    ['锁', 'locked', h => `<span class="param-lock${h.locked?' locked':''}" onclick="toggleHeaderLock('${escapeStr(entry.id)}','${escapeStr(h.name)}')">${h.locked?I.lock:I.unlock}</span>`],
  ], headers), headers.length)

  // Request body
  const reqBody = entry.request_body || {}
  const reqProps = reqBody.properties || {}
  const reqArr = Object.entries(reqProps)
  let reqHtml = ''
  if (reqArr.length > 0) {
    reqHtml += paramTable([
      ['属性', 'name', (_, k, p) => `<span class="param-name">${escapeHtml(k)}</span>`],
      ['类型', 'type', (_, __, p) => `<span class="param-type">${p.type||p.type_||'string'}</span>`],
      ['说明', 'description', (_, __, p) => `<input type="text" value="${escapeHtml(p.description||'')}" placeholder="..." />`],
      ['示例', 'examples', (_, __, p) => `<span class="mono-sm" style="color:var(--fg-hint)">${escapeHtml(p.examples||p.example||'-')}</span>`],
    ], reqArr.map(([k, p]) => ({ name: k, ...p })))
  }
  if (reqBody.example) reqHtml += `<pre class="json-block">${highlightJson(reqBody.example)}</pre>`
  html += sectionCard(I.package + ' 请求体' + (reqBody.content_type ? ` (${reqBody.content_type})` : ''), reqArr.length + (reqBody.example?1:0), reqArr.length === 0 && !reqBody.example ? '<div class="empty-hint">无请求体数据</div>' : reqHtml, reqArr.length + (reqBody.example?1:0))

  // Response
  const resp = entry.response || {}
  const respProps = resp.properties || []
  let respHtml = ''
  if (resp.status_code) {
    const sc = resp.status_code
    const color = sc < 300 ? 'success' : (sc < 500 ? 'caution' : 'danger')
    respHtml += `<div style="padding:8px 16px;border-bottom:1px solid var(--stroke-div);">
      <fluent-badge color="${color}" size="medium">${sc}</fluent-badge>
    </div>`
  }
  if (respProps.length > 0) {
    respHtml += paramTable([
      ['路径', 'path', p => `<span class="param-name">${escapeHtml(p.path)}</span>`],
      ['类型', 'type', p => `<span class="param-type">${p.type||p.type_||'string'}${p.nullable?'?':''}</span>`],
      ['原始', 'original_type', p => `<span class="mono-sm" style="color:var(--fg-hint)">${p.original_type||''}</span>`],
      ['说明', 'description', p => `<input type="text" value="${escapeHtml(p.description||'')}" placeholder="..." onblur="onEditRespProp('${escapeStr(entry.id)}','${escapeStr(p.path)}','description',this.value)" />`],
      ['示例', 'examples', p => `<span class="mono-sm" style="color:var(--fg-hint)">${escapeHtml(p.examples||p.example||'-')}</span>`],
      ['锁', 'locked', p => `<span class="param-lock${p.locked?' locked':''}" onclick="toggleRespPropLock('${escapeStr(entry.id)}','${escapeStr(p.path)}')">${p.locked?I.lock:I.unlock}</span>`],
    ], respProps)
  }
  if (resp.body_sample) {
    let pretty = resp.body_sample
    try { pretty = JSON.stringify(JSON.parse(resp.body_sample), null, 2) } catch {}
    respHtml += `<pre class="json-block">${highlightJson(pretty)}</pre>`
  }
  html += sectionCard(I.mail + ' 响应', respProps.length + (resp.body_sample?1:0), respProps.length === 0 && !resp.body_sample ? '<div class="empty-hint">无响应数据</div>' : respHtml, respProps.length + (resp.body_sample?1:0))

  dv.innerHTML = html
}

function sectionCard(title, count, body, total) {
  const collapsed = total === 0 ? ' collapsed' : ''
  return `<fluent-card class="section-card">
    <div class="section-header" onclick="this.nextElementSibling.classList.toggle('collapsed')">
      <h3>${title}</h3>
      <fluent-badge size="small" color="informative">${count}</fluent-badge>
    </div>
    <div class="section-body${collapsed}">${body}</div>
  </fluent-card>`
}

function paramTable(cols, rows) {
  let html = `<table class="param-table"><thead><tr>`
  for (const [label] of cols) html += `<th>${label}</th>`
  html += '</tr></thead><tbody>'
  for (const row of rows) {
    html += '<tr>'
    for (const [, field, fn] of cols) {
      html += `<td>${fn(row[field], field, row)}</td>`
    }
    html += '</tr>'
  }
  html += '</tbody></table>'
  return html
}

function showEmpty() {
  document.getElementById('emptyState').style.display = 'flex'
  document.getElementById('detailView').style.display = 'none'
  document.getElementById('headerTitle').textContent = 'API 文档管理器'
}

// ══════════════════════════════════════
// Edit handlers
// ══════════════════════════════════════

function onEditSummary(id, el) { updateEntry(id, { summary: el.textContent.trim() }) }
function onEditGroup(id, el) { updateEntry(id, { group: el.textContent.trim() }) }
function toggleLock(id) {
  const e = allEntries.find(x => x.id === id)
  if (e) updateEntry(id, { locked: !e.locked })
}
function onEditParam(id, location, name, field, value) { updateEntry(id, { editParam: { location, name, field, value } }) }
function toggleParamLock(id, location, name) { updateEntry(id, { toggleParamLock: { location, name } }) }
function toggleHeaderLock(id, name) { updateEntry(id, { toggleHeaderLock: { name } }) }
function onEditRespProp(id, path, field, value) { updateEntry(id, { editRespProp: { path, field, value } }) }
function toggleRespPropLock(id, path) { updateEntry(id, { toggleRespPropLock: { path } }) }

// ══════════════════════════════════════
// Theme
// ══════════════════════════════════════

function toggleTheme() { document.documentElement.classList.toggle('dark') }

// ══════════════════════════════════════
// Utilities
// ══════════════════════════════════════

function toast(msg, type = 'info') {
  const c = document.getElementById('toastContainer')
  const t = document.createElement('div')
  t.className = 'toast ' + type
  t.textContent = msg
  c.appendChild(t)
  setTimeout(() => { t.style.opacity = '0'; t.style.transition = 'opacity 0.2s'; setTimeout(() => t.remove(), 200) }, 2500)
}

function escapeHtml(str) {
  if (!str) return ''
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function escapeStr(str) {
  if (!str) return ''
  return str.replace(/'/g,"\\'")
}

function fmtTime(ts) {
  if (!ts || ts === 0) return '-'
  return new Date(ts).toLocaleString('zh-CN', { hour12: false })
}