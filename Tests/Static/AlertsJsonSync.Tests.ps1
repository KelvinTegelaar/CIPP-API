# The scheduler reads backend/Config/alerts.json for each alert's minimumRunInterval; the UI reads the frontend copy.
# Edit frontend/src/data/alerts.json and run build/tools/Update-AlertsJson.ps1 to sync the backend copy.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:Frontend = Join-Path (Split-Path -Parent $BackendRoot) 'frontend/src/data/alerts.json'
    $script:Backend = Join-Path $BackendRoot 'Config/alerts.json'
}

Describe 'alerts.json copies' {
    It 'keeps the backend copy identical to the frontend catalog' {
        $Read = { param($Path) [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n") }
        & $Read $script:Backend | Should -BeExactly (& $Read $script:Frontend) -Because 'run build/tools/Update-AlertsJson.ps1 after editing frontend/src/data/alerts.json'
    }

    It 'has no repeated keys in an entry (the last one silently wins)' {
        $Doc = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($script:Frontend))
        foreach ($Entry in $Doc.RootElement.EnumerateArray()) {
            $Names = @($Entry.EnumerateObject() | ForEach-Object Name)
            $Names | Group-Object | Where-Object Count -GT 1 | ForEach-Object Name | Should -BeNullOrEmpty -Because "$($Entry.GetProperty('name').GetString()) repeats a key"
        }
    }

    It 'sets every minimumRunInterval to a recurrence the alert form offers, at or below the recommended one' {
        $FormPath = Join-Path (Split-Path -Parent $BackendRoot) 'frontend/src/pages/tenant/administration/alert-configuration/alert.jsx'
        $Offered = @([regex]::Matches([System.IO.File]::ReadAllText($FormPath), "\{ value: '(\d+[mhd])', label: 'Every") | ForEach-Object { $_.Groups[1].Value })
        $Seconds = { param($Value) [int64]($Value -replace '\D') * @{ m = 60; h = 3600; d = 86400 }[($Value -replace '\d')] }
        $Catalog = Get-Content -Path $script:Frontend -Raw | ConvertFrom-Json
        foreach ($Alert in $Catalog.Where({ $_.minimumRunInterval })) {
            $Alert.minimumRunInterval | Should -BeIn $Offered -Because "the form raises $($Alert.name) to its minimum, so the minimum must be an option"
            if ($Alert.recommendedRunInterval) {
                (& $Seconds $Alert.recommendedRunInterval) | Should -BeGreaterOrEqual (& $Seconds $Alert.minimumRunInterval) -Because "$($Alert.name) would recommend a recurrence it filters out"
            }
        }
    }
}
