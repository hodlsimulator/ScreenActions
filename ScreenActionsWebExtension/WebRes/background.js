// ScreenActions WebExtension — background.js (full file)
//
// Purpose:
// - Provide a *robust* bridge from popup/content to the native app using
//   runtime.sendNativeMessage, with strict serialisation (queue) to avoid
//   overlapping native requests that can trigger SFErrorDomain errors.
// - Support both sendMessage and long-lived Port (connect) callers.
// - Return uniform { ok: boolean, ... } payloads to the caller.
// - Keep the external message API stable for popup.js.
//
// Notes:
// - Safari’s runtime.sendNativeMessage uses a Promise API. Some builds also
//   accept the (application, message) form. We try both.
// - We always serialise native calls. Only one is in-flight at a time.
//

(() => {
  'use strict';

  // ---- Runtime shims --------------------------------------------------------
  const RT = (typeof chrome !== 'undefined' && chrome.runtime)
    ? chrome.runtime
    : (typeof browser !== 'undefined' && browser.runtime)
      ? browser.runtime
      : (typeof safari !== 'undefined' && safari.runtime)
        ? safari.runtime
        : undefined;

  if (!RT) {
    // If this ever happens, the environment is not a WebExtension runtime.
    // We still expose handlers that answer with an error so the UI shows something.
    const errorPayload = { ok: false, message: 'No extension runtime available.' };
    // Best-effort listeners (won’t really register without RT, but keeps shape complete).
    try {
      (chrome?.runtime || browser?.runtime)?.onMessage?.addListener?.(() => errorPayload);
      (chrome?.runtime || browser?.runtime)?.onConnect?.addListener?.(port => {
        try { port.postMessage(errorPayload); } catch {}
      });
    } catch {}
    return;
  }

  // Optional hint string for Chrome-style native hosts. Safari ignores it.
  // Leave blank unless you have a Chrome native host ID.
  const HOST_HINT = '';

  // Upper bound on how long a native request can take before we treat it as failed.
  const TIMEOUT_MS = 3000;

  // ---- Small utils ----------------------------------------------------------
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));

  function withTimeout(promise, ms, tag = 'native') {
    let t;
    const killer = new Promise((_, rej) => {
      t = setTimeout(() => rej(new Error(`${tag} timeout`)), ms);
    });
    return Promise.race([promise, killer]).finally(() => clearTimeout(t));
  }

  function safeJsonClone(value) {
    // Ensure we only send JSON-serialisable data across the bridge.
    try {
      return JSON.parse(JSON.stringify(value ?? null));
    } catch {
      return null;
    }
  }

  function okResult(extra = {}) {
    return { ok: true, ...extra };
  }
  function errResult(message = 'Native bridge error.') {
    return { ok: false, message };
  }

  // ---- Native bridge (raw) --------------------------------------------------
  async function sendNativeRaw(message) {
    // Normalise the payload up-front.
    const msg = safeJsonClone(message) || {};
    // Prefer the 1-arg form. If Safari build requires (app, message), fall back.
    const fn = RT.sendNativeMessage;
    if (typeof fn !== 'function') {
      throw new Error('sendNativeMessage not available.');
    }

    // Try 1-arg (Safari Promise form).
    try {
      const res = await fn(msg);
      return res;
    } catch (e1) {
      // Try 2-arg form (Safari/Chrome variants).
      try {
        const res = await fn(HOST_HINT, msg);
        return res;
      } catch (e2) {
        // Chrome callback (very unlikely here, but keep for completeness).
        if (fn.length >= 3) {
          return await new Promise((resolve, reject) => {
            try {
              fn(HOST_HINT, msg, (res) => {
                const lastErr = (chrome && chrome.runtime && chrome.runtime.lastError) ? chrome.runtime.lastError : null;
                if (lastErr) reject(new Error(lastErr.message || 'Native callback error.'));
                else resolve(res);
              });
            } catch (e3) {
              reject(e3);
            }
          });
        }
        throw e2 || e1;
      }
    }
  }

  // ---- Serial queue for native calls ---------------------------------------
  const queue = [];
  let inFlight = false;

  async function runQueue() {
    if (inFlight) return;
    const job = queue.shift();
    if (!job) return;
    inFlight = true;
    try {
      const result = await withTimeout(sendNativeRaw(job.message), TIMEOUT_MS, 'native');
      job.resolve(result);
    } catch (err) {
      job.reject(err);
    } finally {
      inFlight = false;
      // Yield back to event loop to let the worker breathe between jobs.
      await sleep(0);
      // Kick next.
      void runQueue();
    }
  }

  function enqueueNative(message) {
    return new Promise((resolve) => {
      // We *never* let a rejection poison the chain for callers;
      // convert exceptions into { ok:false, message } results.
      const wrapped = {
        message,
        resolve: (value) => resolve(value ?? okResult()),
        reject: (error) => {
          // Surface Swift-provided message if present in structured error.
          const msg = (typeof error === 'object' && error && ('message' in error))
            ? (String(error.message) || 'Native bridge error.')
            : 'Native bridge error.';
          resolve(errResult(msg));
        },
      };
      queue.push(wrapped);
      void runQueue();
    });
  }

  // ---- Public API exposed via runtime messaging ----------------------------
  async function handleCommand(request) {
    // Supported commands:
    // { cmd: "native", action: "ping" | "createReminder" | ... , payload: {...} }
    // { cmd: "echo",   payload: any }  (for simple connectivity checks)
    if (!request || typeof request !== 'object') {
      return errResult('Bad request.');
    }

    const cmd = request.cmd || '';
    if (cmd === 'echo') {
      return okResult({ echo: safeJsonClone(request.payload) });
    }

    if (cmd === 'native') {
      const action = String(request.action || '');
      const payload = safeJsonClone(request.payload) || {};
      if (!action) return errResult('Missing action.');

      // Construct the native message exactly as SAWebBridge expects:
      // { action: string, payload: { selection?, title?, url? } }
      const message = { action, payload };
      return await enqueueNative(message);
    }

    // Unknown command: keep behaviour predictable.
    return errResult('Unknown command.');
  }

  // onMessage (Promise-based to work in MV3 service worker)
  RT.onMessage.addListener((request, _sender, _sendResponse) => {
    // In MV3 service workers, returning a Promise keeps the worker alive
    // until the Promise settles.
    return handleCommand(request);
  });

  // onConnect (Port messaging)
  RT.onConnect.addListener((port) => {
    // Optional name check if you only expect a specific port name.
    // if (port?.name !== 'screen-actions') { return; }
    try {
      port.onMessage.addListener(async (request) => {
        const out = await handleCommand(request);
        try { port.postMessage(out); } catch {}
      });
    } catch {}
  });

  // (Optional) Log installs/updates for quick diagnostics.
  try {
    RT.onInstalled?.addListener?.((_details) => {
      // No-op; keep file quiet in production.
    });
  } catch {}

})();
