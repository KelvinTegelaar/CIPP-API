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
    # The real catalog: the endpoint is a projection of it, so the test pins what the frontend sees.
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecContainmentActions.ps1')
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListBECRemediationActions.ps1' | Select-Object -First 1
    . $FunctionPath.FullName

    function New-Request {
        param([hashtable]$Query = @{})
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ListBECRemediationActions' }
            Headers = [pscustomobject]@{ 'x-ms-client-principal' = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"userDetails":"tech@msp.com"}')) }
            Query   = [pscustomobject]$Query
            Body    = $null
        }
    }
}

Describe 'Invoke-ListBECRemediationActions' {
    It 'returns the catalog as a bare array of 21 actions, without needing a tenant' {
        $Response = Invoke-ListBECRemediationActions -Request (New-Request) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        $Response.Body.GetType().IsArray | Should -BeTrue -Because 'list endpoints return rows, not a Results wrapper'
        $Response.Body.Count | Should -Be 21
        $Response.Body[0].Id | Should -Be 'ResetPassword'
        $Response.Body[-1].Id | Should -Be 'RemoveSharingLinks'
    }

    It 'projects exactly the fields the frontend renders, each with a label and description' {
        $Response = Invoke-ListBECRemediationActions -Request (New-Request) -TriggerMetadata $null
        $Expected = @('Id', 'Label', 'Description', 'Impact', 'Reversible', 'DefaultSelected', 'Order', 'TargetSource', 'ParameterName')
        foreach ($Row in $Response.Body) { @($Row.PSObject.Properties.Name) | Should -Be $Expected }
        @($Response.Body | Where-Object { -not $_.Label -or -not $_.Description }).Count | Should -Be 0
        ($Response.Body | Where-Object { $_.Id -eq 'RemoveMFA' }).ParameterName | Should -Be 'MfaMethodIds'
        ($Response.Body | Where-Object { $_.Id -eq 'RemoveMFA' }).TargetSource | Should -Be 'MFADevices'
    }

    It 'flags the destructive actions as Critical and keeps every impact within the four levels' {
        $Body = (Invoke-ListBECRemediationActions -Request (New-Request) -TriggerMetadata $null).Body
        @($Body | Where-Object { $_.Impact -eq 'Critical' }).Id | Should -Be @('ResetPassword', 'DisableAccount', 'RemoveOAuthGrants', 'DisableServicePrincipals', 'RemoveDelegations', 'DisableTransportRules', 'RemoveRegisteredDevices')
        @($Body | Where-Object { $_.Impact -notin @('Low', 'Medium', 'High', 'Critical') }).Count | Should -Be 0
        ($Body | Where-Object { $_.Id -eq 'ResetPassword' }).Reversible | Should -BeFalse
        ($Body | Where-Object { $_.Id -eq 'DisableAccount' }).Reversible | Should -BeTrue
    }

    It 'pre-selects the built-in default set and numbers the actions in dispatcher order' {
        $Body = (Invoke-ListBECRemediationActions -Request (New-Request) -TriggerMetadata $null).Body
        @($Body | Where-Object { $_.DefaultSelected }).Id | Should -Be @('ResetPassword', 'DisableAccount', 'RevokeSessions', 'RemoveMFA', 'DisableInboxRules', 'BlockProtocols')
        @($Body.Id | Select-Object -Unique).Count | Should -Be 21
        @($Body.Order) | Should -Be @(1..21)
    }

    It 'replaces the built-in defaults with the instance-wide defaults saved in settings' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ DefaultActions = '["RevokeSessions","ClearForwarding"]' } } -ParameterFilter { $Filter -match 'BecRemediation' }
        $Body = (Invoke-ListBECRemediationActions -Request (New-Request) -TriggerMetadata $null).Body
        @($Body | Where-Object { $_.DefaultSelected }).Id | Should -Be @('RevokeSessions', 'ClearForwarding')
    }

    It 'keeps the built-in defaults when the settings read fails' {
        Mock Get-CIPPTable { throw 'storage down' }
        $Body = (Invoke-ListBECRemediationActions -Request (New-Request) -TriggerMetadata $null).Body
        @($Body | Where-Object { $_.DefaultSelected }).Count | Should -Be 6
    }

    It 'reports a catalog failure as a 500 with a Results message' {
        Mock Get-CIPPBecContainmentActions { throw 'catalog broken' }
        $Response = Invoke-ListBECRemediationActions -Request (New-Request) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Be 'Failed to list containment actions: catalog broken'
    }
}
