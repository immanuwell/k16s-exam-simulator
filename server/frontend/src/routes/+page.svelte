<script>
  import { onMount, onDestroy } from 'svelte';
  import { marked } from 'marked';
  import { api } from '$lib/api.js';

  // ── State ──────────────────────────────────────────────────────────────────
  let view       = $state('loading'); // loading | home | exam | results
  let profile    = $state('cka');
  let duration   = $state(7200);
  let session    = $state(null);
  let questions  = $state([]);
  let profiles   = $state([]);
  let currentIdx = $state(0);
  let checking   = $state(false);
  let setting_up = $state(false);
  let checkResult = $state(null);
  let timeLeft   = $state(0);
  let error      = $state('');

  let timerInterval = null;
  let terminalIframe = $state(null);
  let rightPanel = $state('terminal'); // terminal | desktop
  let desktopLoaded = $state(false);

  function selectPanel(p) {
    rightPanel = p;
    if (p === 'desktop') desktopLoaded = true;
  }

  // ── Derived ────────────────────────────────────────────────────────────────
  let currentQuestion = $derived(questions[currentIdx] ?? null);
  let progress        = $derived(session?.progress ?? {});

  let score = $derived(
    questions.reduce((acc, q) => progress[q.id]?.status === 'passed' ? acc + q.weight : acc, 0)
  );
  let totalPoints = $derived(questions.reduce((acc, q) => acc + q.weight, 0));

  let ckaProfiles = $derived((profiles.length ? profiles : ['cka']).filter(p => p.startsWith('cka')));
  let cksProfiles = $derived((profiles.length ? profiles : ['cks']).filter(p => p.startsWith('cks')));

  function labelFor(p, group) {
    const sorted = [...group].sort();
    const prefix = p.startsWith('cka') ? 'CKA' : 'CKS';
    return `${prefix} ${sorted.indexOf(p) + 1}`;
  }

  function examLabel(p) {
    const group = (profiles.length ? profiles : [p]).filter(x =>
      x.startsWith(p.startsWith('cka') ? 'cka' : 'cks')
    );
    return labelFor(p, group);
  }

  let timeClass = $derived(
    timeLeft < 300 ? 'text-red-400 animate-pulse' :
    timeLeft < 600 ? 'text-amber-400' :
    'text-slate-200'
  );

  // ── Helpers ────────────────────────────────────────────────────────────────
  function fmt(secs) {
    const h = Math.floor(secs / 3600).toString().padStart(2, '0');
    const m = Math.floor((secs % 3600) / 60).toString().padStart(2, '0');
    const s = (secs % 60).toString().padStart(2, '0');
    return `${h}:${m}:${s}`;
  }

  function statusClass(id) {
    const s = progress[id]?.status;
    if (s === 'passed')   return 'bg-green-700 text-green-100 ring-green-600';
    if (s === 'failed')   return 'bg-red-800   text-red-100   ring-red-700';
    if (s === 'attempted') return 'bg-amber-700 text-amber-100 ring-amber-600';
    return 'bg-[#4a5169] text-slate-400 ring-[#6b7392]';
  }

  // Exam text is authored as Markdown in the YAML under /var/lib/k16s/exams.
  // The previous hand-rolled renderer dropped ordered lists entirely and emitted
  // fenced code blocks as <pre> nested inside <p>, which browsers auto-close into
  // a run of stray empty paragraphs. marked handles the full grammar — including
  // the numbered steps and indented fences the questions actually use.
  //
  // Exam content is root-owned and ships with the repo, so it is trusted, but the
  // old renderer escaped raw HTML and there is no reason to start honouring it:
  // render literal tags as visible text rather than live markup. marked escapes
  // everything else itself, so this must not be combined with pre-escaping the
  // input — that would double-escape entities inside code blocks.
  const escapeHtml = (s) =>
    s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

  marked.use({
    gfm: true,
    renderer: {
      html: (token) => escapeHtml(token.text),
    },
  });

  function md(text) {
    if (!text) return '';
    return marked.parse(text);
  }

  // ── Timer ──────────────────────────────────────────────────────────────────
  function startTimer() {
    clearInterval(timerInterval);
    timerInterval = setInterval(() => {
      if (!session) return;
      const elapsed = Math.floor((Date.now() - new Date(session.started_at).getTime()) / 1000);
      timeLeft = Math.max(0, session.duration_secs - elapsed);
      if (timeLeft === 0) endExam();
    }, 1000);
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  onMount(async () => {
    try {
      const status = await api.get('/api/status');
      profiles = status.profiles ?? [];
      if (status.session) {
        session = status.session;
        const data = await api.get('/api/questions?profile=' + session.profile);
        questions = data.questions ?? [];
        if (session.ended_at) {
          view = 'results';
        } else {
          view = 'exam';
          startTimer();
        }
      } else {
        view = 'home';
      }
    } catch (e) {
      error = e.message;
      view = 'home';
    }
  });

  onDestroy(() => clearInterval(timerInterval));

  // ── Actions ────────────────────────────────────────────────────────────────
  async function startExam() {
    error = '';
    try {
      const resp = await api.post('/api/session/start', { profile, duration_secs: duration });
      session = resp.session;
      const data = await api.get('/api/questions?profile=' + profile);
      questions = data.questions ?? [];
      currentIdx = 0;
      checkResult = null;
      view = 'exam';
      startTimer();
    } catch (e) {
      error = e.message;
    }
  }

  async function checkAnswer() {
    if (!currentQuestion || checking) return;
    checking = true;
    checkResult = null;
    try {
      const result = await api.post('/api/questions/' + currentQuestion.id + '/check', {});
      checkResult = result;
      session = await api.get('/api/session');
    } catch (e) {
      checkResult = { passed: false, output: e.message };
    } finally {
      checking = false;
    }
  }

  async function setupEnv() {
    if (!currentQuestion || setting_up) return;
    setting_up = true;
    checkResult = null;
    try {
      const result = await api.post('/api/questions/' + currentQuestion.id + '/setup', {});
      checkResult = { passed: result.ok, output: result.output, isSetup: true };
      session = await api.get('/api/session');
    } catch (e) {
      checkResult = { passed: false, output: e.message, isSetup: true };
    } finally {
      setting_up = false;
    }
  }

  async function endExam() {
    clearInterval(timerInterval);
    try {
      const resp = await api.post('/api/session/end', {});
      session = resp.session;
    } catch (e) {
      // Session may have already ended (timer ran out and we already called endExam)
    }
    view = 'results';
  }

  function selectQuestion(idx) {
    currentIdx = idx;
    checkResult = null;
  }

  async function newExam() {
    session = null;
    questions = [];
    checkResult = null;
    view = 'home';
  }
</script>

<!-- ── Loading ─────────────────────────────────────────────────────────── -->
{#if view === 'loading'}
  <div class="h-screen flex items-center justify-center">
    <div class="text-slate-400 text-sm">Connecting…</div>
  </div>

<!-- ── Home / Start ────────────────────────────────────────────────────── -->
{:else if view === 'home'}
  <div class="h-screen flex flex-col items-center justify-center gap-8 px-4">
    <div class="text-center">
      <img src="/logo.svg" alt="K16S" class="h-12 mx-auto mb-1" />
      <div class="text-slate-400 text-sm tracking-widest uppercase">Kubernetes Exam Practice</div>
    </div>

    {#if error}
      <div class="text-red-400 text-sm bg-red-950/40 border border-red-900 rounded px-4 py-2 max-w-sm text-center">
        {error}
      </div>
    {/if}

    <div class="bg-[#3b4256] border border-[#5a6280] rounded-lg p-6 w-full max-w-sm space-y-5">
      <div>
        <div class="block text-xs text-slate-400 uppercase tracking-wider mb-1.5">Exam Profile</div>
        <div class="flex gap-2">
          {#if ckaProfiles.length}
            <div class="flex-1 border border-[#5a6280] rounded-md px-2 pt-1.5 pb-2 space-y-1.5">
              <div class="text-[10px] text-slate-500 uppercase tracking-widest text-center">CKA</div>
              <div class="flex gap-1.5">
                {#each ckaProfiles.sort() as p}
                  <button
                    onclick={() => profile = p}
                    class="flex-1 py-1.5 rounded text-sm font-medium transition-colors {profile === p
                      ? 'bg-[#3b82f6] text-white'
                      : 'bg-[#4a5169] text-slate-400 hover:text-slate-200'}"
                  >{labelFor(p, ckaProfiles)}</button>
                {/each}
              </div>
            </div>
          {/if}
          {#if cksProfiles.length}
            <div class="flex-1 border border-[#5a6280] rounded-md px-2 pt-1.5 pb-2 space-y-1.5">
              <div class="text-[10px] text-slate-500 uppercase tracking-widest text-center">CKS</div>
              <div class="flex gap-1.5">
                {#each cksProfiles.sort() as p}
                  <button
                    onclick={() => profile = p}
                    class="flex-1 py-1.5 rounded text-sm font-medium transition-colors {profile === p
                      ? 'bg-[#3b82f6] text-white'
                      : 'bg-[#4a5169] text-slate-400 hover:text-slate-200'}"
                  >{labelFor(p, cksProfiles)}</button>
                {/each}
              </div>
            </div>
          {/if}
        </div>
      </div>

      <div>
        <div class="block text-xs text-slate-400 uppercase tracking-wider mb-1.5">Duration</div>
        <div class="flex gap-2">
          {#each [{label:'2h', val:7200},{label:'3h', val:10800},{label:'30m', val:1800}] as opt}
            <button
              onclick={() => duration = opt.val}
              class="flex-1 py-2 rounded text-sm font-medium transition-colors {duration === opt.val
                ? 'bg-[#3b82f6] text-white'
                : 'bg-[#4a5169] text-slate-400 hover:text-slate-200'}"
            >{opt.label}</button>
          {/each}
        </div>
      </div>

      <button
        onclick={startExam}
        class="w-full py-2.5 bg-[#3b82f6] hover:bg-[#2563eb] text-white font-semibold rounded transition-colors"
      >Start Exam</button>
    </div>

    <p class="text-slate-500 text-xs">
      Open the <a href="/terminal/" target="_blank" class="text-slate-400 hover:text-slate-300 underline">terminal</a>
      or the <a href="/desktop/vnc_lite.html?autoconnect=true&scale=true&reconnect=true&path=desktop/websockify" target="_blank" class="text-slate-400 hover:text-slate-300 underline">desktop</a>
      before starting.
    </p>
  </div>

<!-- ── Exam ────────────────────────────────────────────────────────────── -->
{:else if view === 'exam'}
  <div class="h-screen flex flex-col" style="height: 100dvh">

    <!-- Header -->
    <div class="flex-none bg-[#454c63] border-b border-[#5a6280] px-4 py-2 flex items-center gap-3">
      <img src="/logo.svg" alt="K16S" class="h-5 shrink-0" />
      <span class="text-slate-500 text-sm shrink-0 hidden sm:block">{session?.profile ? examLabel(session.profile) : ''}</span>

      <!-- Question nav pills -->
      <div class="flex gap-1 flex-wrap flex-1 min-w-0 overflow-hidden">
        {#each questions as q, i}
          <button
            onclick={() => selectQuestion(i)}
            class="w-7 h-7 rounded text-xs font-mono font-medium transition-all ring-1 {statusClass(q.id)}
                   {i === currentIdx ? 'ring-2 ring-white/50 scale-110' : 'ring-transparent'}"
            title={q.title}
          >{i + 1}</button>
        {/each}
      </div>

      <!-- Timer -->
      <span class="font-mono text-sm shrink-0 {timeClass}" title="Time remaining">{fmt(timeLeft)}</span>

      <button
        onclick={endExam}
        class="shrink-0 px-3 py-1 bg-red-900/60 hover:bg-red-800 text-red-300 text-xs rounded border border-red-800 transition-colors"
      >End Exam</button>
    </div>

    <!-- Body: question panel + terminal -->
    <div class="flex-1 flex overflow-hidden">

      <!-- Question Panel -->
      <div class="w-[30%] min-w-64 flex flex-col border-r border-[#5a6280] overflow-hidden">
        {#if currentQuestion}
          <div class="flex-1 overflow-y-auto p-4 space-y-4">
            <div class="flex items-start justify-between gap-2">
              <div>
                <div class="text-xs text-slate-400 uppercase tracking-wide mb-0.5">
                  Task {currentIdx + 1} of {questions.length}
                </div>
                <h2 class="text-base font-semibold text-[#eef0f5]">{currentQuestion.title}</h2>
              </div>
              <span class="shrink-0 text-xs bg-[#4a5169] text-slate-400 px-2 py-1 rounded font-mono">
                {currentQuestion.weight}pt{currentQuestion.weight !== 1 ? 's' : ''}
              </span>
            </div>

            {#if currentQuestion.context}
              <div class="text-xs text-slate-400">
                Context: <code class="text-slate-400">{currentQuestion.context}</code>
              </div>
            {/if}

            <div
              class="text-sm text-slate-300 leading-relaxed
                     [&_p]:my-2 [&_strong]:text-slate-200 [&_strong]:font-semibold
                     [&_ul]:list-disc [&_ol]:list-decimal [&_ul]:pl-5 [&_ol]:pl-5
                     [&_ul]:my-2 [&_ol]:my-2 [&_li]:my-1 [&_li]:pl-1
                     [&_li>ul]:my-1 [&_li>ol]:my-1
                     [&_pre]:my-2 [&_li_pre]:my-1.5
                     [&_h1]:text-base [&_h2]:text-base [&_h3]:text-sm
                     [&_h1]:font-semibold [&_h2]:font-semibold [&_h3]:font-semibold
                     [&_h1]:text-slate-200 [&_h2]:text-slate-200 [&_h3]:text-slate-200
                     [&_h1]:mt-4 [&_h2]:mt-4 [&_h3]:mt-3 [&_h1]:mb-1 [&_h2]:mb-1 [&_h3]:mb-1
                     [&_a]:text-[#3b82f6] [&_a]:underline hover:[&_a]:text-blue-300
                     [&_blockquote]:border-l-2 [&_blockquote]:border-[#5a6280]
                     [&_blockquote]:pl-3 [&_blockquote]:text-slate-400 [&_blockquote]:my-2
                     [&>*:first-child]:mt-0 [&>*:last-child]:mb-0"
            >
              {@html md(currentQuestion.description)}
            </div>

            {#if currentQuestion.hint}
              <details class="group">
                <summary class="cursor-pointer text-xs text-[#3b82f6] hover:text-blue-300 select-none">
                  Show hint
                </summary>
                <div class="mt-2 text-xs text-slate-400 bg-[#3b4256] border border-[#5a6280] rounded p-3 leading-relaxed">
                  {currentQuestion.hint}
                </div>
              </details>
            {/if}

            {#if checkResult}
              <div class="rounded border {checkResult.passed
                ? 'border-green-800 bg-green-950/40'
                : 'border-red-900 bg-red-950/30'} p-3">
                <div class="text-xs font-semibold mb-1 {checkResult.passed ? 'text-green-400' : 'text-red-400'}">
                  {#if checkResult.isSetup}
                    {checkResult.passed ? 'Environment ready' : 'Setup failed'}
                  {:else}
                    {checkResult.passed ? 'PASSED' : 'FAILED'}
                  {/if}
                </div>
                {#if checkResult.output}
                  <pre class="text-xs text-slate-400 whitespace-pre-wrap !bg-transparent !border-0 !p-0">{checkResult.output}</pre>
                {/if}
              </div>
            {/if}
          </div>

          <!-- Action bar -->
          <div class="flex-none border-t border-[#5a6280] p-3 flex gap-2">
            <button
              onclick={setupEnv}
              disabled={setting_up}
              class="flex-1 py-1.5 text-xs rounded border border-[#5a6280] text-slate-400 hover:text-slate-200 hover:border-slate-500 transition-colors disabled:opacity-50"
            >{setting_up ? 'Setting up…' : 'Setup Env'}</button>
            <button
              onclick={checkAnswer}
              disabled={checking}
              class="flex-1 py-1.5 text-xs rounded bg-[#3b82f6] hover:bg-[#2563eb] text-white font-medium transition-colors disabled:opacity-50"
            >{checking ? 'Checking…' : 'Check Answer'}</button>
          </div>
        {/if}
      </div>

      <!-- Terminal / Desktop -->
      <div class="flex-1 flex flex-col overflow-hidden">
        <div class="flex-none flex gap-1 bg-[#454c63] border-b border-[#5a6280] px-2 py-1.5">
          <button
            onclick={() => selectPanel('terminal')}
            class="px-3 py-1 rounded text-xs font-medium transition-colors {rightPanel === 'terminal'
              ? 'bg-[#3b82f6] text-white'
              : 'bg-[#4a5169] text-slate-400 hover:text-slate-200'}"
          >Terminal</button>
          <button
            onclick={() => selectPanel('desktop')}
            class="px-3 py-1 rounded text-xs font-medium transition-colors {rightPanel === 'desktop'
              ? 'bg-[#3b82f6] text-white'
              : 'bg-[#4a5169] text-slate-400 hover:text-slate-200'}"
          >Desktop</button>
        </div>

        <div class="flex-1 relative">
          <iframe
            bind:this={terminalIframe}
            src="/terminal/"
            title="Terminal"
            class="absolute inset-0 w-full h-full border-0"
            style={rightPanel === 'terminal' ? '' : 'display:none'}
            onload={() => {
              const win = terminalIframe?.contentWindow;
              if (!win) return;
              win.focus();
              win.document.addEventListener('keydown', (e) => {
                if (e.ctrlKey && e.shiftKey && e.key.toUpperCase() === 'C') {
                  e.preventDefault();
                  e.stopPropagation();
                  const text = win.term?.getSelection?.();
                  if (text) navigator.clipboard.writeText(text).catch(() => {});
                }
              }, true);
            }}
          ></iframe>

          {#if desktopLoaded}
            <iframe
              src="/desktop/vnc_lite.html?autoconnect=true&scale=true&reconnect=true&path=desktop/websockify"
              title="Desktop"
              class="absolute inset-0 w-full h-full border-0"
              style={rightPanel === 'desktop' ? '' : 'display:none'}
            ></iframe>
          {/if}
        </div>
      </div>

    </div>
  </div>

<!-- ── Results ─────────────────────────────────────────────────────────── -->
{:else if view === 'results'}
  <div class="h-screen flex flex-col items-center justify-start overflow-y-auto py-12 px-4 gap-8">
    <div class="text-center">
      <div class="text-4xl font-bold text-white mb-1">
        <span class="text-[#3b82f6]">{score}</span>
        <span class="text-slate-400 text-2xl">/{totalPoints}</span>
      </div>
      <div class="text-slate-400 text-sm">
        {session?.profile ? examLabel(session.profile) : ''} — {Math.round((score / (totalPoints || 1)) * 100)}% score
      </div>
    </div>

    <div class="w-full max-w-lg space-y-2">
      {#each questions as q, i}
        {@const p = progress[q.id]}
        <div class="flex items-start gap-3 bg-[#3b4256] border border-[#5a6280] rounded p-3">
          <div class="w-6 h-6 rounded flex items-center justify-center text-xs font-mono shrink-0 mt-0.5
            {p?.status === 'passed' ? 'bg-green-700 text-green-100' :
             p?.status === 'failed' ? 'bg-red-800 text-red-100' :
             'bg-[#4a5169] text-slate-400'}"
          >{i + 1}</div>
          <div class="flex-1 min-w-0">
            <div class="text-sm text-slate-300">{q.title}</div>
            <div class="text-xs text-slate-500 mt-0.5">{q.weight} pt{q.weight !== 1 ? 's' : ''}</div>
          </div>
          <div class="text-xs font-medium shrink-0 mt-0.5
            {p?.status === 'passed' ? 'text-green-400' :
             p?.status === 'failed' ? 'text-red-400' :
             'text-slate-500'}"
          >
            {p?.status === 'passed' ? '+'+q.weight : p?.status === 'failed' ? '0' : '—'}
          </div>
        </div>
      {/each}
    </div>

    <button
      onclick={newExam}
      class="px-6 py-2.5 bg-[#3b82f6] hover:bg-[#2563eb] text-white font-semibold rounded transition-colors"
    >New Exam</button>
  </div>
{/if}
