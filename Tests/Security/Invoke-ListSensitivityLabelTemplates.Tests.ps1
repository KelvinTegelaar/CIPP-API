# Pester tests for Invoke-ListSensitivityLabelTemplates ordering and ID filter

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Path = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Security/Compliance-SensitivityLabel'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Filter, $TableName) $script:rows }

    . (Join-Path $Path 'Invoke-ListSensitivityLabelTemplates.ps1')

    function New-Row($Guid, $Object) { [pscustomobject]@{ RowKey = $Guid; JSON = ($Object | ConvertTo-Json) } }
    function Get-Names($Query) {
        $Request = [pscustomobject]@{ Query = $Query }
        @((Invoke-ListSensitivityLabelTemplates -Request $Request -TriggerMetadata $null).Body | ForEach-Object { $_.DisplayName })
    }
}

Describe 'Invoke-ListSensitivityLabelTemplates' {
    BeforeEach {
        $script:rows = @(
            New-Row 'g1' @{ DisplayName = 'Ten'; Priority = 10 }
            New-Row 'g2' @{ DisplayName = 'Two'; Priority = '2' }
            New-Row 'g3' @{ DisplayName = 'NoPriorityB' }
            New-Row 'g4' @{ DisplayName = 'Beta'; Priority = 5 }
            New-Row 'g5' @{ DisplayName = 'Alpha'; Priority = 5 }
            New-Row 'g6' @{ DisplayName = 'NoPriorityA' }
        )
    }

    It 'sorts by numeric priority, name as tiebreak, missing priority last' {
        Get-Names ([pscustomobject]@{}) | Should -Be @('Two', 'Alpha', 'Beta', 'Ten', 'NoPriorityA', 'NoPriorityB')
    }

    It 'keeps the ID filter' {
        Get-Names ([pscustomobject]@{ ID = 'g4' }) | Should -Be @('Beta')
    }

    It 'falls back to Name when DisplayName is absent' {
        $script:rows = @(
            New-Row 'g1' @{ Name = 'Zed'; Priority = 1 }
            New-Row 'g2' @{ Name = 'Abe'; Priority = 1 }
        )
        $Request = [pscustomobject]@{ Query = [pscustomobject]@{} }
        $Body = (Invoke-ListSensitivityLabelTemplates -Request $Request -TriggerMetadata $null).Body
        @($Body | ForEach-Object { $_.Name }) | Should -Be @('Abe', 'Zed')
    }
}
