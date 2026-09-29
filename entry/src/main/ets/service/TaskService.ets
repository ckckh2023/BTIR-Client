import { HttpClient, TokenManager } from '../common/HttpClient';
import { http } from '@kit.NetworkKit';
import { ApiConfig } from '../common/ApiConfig';
import { ApiError } from '../common/ApiError';
import {
  TaskCreatedResponse,
  TaskStatusResponse,
  TaskListResponse,
  TaskEnqueuedResponse,
  TaskCancellationResponse,
  TaskFollowUpResponse,
  TaskRunListResponse,
} from '../model/TaskModels';

interface NiftiFileUpload {
  name: string;
  type: string;
  uri: string;
}

interface RenameRequest {
  name: string;
}

export class TaskService {
  private httpClient: HttpClient = HttpClient.getInstance();

  async uploadArchive(
    archiveUri: string,
    name?: string,
    caseId?: string,
    caseName?: string,
    studyDate?: string,
    modalityEntries?: Record<string, string>,
    modalitySeriesUids?: Record<string, string>
  ): Promise<TaskCreatedResponse> {
    const extraFields: Record<string, string> = {};
    if (name) extraFields['name'] = name;
    if (caseId) extraFields['case_id'] = caseId;
    if (caseName) extraFields['case_name'] = caseName;
    if (studyDate) extraFields['study_date'] = studyDate;
    if (modalityEntries) {
      for (const key of Object.keys(modalityEntries)) {
        extraFields[key] = modalityEntries[key];
      }
    }
    if (modalitySeriesUids) {
      for (const key of Object.keys(modalitySeriesUids)) {
        extraFields[key] = modalitySeriesUids[key];
      }
    }

    const fileName = archiveUri.split('/').pop() ?? 'archive.zip';
    return this.httpClient.uploadFile<TaskCreatedResponse>(
      '/tasks/3d/archive', archiveUri, fileName, 'application/zip', extraFields
    );
  }

  async uploadNiftiFiles(
    files: Record<string, string>,
    name?: string,
    caseId?: string,
    caseName?: string,
    studyDate?: string
  ): Promise<TaskCreatedResponse> {
    const baseUrl = ApiConfig.getInstance().baseUrl;
    const url = `${baseUrl}/tasks/3d`;
    const headers: Record<string, string> = {};
    const token = TokenManager.getInstance().getToken();
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }

    const extraData: Record<string, Object> = {};
    for (const key of Object.keys(files)) {
      const uri = files[key];
      const fileName = uri.split('/').pop() ?? `${key}.nii.gz`;
      const fileObj: NiftiFileUpload = {
        name: fileName,
        type: 'application/gzip',
        uri: uri,
      };
      extraData[key] = fileObj;
    }
    if (name) extraData['name'] = name;
    if (caseId) extraData['case_id'] = caseId;
    if (caseName) extraData['case_name'] = caseName;
    if (studyDate) extraData['study_date'] = studyDate;

    try {
      const httpRequest = http.createHttp();
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        extraData: extraData,
      };

      const response = await httpRequest.request(url, options);
      httpRequest.destroy();

      const status = response.responseCode;
      const responseText = response.result as string;
      let responseData: Object | string = responseText;
      try {
        responseData = JSON.parse(responseText);
      } catch (e) {
        // 非 JSON
      }

      if (status >= 400) {
        throw new ApiError(status, responseData);
      }

      return responseData as TaskCreatedResponse;
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      throw new ApiError(0, String(error), `NIfTI 上传失败: ${String(error)}`);
    }
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
