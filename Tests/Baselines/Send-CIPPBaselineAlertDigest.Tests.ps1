# Pester tests for Send-CIPPBaselineAlertDigest: every finished baseline orchestration runs the digest, so
# concurrent callers must each send only the queued rows they managed to delete (issue #1159).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Send-CIPPBaselineAlertDigest.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    function Get-CippTable { param($TableName) @{ Context = $TableName } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Remove-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function New-CIPPAlertTemplate { param($Format, $InputObject, $Data, $CIPPURL, $Tenant) @{ title = 'title'; htmlcontent = 'html' } }
    function Send-CIPPAlert { param($Type, $Title, $HTMLContent, $JSONContent, $TenantFilter, $altEmail, $altWebhook, $APIName, $SchemaSource, $InvokingCommand, [switch]$UseStandardizedSchema) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev) }

    . $FunctionPath
}

Describe 'Send-CIPPBaselineAlertDigest' {
    BeforeEach {
        $Queued = @(
            [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'ManualTask~a-Drift'; Event = 'Drift'; Standard = 'ManualTask#a'; Differences = '[]'; Timestamp = [datetime]::UtcNow }
            [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'ManualTask~b-Drift'; Event = 'Drift'; Standard = 'ManualTask#b'; Differences = '[]'; Timestamp = [datetime]::UtcNow }
        )
        Mock Get-CIPPAzDataTableEntity { if ($Context -eq 'BaselineAlertQueue') { $Queued } }
        Mock Remove-AzDataTableEntity { }
        Mock New-CIPPAlertTemplate { @{ title = 'title'; htmlcontent = 'html' } }
        Mock Send-CIPPAlert { }
        Mock Write-LogMessage { }
    }

    It 'sends every row it claims, once per channel' {
        Send-CIPPBaselineAlertDigest

        Should -Invoke Send-CIPPAlert -Times 2 -Exactly
        Should -Invoke New-CIPPAlertTemplate -Times 1 -Exactly -ParameterFilter { @($Data).Count -eq 2 }
    }

    It 'skips rows another digest already deleted' {
        Mock Remove-AzDataTableEntity { if ($Entity.RowKey -eq 'ManualTask~a-Drift') { throw 'ResourceNotFound' } }

        Send-CIPPBaselineAlertDigest

        Should -Invoke New-CIPPAlertTemplate -Times 1 -Exactly -ParameterFilter { @($Data).Count -eq 1 -and $Data[0].Standard -eq 'ManualTask#b' }
    }

    It 'sends nothing when every row was claimed elsewhere' {
        Mock Remove-AzDataTableEntity { throw 'ResourceNotFound' }

        Send-CIPPBaselineAlertDigest

        Should -Invoke Send-CIPPAlert -Times 0 -Exactly
    }

    It 'deletes with the ETag check, so a row re-queued after the read is left for the next digest' {
        Send-CIPPBaselineAlertDigest

        Should -Invoke Remove-AzDataTableEntity -Times 0 -Exactly -ParameterFilter { $Force }
    }
}
