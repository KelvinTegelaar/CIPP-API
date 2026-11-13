# Pester tests for Write-LogMessage: a Debug line with DebugMode off is dropped before any table work, and an API
# client's name comes from Get-CippApiClient (read once per invocation) instead of a table read per log line.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Write-LogMessage.ps1')

    function Get-CIPPTable { param($tablename) @{ TableName = $tablename } }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity) }
    function Get-CippApiClient { param($AppId) }

    $script:ApiHeaders = @{ 'x-ms-client-principal-idp' = 'aad'; 'x-ms-client-principal-name' = '11111111-2222-3333-4444-555555555555' }
}

Describe 'Write-LogMessage' {
    BeforeEach {
        $script:Written = $null
        Mock Get-CIPPTable { @{ TableName = $tablename } }
        Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }
        Mock Get-CippApiClient { [pscustomobject]@{ AppName = 'ActionCenter' } }
    }

    It 'drops a Debug line with DebugMode off before looking up the caller or touching a table' {
        $Previous = [System.Environment]::GetEnvironmentVariable('DebugMode')
        [System.Environment]::SetEnvironmentVariable('DebugMode', $null)
        try { Write-LogMessage -API 'Test' -message 'debug' -sev 'Debug' -headers $script:ApiHeaders }
        finally { [System.Environment]::SetEnvironmentVariable('DebugMode', $Previous) }
        Should -Invoke Get-CippApiClient -Times 0 -Exactly
        Should -Invoke Get-CIPPTable -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'names an API client from Get-CippApiClient' {
        Write-LogMessage -API 'Test' -message 'hello' -sev 'Info' -headers $script:ApiHeaders
        Should -Invoke Get-CippApiClient -Times 1 -Exactly -ParameterFilter { $AppId -eq $script:ApiHeaders.'x-ms-client-principal-name' }
        $script:Written.Username | Should -Be 'ActionCenter'
        $script:Written.AppId | Should -Be $script:ApiHeaders.'x-ms-client-principal-name'
    }

    It 'falls back to CIPP-API for an unknown client' {
        Mock Get-CippApiClient { }
        Write-LogMessage -API 'Test' -message 'hello' -sev 'Info' -headers $script:ApiHeaders
        $script:Written.Username | Should -Be 'CIPP-API'
    }
}
