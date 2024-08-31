param($Timer)

if ($env:DEV_SKIP_DOMAIN_TIMER) {
    Write-Host 'Skipping DomainAnalyser timer'
    exit 0
}

Start-DomainOrchestrator
