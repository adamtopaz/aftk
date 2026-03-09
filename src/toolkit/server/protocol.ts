export interface SourcePosition {
  line: number;
  col: number;
}

export interface SourceRange {
  start: SourcePosition;
  stop: SourcePosition;
}

export interface OpenParams {
  path: string;
}

export interface OpenResult {
  path: string;
  opened: boolean;
}

export interface CloseParams {
  path: string;
}

export interface CloseResult {
  path: string;
  closed: boolean;
}

export interface FileLocationParams {
  path: string;
  line: number;
  col: number;
}

export interface FileNodeParams {
  path: string;
  id: string;
}

export interface RunTacticParams {
  path: string;
  id: string;
  tactic: string;
}

export interface RunTacticStepsParams {
  path: string;
  id: string;
  tactics: string[];
}

export interface ShutdownParams {}

export interface HoverResult {
  text: string;
  range?: SourceRange | null;
}

export interface PlainGoalResult {
  goals: string[];
  rendered: string;
}

export interface PlainTermGoalResult {
  goal: string;
  range?: SourceRange | null;
}

export interface InfoViewResult {
  hover?: HoverResult | null;
  plainGoal?: PlainGoalResult | null;
  plainTermGoal?: PlainTermGoalResult | null;
}

export interface LoadNodeResult {
  id: string[];
}

export interface GetGoalsResult {
  goals: string[];
}

export interface RunTacticResult {
  goals: string[];
  nextId: string;
}

export interface RunTacticStepsResult {
  results: RunTacticResult[];
}

export interface ShutdownResult {
  stopped: number;
}

export interface AftkServerProtocolMap {
  open: { params: OpenParams; result: OpenResult };
  close: { params: CloseParams; result: CloseResult };
  load_node: { params: FileLocationParams; result: LoadNodeResult };
  get_hover: { params: FileLocationParams; result: HoverResult | null };
  get_plain_goal: { params: FileLocationParams; result: PlainGoalResult | null };
  get_plain_term_goal: { params: FileLocationParams; result: PlainTermGoalResult | null };
  get_infoview: { params: FileLocationParams; result: InfoViewResult };
  get_goals: { params: FileNodeParams; result: GetGoalsResult };
  run_tactic: { params: RunTacticParams; result: RunTacticResult };
  run_tactic_steps: { params: RunTacticStepsParams; result: RunTacticStepsResult };
  shutdown: { params: ShutdownParams; result: ShutdownResult };
}

export type AftkServerMethod = keyof AftkServerProtocolMap;
export type ParamsFor<M extends AftkServerMethod> = AftkServerProtocolMap[M]["params"];
export type ResultFor<M extends AftkServerMethod> = AftkServerProtocolMap[M]["result"];

export const AftkServerErrorCode = {
  TacticFailed: -32001,
  FileNotOpen: -32010,
  FileChanged: -32011,
  WorkerUnavailable: -32012,
  StaleNode: -32013,
} as const;

export type AftkServerErrorCode = (typeof AftkServerErrorCode)[keyof typeof AftkServerErrorCode];

export type AftkServerErrorCategory =
  | "tactic_failed"
  | "file_not_open"
  | "file_changed"
  | "worker_unavailable"
  | "stale_node"
  | "operational";

export function classifyAftkServerErrorCode(code: number): AftkServerErrorCategory {
  switch (code) {
    case AftkServerErrorCode.TacticFailed:
      return "tactic_failed";
    case AftkServerErrorCode.FileNotOpen:
      return "file_not_open";
    case AftkServerErrorCode.FileChanged:
      return "file_changed";
    case AftkServerErrorCode.WorkerUnavailable:
      return "worker_unavailable";
    case AftkServerErrorCode.StaleNode:
      return "stale_node";
    default:
      return "operational";
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isString(value: unknown): value is string {
  return typeof value === "string";
}

function isBoolean(value: unknown): value is boolean {
  return typeof value === "boolean";
}

function isPositiveInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 1;
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every(isString);
}

export function isSourcePosition(value: unknown): value is SourcePosition {
  return isRecord(value) && isPositiveInteger(value.line) && isPositiveInteger(value.col);
}

export function isSourceRange(value: unknown): value is SourceRange {
  return isRecord(value) && isSourcePosition(value.start) && isSourcePosition(value.stop);
}

export function isHoverResult(value: unknown): value is HoverResult {
  return (
    isRecord(value) &&
    isString(value.text) &&
    (value.range === undefined || value.range === null || isSourceRange(value.range))
  );
}

export function isPlainGoalResult(value: unknown): value is PlainGoalResult {
  return isRecord(value) && isStringArray(value.goals) && isString(value.rendered);
}

export function isPlainTermGoalResult(value: unknown): value is PlainTermGoalResult {
  return (
    isRecord(value) &&
    isString(value.goal) &&
    (value.range === undefined || value.range === null || isSourceRange(value.range))
  );
}

export function isInfoViewResult(value: unknown): value is InfoViewResult {
  return (
    isRecord(value) &&
    (value.hover === undefined || value.hover === null || isHoverResult(value.hover)) &&
    (value.plainGoal === undefined || value.plainGoal === null || isPlainGoalResult(value.plainGoal)) &&
    (value.plainTermGoal === undefined || value.plainTermGoal === null || isPlainTermGoalResult(value.plainTermGoal))
  );
}

export function isOpenResult(value: unknown): value is OpenResult {
  return isRecord(value) && isString(value.path) && isBoolean(value.opened);
}

export function isCloseResult(value: unknown): value is CloseResult {
  return isRecord(value) && isString(value.path) && isBoolean(value.closed);
}

export function isLoadNodeResult(value: unknown): value is LoadNodeResult {
  return isRecord(value) && isStringArray(value.id);
}

export function isGetGoalsResult(value: unknown): value is GetGoalsResult {
  return isRecord(value) && isStringArray(value.goals);
}

export function isRunTacticResult(value: unknown): value is RunTacticResult {
  return isRecord(value) && isStringArray(value.goals) && isString(value.nextId);
}

export function isRunTacticStepsResult(value: unknown): value is RunTacticStepsResult {
  return isRecord(value) && Array.isArray(value.results) && value.results.every(isRunTacticResult);
}

export function isShutdownResult(value: unknown): value is ShutdownResult {
  return isRecord(value) && typeof value.stopped === "number" && Number.isInteger(value.stopped) && value.stopped >= 0;
}

export function validateMethodResult<M extends AftkServerMethod>(method: M, value: unknown): value is ResultFor<M> {
  switch (method) {
    case "open":
      return isOpenResult(value);
    case "close":
      return isCloseResult(value);
    case "load_node":
      return isLoadNodeResult(value);
    case "get_hover":
      return value === null || isHoverResult(value);
    case "get_plain_goal":
      return value === null || isPlainGoalResult(value);
    case "get_plain_term_goal":
      return value === null || isPlainTermGoalResult(value);
    case "get_infoview":
      return isInfoViewResult(value);
    case "get_goals":
      return isGetGoalsResult(value);
    case "run_tactic":
      return isRunTacticResult(value);
    case "run_tactic_steps":
      return isRunTacticStepsResult(value);
    case "shutdown":
      return isShutdownResult(value);
    default:
      return false;
  }
}
