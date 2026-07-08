const basePath = import.meta.env.BASE_URL || "/";

export const pathFor = (value = "/") => {
  if (!value) return "";
  if (/^(https?:|mailto:|tel:|#)/.test(value)) return value;
  if (value === "/") return basePath;
  if (value.startsWith("/#")) return `${basePath}${value.slice(1)}`;
  const cleanBase = basePath.endsWith("/") ? basePath.slice(0, -1) : basePath;
  return `${cleanBase}${value.startsWith("/") ? value : `/${value}`}`;
};
