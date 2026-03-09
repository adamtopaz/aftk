export {
  createToolkitRuntimeContext,
  DEFAULT_CAPTURE_POLICY,
  DEFAULT_TIMEOUT_POLICY,
  type ToolkitCapturePolicy,
  type ToolkitDebugEvent,
  type ToolkitRuntimeContext,
  type ToolkitRuntimeOptions,
  type ToolkitTimeoutPolicy,
} from "./toolkit/runtime/options.ts";

export {
  ToolkitCancellationError,
  ToolkitConfigError,
  ToolkitLifecycleError,
  ToolkitProcessError,
  ToolkitProcessStartError,
  ToolkitProtocolError,
  ToolkitRuntimeError,
  ToolkitTimeoutError,
  isToolkitRuntimeError,
  type ToolkitRuntimeErrorDetails,
  type ToolkitRuntimeErrorKind,
} from "./toolkit/runtime/errors.ts";

export {
  AftkServerClient,
  AftkServerProtocolError,
  AftkServerRpcError,
  isAftkServerRpcError,
  type AftkServerRequestOptions,
  type CreateAftkServerClientOptions,
} from "./toolkit/server/client.ts";

export {
  AftkServerErrorCode,
  classifyAftkServerErrorCode,
  type AftkServerErrorCategory,
  type AftkServerMethod,
  type AftkServerProtocolMap,
  type CloseParams,
  type CloseResult,
  type FileLocationParams,
  type FileNodeParams,
  type GetGoalsResult,
  type HoverResult,
  type InfoViewResult,
  type LoadNodeResult,
  type OpenParams,
  type OpenResult,
  type ParamsFor,
  type PlainGoalResult,
  type PlainTermGoalResult,
  type ResultFor,
  type RunTacticParams,
  type RunTacticResult,
  type RunTacticStepsParams,
  type RunTacticStepsResult,
  type ShutdownParams,
  type ShutdownResult,
  type SourcePosition,
  type SourceRange,
} from "./toolkit/server/protocol.ts";

export {
  buildFailureResult,
  buildSuccessResult,
  cliCategoryFromExitCode,
  diagnosticsFromRuntimeLike,
  toolErrorFromUnknown,
  type ToolkitBackendInfo,
  type ToolkitDiagnostics,
  type ToolkitErrorKind,
  type ToolkitFailureDetails,
  type ToolkitFamily,
  type ToolkitSuccessDetails,
  type ToolkitToolContent,
  type ToolkitToolDetails,
  type ToolkitToolError,
  type ToolkitToolResult,
  type ToolkitTruncationInfo,
  type ToolkitWarning,
} from "./toolkit/output/result.ts";

export {
  DEFAULT_TEXT_TRUNCATION_POLICY,
  truncateText,
  type ToolkitTextTruncationInfo,
  type ToolkitTextTruncationPolicy,
} from "./toolkit/output/truncate.ts";

export {
  createAFTKTools,
  createAftkLeanTools,
  type CreateAftkLeanToolsOptions,
} from "./toolkit/tools/lean.ts";

export {
  createKnowledgeBaseTools,
  type CreateKnowledgeBaseToolsOptions,
} from "./toolkit/tools/knowledgebase.ts";

export {
  createInformalTools,
  type CreateInformalToolsOptions,
} from "./toolkit/tools/informal.ts";

export {
  createToolkitTools,
  type CreateToolkitToolsOptions,
  type ToolkitAggregateToolset,
} from "./toolkit/tools/aggregate.ts";

export {
  Schema,
  ToolInputError,
  type ToolkitFamilySelection,
  type ToolkitJsonSchema,
  type ToolkitManagedToolset,
  type ToolkitStatelessToolset,
  type ToolkitToolDefinition,
} from "./toolkit/tools/common.ts";

export {
  KnowledgeBaseClient,
  type CreateKnowledgeBaseClientOptions,
  type IncomingRelationship,
  type KnowledgeBaseCliFailure,
  type KnowledgeBaseCliResponse,
  type KnowledgeBaseCliSuccess,
  type KnowledgeBaseCommandOptions,
  type KnowledgeBaseListOptions,
  type KnowledgeBaseListResult,
  type KnowledgeBaseRelationshipsMode,
  type KnowledgeBaseRelationshipsResult,
  type KnowledgeBaseSearchOptions,
  type KnowledgeBaseSearchTagResult,
  type KnowledgeBaseSearchTextResult,
  type KnowledgeBaseShowOptions,
  type KnowledgeBaseShowResult,
  type KnowledgeBaseShowView,
  type KnowledgeBaseStatusResult,
  type KnowledgeBaseValidationResult,
  type LeanDeclRef,
  type Node,
  type NodeKind,
  type NodeMetadata,
  type NodePaths,
  type NodeStatus,
  type RelatedRelationships,
  type Relationship,
  type RelationshipKind,
  type SearchHit,
  type SearchResult,
  type SearchScope,
  type StatusInfo,
  type StorageManifest,
  type StoredNode,
  type ValidationIssue,
  type ValidationReport,
  type ValidationScope,
  type ValidationSeverity,
} from "./toolkit/knowledgebase/client.ts";

export {
  InformalClient,
  type CreateInformalClientOptions,
  type InformalBodyPresentation,
  type InformalCliFailure,
  type InformalCliResponse,
  type InformalCliSuccess,
  type InformalCommandOptions,
  type InformalDeclDependencyRow,
  type InformalDeclEntry,
  type InformalDeclResult,
  type InformalDeclsOptions,
  type InformalDeclsResult,
  type InformalDepsOptions,
  type InformalDepsResult,
  type InformalEnvironmentOptions,
  type InformalPresentOptions,
  type InformalPresentResult,
  type InformalPresentationPayload,
  type InformalPresentationSummary,
  type InformalRefResult,
  type InformalReferenceDependencyRow,
  type InformalReferenceEntry,
  type InformalRefsOptions,
  type InformalRefsResult,
  type InformalStatusResult,
} from "./toolkit/informal/client.ts";
