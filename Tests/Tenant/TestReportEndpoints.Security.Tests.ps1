# The custom-report Add/Delete endpoints create, overwrite and delete report definitions, so they must carry a
# write permission (Tenant.Tests.ReadWrite), not the read-only CIPP.Dashboard.Read, and must validate ReportId
# as a GUID so a crafted value cannot inject into the table filter and mass-delete every report.

Describe 'Test report endpoint permissions' {
    It 'tags <_> as a write permission, not a read role' -ForEach @('Invoke-AddTestReport.ps1', 'Invoke-DeleteTestReport.ps1') {
        $TestsRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Tests'
        $Source = Get-Content (Join-Path $TestsRoot $_) -Raw
        $Source | Should -Match 'Tenant\.Tests\.ReadWrite'
        $Source | Should -Not -Match 'CIPP\.Dashboard\.Read'
    }
}

Describe 'Invoke-DeleteTestReport ReportId validation' {
    BeforeAll {
        $BackendRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Tests/Invoke-DeleteTestReport.ps1'
        $FilterHelper = Join-Path $BackendRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1'
        ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
            $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
        class HttpResponseContext { [int]$StatusCode; [object]$Body }
        function Get-CippTable { param($tablename) @{} }
        function Get-CIPPAzDataTableEntity { param($Filter) }
        function Remove-CIPPAzDataTableEntity { param($Entity) }
        function Write-LogMessage { param($user, $API, $tenant, $message, $Sev, $LogData) }
        function Get-CippException { param($Exception) @{ NormalizedError = 'err' } }
        . $FilterHelper
        . $FunctionPath
    }

    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'Report'; RowKey = 'r' } }
        Mock Remove-CIPPAzDataTableEntity { }
    }

    It 'rejects an injection ReportId and never deletes' {
        $Request = [pscustomobject]@{ Headers = @{}; Body = [pscustomobject]@{ ReportId = "x' or RowKey eq 'y" } }
        $Response = Invoke-DeleteTestReport -Request $Request -TriggerMetadata @{ FunctionName = 'DeleteTestReport' }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'deletes a single report for a valid GUID (scoped to PartitionKey Report)' {
        $Request = [pscustomobject]@{ Headers = @{}; Body = [pscustomobject]@{ ReportId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } }
        $Response = Invoke-DeleteTestReport -Request $Request -TriggerMetadata @{ FunctionName = 'DeleteTestReport' }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Filter -match "PartitionKey eq 'Report'" -and $Filter -match 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly
    }
}
