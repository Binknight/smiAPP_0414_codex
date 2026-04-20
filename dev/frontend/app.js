const els = {
  title: document.getElementById("task-title"),
  branch: document.getElementById("task-branch"),
  statusPill: document.getElementById("status-pill"),
  scenarioId: document.getElementById("scenario-id"),
  appType: document.getElementById("app-type"),
  agentPid: document.getElementById("agent-pid"),
  startedAt: document.getElementById("started-at"),
  updatedAt: document.getElementById("updated-at"),
  resultJson: document.getElementById("result-json"),
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
};

function fmt(value) {
  return value || "-";
}

function classifyStatus(status) {
  if (["pushed", "completed", "dry_run_success_detected"].includes(status)) return "status-success";
  if (["build_failed", "agent_exited_without_result"].includes(status)) return "status-failed";
  if (status === "cancelled") return "status-cancelled";
  return "status-running";
}

function renderTask(task) {
  els.title.textContent = task.scenarioKey || "当前任务";
  els.branch.textContent = task.scenarioBranch || "-";
  els.statusPill.textContent = fmt(task.status);
  els.statusPill.className = `status-pill ${classifyStatus(task.status)}`;
  els.scenarioId.textContent = fmt(task.scenarioId);
  els.appType.textContent = fmt(task.appDisplayName || task.appType);
  els.agentPid.textContent = fmt(task.agent.pid);
  els.startedAt.textContent = fmt(task.agent.startedAt);
  els.updatedAt.textContent = fmt(task.updatedAt);
  els.resultJson.textContent = fmt(task.resultJson);
  els.progressLabel.textContent = fmt(task.progress.label);
  els.progressPercent.textContent = `${task.progress.percent || 0}%`;
  els.progressBar.style.width = `${task.progress.percent || 0}%`;
  els.steps.innerHTML = "";
  (task.progress.steps || []).forEach((step, index) => {
    const li = document.createElement("li");
    li.textContent = step;
    if (index + 1 === task.progress.currentStep) {
      li.classList.add("active");
    }
    els.steps.appendChild(li);
  });
  els.inspectionStatus.textContent = fmt(task.inspection.status);
  els.inspectionCycles.textContent = fmt(task.inspection.cycleCount);
  els.inspectionLast.textContent = fmt(task.inspection.lastCheckedAt);
  els.inspectionMessage.textContent = fmt(task.inspection.message);

  const terminal = task.status === "cancelled" || task.status === "pushed" || task.status === "completed" || task.status === "build_failed" || task.status === "agent_exited_without_result";
  els.terminateButton.disabled = terminal;
  if (terminal) {
    els.terminateHint.textContent = "当前状态不可再终止。";
  }
}

async function refreshLogs() {
  const res = await fetch("/api/task/current/logs?tail=80", { cache: "no-store" });
  const logs = await res.json();
  els.pipelineLog.textContent = logs.pipelineLog || "暂无日志";
  els.agentLog.textContent = logs.agentLog || "暂无日志";
}

async function refreshTask() {
  const res = await fetch("/api/task/current", { cache: "no-store" });
  const task = await res.json();
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
      document.body.innerHTML = "<main class=\"shell\"><section class=\"hero\"><div><p class=\"eyebrow\">Console Closed</p><h1>控制台已关闭</h1><p class=\"hero-meta\">请重新执行 run_pipeline 再次启动 Web 页面。</p></div></section></main>";
    }, 500);
  } catch (error) {
    els.shutdownConsoleButton.disabled = false;
    els.terminateHint.textContent = `关闭控制台失败: ${error}`;
  }
});

refreshAll();
window.setInterval(refreshAll, 2000);
