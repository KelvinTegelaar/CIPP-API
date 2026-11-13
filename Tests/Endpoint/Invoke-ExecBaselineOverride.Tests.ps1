BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) [pscustomobject]@{ customerId = 'tenant-id' } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value) $Value }
    function Add-CIPPBaselineHistoryEvent { param($TenantFilter, $Standard, $Mode, $TriggeredBy, $Outcome, $Detail) }
    function Write-LogMessage { param($headers, $API, $message, $Sev) }
    function Get-CippErrorStatusCode { param($ErrorRecord) 500 }
    . (Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-ExecBaselineOverride.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Resolve-CIPPBaselineExpiry.ps1')
    function Get-CIPPBaselineExpiryPolicy { [pscustomobject]@{ defaultDays = 0; maxDays = 0 } }

    function New-Row($Tiers) {
        [pscustomobject]@{
            PartitionKey    = 'contoso.com'
            RowKey          = 'UserPreferredLanguage'
            StandardName    = 'UserPreferredLanguage'
            TemplateId      = ''
            Status          = 'Accepted'
            DeviationReason = 'accepted by test'
            Inheritance     = ConvertTo-Json -Compress -Depth 10 -InputObject $Tiers
        }
    }

    $script:BaselineTier = [pscustomobject]@{ templateName = 'CIPPTestBaseline'; assignedTo = 'contoso.com'; value = [pscustomobject]@{ Language = 'en-US' }; effective = $false }
    $script:OverrideTier = [pscustomobject]@{ templateName = 'Tenant Override'; assignedTo = 'contoso.com'; value = [pscustomobject]@{ Language = 'de-DE' }; effective = $true }
}

Describe 'Invoke-ExecBaselineOverride deleteOverride' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { if ($Filter -notlike '*standardItem*') { $script:Row } }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Remove-CIPPAzDataTableEntity { }
        $Principal = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"userDetails":"tester@example.com"}'))
        $script:Request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecBaselineOverride' }
            Headers = @{ 'x-ms-client-principal' = $Principal }
            Body    = [pscustomobject]@{ action = 'deleteOverride'; tenantFilter = 'contoso.com'; standard = 'UserPreferredLanguage' }
        }
    }

    It 'keeps the row and its triage when a baseline tier remains' {
        $script:Row = New-Row @($script:BaselineTier, $script:OverrideTier)
        (Invoke-ExecBaselineOverride -Request $script:Request).StatusCode | Should -Be 200
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -ParameterFilter { $TableName -eq 'BaselineAlignment' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.DeviationReason -eq 'accepted by test' }
    }

    It 'still removes a row that only the tenant override backs' {
        $script:Row = New-Row @($script:OverrideTier)
        (Invoke-ExecBaselineOverride -Request $script:Request).StatusCode | Should -Be 200
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $TableName -eq 'BaselineAlignment' }
    }
}

Describe 'Invoke-ExecBaselineOverride createOverride' {
    BeforeEach {
        $script:Added = [System.Collections.Generic.List[object]]::new()
        $script:Events = [System.Collections.Generic.List[string]]::new()
        Mock Get-CIPPAzDataTableEntity { }
        Mock Add-CIPPAzDataTableEntity { $script:Added.Add($Entity) }
        Mock Add-CIPPBaselineHistoryEvent { $script:Events.Add($Detail) }
        $Principal = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"userDetails":"admin@contoso.com"}'))
        $script:NewRequest = {
            param($Body)
            [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecBaselineOverride' }; Headers = @{ 'x-ms-client-principal' = $Principal }; Body = [pscustomobject]$Body }
        }
    }

    It 'stores the reason and expiry on the override and in its history event' {
        $Response = Invoke-ExecBaselineOverride -Request (& $script:NewRequest @{
                action = 'createOverride'; tenantFilter = 'contoso.com'; standard = 'DisableGuests'
                reason = 'Change ticket 42'; expires = 1893456000; variables = @{}
            })

        $Response.StatusCode | Should -Be 200
        $script:Added[0].reason | Should -Be 'Change ticket 42'
        $script:Added[0].expires | Should -Be '1893456000'
        $script:Added[0].updatedBy | Should -Be 'admin@contoso.com'
        $Response.Body.Results | Should -Match 'expires on 2030-01-01'
        $script:Events[0] | Should -Match 'Change ticket 42'
    }

    It 'stores no expiry when none is given' {
        $null = Invoke-ExecBaselineOverride -Request (& $script:NewRequest @{
                action = 'createOverride'; tenantFilter = 'contoso.com'; standard = 'DisableGuests'; reason = 'Customer request'
            })

        $script:Added[0].expires | Should -Be ''
    }
}
