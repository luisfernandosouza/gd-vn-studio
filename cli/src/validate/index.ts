/** Content Validator (Data Model §11, UI Spec §11, Req §6 e §14): API usada pela CLI e, depois, pelo Studio. */
export { formatDiagnostic, validateProject, type Diagnostic, type Severity, type ValidateOptions, type ValidationResult } from './validator.js';
export { plainMessage, KNOWN_CODES } from './messages.js';
export { findSpecs } from './schemas.js';
