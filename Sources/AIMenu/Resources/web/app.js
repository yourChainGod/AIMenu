/* ==========================================================================
   AIMenu Web Remote - Application Logic
   ========================================================================== */

(function () {
  'use strict';

  // ── Constants ──────────────────────────────────────────────────────────
  const STORAGE_TOKEN_KEY = 'aiMenuToken';
  const STORAGE_DIRS_KEY  = 'aiMenuDirs';
  const MAX_RECONNECT_DELAY = 30000;
  const BASE_RECONNECT_DELAY = 1000;
  const RENDER_DEBOUNCE_MS = 50;
  const TOAST_DURATION = 4000;
  const MAX_DIRS_HISTORY = 20;

  // ── State ──────────────────────────────────────────────────────────────
  const state = {
    ws: null,
    token: new URLSearchParams(location.hash.slice(1)).get('token') || new URLSearchParams(location.search).get('token') || localStorage.getItem(STORAGE_TOKEN_KEY) || '',
    connected: false,
    authenticating: false,
    reconnectAttempts: 0,
    reconnectTimer: null,

    // Sessions
    sessions: [],
    activeSessionID: null,
    messages: {},          // sessionID -> [message, ...]
    streaming: {},         // sessionID -> { text, toolCalls }
    isStreaming: false,

    // Providers
    providers: [],
    providerFilter: 'all',
    editingProviderID: null,

    // Settings
    proxyStatus: null,

    // Slash commands
    slashCommands: [],
    slashPopupIndex: -1,

    // Directories
    directories: [],
    browsingDirs: false,
  };

  // ── DOM References ─────────────────────────────────────────────────────
  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => document.querySelectorAll(sel);

  const dom = {};

  function cacheDom() {
    dom.loader          = $('#app-loader');
    dom.authOverlay     = $('#auth-overlay');
    dom.authForm        = $('#auth-form');
    dom.authTokenInput  = $('#auth-token-input');
    dom.authSubmitBtn   = $('#auth-submit-btn');
    dom.authError       = $('#auth-error');
    dom.app             = $('#app');
    dom.connStatus      = $('#conn-status');
    dom.connDot         = dom.connStatus.querySelector('.conn-dot');
    dom.connLabel       = dom.connStatus.querySelector('.conn-label');
    dom.tabBtns         = $$('.tab-btn');
    dom.tabPanels       = $$('.tab-panel');
    dom.sidebarToggle   = $('#sidebar-toggle');
    dom.sidebarBackdrop = $('#sidebar-backdrop');
    dom.sessionSidebar  = $('#session-sidebar');
    dom.newSessionBtn   = $('#new-session-btn');
    dom.sessionList     = $('#session-list');
    dom.messageStream   = $('#message-stream');
    dom.chatEmpty       = $('#chat-empty');
    dom.slashPopup      = $('#slash-popup');
    dom.agentSelect     = $('#agent-select');
    dom.modeSelect      = $('#mode-select');
    dom.cwdInput        = $('#cwd-input');
    dom.cwdDatalist     = $('#cwd-datalist');
    dom.browseDirBtn    = $('#browse-dir-btn');
    dom.messageInput    = $('#message-input');
    dom.sendBtn         = $('#send-btn');
    dom.stopBtn         = $('#stop-btn');
    dom.mobileQuickActionBtns = $$('[data-quick-action]');
    dom.addProviderBtn  = $('#add-provider-btn');
    dom.addProviderForm = $('#add-provider-form');
    dom.providerForm    = $('#provider-form');
    dom.pfCancel        = $('#pf-cancel');
    dom.filterTabs      = $$('.filter-tab');
    dom.providerList    = $('#provider-list');
    dom.settingsToken   = $('#settings-token');
    dom.tokenToggleVis  = $('#token-toggle-vis');
    dom.tokenCopy       = $('#token-copy');
    dom.proxyStatusBadge= $('#proxy-status-badge');
    dom.proxyPort       = $('#proxy-port');
    dom.proxyAccounts   = $('#proxy-accounts');
    dom.wsStatusBadge   = $('#ws-status-badge');
    dom.wsServerUrl     = $('#ws-server-url');
    dom.disconnectBtn   = $('#disconnect-btn');
    dom.toastContainer  = $('#toast-container');
  }

  // ── Utilities ──────────────────────────────────────────────────────────

  function toast(message, type) {
    type = type || 'info';
    var el = document.createElement('div');
    el.className = 'toast ' + type;
    el.textContent = message;
    dom.toastContainer.appendChild(el);
    setTimeout(function () {
      el.classList.add('out');
      setTimeout(function () { el.remove(); }, 300);
    }, TOAST_DURATION);
  }

  function escapeHtml(str) {
    var div = document.createElement('div');
    div.appendChild(document.createTextNode(str));
    return div.innerHTML;
  }

  function maskString(str, visibleChars) {
    visibleChars = visibleChars || 4;
    if (!str) return '';
    if (str.length <= visibleChars) return str;
    return str.substring(0, visibleChars) + '*'.repeat(Math.min(str.length - visibleChars, 20));
  }

  function formatTimestamp(ts) {
    if (!ts) return '';
    var d = new Date(ts);
    var now = new Date();
    var isToday = d.toDateString() === now.toDateString();
    if (isToday) {
      return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }
    return d.toLocaleDateString([], { month: 'short', day: 'numeric' });
  }

  function loadDirsHistory() {
    try {
      var raw = localStorage.getItem(STORAGE_DIRS_KEY);
      return raw ? JSON.parse(raw) : [];
    } catch (e) {
      return [];
    }
  }

  function saveDirHistory(dir) {
    if (!dir) return;
    var dirs = loadDirsHistory();
    // Remove existing to avoid duplicates, then prepend
    dirs = dirs.filter(function (d) { return d !== dir; });
    dirs.unshift(dir);
    if (dirs.length > MAX_DIRS_HISTORY) dirs = dirs.slice(0, MAX_DIRS_HISTORY);
    localStorage.setItem(STORAGE_DIRS_KEY, JSON.stringify(dirs));
    updateCwdDatalist();
  }

  function updateCwdDatalist() {
    var dirs = loadDirsHistory();
    // Merge server directories
    var all = dirs.slice();
    state.directories.forEach(function (d) {
      if (all.indexOf(d) === -1) all.push(d);
    });
    dom.cwdDatalist.innerHTML = all.map(function (d) {
      return '<option value="' + escapeHtml(d) + '">';
    }).join('');
  }

  // ── WebSocket ──────────────────────────────────────────────────────────

  function getWsUrl() {
    var params = new URLSearchParams(location.search);
    var wsPort = params.get('wsPort') || (parseInt(location.port || '9090') + 1).toString();
    var host = location.hostname || '127.0.0.1';
    return 'ws://' + host + ':' + wsPort;
  }

  function connect() {
    if (state.ws && (state.ws.readyState === WebSocket.CONNECTING || state.ws.readyState === WebSocket.OPEN)) {
      return;
    }

    updateConnectionStatus('connecting');

    var url = getWsUrl();
    dom.wsServerUrl.textContent = url;

    try {
      state.ws = new WebSocket(url);
    } catch (e) {
      updateConnectionStatus('disconnected');
      scheduleReconnect();
      return;
    }

    state.ws.onopen = function () {
      state.reconnectAttempts = 0;
      // Authenticate immediately
      wsSend({ type: 'auth', token: state.token });
    };

    state.ws.onmessage = function (event) {
      var msg;
      try {
        msg = JSON.parse(event.data);
      } catch (e) {
        return;
      }
      handleMessage(msg);
    };

    state.ws.onclose = function () {
      state.connected = false;
      updateConnectionStatus('disconnected');
      scheduleReconnect();
    };

    state.ws.onerror = function () {
      // onclose will fire after this
    };
  }

  function disconnect() {
    if (state.reconnectTimer) {
      clearTimeout(state.reconnectTimer);
      state.reconnectTimer = null;
    }
    state.reconnectAttempts = 0;
    if (state.ws) {
      state.ws.onclose = null;
      state.ws.close();
      state.ws = null;
    }
    state.connected = false;
    updateConnectionStatus('disconnected');
  }

  function scheduleReconnect() {
    if (state.reconnectTimer) return;
    if (!state.token) return;

    var delay = Math.min(
      BASE_RECONNECT_DELAY * Math.pow(2, state.reconnectAttempts),
      MAX_RECONNECT_DELAY
    );
    state.reconnectAttempts++;

    state.reconnectTimer = setTimeout(function () {
      state.reconnectTimer = null;
      connect();
    }, delay);
  }

  function wsSend(msg) {
    if (state.ws && state.ws.readyState === WebSocket.OPEN) {
      state.ws.send(JSON.stringify(msg));
    }
  }

  function updateConnectionStatus(status) {
    dom.connStatus.className = 'conn-indicator ' + status;

    var labels = {
      connected: '在线',
      connecting: '连接中',
      disconnected: '离线'
    };
    dom.connLabel.textContent = labels[status] || status;
    dom.connStatus.title = labels[status] || status;
    dom.connStatus.setAttribute('aria-label', 'Connection status: ' + (labels[status] || status));

    // Settings panel WS status
    if (status === 'connected') {
      dom.wsStatusBadge.className = 'status-badge running';
      dom.wsStatusBadge.textContent = '已连接';
    } else {
      dom.wsStatusBadge.className = 'status-badge stopped';
      dom.wsStatusBadge.textContent = status === 'connecting' ? '连接中...' : '未连接';
    }
  }

  // ── Message Handler ────────────────────────────────────────────────────

  function handleMessage(msg) {
    switch (msg.type) {
      case 'authResult':
        handleAuthResult(msg);
        break;
      case 'pong':
        // Keepalive acknowledged
        break;
      case 'sessionList':
        handleSessionList(msg.payload);
        break;
      case 'sessionDetail':
        handleSessionDetail(msg.payload);
        break;
      case 'textDelta':
        handleTextDelta(msg.payload);
        break;
      case 'toolStart':
        handleToolStart(msg.payload);
        break;
      case 'toolEnd':
        handleToolEnd(msg.payload);
        break;
      case 'chatDone':
        handleChatDone(msg.payload);
        break;
      case 'chatError':
        handleChatError(msg);
        break;
      case 'providerList':
        handleProviderList(msg.payload);
        break;
      case 'proxyStatusSnapshot':
        handleProxyStatus(msg.payload);
        break;
      case 'directoryList':
        handleDirectoryList(msg.payload);
        break;
      case 'slashCommands':
        handleSlashCommands(msg.payload);
        break;
      case 'sessionRenamed':
        handleSessionRenamed(msg.payload);
        break;
      case 'usageUpdate':
        handleUsageUpdate(msg.payload);
        break;
      case 'providerSaved':
      case 'providerDeleted':
      case 'tokenUpdated':
        wsSend({ type: 'listAllProviders' });
        break;
      case 'error':
        toast(msg.message || '未知错误', 'error');
        break;
      default:
        break;
    }
  }

  // ── Auth ───────────────────────────────────────────────────────────────

  function handleAuthResult(msg) {
    state.authenticating = false;
    dom.authSubmitBtn.classList.remove('loading');

    if (msg.success) {
      state.connected = true;
      // msg.message may contain the token value
      if (msg.message && msg.message !== 'ok' && msg.message !== 'authenticated') {
        state.token = msg.message;
        localStorage.setItem(STORAGE_TOKEN_KEY, state.token);
      }
      updateConnectionStatus('connected');
      showApp();
      // Fetch initial data
      wsSend({ type: 'listSessions' });
      wsSend({ type: 'listAllProviders' });
      wsSend({ type: 'requestProxyStatus' });
      wsSend({ type: 'listDirectories' });
      wsSend({ type: 'requestSlashCommands' });

      // Update settings token display
      dom.settingsToken.value = state.token;

      // Start ping interval
      startPing();
    } else {
      dom.authError.textContent = msg.message || '认证失败';
      showAuth();
    }
  }

  var pingInterval = null;
  function startPing() {
    stopPing();
    pingInterval = setInterval(function () {
      wsSend({ type: 'ping' });
    }, 30000);
  }
  function stopPing() {
    if (pingInterval) {
      clearInterval(pingInterval);
      pingInterval = null;
    }
  }

  function showAuth() {
    dom.authOverlay.classList.remove('hidden');
    dom.app.setAttribute('aria-hidden', 'true');
    dom.loader.classList.add('hidden');
    dom.authTokenInput.focus();
  }

  function showApp() {
    dom.authOverlay.classList.add('hidden');
    dom.app.removeAttribute('aria-hidden');
    dom.app.style.opacity = '1';
    dom.loader.classList.add('hidden');
  }

  // ── Sessions ───────────────────────────────────────────────────────────

  function handleSessionList(payload) {
    state.sessions = (payload && payload.sessions) || [];
    renderSessionList();

    // Auto-select the most recent session if none is selected
    if (!state.activeSessionID && state.sessions.length > 0) {
      selectSession(state.sessions[0].id);
    }
  }

  function handleSessionDetail(payload) {
    if (!payload || !payload.id) return;
    state.messages[payload.id] = (payload.messages || []).map(normalizeMessage);

    // Auto-select newly created or loaded session
    if (!state.activeSessionID) {
      state.activeSessionID = payload.id;
      wsSend({ type: 'listSessions' });
    }

    if (state.activeSessionID === payload.id) {
      if (!state.isStreaming) {
        dom.sendBtn.style.display = '';
        dom.stopBtn.style.display = 'none';
      }
      renderMessages();
      updateSendBtnState();
    }
  }

  function normalizeMessage(m) {
    return {
      role: m.role || 'assistant',
      content: m.content || m.text || '',
      timestamp: m.timestamp || null,
      toolCalls: m.toolCalls || []
    };
  }

  function selectSession(sessionID) {
    state.activeSessionID = sessionID;
    state.isStreaming = false;
    // Reset button visibility
    dom.sendBtn.style.display = '';
    dom.stopBtn.style.display = 'none';
    renderSessionList();
    renderMessages();
    updateSendBtnState();
    wsSend({ type: 'loadSession', sessionID: sessionID });
    closeSidebar();
  }

  function createSession() {
    var agent = dom.agentSelect.value;
    var mode = dom.modeSelect.value;
    var cwd = dom.cwdInput.value.trim();
    if (cwd) saveDirHistory(cwd);
    wsSend({
      type: 'createSession',
      agent: agent,
      mode: mode,
      cwd: cwd || undefined
    });
    closeSidebar();
  }

  function deleteSession(sessionID, e) {
    if (e) { e.stopPropagation(); e.preventDefault(); }
    if (!confirm('确认删除此会话？')) return;
    wsSend({ type: 'deleteSession', sessionID: sessionID });
    if (state.activeSessionID === sessionID) {
      state.activeSessionID = null;
      state.messages[sessionID] = [];
      renderMessages();
    }
  }

  function startSessionRename(el) {
    var sid = el.dataset.id;
    var titleEl = el.querySelector('.session-item-title');
    if (!titleEl) return;
    var currentTitle = titleEl.textContent;

    var input = document.createElement('input');
    input.type = 'text';
    input.className = 'session-rename-input';
    input.value = currentTitle;
    titleEl.replaceWith(input);
    input.focus();
    input.select();

    function commit() {
      var newTitle = input.value.trim();
      if (newTitle && newTitle !== currentTitle) {
        wsSend({ type: 'renameSession', sessionID: sid, sessionTitle: newTitle });
      }
      renderSessionList();
    }

    input.addEventListener('blur', commit);
    input.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') { e.preventDefault(); input.blur(); }
      if (e.key === 'Escape') { e.preventDefault(); renderSessionList(); }
    });
  }

  function renderSessionList() {
    if (!state.sessions.length) {
      dom.sessionList.innerHTML = '<div class="session-empty"><span>暂无会话</span><span>新建一个会话开始对话</span></div>';
      return;
    }

    var html = '';
    state.sessions.forEach(function (s) {
      var isActive = s.id === state.activeSessionID;
      var title = s.title || s.id || '未命名';
      if (title.length > 32) title = title.substring(0, 32) + '...';
      var agent = s.agent || 'claude';
      var time = formatTimestamp(s.updatedAt || s.createdAt);
      html += '<div class="session-item' + (isActive ? ' active' : '') + '" role="listitem" data-id="' + escapeHtml(s.id) + '" tabindex="0">';
      html += '  <div class="session-item-info">';
      html += '    <div class="session-item-title">' + escapeHtml(title) + '</div>';
      html += '    <div class="session-item-meta">';
      html += '      <span class="session-item-agent">' + escapeHtml(agent) + '</span>';
      if (time) html += '      <span>' + escapeHtml(time) + '</span>';
      html += '    </div>';
      html += '  </div>';
      html += '  <button class="session-item-delete" aria-label="删除会话" data-delete="' + escapeHtml(s.id) + '">';
      html += '    <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><line x1="3" y1="3" x2="11" y2="11"/><line x1="11" y1="3" x2="3" y2="11"/></svg>';
      html += '  </button>';
      html += '</div>';
    });
    dom.sessionList.innerHTML = html;

    // Bind events
    dom.sessionList.querySelectorAll('.session-item').forEach(function (el) {
      el.addEventListener('click', function (e) {
        if (e.target.closest('.session-item-delete')) return;
        if (e.target.closest('.session-rename-input')) return;
        selectSession(el.dataset.id);
      });
      el.addEventListener('dblclick', function (e) {
        if (e.target.closest('.session-item-delete')) return;
        startSessionRename(el);
      });
      el.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          selectSession(el.dataset.id);
        }
      });
    });
    dom.sessionList.querySelectorAll('.session-item-delete').forEach(function (el) {
      el.addEventListener('click', function (e) {
        deleteSession(el.dataset.delete, e);
      });
    });
  }

  // ── Messages ───────────────────────────────────────────────────────────

  var renderTimeout = null;
  function scheduleRender() {
    if (renderTimeout) return;
    renderTimeout = setTimeout(function () {
      renderTimeout = null;
      renderMessages();
    }, RENDER_DEBOUNCE_MS);
  }

  function renderMessages() {
    var sid = state.activeSessionID;
    if (!sid) {
      dom.chatEmpty.style.display = '';
      dom.messageStream.querySelectorAll('.message').forEach(function (el) { el.remove(); });
      return;
    }

    var msgs = state.messages[sid] || [];
    dom.chatEmpty.style.display = msgs.length ? 'none' : '';

    // Build HTML
    var html = '';
    msgs.forEach(function (m, idx) {
      html += buildMessageHtml(m, idx);
    });

    // Append streaming content if active
    var stream = state.streaming[sid];
    if (stream && state.isStreaming) {
      html += buildStreamingHtml(stream);
    }

    // Only replace inner messages (keep chat-empty)
    var container = dom.messageStream;
    // Remove old messages
    container.querySelectorAll('.message').forEach(function (el) { el.remove(); });
    // Insert new
    container.insertAdjacentHTML('beforeend', html);

    // Bind tool call toggles
    container.querySelectorAll('.tool-call-header').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var tc = btn.closest('.tool-call');
        tc.classList.toggle('expanded');
      });
    });

    // Scroll to bottom
    scrollToBottom();
  }

  function buildMessageHtml(m) {
    var role = m.role === 'user' ? 'user' : 'assistant';
    var avatarText = role === 'user' ? 'U' : 'AI';

    var html = '<div class="message ' + role + '">';
    html += '<div class="message-avatar">' + avatarText + '</div>';
    html += '<div class="message-body">';
    html += '<div class="message-content">' + formatContent(m.content) + '</div>';

    // Tool calls
    if (m.toolCalls && m.toolCalls.length) {
      m.toolCalls.forEach(function (tc) {
        html += buildToolCallHtml(tc.id || '', tc.name || 'tool', tc.result || '', true);
      });
    }

    html += '</div></div>';
    return html;
  }

  function buildStreamingHtml(stream) {
    var html = '<div class="message assistant">';
    html += '<div class="message-avatar">AI</div>';
    html += '<div class="message-body">';

    if (stream.text) {
      html += '<div class="message-content">' + formatContent(stream.text) + '<span class="streaming-cursor"></span></div>';
    }

    // Active tool calls
    if (stream.toolCalls) {
      Object.keys(stream.toolCalls).forEach(function (id) {
        var tc = stream.toolCalls[id];
        html += buildToolCallHtml(id, tc.name || 'tool', tc.result || '', !!tc.done);
      });
    }

    // Show cursor if no text yet
    if (!stream.text && (!stream.toolCalls || Object.keys(stream.toolCalls).length === 0)) {
      html += '<div class="message-content"><span class="streaming-cursor"></span></div>';
    }

    html += '</div></div>';
    return html;
  }

  function buildToolCallHtml(id, name, result, isDone) {
    var html = '<div class="tool-call" data-tool-id="' + escapeHtml(id) + '">';
    html += '<button class="tool-call-header" aria-expanded="false">';
    html += '<svg class="tool-call-chevron" width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 2l4 4-4 4"/></svg>';
    html += '<span class="tool-call-name">' + escapeHtml(name) + '</span>';
    html += '<span class="tool-call-status ' + (isDone ? 'done' : 'running') + '">' + (isDone ? '完成' : '运行中...') + '</span>';
    html += '</button>';
    html += '<div class="tool-call-body">' + escapeHtml(result) + '</div>';
    html += '</div>';
    return html;
  }

  function formatContent(text) {
    if (!text) return '';

    // Process code blocks first
    var parts = [];
    var remaining = text;
    var codeBlockRegex = /```(\w*)\n?([\s\S]*?)```/g;
    var lastIndex = 0;
    var match;

    while ((match = codeBlockRegex.exec(text)) !== null) {
      // Text before code block
      if (match.index > lastIndex) {
        parts.push({ type: 'text', content: text.substring(lastIndex, match.index) });
      }
      parts.push({ type: 'code', lang: match[1], content: match[2] });
      lastIndex = match.index + match[0].length;
    }

    if (lastIndex < text.length) {
      parts.push({ type: 'text', content: text.substring(lastIndex) });
    }

    if (parts.length === 0) {
      parts.push({ type: 'text', content: text });
    }

    return parts.map(function (p) {
      if (p.type === 'code') {
        var langLabel = p.lang ? '<span class="code-lang">' + escapeHtml(p.lang) + '</span>' : '';
        return '<div class="code-block-wrapper">'
          + '<div class="code-block-header">' + langLabel + '<button class="code-copy-btn" onclick="copyCodeBlock(this)" title="复制">📋</button></div>'
          + '<pre><code>' + escapeHtml(p.content.replace(/\n$/, '')) + '</code></pre>'
          + '</div>';
      }
      return formatInlineText(p.content);
    }).join('');
  }

  // Expose to onclick
  window.copyCodeBlock = function (btn) {
    var code = btn.closest('.code-block-wrapper').querySelector('code').textContent;
    if (navigator.clipboard) {
      navigator.clipboard.writeText(code).then(function () {
        btn.textContent = '✓';
        setTimeout(function () { btn.textContent = '📋'; }, 1500);
      });
    }
  };

  function formatInlineText(text) {
    // Escape HTML first
    var html = escapeHtml(text);
    // Inline code
    html = html.replace(/`([^`]+)`/g, '<code class="inline-code">$1</code>');
    // Bold
    html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    // Italic
    html = html.replace(/\*([^*]+)\*/g, '<em>$1</em>');
    // Links [text](url)
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
    // Bullet lists (lines starting with - or *)
    html = html.replace(/^([*\-]) (.+)$/gm, '<li>$2</li>');
    // Line breaks
    html = html.replace(/\n/g, '<br>');
    return html;
  }

  function scrollToBottom() {
    var el = dom.messageStream;
    // Use requestAnimationFrame for smooth scroll
    requestAnimationFrame(function () {
      el.scrollTop = el.scrollHeight;
    });
  }

  // ── Streaming Handlers ─────────────────────────────────────────────────

  function handleTextDelta(payload) {
    if (!payload || !payload.sessionID) return;
    var sid = payload.sessionID;

    if (!state.streaming[sid]) {
      state.streaming[sid] = { text: '', toolCalls: {} };
    }

    state.streaming[sid].text += (payload.text || '');
    state.isStreaming = true;

    updateStreamingUI();

    if (sid === state.activeSessionID) {
      dom.sendBtn.hidden = true;
      dom.stopBtn.hidden = false;
      scheduleRender();
    }
  }

  function handleToolStart(payload) {
    if (!payload || !payload.sessionID) return;
    var sid = payload.sessionID;

    if (!state.streaming[sid]) {
      state.streaming[sid] = { text: '', toolCalls: {} };
    }

    state.streaming[sid].toolCalls[payload.toolId] = {
      name: payload.name || 'tool',
      result: '',
      done: false
    };

    state.isStreaming = true;

    if (sid === state.activeSessionID) {
      dom.sendBtn.hidden = true;
      dom.stopBtn.hidden = false;
      scheduleRender();
    }
  }

  function handleToolEnd(payload) {
    if (!payload || !payload.sessionID) return;
    var sid = payload.sessionID;

    if (state.streaming[sid] && state.streaming[sid].toolCalls[payload.toolId]) {
      state.streaming[sid].toolCalls[payload.toolId].result = payload.result || '';
      state.streaming[sid].toolCalls[payload.toolId].done = true;
    }

    if (sid === state.activeSessionID) {
      scheduleRender();
    }
  }

  function handleChatDone(payload) {
    if (!payload || !payload.sessionID) return;
    var sid = payload.sessionID;

    // Commit streaming content to messages
    if (state.streaming[sid]) {
      var streamData = state.streaming[sid];
      var toolCalls = [];
      Object.keys(streamData.toolCalls).forEach(function (id) {
        var tc = streamData.toolCalls[id];
        toolCalls.push({ id: id, name: tc.name, result: tc.result });
      });

      if (streamData.text || toolCalls.length) {
        if (!state.messages[sid]) state.messages[sid] = [];
        state.messages[sid].push({
          role: 'assistant',
          content: streamData.text,
          timestamp: new Date().toISOString(),
          toolCalls: toolCalls
        });
      }

      delete state.streaming[sid];
    }

    state.isStreaming = false;
    dom.sendBtn.style.display = '';
    dom.stopBtn.style.display = 'none';

    if (sid === state.activeSessionID) {
      renderMessages();
    }

    // Refresh session list to update titles
    wsSend({ type: 'listSessions' });
  }

  function handleChatError(msg) {
    state.isStreaming = false;
    dom.sendBtn.style.display = '';
    dom.stopBtn.style.display = 'none';
    toast(msg.message || '对话错误', 'error');

    if (state.activeSessionID) {
      // Clean up streaming state
      delete state.streaming[state.activeSessionID];
      renderMessages();
    }
  }

  function updateStreamingUI() {
    // Update session list item to show streaming indicator
  }

  // ── Send Message ───────────────────────────────────────────────────────

  function sendMessage() {
    if (dom.sendBtn.disabled) return;
    var text = dom.messageInput.value.trim();
    if (!text || !state.activeSessionID) return;

    // Save working directory if changed
    var cwd = dom.cwdInput.value.trim();
    if (cwd) saveDirHistory(cwd);

    // Add user message locally
    if (!state.messages[state.activeSessionID]) {
      state.messages[state.activeSessionID] = [];
    }
    state.messages[state.activeSessionID].push({
      role: 'user',
      content: text,
      timestamp: new Date().toISOString(),
      toolCalls: []
    });

    // Initialize streaming state
    state.streaming[state.activeSessionID] = { text: '', toolCalls: {} };
    state.isStreaming = true;

    renderMessages();

    // Send to server
    wsSend({
      type: 'sendMessage',
      sessionID: state.activeSessionID,
      text: text
    });

    // Clear input
    dom.messageInput.value = '';
    autoResizeInput();
    dom.sendBtn.disabled = true;
    dom.sendBtn.style.display = 'none';
    dom.stopBtn.style.display = '';

    hideSlashPopup();
  }

  function abortSession() {
    if (!state.activeSessionID) return;
    wsSend({ type: 'abortSession', sessionID: state.activeSessionID });

    state.isStreaming = false;
    dom.sendBtn.style.display = '';
    dom.stopBtn.style.display = 'none';

    // Commit whatever we have
    handleChatDone({ sessionID: state.activeSessionID });
  }

  // ── Slash Commands ─────────────────────────────────────────────────────

  function handleSlashCommands(payload) {
    state.slashCommands = (payload && payload.commands) || [];
  }

  function handleSessionRenamed(payload) {
    if (!payload || !payload.id) return;
    var s = state.sessions.find(function (s) { return s.id === payload.id; });
    if (s) {
      s.title = payload.title || s.title;
      renderSessionList();
    }
  }

  function handleUsageUpdate(payload) {
    if (!payload || !payload.sessionID) return;
    var sid = payload.sessionID;
    if (sid !== state.activeSessionID) return;

    var parts = [];
    var input = payload.inputTokens || 0;
    var cached = payload.cachedTokens || 0;
    var output = payload.outputTokens || 0;
    if (input) parts.push('In: ' + input.toLocaleString());
    if (cached) parts.push('Cached: ' + cached.toLocaleString());
    if (output) parts.push('Out: ' + output.toLocaleString());
    if (payload.costUSD) parts.push('$' + payload.costUSD.toFixed(4));

    if (parts.length) {
      var badge = document.getElementById('usage-badge');
      if (!badge) {
        badge = document.createElement('div');
        badge.id = 'usage-badge';
        badge.className = 'usage-badge';
        dom.messageStream.parentElement.insertBefore(badge, dom.messageStream);
      }
      badge.textContent = parts.join(' · ');
    }
  }

  function showSlashPopup(filter) {
    var cmds = state.slashCommands;
    if (!cmds.length) return;

    var filtered = cmds.filter(function (c) {
      var name = (c.name || c.command || '').toLowerCase();
      return name.indexOf(filter.toLowerCase()) !== -1;
    });

    if (!filtered.length) {
      hideSlashPopup();
      return;
    }

    state.slashPopupIndex = 0;

    var html = '';
    filtered.forEach(function (c, idx) {
      var name = c.name || c.command || '';
      var desc = c.description || '';
      html += '<div class="slash-item' + (idx === 0 ? ' focused' : '') + '" role="option" data-cmd="' + escapeHtml(name) + '">';
      html += '<span class="slash-item-cmd">/' + escapeHtml(name) + '</span>';
      html += '<span class="slash-item-desc">' + escapeHtml(desc) + '</span>';
      html += '</div>';
    });

    dom.slashPopup.innerHTML = html;
    dom.slashPopup.hidden = false;

    dom.slashPopup.querySelectorAll('.slash-item').forEach(function (el) {
      el.addEventListener('click', function () {
        insertSlashCommand(el.dataset.cmd);
      });
    });
  }

  function hideSlashPopup() {
    dom.slashPopup.hidden = true;
    dom.slashPopup.innerHTML = '';
    state.slashPopupIndex = -1;
  }

  function insertSlashCommand(cmd) {
    dom.messageInput.value = '/' + cmd + ' ';
    dom.messageInput.focus();
    hideSlashPopup();
    updateSendBtnState();
  }

  function navigateSlashPopup(direction) {
    var items = dom.slashPopup.querySelectorAll('.slash-item');
    if (!items.length) return;

    items[state.slashPopupIndex]?.classList.remove('focused');

    state.slashPopupIndex += direction;
    if (state.slashPopupIndex < 0) state.slashPopupIndex = items.length - 1;
    if (state.slashPopupIndex >= items.length) state.slashPopupIndex = 0;

    items[state.slashPopupIndex].classList.add('focused');
    items[state.slashPopupIndex].scrollIntoView({ block: 'nearest' });
  }

  function confirmSlashPopup() {
    var items = dom.slashPopup.querySelectorAll('.slash-item');
    if (state.slashPopupIndex >= 0 && items[state.slashPopupIndex]) {
      insertSlashCommand(items[state.slashPopupIndex].dataset.cmd);
    }
  }

  // ── Providers ──────────────────────────────────────────────────────────

  function handleProviderList(payload) {
    state.providers = (payload && payload.providers) || [];
    renderProviders();
  }

  function renderProviders() {
    var providers = state.providers;
    var filter = state.providerFilter;

    if (filter !== 'all') {
      providers = providers.filter(function (p) {
        return (p.appType || p.providerAppType || '').toLowerCase() === filter;
      });
    }

    if (!providers.length) {
      dom.providerList.innerHTML = '<div class="provider-empty">未找到提供商，添加一个开始使用。</div>';
      return;
    }

    var html = '';
    providers.forEach(function (p) {
      var id = p.id || p.providerID || '';
      var name = p.name || p.providerName || 'Unnamed';
      var appType = p.appType || p.providerAppType || '';
      var apiKey = p.apiKey || p.providerApiKey || '';
      var baseUrl = p.baseUrl || p.providerBaseUrl || '';
      var model = p.model || p.providerModel || '';
      var isCurrent = p.current || p.isCurrent || false;
      var isEditing = state.editingProviderID === id;

      html += '<div class="provider-card' + (isCurrent ? ' current' : '') + (isEditing ? ' editing' : '') + '" data-id="' + escapeHtml(id) + '" role="listitem">';
      html += '<div class="provider-card-header">';
      html += '<span class="provider-card-name">' + escapeHtml(name) + '</span>';
      if (isCurrent) {
        html += '<span class="provider-badge badge-current">当前</span>';
      }
      html += '<span class="provider-badge badge-type">' + escapeHtml(appType) + '</span>';
      html += '</div>';

      if (isEditing) {
        // Inline edit form
        html += '<div class="provider-edit-fields">';
        html += '<div class="provider-edit-field"><label>名称</label><input type="text" class="text-input" data-field="name" value="' + escapeHtml(name) + '"></div>';
        html += '<div class="provider-edit-field"><label>API Key</label><input type="password" class="text-input" data-field="apiKey" placeholder="保持不变" value=""></div>';
        html += '<div class="provider-edit-field"><label>Base URL</label><input type="url" class="text-input" data-field="baseUrl" value="' + escapeHtml(baseUrl) + '" placeholder="https://api.example.com/v1"></div>';
        html += '<div class="provider-edit-field"><label>模型</label><input type="text" class="text-input" data-field="model" value="' + escapeHtml(model) + '"></div>';
        html += '</div>';
        html += '<div class="provider-card-actions">';
        html += '<button class="btn btn-accent btn-sm" data-action="save" data-id="' + escapeHtml(id) + '">保存</button>';
        html += '<button class="btn btn-ghost btn-sm" data-action="cancel-edit">取消</button>';
        html += '</div>';
      } else {
        // Display fields
        html += '<div class="provider-card-fields">';
        html += '<div class="provider-field"><span class="provider-field-label">API Key</span><span class="provider-field-value">' + escapeHtml(maskString(apiKey, 8)) + '</span></div>';
        if (baseUrl) {
          html += '<div class="provider-field"><span class="provider-field-label">Base URL</span><span class="provider-field-value">' + escapeHtml(baseUrl) + '</span></div>';
        }
        if (model) {
          html += '<div class="provider-field"><span class="provider-field-label">模型</span><span class="provider-field-value">' + escapeHtml(model) + '</span></div>';
        }
        html += '</div>';
        html += '<div class="provider-card-actions">';
        if (!isCurrent) {
          html += '<button class="btn btn-accent btn-sm" data-action="switch" data-id="' + escapeHtml(id) + '" data-app-type="' + escapeHtml(appType) + '">应用</button>';
        }
        html += '<button class="btn btn-outline btn-sm" data-action="edit" data-id="' + escapeHtml(id) + '">编辑</button>';
        html += '<button class="btn btn-outline btn-sm btn-danger" data-action="delete" data-id="' + escapeHtml(id) + '" data-app-type="' + escapeHtml(appType) + '">删除</button>';
        html += '</div>';
      }

      html += '</div>';
    });

    dom.providerList.innerHTML = html;
    bindProviderActions();
  }

  function bindProviderActions() {
    dom.providerList.querySelectorAll('[data-action]').forEach(function (btn) {
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        var action = btn.dataset.action;
        var id = btn.dataset.id;
        var appType = btn.dataset.appType;

        switch (action) {
          case 'switch':
            wsSend({ type: 'switchProvider', providerID: id, providerAppType: appType });
            toast('正在切换提供商...', 'info');
            break;
          case 'edit':
            state.editingProviderID = id;
            renderProviders();
            break;
          case 'cancel-edit':
            state.editingProviderID = null;
            renderProviders();
            break;
          case 'save':
            saveProviderEdit(id);
            break;
          case 'delete':
            if (confirm('确认删除此提供商？')) {
              wsSend({ type: 'deleteProvider', providerID: id, providerAppType: appType });
              toast('已删除', 'info');
            }
            break;
        }
      });
    });
  }

  function saveProviderEdit(id) {
    var card = dom.providerList.querySelector('.provider-card[data-id="' + id + '"]');
    if (!card) return;

    // Find the original provider data to get appType and detect unchanged apiKey
    var original = state.providers.find(function (p) { return (p.id || p.providerID) === id; });

    var fields = {};
    card.querySelectorAll('[data-field]').forEach(function (input) {
      fields[input.dataset.field] = input.value.trim();
    });

    var payload = {
      type: 'updateProvider',
      providerID: id,
      providerAppType: original ? (original.appType || original.providerAppType || '') : '',
      providerName: fields.name || '',
      providerBaseUrl: fields.baseUrl || '',
      providerModel: fields.model || ''
    };

    // Only send apiKey if the user actually changed it (not the masked value)
    var originalKey = original ? (original.apiKey || original.providerApiKey || '') : '';
    if (fields.apiKey && fields.apiKey !== originalKey) {
      payload.providerApiKey = fields.apiKey;
    }

    wsSend(payload);

    state.editingProviderID = null;
    toast('已更新', 'success');
  }

  function addProvider(e) {
    e.preventDefault();
    var name = $('#pf-name').value.trim();
    var appType = $('#pf-type').value;
    var apiKey = $('#pf-apikey').value.trim();
    var baseUrl = $('#pf-baseurl').value.trim();
    var model = $('#pf-model').value.trim();

    if (!name || !apiKey) {
      toast('名称和 API Key 不能为空', 'error');
      return;
    }

    wsSend({
      type: 'addProvider',
      providerName: name,
      providerAppType: appType,
      providerApiKey: apiKey,
      providerBaseUrl: baseUrl || undefined,
      providerModel: model || undefined
    });

    dom.providerForm.reset();
    dom.addProviderForm.hidden = true;
    toast('已添加', 'success');
  }

  // ── Settings ───────────────────────────────────────────────────────────

  function handleProxyStatus(payload) {
    state.proxyStatus = payload || {};
    var proxy = payload.proxy || payload;
    var isRunning = proxy.running || false;
    dom.proxyStatusBadge.className = 'status-badge ' + (isRunning ? 'running' : 'stopped');
    dom.proxyStatusBadge.textContent = isRunning ? '运行中' : '已停止';
    dom.proxyPort.textContent = proxy.port || '--';
    dom.proxyAccounts.textContent = proxy.availableAccounts != null ? proxy.availableAccounts : '--';
  }

  function handleDirectoryList(payload) {
    state.directories = (payload && payload.directories) || [];
    var currentPath = (payload && payload.currentPath) || '';
    var parentPath = (payload && payload.parentPath) || '';
    updateCwdDatalist();

    // Only show picker if explicitly browsing (not on initial load)
    if (state.browsingDirs && state.directories.length > 0) {
      showDirectoryPicker(state.directories, currentPath, parentPath);
    }
  }

  function showDirectoryPicker(dirs, currentPath, parentPath) {
    // Create a simple modal picker
    var existing = document.getElementById('dir-picker-overlay');
    if (existing) existing.remove();

    var overlay = document.createElement('div');
    overlay.id = 'dir-picker-overlay';
    overlay.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.6);z-index:2000;display:flex;align-items:center;justify-content:center;padding:20px;';

    var card = document.createElement('div');
    card.style.cssText = 'background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:20px;width:100%;max-width:500px;max-height:70vh;display:flex;flex-direction:column;box-shadow:var(--shadow);';

    var header = '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;">';
    header += '<h3 style="font-size:0.9375rem;font-weight:600;">选择工作目录</h3>';
    header += '<button id="dir-picker-close" style="background:none;border:none;color:var(--text-sec);cursor:pointer;font-size:1.2rem;padding:4px;">&times;</button>';
    header += '</div>';
    header += '<div style="font-size:0.75rem;color:var(--text-dim);margin-bottom:8px;font-family:var(--font-mono);word-break:break-all;">' + escapeHtml(currentPath) + '</div>';

    var list = '<div style="flex:1;overflow-y:auto;">';

    // Parent directory button
    if (parentPath && parentPath !== currentPath) {
      list += '<div class="dir-item" data-path="' + escapeHtml(parentPath) + '" data-browse="true" style="display:flex;align-items:center;gap:8px;padding:10px 12px;cursor:pointer;border-radius:var(--radius-sm);min-height:44px;color:var(--text-sec);">';
      list += '<span style="font-size:1rem;">&#x2191;</span>';
      list += '<span style="font-size:0.8125rem;">..</span>';
      list += '</div>';
    }

    dirs.forEach(function (d) {
      var name = d.split('/').pop() || d;
      list += '<div class="dir-item" data-path="' + escapeHtml(d) + '" style="display:flex;align-items:center;gap:8px;padding:10px 12px;cursor:pointer;border-radius:var(--radius-sm);min-height:44px;transition:background 0.15s;">';
      list += '<span style="font-size:1rem;">&#x1F4C1;</span>';
      list += '<span style="font-size:0.8125rem;flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">' + escapeHtml(name) + '</span>';
      list += '<button class="dir-browse-sub" data-browse="true" data-path="' + escapeHtml(d) + '" style="background:none;border:1px solid var(--border);border-radius:4px;color:var(--text-sec);cursor:pointer;padding:2px 8px;font-size:0.6875rem;">展开</button>';
      list += '</div>';
    });

    list += '</div>';

    card.innerHTML = header + list;
    overlay.appendChild(card);
    document.body.appendChild(overlay);

    // Add hover effect
    overlay.querySelectorAll('.dir-item').forEach(function (el) {
      el.addEventListener('mouseenter', function () { el.style.background = 'var(--card)'; });
      el.addEventListener('mouseleave', function () { el.style.background = ''; });
    });

    // Select directory (click on row, not browse button)
    overlay.querySelectorAll('.dir-item').forEach(function (el) {
      el.addEventListener('click', function (e) {
        if (e.target.closest('.dir-browse-sub')) return;
        if (el.dataset.browse === 'true') {
          // Navigate to parent
          wsSend({ type: 'listDirectories', cwd: el.dataset.path });
          return;
        }
        dom.cwdInput.value = el.dataset.path;
        saveDirHistory(el.dataset.path);
        state.browsingDirs = false;
        overlay.remove();
      });
    });

    // Browse subdirectory
    overlay.querySelectorAll('.dir-browse-sub').forEach(function (btn) {
      btn.addEventListener('click', function (e) {
        e.stopPropagation();
        wsSend({ type: 'listDirectories', cwd: btn.dataset.path });
      });
    });

    // Close
    overlay.querySelector('#dir-picker-close').addEventListener('click', function () { state.browsingDirs = false; overlay.remove(); });
    overlay.addEventListener('click', function (e) {
      if (e.target === overlay) { state.browsingDirs = false; overlay.remove(); }
    });
  }

  // ── Sidebar ────────────────────────────────────────────────────────────

  function openSidebar() {
    dom.sessionSidebar.classList.add('open');
    dom.sidebarBackdrop.classList.add('visible');
    dom.sidebarToggle.setAttribute('aria-expanded', 'true');
    dom.sessionSidebar.setAttribute('aria-hidden', 'false');
    dom.sidebarBackdrop.setAttribute('aria-hidden', 'false');
  }

  function closeSidebar() {
    dom.sessionSidebar.classList.remove('open');
    dom.sidebarBackdrop.classList.remove('visible');
    dom.sidebarToggle.setAttribute('aria-expanded', 'false');
    dom.sessionSidebar.setAttribute('aria-hidden', 'true');
    dom.sidebarBackdrop.setAttribute('aria-hidden', 'true');
  }

  function toggleSidebar() {
    if (dom.sessionSidebar.classList.contains('open')) {
      closeSidebar();
    } else {
      openSidebar();
    }
  }

  // ── Tab Navigation ─────────────────────────────────────────────────────

  function switchTab(tabName) {
    dom.tabBtns.forEach(function (btn) {
      var isActive = btn.dataset.tab === tabName;
      btn.classList.toggle('active', isActive);
      btn.setAttribute('aria-selected', isActive ? 'true' : 'false');
    });

    dom.tabPanels.forEach(function (panel) {
      var panelTab = panel.id.replace('panel-', '');
      var isActive = panelTab === tabName;
      panel.classList.toggle('active', isActive);
      panel.hidden = !isActive;
    });

    // Refresh data when switching to certain tabs
    if (tabName === 'providers') {
      wsSend({ type: 'listAllProviders' });
    } else if (tabName === 'settings') {
      wsSend({ type: 'requestProxyStatus' });
      dom.settingsToken.value = state.token;
    }

    if (window.matchMedia('(max-width: 767px)').matches) {
      closeSidebar();
    }
  }

  function handleQuickAction(action) {
    switch (action) {
      case 'sessions':
        switchTab('chat');
        toggleSidebar();
        break;
      case 'new-session':
        switchTab('chat');
        createSession();
        break;
      case 'providers':
        switchTab('providers');
        break;
      case 'settings':
        switchTab('settings');
        break;
      default:
        break;
    }
  }

  // ── Input Handling ─────────────────────────────────────────────────────

  function autoResizeInput() {
    var el = dom.messageInput;
    el.style.height = 'auto';
    el.style.height = Math.min(el.scrollHeight, 120) + 'px';
  }

  function showSendBtn() {
    dom.sendBtn.style.display = '';
    dom.stopBtn.style.display = 'none';
  }

  function showStopBtn() {
    dom.sendBtn.style.display = 'none';
    dom.stopBtn.style.display = '';
  }

  function updateSendBtnState() {
    var hasText = dom.messageInput.value.trim().length > 0;
    var hasSession = !!state.activeSessionID;
    dom.sendBtn.disabled = !(hasText && hasSession);
  }

  function handleInputChange() {
    autoResizeInput();
    updateSendBtnState();

    var val = dom.messageInput.value;

    // Check for slash command
    if (val.startsWith('/')) {
      var slashText = val.substring(1).split(' ')[0];
      // Show popup while typing command name (before first space)
      // Once a space is typed, autocomplete the selection and dismiss
      if (val.indexOf(' ') === -1) {
        showSlashPopup(slashText);
      } else if (!dom.slashPopup.hidden) {
        // User pressed space — auto-confirm if a command is selected
        confirmSlashPopup();
      }
    } else {
      hideSlashPopup();
    }
  }

  function handleInputKeydown(e) {
    // Slash popup navigation
    if (!dom.slashPopup.hidden) {
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        navigateSlashPopup(1);
        return;
      }
      if (e.key === 'ArrowUp') {
        e.preventDefault();
        navigateSlashPopup(-1);
        return;
      }
      if (e.key === 'Tab' || e.key === 'Enter') {
        if (state.slashPopupIndex >= 0) {
          e.preventDefault();
          confirmSlashPopup();
          return;
        }
      }
      if (e.key === 'Escape') {
        e.preventDefault();
        hideSlashPopup();
        return;
      }
    }

    // Send on Enter (without Shift)
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      if (!dom.sendBtn.disabled) {
        sendMessage();
      }
    }
  }

  // ── Token Management ───────────────────────────────────────────────────

  var tokenVisible = false;

  function toggleTokenVisibility() {
    tokenVisible = !tokenVisible;
    dom.settingsToken.type = tokenVisible ? 'text' : 'password';
  }

  function copyToken() {
    var token = state.token;
    if (!token) return;

    if (navigator.clipboard) {
      navigator.clipboard.writeText(token).then(function () {
        toast('已复制到剪贴板', 'success');
      }).catch(function () {
        fallbackCopy(token);
      });
    } else {
      fallbackCopy(token);
    }
  }

  function fallbackCopy(text) {
    var textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.style.cssText = 'position:fixed;opacity:0;left:-9999px';
    document.body.appendChild(textarea);
    textarea.select();
    textarea.setSelectionRange(0, text.length);
    var ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { /* ignore */ }
    document.body.removeChild(textarea);
    toast(ok ? '已复制' : '请手动复制', ok ? 'success' : 'error');
  }

  function regenerateToken() {
    // Token management is handled in the AIMenu desktop app
    toast('请在 AIMenu 应用中管理令牌', 'info');
  }

  function setCustomToken() {
    toast('请在 AIMenu 应用中设置自定义令牌', 'info');
  }

  // ── Event Binding ──────────────────────────────────────────────────────

  function bindEvents() {
    // Auth form
    dom.authForm.addEventListener('submit', function (e) {
      e.preventDefault();
      var token = dom.authTokenInput.value.trim();
      if (!token) return;

      state.token = token;
      state.authenticating = true;
      localStorage.setItem(STORAGE_TOKEN_KEY, token);
      dom.authSubmitBtn.classList.add('loading');
      dom.authError.textContent = '';

      connect();
    });

    // Tab navigation
    dom.tabBtns.forEach(function (btn) {
      btn.addEventListener('click', function () {
        switchTab(btn.dataset.tab);
      });
    });

    dom.mobileQuickActionBtns.forEach(function (btn) {
      btn.addEventListener('click', function () {
        handleQuickAction(btn.dataset.quickAction);
      });
    });

    // Sidebar
    dom.sidebarToggle.addEventListener('click', toggleSidebar);
    dom.sidebarBackdrop.addEventListener('click', closeSidebar);

    // New session
    dom.newSessionBtn.addEventListener('click', createSession);

    // Message input
    dom.messageInput.addEventListener('input', handleInputChange);
    dom.messageInput.addEventListener('keydown', handleInputKeydown);

    // Send / Stop
    dom.sendBtn.addEventListener('click', sendMessage);
    dom.stopBtn.addEventListener('click', abortSession);

    // Providers
    dom.addProviderBtn.addEventListener('click', function () {
      dom.addProviderForm.hidden = !dom.addProviderForm.hidden;
      if (!dom.addProviderForm.hidden) {
        dom.addProviderForm.querySelector('input')?.focus();
      }
    });
    dom.pfCancel.addEventListener('click', function () {
      dom.addProviderForm.hidden = true;
      dom.providerForm.reset();
    });
    dom.providerForm.addEventListener('submit', addProvider);

    // Filter tabs
    dom.filterTabs.forEach(function (tab) {
      tab.addEventListener('click', function () {
        dom.filterTabs.forEach(function (t) {
          t.classList.remove('active');
          t.setAttribute('aria-selected', 'false');
        });
        tab.classList.add('active');
        tab.setAttribute('aria-selected', 'true');
        state.providerFilter = tab.dataset.filter;
        renderProviders();
      });
    });

    // Settings - Token (read-only: visibility toggle + copy only)
    dom.tokenToggleVis.addEventListener('click', toggleTokenVisibility);
    dom.tokenCopy.addEventListener('click', copyToken);

    // Settings - Disconnect
    dom.disconnectBtn.addEventListener('click', function () {
      disconnect();
      stopPing();
      state.token = '';
      localStorage.removeItem(STORAGE_TOKEN_KEY);
      showAuth();
      toast('已断开连接', 'info');
    });

    // Directory browse
    dom.browseDirBtn.addEventListener('click', function () {
      state.browsingDirs = true;
      wsSend({ type: 'listDirectories', cwd: dom.cwdInput.value.trim() || undefined });
    });

    // Close slash popup when clicking outside
    document.addEventListener('click', function (e) {
      if (!dom.slashPopup.contains(e.target) && e.target !== dom.messageInput) {
        hideSlashPopup();
      }
    });

    // Keyboard shortcut: Escape to close sidebar
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') {
        closeSidebar();
        hideSlashPopup();
      }
    });

    // Handle visibility change (reconnect when coming back)
    document.addEventListener('visibilitychange', function () {
      if (!document.hidden && state.token && !state.connected) {
        connect();
      }
    });
  }

  // ── Initialization ─────────────────────────────────────────────────────

  function init() {
    cacheDom();
    bindEvents();
    updateCwdDatalist();

    // Ensure stop button is hidden initially
    dom.stopBtn.style.display = 'none';

    // If we have a stored token, try auto-connect
    if (state.token) {
      dom.authTokenInput.value = state.token;
      dom.authSubmitBtn.classList.add('loading');
      state.authenticating = true;
      // Short delay for UI to render
      setTimeout(function () {
        connect();
      }, 200);
    } else {
      showAuth();
    }
  }

  // ── Boot ───────────────────────────────────────────────────────────────

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();
