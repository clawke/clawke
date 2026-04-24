export type TaskStatus = 'active' | 'paused' | 'disabled' | 'error';
export type TaskRunStatus = 'running' | 'success' | 'failed' | 'cancelled';

export interface ManagedTask {
  id: string;
  account_id: string;
  agent: string;
  name: string;
  schedule: string;
  schedule_text?: string;
  prompt: string;
  enabled: boolean;
  status: TaskStatus;
  skills?: string[];
  deliver?: string;
  next_run_at?: string;
  last_run?: TaskRun;
  created_at?: string;
  updated_at?: string;
}

export interface TaskDraft {
  account_id: string;
  name?: string;
  schedule: string;
  prompt: string;
  enabled?: boolean;
  skills?: string[];
  deliver?: string;
}

export interface TaskRun {
  id: string;
  task_id: string;
  started_at: string;
  finished_at?: string;
  status: TaskRunStatus;
  output_preview?: string;
  error?: string;
}

export type TaskGatewayCommandType =
  | 'task_list'
  | 'task_get'
  | 'task_create'
  | 'task_update'
  | 'task_delete'
  | 'task_set_enabled'
  | 'task_run'
  | 'task_runs'
  | 'task_output';

export interface TaskGatewayRequest {
  type: TaskGatewayCommandType;
  request_id?: string;
  account_id: string;
  task_id?: string;
  run_id?: string;
  task?: TaskDraft;
  patch?: Partial<TaskDraft>;
  enabled?: boolean;
}

export interface TaskGatewayResponse {
  type: string;
  request_id: string;
  ok?: boolean;
  task?: ManagedTask;
  tasks?: ManagedTask[];
  runs?: TaskRun[];
  output?: string;
  error?: string;
  message?: string;
  details?: unknown;
}
