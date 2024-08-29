param($Timer)

try {
    Start-ApplicationOrchestrator
} catch {
    Write-Host "AddChocoApp_OrchestratorStarterTimer Exception: $($_.Exception.Message)"
}
