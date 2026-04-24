const els = {
  pipelineSelect: document.getElementById("pipeline-select"),
  title: document.getElementById("task-title"),
  artifactDownloadButton: document.getElementById("artifact-download-button"),
  statusPill: document.getElementById("status-pill"),
  scenarioId: document.getElementById("scenario-id"),
  scenarioQuestion: document.getElementById("scenario-question"),
  appType: document.getElementById("app-type"),
  baseBranch: document.getElementById("base-branch"),
  branchName: document.getElementById("branch-name"),
  workspace: document.getElementById("workspace"),
  workspaceCopyButton: document.getElementById("workspace-copy-button"),
  agentPid: document.getElementById("agent-pid"),
  startedAt: document.getElementById("started-at"),
  updatedAt: document.getElementById("updated-at"),
  runtimeDuration: document.getElementById("runtime-duration"),
  progressLabel: document.getElementById("progress-label"),
  progressPercent: document.getElementById("progress-percent"),
  progressBar: document.getElementById("progress-bar"),
  steps: document.getElementById("steps"),
  inspectionStatus: document.getElementById("inspection-status"),
  inspectionCycles: document.getElementById("inspection-cycles"),
  inspectionLast: document.getElementById("inspection-last"),
  inspectionMessage: document.getElementById("inspection-message"),
  pipelineLog: document.getElementById("pipeline-log"),
  agentLog: document.getElementById("agent-log"),
  terminateButton: document.getElementById("terminate-button"),
  shutdownConsoleButton: document.getElementById("shutdown-console-button"),
  terminateHint: document.getElementById("terminate-hint"),
  agentRunningState: document.getElementById("agent-running-state"),
  agentName: document.getElementById("agent-name"),
  agentModel: document.getElementById("agent-model"),
  agentProvider: document.getElementById("agent-provider"),
  agentApproval: document.getElementById("agent-approval"),
  agentSandbox: document.getElementById("agent-sandbox"),
  agentReasoningEffort: document.getElementById("agent-reasoning-effort"),
  agentReasoningSummary: document.getElementById("agent-reasoning-summary"),
  agentSessionId: document.getElementById("agent-session-id"),
};

let latestTask = null;
let currentPipeline = "baseApp";
const BEIJING_OFFSET_MINUTES = 8 * 60;

function fmt(value) {
  return value || "-";
}

function formatBytes(bytes) {
  const value = Number(bytes);
  if (!Number.isFinite(value) || value < 0) return "-";
  if (value < 1024) return `${value} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let size = value / 1024;
  let unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }
  return `${size.toFixed(size >= 10 ? 0 : 1)} ${units[unitIndex]}`;
}

function formatDisplayTime(value) {
  if (!value) return "-";
  const text = String(value).trim();
  if (!text) return "-";
  const match = text.match(/^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})(?:[+-]\d{2}:\d{2}|Z)?$/);
  if (match) return `${match[1]} ${match[2]}`;
  return text;
}

function setText(el, value) {
  const text = fmt(value);
  el.textContent = text;
  el.title = text;
}

function parseDisplayTimeMs(value) {
  if (!value) return null;
  const text = String(value).trim();
  const match = text.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:([+-])(\d{2}):(\d{2})|Z)?$/);
  if (!match) return null;

  const utcMs = Date.UTC(
    Number(match[1]),
    Number(match[2]) - 1,
    Number(match[3]),
    Number(match[4]),
    Number(match[5]),
    Number(match[6])
  );

  if (match[7]) {
    const sign = match[7] === "+" ? 1 : -1;
    const offsetMinutes = Number(match[8]) * 60 + Number(match[9]);
    return utcMs - sign * offsetMinutes * 60 * 1000;
  }
  return utcMs - BEIJING_OFFSET_MINUTES * 60 * 1000;
}

function formatDurationSeconds(totalSeconds) {
  const safeSeconds = Math.max(0, Math.floor(Number(totalSeconds) || 0));
  const days = Math.floor(safeSeconds / 86400);
  const hours = Math.floor((safeSeconds % 86400) / 3600);
  const minutes = Math.floor((safeSeconds % 3600) / 60);
  const seconds = safeSeconds % 60;
  const hhmmss = [hours, minutes, seconds].map((part) => String(part).padStart(2, "0")).join(":");
  return days > 0 ? `${days}d ${hhmmss}` : hhmmss;
}

function formatRuntimeDuration(startValue, endValue) {
  const startMs = parseDisplayTimeMs(startValue);
  if (startMs === null) return "-";
  const endMs = endValue ? parseDisplayTimeMs(endValue) : Date.now();
  if (endMs === null) return "-";
  return formatDurationSeconds((endMs - startMs) / 1000);
}

function getRuntimeStart(task) {
  return task.runtimeStartedAt || task.createdAt || task.agent.startedAt || null;
}

function isTerminalStatus(status) {
  return ["cancelled", "pushed", "completed", "build_failed", "agent_exited_without_result", "dry_run_success_detected"].includes(status);
}

function getRuntimeEnd(task) {
  if (task.runtimeEndedAt) return task.runtimeEndedAt;
  if (isTerminalStatus(task.status)) return null;
  return task.updatedAt || null;
}

async function copyToClipboard(text) {
  if (!text || text === "-") return false;
  if (navigator.clipboard && navigator.clipboard.writeText) {
    await navigator.clipboard.writeText(text);
    return true;
  }

  const textarea = document.createElement("textarea");
  textarea.value = text;
  textarea.setAttribute("readonly", "");
  textarea.style.position = "fixed";
  textarea.style.opacity = "0";
  document.body.appendChild(textarea);
  textarea.select();
  const copied = document.execCommand("copy");
  document.body.removeChild(textarea);
  return copied;
}

function classifyStatus(status) {
  if (["pushed", "completed", "dry_run_success_detected", "ready"].includes(status)) return "status-success";
  if (["build_failed", "agent_exited_without_result"].includes(status)) return "status-failed";
  if (status === "cancelled") return "status-cancelled";
  return "status-running";
}

function renderArtifact(task) {
  const artifact = task.artifact;
  if (!artifact || !artifact.downloadUrl) {
    els.artifactDownloadButton.classList.add("is-hidden");
    els.artifactDownloadButton.removeAttribute("href");
    els.artifactDownloadButton.removeAttribute("download");
    els.artifactDownloadButton.removeAttribute("title");
    return;
  }

  els.artifactDownloadButton.classList.remove("is-hidden");
  els.artifactDownloadButton.href = `${artifact.downloadUrl}`;
  els.artifactDownloadButton.setAttribute("download", artifact.name || "app.hap");
  const meta = [artifact.name, formatBytes(artifact.sizeBytes)].filter((part) => part && part !== "-").join(" · ");
  els.artifactDownloadButton.title = meta || "下载 HAP 安装包";
}

function renderPipelineOptions(items) {
  const previous = currentPipeline;
  els.pipelineSelect.innerHTML = "";
  items.forEach((item) => {
    const option = document.createElement("option");
    option.value = item.key;
    option.textContent = item.type === "baseApp" ? "baseApp" : `${item.key} (${item.status})`;
    if (item.key === previous) option.selected = true;
    els.pipelineSelect.appendChild(option);
  });
  if (![...els.pipelineSelect.options].some((option) => option.value === previous) && els.pipelineSelect.options.length > 0) {
    currentPipeline = els.pipelineSelect.options[0].value;
  }
  els.pipelineSelect.value = currentPipeline;
}

function renderTask(task) {
  latestTask = task;
  const runtime = task.agent.runtime || {};
  renderArtifact(task);
  els.title.textContent = task.pipelineName || task.pipelineKey || "当前任务";
  setText(els.statusPill, task.status);
  els.statusPill.className = `card-state ${classifyStatus(task.status)}`;
  setText(els.scenarioId, task.scenarioId || task.pipelineKey);
  setText(els.scenarioQuestion, task.scenarioQuestion || task.pipelineRoot || "当前 pipeline 无场景说明");
  setText(els.appType, task.appDisplayName || task.appType);
  setText(els.baseBranch, task.baseBranch);
  setText(els.branchName, task.branchName);
  setText(els.workspace, task.pipelineRoot || task.agent.workspace || runtime.workspace);
  setText(els.agentPid, task.agent.pid);
  setText(els.startedAt, formatDisplayTime(task.agent.startedAt));
  setText(els.updatedAt, formatDisplayTime(task.updatedAt));
  setText(els.agentRunningState, task.agent.running ? "运行中" : "未运行");
  els.agentRunningState.className = `card-state ${task.agent.running ? "status-running" : "status-cancelled"}`;
  setText(els.agentName, runtime.name || task.agent.type);
  setText(els.agentModel, runtime.model);
  setText(els.agentProvider, runtime.provider);
  setText(els.agentApproval, runtime.approval_policy);
  setText(els.agentSandbox, runtime.sandbox_mode);
  setText(els.agentReasoningEffort, runtime.reasoning_effort);
  setText(els.agentReasoningSummary, runtime.reasoning_summary);
  setText(els.agentSessionId, task.agent.sessionId || runtime.session_id || runtime.sessionId);
  setText(els.progressLabel, task.progress.label);
  setText(els.progressPercent, `${task.progress.percent || 0}%`);
  els.progressPercent.className = "card-state status-progress";
  els.progressBar.style.width = `${task.progress.percent || 0}%`;
  els.steps.innerHTML = "";

  (task.progress.steps || []).forEach((step, index) => {
    const li = document.createElement("li");
    li.className = "progress-step";
    if (index + 1 < task.progress.currentStep) li.classList.add("done");
    if (index + 1 === task.progress.currentStep) li.classList.add("active");
    li.innerHTML = `<span class="step-node" aria-hidden="true"></span><span class="step-text">${step}</span>`;
    els.steps.appendChild(li);
  });

  setText(els.inspectionStatus, task.inspection.status);
  els.inspectionStatus.className = `card-state ${classifyStatus(task.inspection.status)}`;
  setText(els.runtimeDuration, formatRuntimeDuration(getRuntimeStart(task), getRuntimeEnd(task)));
  setText(els.inspectionCycles, task.inspection.cycleCount);
  setText(els.inspectionLast, formatDisplayTime(task.inspection.lastCheckedAt));
  setText(els.inspectionMessage, task.inspection.message);

  const terminal = isTerminalStatus(task.status) || task.pipelineType === "baseApp" || task.status === "idle" || task.status === "ready";
  els.terminateButton.disabled = terminal;
  if (terminal) {
    els.terminateHint.textContent = "当前对象不可终止。";
  }
}

function refreshRuntimeDurationTick() {
  if (!latestTask) return;
  setText(els.runtimeDuration, formatRuntimeDuration(getRuntimeStart(latestTask), getRuntimeEnd(latestTask)));
}

els.workspaceCopyButton.addEventListener("click", async () => {
  const workspace = els.workspace.textContent.trim();
  try {
    const copied = await copyToClipboard(workspace);
    els.workspaceCopyButton.textContent = copied ? "✓" : "!";
    els.workspaceCopyButton.title = copied ? "已复制" : "复制失败";
    window.setTimeout(() => {
      els.workspaceCopyButton.textContent = "⧉";
      els.workspaceCopyButton.title = "复制工作空间";
    }, 1000);
  } catch (error) {
    els.workspaceCopyButton.textContent = "!";
    els.workspaceCopyButton.title = `复制失败: ${error}`;
    window.setTimeout(() => {
      els.workspaceCopyButton.textContent = "⧉";
      els.workspaceCopyButton.title = "复制工作空间";
    }, 1200);
  }
});

async function fetchJson(url, options = {}) {
  const res = await fetch(url, { cache: "no-store", ...options });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.json();
}

async function refreshPipelineList() {
  const payload = await fetchJson("/api/pipelines");
  renderPipelineOptions(payload.items || []);
}

async function refreshLogs() {
  const logs = await fetchJson(`/api/pipelines/current/logs?pipeline=${encodeURIComponent(currentPipeline)}`);
  els.pipelineLog.textContent = logs.pipelineLog || "暂无日志";
  els.agentLog.textContent = logs.agentLog || "暂无日志";
}

async function refreshTask() {
  const task = await fetchJson(`/api/pipelines/current?pipeline=${encodeURIComponent(currentPipeline)}`);
  renderTask(task);
}

async function refreshAll() {
  try {
    await refreshPipelineList();
    await Promise.all([refreshTask(), refreshLogs()]);
    els.terminateHint.textContent = "";
  } catch (error) {
    els.terminateHint.textContent = `刷新失败: ${error}`;
  }
}

els.pipelineSelect.addEventListener("change", async (event) => {
  currentPipeline = event.target.value;
  await refreshAll();
});

els.terminateButton.addEventListener("click", async () => {
  const confirmed = window.confirm(`确定终止 ${currentPipeline} 的 Agent 任务吗？`);
  if (!confirmed) return;
  els.terminateButton.disabled = true;
  try {
    const payload = await fetchJson(`/api/pipelines/current/terminate?pipeline=${encodeURIComponent(currentPipeline)}`, { method: "POST" });
    els.terminateHint.textContent = payload.ok ? "终止请求已提交。" : "终止失败。";
    await refreshAll();
  } catch (error) {
    els.terminateHint.textContent = `终止失败: ${error}`;
  }
});

els.shutdownConsoleButton.addEventListener("click", async () => {
  const confirmed = window.confirm("确定关闭当前 Web 控制台吗？");
  if (!confirmed) return;
  els.shutdownConsoleButton.disabled = true;
  try {
    // 与 terminate 一样必须为 POST，否则走 GET 会得到 404，页面无法进入“已关闭”状态
    const payload = await fetchJson("/api/console/shutdown", { method: "POST" });
    els.terminateHint.textContent = payload.ok ? "控制台正在关闭。" : "关闭控制台失败。";
    window.setTimeout(() => {
      window.clearInterval(refreshAllIntervalId);
      window.clearInterval(refreshRuntimeIntervalId);
      document.body.innerHTML = "<main class=\"shell\"><section class=\"card hero-card\"><div><p class=\"eyebrow\">Console Closed</p><h1>控制台已关闭</h1><p class=\"card-note\">请重新执行 run_pipeline 再次启动 Web 页面。</p></div></section></main>";
    }, 500);
  } catch (error) {
    els.shutdownConsoleButton.disabled = false;
    els.terminateHint.textContent = `关闭控制台失败: ${error}`;
  }
});

refreshAll();
const refreshAllIntervalId = window.setInterval(refreshAll, 3000);
const refreshRuntimeIntervalId = window.setInterval(refreshRuntimeDurationTick, 1000);
