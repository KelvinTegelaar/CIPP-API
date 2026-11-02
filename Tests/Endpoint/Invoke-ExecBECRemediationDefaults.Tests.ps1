[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'New-Request only builds an in-memory request object for the tests.')]
param()

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Write-LogMessage { param($message, $API, $headers, $sev) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecContainmentActions.ps1')
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecBECRemediationDefaults.ps1' | Select-Object -First 1).FullName

    function New-Request {
        param($Query = @{}, $Body = $null)
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecBECRemediationDefaults' }
            Headers = $null
            Query   = [pscustomobject]$Query
            Body    = $Body
        }
    }
}

Describe 'Invoke-ExecBECRemediationDefaults' {
    BeforeEach {
        Mock Add-CIPPAzDataTableEntity { }
        Mock Write-LogMessage { }
    }

    It 'lists the catalog with the effective defaults' {
        $Response = Invoke-ExecBECRemediationDefaults -Request (New-Request -Query @{ List = 'true' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results.Count | Should -Be 21
        @($Response.Body.Results | Where-Object { $_.DefaultSelected }).Id | Should -Contain 'BlockProtocols'
    }

    It 'saves the selected ids as a JSON array' {
        $Response = Invoke-ExecBECRemediationDefaults -Request (New-Request -Body ([pscustomobject]@{ DefaultActions = @('RevokeSessions', 'ClearForwarding') })) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.PartitionKey -eq 'BecRemediation' -and $Entity.RowKey -eq 'Defaults' -and $Entity.DefaultActions -eq '["RevokeSessions","ClearForwarding"]' }
    }

    It 'rejects an empty selection and unknown ids without saving' {
        (Invoke-ExecBECRemediationDefaults -Request (New-Request -Body ([pscustomobject]@{ DefaultActions = @() })) -TriggerMetadata $null).StatusCode | Should -Be 400
        (Invoke-ExecBECRemediationDefaults -Request (New-Request -Body ([pscustomobject]@{ DefaultActions = @('Nope') })) -TriggerMetadata $null).StatusCode | Should -Be 400
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }
}
