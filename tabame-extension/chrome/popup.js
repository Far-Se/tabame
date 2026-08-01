"use strict";

const statusTitle = document.querySelector("#statusTitle");
const statusDetail = document.querySelector("#statusDetail");
const stateLamp = document.querySelector("#stateLamp");
const retryButton = document.querySelector("#retryButton");
const pairingForm = document.querySelector("#pairingForm");
const tokenInput = document.querySelector("#tokenInput");
const portInput = document.querySelector("#portInput");
const formMessage = document.querySelector("#formMessage");
const versionLabel = document.querySelector("#versionLabel");

function runtimeMessage(message) {
  return chrome.runtime.sendMessage({ type: "popup", ...message });
}

function setFormMessage(text, error = false) {
  formMessage.textContent = text;
  formMessage.classList.toggle("error", error);
}

async function refreshStatus(syncFields = true) {
  const status = await runtimeMessage({ action: "status" });
  if (syncFields) {
    tokenInput.value = status.token || "";
    portInput.value = String(status.port || 17373);
  }
  versionLabel.textContent = `v${status.version}`;
  stateLamp.classList.toggle("connected", status.connected);

  if (status.connected) {
    statusTitle.textContent = status.userScriptsAvailable
      ? "Connected"
      : "Connected · scripts disabled";
    statusDetail.textContent = status.userScriptsAvailable
      ? "Trusted Tabame plugins can inspect and control this browser profile."
      : status.userScriptsError ||
        'Enable "Allow User Scripts" on this extension\'s details page.';
    return status;
  }

  if (!status.configured) {
    statusTitle.textContent = "Pairing required";
    statusDetail.textContent =
      "Open the launcher, type “browser”, then copy the token from Connection.";
    return status;
  }

  statusTitle.textContent = status.connecting
    ? "Waiting for Tabame"
    : "Bridge offline";
  statusDetail.textContent =
    status.lastError || "Open the Tabame launcher and activate the browser plugin.";
  return status;
}

async function waitForConnection() {
  for (let attempt = 0; attempt < 12; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 400));
    const status = await refreshStatus(false);
    if (status.connected) {
      setFormMessage("Connected to Tabame.");
      return true;
    }
  }
  setFormMessage(
    "Saved. If Tabame is closed, reopen the launcher and type “browser”; pairing will continue automatically.",
  );
  return false;
}

pairingForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const token = tokenInput.value.replace(/\s+/g, "");
  const port = Number(portInput.value);

  if (!token) {
    setFormMessage("Paste the pairing token from Tabame.", true);
    tokenInput.focus();
    return;
  }
  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
    setFormMessage("Use a port between 1024 and 65535.", true);
    portInput.focus();
    return;
  }

  await chrome.storage.local.set({
    bridgeToken: token,
    bridgePort: port,
  });
  tokenInput.value = token;
  setFormMessage("Saved. Connecting…");
  await runtimeMessage({ action: "reconnect" });
  await waitForConnection();
});

retryButton.addEventListener("click", async () => {
  setFormMessage("Retrying…");
  await runtimeMessage({ action: "reconnect" });
  await waitForConnection();
});

void refreshStatus();
