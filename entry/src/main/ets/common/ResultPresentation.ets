import { ModelConsensus, ClassificationResult, SegmentationResult, TaskFollowUpResponse,
  TaskFollowUpHistoryItem } from '../model/TaskModels';

export interface ResultMetric {
  key: string;
  label: string;
  value: string;
  detail: string;
  meter?: number;
}

export function validNumber(value?: number): boolean {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

export function formatMeasure(value?: number, unit: string = 'mm³'): string {
  return validNumber(value) ? `${value!.toFixed(1)} ${unit}` : '—';
}

export function formatProbability(value?: number): string {
  return validNumber(value) && value! <= 1 ? `${(value! * 100).toFixed(1)}%` : '—';
}

export function classificationLabel(classification: ClassificationResult): string {
  return classification.class === 'yes' ? '提示肿瘤相关异常' :
    classification.class === 'no' ? '未发现明显异常' : '分类结果待确认';
}

export function taskStatusLabel(status: string): string {
  switch (status) {
    case 'created': return '待运行';
    case 'queued': return '排队中';
    case 'running': return '运行中';
    case 'cancel_requested': return '取消中';
    case 'partial': return '部分完成';
    case 'succeeded': return '已完成';
    case 'failed': return '失败';
    case 'canceled': return '已取消';
    default: return '未知状态';
  }
}

export function consensusLevel(consensus: ModelConsensus, classification?: ClassificationResult): string {
  if (['high_probability_present', 'possible_present', 'likely_absent', 'high_probability_absent',
    'inconclusive'].includes(consensus.level || '')) return consensus.level!;
  if (consensus.requires_review) return 'inconclusive';
  if (consensus.segmentation_detected === true) {
    return classification?.class === 'yes' ? 'high_probability_present' : 'possible_present';
  }
  if (consensus.segmentation_detected === false && classification?.class === 'no') return 'likely_absent';
  if (classification?.class === 'yes') return 'possible_present';
  return 'inconclusive';
}

export function consensusTone(consensus: ModelConsensus, classification?: ClassificationResult): string {
  switch (consensusLevel(consensus, classification)) {
    case 'high_probability_present': return 'present';
    case 'possible_present': return 'possible';
    case 'likely_absent':
    case 'high_probability_absent': return 'absent';
    default: return 'review';
  }
}

export function consensusLabel(consensus: ModelConsensus, classification?: ClassificationResult): string {
  if (consensus.label) return consensus.label;
  switch (consensusLevel(consensus, classification)) {
    case 'high_probability_present': return '高概率存在肿瘤相关区域';
    case 'possible_present': return '存在肿瘤相关区域的可能';
    case 'likely_absent': return '倾向不存在肿瘤相关区域';
    case 'high_probability_absent': return '高概率不存在肿瘤相关区域';
    default: return '综合结果待确认';
  }
}

export function evidenceLabel(evidence?: string): string {
  if (evidence === 'segmentation') return '以分割结果为主要依据';
  if (evidence === 'classification') return '以分类结果为主要依据';
  return evidence || '';
}

export function imagingMetrics(segmentation: SegmentationResult): ResultMetric[] {
  const metrics: ResultMetric[] = [];
  const morphology = segmentation.morphology;
  const dimensions = morphology?.bounding_box_size_mm;
  if (dimensions && dimensions.length === 3 && dimensions.every((value: number) => validNumber(value))) {
    metrics.push({ key: 'extent', label: '病灶范围',
      value: `${dimensions.map((value: number) => value.toFixed(1)).join(' × ')} mm`, detail: '三维大小' });
  }
  metrics.push({ key: 'area', label: '最大横截面积', value: formatMeasure(morphology?.max_axial_area_mm2, 'mm²'),
    detail: validNumber(morphology?.max_axial_slice_index) ? `切片 ${morphology!.max_axial_slice_index}` : '' });
  const wt = segmentation.composites?.['WT']?.volume_mm3;
  const tc = segmentation.composites?.['TC']?.volume_mm3;
  const et = segmentation.composites?.['ET']?.volume_mm3;
  const edema = segmentation.regions?.['2']?.volume_mm3;
  if (validNumber(edema) && validNumber(wt) && wt! > 0) {
    const ratio = Math.max(0, Math.min(100, edema! / wt! * 100));
    metrics.push({ key: 'edema', label: '瘤周水肿', value: `${ratio.toFixed(1)}%`,
      detail: `ED ${formatMeasure(edema)} · 占全病灶`, meter: ratio });
  }
  if (validNumber(et) && validNumber(tc) && tc! > 0) {
    const ratio = Math.max(0, Math.min(100, et! / tc! * 100));
    metrics.push({ key: 'enhancement', label: '强化成分', value: `${ratio.toFixed(1)}%`,
      detail: `ET ${formatMeasure(et)} · 占肿瘤核心`, meter: ratio });
  }
  if (validNumber(morphology?.connected_components) && morphology!.connected_components! > 0 && validNumber(morphology?.largest_component_ratio)) {
    const ratio = Math.max(0, Math.min(100, morphology!.largest_component_ratio! * 100));
    metrics.push({ key: 'distribution', label: '空间分布', value: `主体 ${ratio.toFixed(1)}%`,
      detail: `${morphology!.connected_components} 个分割连通域`, meter: ratio });
  }
  const keys: string[] = ['WT', 'TC', 'ET'];
  const names: string[] = ['全肿瘤体积', '肿瘤核心体积', '强化肿瘤体积'];
  keys.forEach((key: string, index: number) => {
    metrics.push({ key: key, label: names[index], value: formatMeasure(segmentation.composites?.[key]?.volume_mm3), detail: key });
  });
  return metrics;
}

export function followUpHistory(response: TaskFollowUpResponse | null): TaskFollowUpHistoryItem[] {
  if (!response) return [];
  const history = response.history || [];
  const baseline = response.baseline;
  if (baseline && response.baseline_frontend_result && !history.some((item: TaskFollowUpHistoryItem) => item.task.task_id === baseline.task_id)) {
    const item: TaskFollowUpHistoryItem = { task: baseline, frontend_result: response.baseline_frontend_result };
    return [item].concat(history);
  }
  return history;
}

export function formatDate(value?: string): string {
  if (!value) return '未提供';
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return value;
  const pad = (number: number): string => String(number).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}
