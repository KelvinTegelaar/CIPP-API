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
