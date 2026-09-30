import { HttpClient, MultipartUploadFile } from '../common/HttpClient';
import {
  TaskCreatedResponse,
  TaskStatusResponse,
  TaskListResponse,
  TaskEnqueuedResponse,
  TaskCancellationResponse,
  TaskFollowUpResponse,
  TaskRunListResponse,
} from '../model/TaskModels';

interface RenameRequest {
  name: string;
}

export interface UploadArchiveOptions {
  name?: string;
  caseId?: string;
  caseName?: string;
  studyDate?: string;
  modalityEntries?: Record<string, string>;
  modalitySeriesUids?: Record<string, string>;
  replacementFiles?: Record<string, string>;
  replacementNames?: Record<string, string>;
  onStage?: (stage: string) => void;
}

export class TaskService {
  private httpClient: HttpClient = HttpClient.getInstance();

  async uploadArchive(
    archiveUri: string,
    cacheDir: string,
    archiveName: string,
    options: UploadArchiveOptions
  ): Promise<TaskCreatedResponse> {
    const extraFields: Record<string, string> = {};
    if (options.name) extraFields['name'] = options.name;
    if (options.caseId) extraFields['case_id'] = options.caseId;
    if (options.caseName) extraFields['case_name'] = options.caseName;
    if (options.studyDate) extraFields['study_date'] = options.studyDate;
    if (options.modalityEntries) {
      for (const key of Object.keys(options.modalityEntries)) {
        const modality = key.replace(/_entry$/, '');
        if (!options.replacementFiles || !options.replacementFiles[modality]) {
          extraFields[key] = options.modalityEntries[key];
        }
      }
    }
    if (options.modalitySeriesUids) {
      for (const key of Object.keys(options.modalitySeriesUids)) {
        const modality = key.replace(/_series_uid$/, '');
        if (!options.replacementFiles || !options.replacementFiles[modality]) {
          extraFields[key] = options.modalitySeriesUids[key];
        }
      }
    }

    const fileName = archiveName.toLowerCase().endsWith('.zip') ? archiveName : 'archive.zip';
    const files: MultipartUploadFile[] = [
      { fieldName: 'archive', uri: archiveUri, fileName: fileName, contentType: 'application/zip' }
    ];
    if (options.replacementFiles) {
      for (const key of ['flair', 't1ce', 't1', 't2']) {
        const uri = options.replacementFiles[key];
        if (uri) {
          const selectedName = options.replacementNames ? options.replacementNames[key] : '';
          const replacementName = selectedName && /\.nii(\.gz)?$/i.test(selectedName)
            ? selectedName : `${key}.nii.gz`;
          files.push({
            fieldName: key,
            uri: uri,
            fileName: replacementName,
            contentType: replacementName.toLowerCase().endsWith('.gz')
              ? 'application/gzip' : 'application/octet-stream',
          });
        }
      }
    }
    return this.httpClient.uploadFiles<TaskCreatedResponse>(
      '/tasks/3d/archive', files, cacheDir, extraFields, options.onStage
    );
  }

  async uploadNiftiFiles(
    files: Record<string, string>,
    fileNames: Record<string, string>,
    cacheDir: string,
    name?: string,
    caseId?: string,
    caseName?: string,
    studyDate?: string,
    onStage?: (stage: string) => void
  ): Promise<TaskCreatedResponse> {
    const uploadFiles: MultipartUploadFile[] = [];
    for (const key of ['flair', 't1ce', 't1', 't2']) {
      const uri = files[key];
      const selectedName = fileNames[key] ?? '';
      const fileName = /\.nii(\.gz)?$/i.test(selectedName) ? selectedName : `${key}.nii.gz`;
      uploadFiles.push({
        fieldName: key,
        uri: uri,
        fileName: fileName,
        contentType: fileName.toLowerCase().endsWith('.gz') ? 'application/gzip' : 'application/octet-stream',
      });
    }
    const fields: Record<string, string> = {};
    if (name) fields['name'] = name;
    if (caseId) fields['case_id'] = caseId;
    if (caseName) fields['case_name'] = caseName;
    if (studyDate) fields['study_date'] = studyDate;
    return this.httpClient.uploadFiles<TaskCreatedResponse>('/tasks/3d', uploadFiles, cacheDir, fields, onStage);
  }

  async runAsync(taskId: string): Promise<TaskEnqueuedResponse> {
    return this.httpClient.post<TaskEnqueuedResponse>(`/tasks/${taskId}/run-async`);
  }

  async getTask(taskId: string): Promise<TaskStatusResponse> {
    return this.httpClient.get<TaskStatusResponse>(`/tasks/${taskId}`);
  }

  async getTaskList(
    limit: number = 20,
    offset: number = 0,
    status?: string,
    q?: string
  ): Promise<TaskListResponse> {
    let path = `/tasks?limit=${limit}&offset=${offset}`;
    if (status) path += `&status=${encodeURIComponent(status)}`;
    if (q) path += `&q=${encodeURIComponent(q)}`;
    return this.httpClient.get<TaskListResponse>(path);
  }

  async getFollowUp(taskId: string): Promise<TaskFollowUpResponse> {
    return this.httpClient.get<TaskFollowUpResponse>(`/tasks/${taskId}/follow-up`);
  }

  async getRunHistory(taskId: string, limit: number = 20, offset: number = 0): Promise<TaskRunListResponse> {
    return this.httpClient.get<TaskRunListResponse>(`/tasks/${taskId}/runs?limit=${limit}&offset=${offset}`);
  }

  async retryTask(taskId: string): Promise<TaskEnqueuedResponse> {
    return this.httpClient.post<TaskEnqueuedResponse>(`/tasks/${taskId}/retry`);
  }

  async cancelTask(taskId: string): Promise<TaskCancellationResponse> {
    return this.httpClient.post<TaskCancellationResponse>(`/tasks/${taskId}/cancel`);
  }

  async renameTask(taskId: string, name: string): Promise<Object> {
    const request: RenameRequest = { name };
    return this.httpClient.patch<Object>(`/tasks/${taskId}/rename`, request);
  }

  async deleteTask(taskId: string): Promise<Object> {
    return this.httpClient.delete<Object>(`/tasks/${taskId}`);
  }

  async restoreTask(taskId: string): Promise<Object> {
    return this.httpClient.post<Object>(`/tasks/${taskId}/restore`);
  }

  async getArchivedTasks(limit: number = 20, offset: number = 0): Promise<TaskListResponse> {
    return this.httpClient.get<TaskListResponse>(`/tasks/archived?limit=${limit}&offset=${offset}`);
  }

  buildFilePath(taskId: string, filePath: string): string {
    const encodedPath = filePath.split('/').map(segment => encodeURIComponent(segment)).join('/');
    return `/tasks/${taskId}/files/${encodedPath}`;
  }

  async downloadFile(taskId: string, filePath: string): Promise<ArrayBuffer> {
    const path = this.buildFilePath(taskId, filePath);
    return this.httpClient.downloadFile(path);
  }
}
