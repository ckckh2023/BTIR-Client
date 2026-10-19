import { ClassificationResult, SliceProbability } from '../model/TaskModels';

export function probabilitySeries(classification: ClassificationResult): SliceProbability[] {
  if (!Array.isArray(classification.slice_probability_series)) return [];
  return classification.slice_probability_series.filter((item: SliceProbability) =>
    !!item && Number.isInteger(item.slice_index) && item.slice_index >= 0 &&
    Number.isFinite(item.yes_probability) && item.yes_probability >= 0 && item.yes_probability <= 1)
    .slice().sort((left: SliceProbability, right: SliceProbability) => left.slice_index - right.slice_index);
}

export function probabilityThreshold(classification: ClassificationResult): number {
  return typeof classification.threshold === 'number' && Number.isFinite(classification.threshold) &&
    classification.threshold >= 0 && classification.threshold <= 1 ? classification.threshold : 0.548381;
}
