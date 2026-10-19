import { TaskStatusResponse, PreviewFrame } from '../model/TaskModels';
import { consensusLabel, evidenceLabel, imagingMetrics, ResultMetric, classificationLabel,
  formatProbability, formatDate, taskStatusLabel, formatMeasure, validNumber } from './ResultPresentation';

export interface ReportImage {
  label: string;
  dataUrl: string;
}

function escapeHtml(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function reportText(value?: string): string { return escapeHtml(value || '未提供'); }

export function buildReportHtml(task: TaskStatusResponse, images: ReportImage[]): string {
    const result = task.frontend_result;
    const sections: string[] = [];
    if (result?.model_consensus) {
      const consensus = result.model_consensus;
      const segmentationEvidence = consensus.segmentation_detected === undefined ? '' :
        `<p>分割结果：${consensus.segmentation_detected ? '检出区域' : '未检出区域'}` +
        `${validNumber(consensus.segmentation_volume_mm3) ? ' · ' + formatMeasure(consensus.segmentation_volume_mm3) : ''}` +
        `${validNumber(consensus.segmentation_ratio) && consensus.segmentation_ratio! <= 1 ? ' · 占比 ' + formatProbability(consensus.segmentation_ratio) : ''}</p>`;
      sections.push(`<section><h2>综合结果</h2><p class="key">${reportText(consensusLabel(consensus, result?.classification))}</p><p>${reportText(consensus.summary)}</p>` +
        `<p>${reportText(evidenceLabel(consensus.primary_evidence))}</p>` +
        `<p>模型一致性：${consensus.consistency === 'consistent' ? '相互支持' : '存在差异'}` +
        `${consensus.requires_review ? ' · 建议复核' : ''}</p>${segmentationEvidence}</section>`);
    }
    if (result?.classification) {
      const classification = result.classification;
      const probabilityKeys: string[] = classification.probabilities
        ? Object.keys(classification.probabilities) : [];
      const probabilities = probabilityKeys.map((key: string) =>
        `<li>${reportText(key === 'yes' ? '异常' : key === 'no' ? '正常' : key)}：` +
        `${formatProbability(classification.probabilities[key])}</li>`).join('');
      sections.push(`<section><h2>分类结论</h2><p class="key">${classificationLabel(classification)}</p>` +
        `<p>置信度：${formatProbability(classification.confidence)}</p><ul>${probabilities}</ul>` +
        `</section>`);
    }
    if (result?.segmentation) {
      const metrics = imagingMetrics(result.segmentation);
      const metricRows = metrics.map((metric: ResultMetric) => `<tr><td>${reportText(metric.label)}</td><td>${reportText(metric.value)}</td><td>${escapeHtml(metric.detail)}</td></tr>`).join('');
      sections.push(`<section><h2>影像量化指标</h2><table><thead><tr><th>指标</th><th>数值</th><th>说明</th></tr></thead><tbody>${metricRows}</tbody></table></section>`);
      const regions = result.segmentation.regions;
      const rows = regions ? Object.keys(regions).map((key: string) =>
        `<tr><td>${reportText(regions[key].name || key)}</td><td>${formatMeasure(regions[key].volume_mm3)}</td></tr>`).join('') : '';
      sections.push(`<section><h2>分割结果</h2>${rows ? `<table><thead><tr><th>区域</th><th>体积</th></tr></thead><tbody>${rows}</tbody></table>` : '<p>暂无可量化区域。</p>'}</section>`);
    }
    if (result?.supplementary_analysis?.content) {
      const content = result.supplementary_analysis.content;
      const observations = (content.observations || []).map((item: string) => `<li>${reportText(item)}</li>`).join('');
      const uncertainties = (content.uncertainties || []).map((item: string) => `<li>${reportText(item)}</li>`).join('');
      sections.push(`<section><h2>AI 辅助分析</h2><p><strong>结论：</strong>${reportText(content.summary)}</p>` +
        `<p><strong>建议：</strong>${reportText(content.follow_up)}</p>` +
        `${observations ? `<h3>观察项</h3><ul>${observations}</ul>` : ''}` +
        `${uncertainties ? `<h3>不确定项</h3><ul>${uncertainties}</ul>` : ''}</section>`);
    }
    if (images.length > 0) {
      sections.push(`<section><h2>影像预览</h2><div class="images">${images.map((item: ReportImage) =>
        `<figure><img src="${item.dataUrl}" alt=""><figcaption>${reportText(item.label)}</figcaption></figure>`).join('')}</div></section>`);
    }
    const expectedImages: string[] = [];
    const files = result?.result_files;
    if (files?.preview) expectedImages.push(files.preview);
    const frames = files?.preview_series?.frames || [];
    frames.slice(0, 3).forEach((frame: PreviewFrame) => {
      const path = frame.overlay || frame.raw;
      if (path && !expectedImages.includes(path)) expectedImages.push(path);
    });
    if (images.length < expectedImages.length) sections.push('<p class="note">部分影像预览未能加载，本报告保留已有文字与量化结果。</p>');
    if (task.status === 'partial') sections.push('<p class="note">本次任务仅部分完成，报告仅包含当前可用结果。</p>');
    const content = sections.length ? sections.join('') : '<section><p>当前任务尚无可导出的分析结果。</p></section>';
    return `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>` +
      `@page{size:A4;margin:14mm}*{box-sizing:border-box}html,body{width:100%;max-width:100%;overflow-x:hidden}` +
      `body{font:14px sans-serif;color:#1e2d3e;background:#fff;margin:0;padding:20px;line-height:1.6}` +
      `p,li,td,th,figcaption{overflow-wrap:anywhere;word-break:break-word;white-space:pre-wrap}` +
      `h1{color:#1f477d;font-size:24px;margin:0 0 6px}h2{color:#1f477d;font-size:17px;border-bottom:1px solid #d9e3ef;padding-bottom:6px}` +
      `h3{font-size:14px;margin:10px 0 4px}.sub{color:#586b82;font-size:12px}.key{font-weight:700;font-size:17px}` +
      `section{margin:18px 0}h2,h3{break-after:avoid}table{width:100%;table-layout:fixed;border-collapse:collapse}` +
      `td,th{border:1px solid #d9e3ef;padding:7px;text-align:left;vertical-align:top}` +
      `.note{background:#fffbeb;padding:8px}.images{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}` +
      `figure{margin:0;min-width:0;break-inside:avoid}img{display:block;max-width:100%;max-height:240px;object-fit:contain;background:#02060b}` +
      `figcaption{font-size:12px;color:#586b82;text-align:center}` +
      `</style></head><body><h1>智瞳医脑 · 病例分析报告</h1>` +
      `<p class="sub">病例：${reportText(task.case_name || task.name)}　检查日期：${reportText(formatDate(task.study_date))}<br>` +
      `任务 ID：${reportText(task.task_id)}　状态：${reportText(taskStatusLabel(task.status))}</p>${content}` +
      `</body></html>`;
  }
