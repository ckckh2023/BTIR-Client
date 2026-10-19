export function normalizeServerUrl(value: string): string {
  const text = value.trim().replace(/\/+$/, '');
  const match = text.match(/^(https?):\/\/(\[[0-9a-f:]+\]|[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?)(?::(\d{1,5}))?(\/[^\s?#]*)?$/i);
  if (!match || (match[3] && (Number(match[3]) < 1 || Number(match[3]) > 65535))) {
    throw new Error('请输入有效的 http:// 或 https:// 服务器地址，不包含账号、查询参数或空格');
  }
  return `${match[1].toLowerCase()}://${match[2].toLowerCase()}${match[3] ? ':' + match[3] : ''}${match[4] || ''}`;
}
