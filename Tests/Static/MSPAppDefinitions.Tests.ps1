BeforeDiscovery {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AppDefinitions = @(Get-ChildItem -Path (Join-Path $BackendRoot 'AddMSPApp') -Filter '*.app.json' -File)
    if ($AppDefinitions.Count -lt 5) { throw "Expected the MSP app definitions to be present; found $($AppDefinitions.Count)" }
}

Describe 'MSP app definitions' {
    It '<_.Name> sets setupFilePath' -ForEach $AppDefinitions {
        $Definition = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json
        $Definition.setupFilePath | Should -Not -BeNullOrEmpty -Because 'Graph rejects a win32LobApp without a valid setupFilePath'
    }
}
