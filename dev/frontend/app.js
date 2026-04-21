const els = {
  title: document.getElementById("task-title"),
  statusPill: document.getElementById("status-pill"),
  scenarioId: document.getElementById("scenario-id"),
  scenarioQuestion: document.getElementById("scenario-question"),
  appType: document.getElementById("app-type"),
  baseBranch: document.getElementById("base-branch"),
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
const BEIJING_OFFSET_MINUTES = 8 * 60;

function fmt(value) {
  return value || "-";
}

function formatDisplayTime(value) {
  if (!value) return "-";
  const text = String(value).trim();
  if (!text) return "-";
  const match = text.match(/^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})(?:[+-]\d{2}:\d{2}|Z)?$/);
  if (match) {
    return `${match[1]} ${match[2]}`;
  }
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
  if (["pushed", "completed", "dry_run_success_detected"].includes(status)) return "status-success";
  if (["build_failed", "agent_exited_without_result"].includes(status)) return "status-failed";
  if (status === "cancelled") return "status-cancelled";
  return "status-running";
}

function renderTask(task) {
  const runtime = task.agent.runtime || {};
  els.title.textContent = task.scenarioBranch || task.scenarioKey || "当前任务";
  setText(els.statusPill, task.status);
  els.statusPill.className = `card-state ${classifyStatus(task.status)}`;
  setText(els.scenarioId, task.scenarioId);
  setText(els.scenarioQuestion, task.scenarioQuestion);
  setText(els.appType, task.appDisplayName || task.appType);
  setText(els.baseBranch, task.baseBranch);
  setText(els.workspace, task.agent.workspace || runtime.workspace);
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

  const terminal = isTerminalStatus(task.status);
  els.terminateButton.disabled = terminal;
  if (terminal) {
    els.terminateHint.textContent = "当前状态不可再终止。";
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

async function refreshLogs() {
  const res = await fetch("/api/task/current/logs", { cache: "no-store" });
  const logs = await res.json();
  els.pipelineLog.textContent = logs.pipelineLog || "暂无日志";
  els.agentLog.textContent = logs.agentLog || "暂无日志";
}

async function refreshTask() {
  const res = await fetch("/api/task/current", { cache: "no-store" });
  const task = await res.json();
  latestTask = task;
  renderTask(task);
}

async function refreshAll() {
  try {
    await Promise.all([refreshTask(), refreshLogs()]);
    els.terminateHint.textContent = "";
  } catch (error) {
    els.terminateHint.textContent = `刷新失败: ${error}`;
  }
}

els.terminateButton.addEventListener("click", async () => {
  const confirmed = window.confirm("确定终止当前 Agent 任务吗？");
  if (!confirmed) return;
  els.terminateButton.disabled = true;
  try {
    const res = await fetch("/api/task/current/terminate", { method: "POST" });
    const payload = await res.json();
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
    const res = await fetch("/api/console/shutdown", { method: "POST" });
    const payload = await res.json();
    els.terminateHint.textContent = payload.ok ? "控制台正在关闭。" : "关闭控制台失败。";
    window.setTimeout(() => {
      document.body.innerHTML = "<main class=\"shell\"><section class=\"card hero-card\"><div><p class=\"eyebrow\">Console Closed</p><h1>控制台已关闭</h1><p class=\"card-note\">请重新执行 run_pipeline 再次启动 Web 页面。</p></div></section></main>";
    }, 500);
  } catch (error) {
    els.shutdownConsoleButton.disabled = false;
    els.terminateHint.textContent = `关闭控制台失败: ${error}`;
  }
});

refreshAll();
window.setInterval(refreshAll, 2000);
window.setInterval(refreshRuntimeDurationTick, 1000);
