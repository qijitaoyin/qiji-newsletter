const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export const parseRetryAfterMs = (value, now = Date.now()) => {
  if (!value) return 0;
  const seconds = Number.parseFloat(value);
  if (Number.isFinite(seconds)) return Math.max(0, Math.ceil(seconds * 1000));
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? Math.max(0, timestamp - now) : 0;
};

export const createResilientRequester = ({
  fetchImpl = fetch,
  timeoutMs = 180000,
  minIntervalMs = 0,
  maxAttempts = 5,
  baseDelayMs = 1500,
  sleepImpl = sleep,
  nowImpl = Date.now,
  onRetry = () => {}
} = {}) => {
  let lastRequestStartedAt = 0;

  return async (url, options = {}, context = {}) => {
    let lastError;

    for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
      const intervalWait = Math.max(0, lastRequestStartedAt + minIntervalMs - nowImpl());
      if (intervalWait > 0) await sleepImpl(intervalWait);
      lastRequestStartedAt = nowImpl();

      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), timeoutMs);
      let response;
      try {
        response = await fetchImpl(url, { ...options, signal: controller.signal });
      } catch (error) {
        lastError = error;
        if (attempt >= maxAttempts) throw error;
        const delayMs = Math.max(baseDelayMs * 2 ** (attempt - 1), minIntervalMs);
        onRetry({ attempt, delayMs, status: 0, label: context.label || "", error });
        await sleepImpl(delayMs);
        continue;
      } finally {
        clearTimeout(timeout);
      }

      if (response.ok || ![408, 429, 500, 502, 503, 504].includes(response.status)) {
        return response;
      }

      if (attempt >= maxAttempts) return response;
      const retryAfterMs = parseRetryAfterMs(response.headers.get("retry-after"), nowImpl());
      const delayMs = Math.max(
        retryAfterMs,
        response.status === 429 ? minIntervalMs : baseDelayMs * 2 ** (attempt - 1)
      );
      const errorText = (await response.text()).slice(0, 300);
      onRetry({
        attempt,
        delayMs,
        status: response.status,
        label: context.label || "",
        error: new Error(errorText)
      });
      await sleepImpl(delayMs);
    }

    throw lastError || new Error("AI request failed after all retry attempts");
  };
};
