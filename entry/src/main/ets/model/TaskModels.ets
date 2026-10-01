export interface TaskCreatedResponse {
  schema_version: string;
  task_id: string;
  status: string;
  analysis_mode: string;
  input_files: Record<string, string>;
  case_id?: string;
}

export interface TaskInputFileData {
  filename: string;
  size_bytes: number;
  sha256: string;
}

export interface TaskInputData {
  size_bytes: number;
  sha256: string;
  files: Record<string, TaskInputFileData>;
}

export interface TaskJobData {
  id: string;
  queue: string;
  status: string;
  attempt: number;
  max_retries: number;
  queued_at?: string;
  started_at?: string;
  finished_at?: string;
  queue_wait_ms?: number;
  execution_ms?: number;
}

export interface TaskErrorData {
  code: string;
  message: string;
  updated_at: string;
}

export interface TaskStatusResponse {
  schema_version: string;
  task_id: string;
  name: string;
  status: string;
  created_at: string;
  updated_at: string;
  case_id?: string;
  case_name?: string;
  study_date?: string;
  analysis_mode: string;
  completed_models: string[];
  input: TaskInputData;
  job?: TaskJobData;
  error?: TaskErrorData;
  frontend_result?: FrontendResult;
  progress?: number;
  progress_stage?: string;
}

export interface TaskSummaryResponse {
  task_id: string;
  name: string;
  status: string;
  created_at: string;
  updated_at: string;
  case_id?: string;
  case_name?: string;
  study_date?: string;
  analysis_mode: string;
  completed_models: string[];
  input: TaskInputData;
  job?: TaskJobData;
  error?: TaskErrorData;
  archived_at?: string;
  purge_eligible_at?: string;
}

export interface TaskListResponse {
  schema_version: string;
  items: TaskSummaryResponse[];
  total: number;
  limit: number;
  offset: number;
}

export interface TaskEnqueuedResponse {
  schema_version: string;
  task_id: string;
  status: string;
  job: TaskJobData;
  reused_existing_job: boolean;
}

export interface FrontendResult {
  schema_version?: string;
  task_id?: string;
  analysis_mode?: string;
  status?: string;
  completed_models?: string[];
  input_files?: Record<string, string>;
  classification?: ClassificationResult;
  segmentation?: SegmentationResult;
  model_consensus?: ModelConsensus;
  supplementary_analysis?: SupplementaryAnalysis;
  result_files?: ResultFiles;
}

export interface ClassificationResult {
  model: string;
  class: string;
  confidence: number;
  probabilities: Record<string, number>;
  threshold?: number;
  method?: string;
  experimental?: boolean;
  modality?: string;
  evaluated_slices?: number;
  aggregation?: string;
}

export interface SegmentationResult {
  model: string;
  model_metadata?: Record<string, string>;
  spatial?: Record<string, Object>;
  labels?: Record<string, Object>;
  regions?: Record<string, RegionInfo>;
  composites?: Record<string, CompositeRegionInfo>;
  morphology?: SegmentationMorphology;
  mask_file?: string;
}

export interface CompositeRegionInfo {
  volume_mm3?: number;
}

export interface SegmentationMorphology {
  max_axial_area_mm2?: number;
}

export interface RegionInfo {
  label: string;
  name: string;
  volume_mm3?: number;
  pixel_count?: number;
  color?: string;
}

export interface ModelConsensus {
  version?: string;
  summary?: string;
  consistency?: string;
  primary_evidence?: string;
  segmentation_detected?: boolean;
  segmentation_volume_mm3?: number;
  requires_review?: boolean;
}

export interface SupplementaryAnalysisContent {
  summary?: string;
  follow_up?: string;
  uncertainties?: string[];
  observations?: string[];
}

export interface SupplementaryAnalysis {
  status?: string;
  content?: SupplementaryAnalysisContent;
}

export interface PreviewSeries {
  frames?: PreviewFrame[];
}

export interface ResultFiles {
  preview?: string;
  preview_series?: PreviewSeries;
  mask?: string;
}

export interface PreviewFrame {
  slice_index: number;
  offset?: number;
  raw?: string;
  overlay?: string;
}

export interface ModalityCandidate {
  filename?: string;
  size_bytes?: number;
  series_uid?: string;
  label?: string;
  file_count?: number;
  source_name?: string;
}

export interface ModalitySelectionDetail {
  reason?: string;
  message?: string;
  candidates?: ModalityCandidate[];
}

export interface ArchiveModalitySelectionDetail {
  code: string;
  message: string;
  modalities: Record<string, ModalitySelectionDetail>;
}

export interface ArchiveModalitySelectionResponse {
  detail: ArchiveModalitySelectionDetail;
}

export interface TaskFollowUpResponse {
  schema_version: string;
  task_id: string;
  case_id?: string;
  case_name?: string;
  study_date?: string;
  baseline?: TaskSummaryResponse;
  baseline_frontend_result?: FrontendResult;
  history: TaskFollowUpHistoryItem[];
}

export interface TaskFollowUpHistoryItem {
  task: TaskSummaryResponse;
  frontend_result: FrontendResult;
}

export interface TaskRunSummaryResponse {
  run_id: string;
  model: string;
  created_at: string;
  inference_ms?: number;
}

export interface TaskRunListResponse {
  schema_version: string;
  task_id: string;
  items: TaskRunSummaryResponse[];
  total: number;
  limit: number;
  offset: number;
}

export interface TaskCancellationResponse {
  schema_version: string;
  task_id: string;
  status: string;
}
