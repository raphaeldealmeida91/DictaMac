enum DiagnosticMemoryContext: String, Sendable {
    case startup
    case memoryPressureWarning = "memory_pressure_warning"
    case memoryPressureCritical = "memory_pressure_critical"
    case dictationStarted = "dictation_started"
    case dictationFinished = "dictation_finished"
    case whisperUnloaded = "whisper_unloaded"
    case whisperLoaded = "whisper_loaded"
    case mlxUnloaded = "mlx_unloaded"
    case mlxLoadFinished = "mlx_load_finished"
}
