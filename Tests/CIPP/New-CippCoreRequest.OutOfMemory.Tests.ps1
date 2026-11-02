# An endpoint that runs out of memory catches the error itself and returns a bare "Exception of type
# 'System.OutOfMemoryException' was thrown". The dispatcher replaces that with a message telling the caller to page
# or narrow the request, because API automations otherwise retry the same oversized read.

BeforeAll {
    if (-not ('Microsoft.Azure.Functions.PowerShellWorker.HttpResponseContext' -as [type])) {
        Add-Type -TypeDefinition 'namespace Microsoft.Azure.Functions.PowerShellWorker { public class HttpResponseContext { public object StatusCode { get; set; } public object Body { get; set; } } }'
    }

    # Dispatcher and endpoints each live in a module, as CIPPCore and CIPPHTTP do under Craft: a module has its own
    # empty $Error, so a dispatcher that read it instead of the runspace's would never see the endpoint's error.
    $DispatcherPath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'Modules/CIPPCore/Public/Entrypoints/HTTP Functions/New-CippCoreRequest.ps1'
    $null = New-Module -Name OomHintCore -ArgumentList $DispatcherPath -ScriptBlock {
        param($Path)
        function Initialize-CippRequestContext {}
        function Set-CippUserAgentContext { param($Headers) }
        function Get-CIPPFeatureFlag { @() }
        function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
        function Measure-CippTask { param($TaskName, $Metadata, $Script) & $Script }
        function Test-CIPPAccess {
            param($Request, [switch]$TenantList, [switch]$GroupList)
            if ($TenantList) { 'AllTenants' } elseif ($GroupList) { 'AllGroups' } else { $true }
        }
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = $null }
        $script:CippAllowedGroupsStorage = [pscustomobject]@{ Value = $null }
        . $Path
        Export-ModuleMember -Function New-CippCoreRequest
    }
    $null = New-Module -Name OomHintHttp -ScriptBlock {
        function New-Response($StatusCode, $Body) {
            [Microsoft.Azure.Functions.PowerShellWorker.HttpResponseContext]@{ StatusCode = $StatusCode; Body = $Body }
        }
        function Invoke-ListPaged {
            param($Request, $TriggerMetadata)
            if ($Request.Query.manualPagination -eq $true) { 'paged' }
            try { throw [System.OutOfMemoryException]::new() } catch { return (New-Response 500 @($_.Exception.Message)) }
        }
        function Invoke-ListUnpaged {
            param($Request, $TriggerMetadata)
            try { $null = [string]::new('a', [int]::MaxValue) } catch { return (New-Response 500 @($_.Exception.Message)) }
        }
        function Invoke-ListEscapes {
            param($Request, $TriggerMetadata)
            throw [System.OutOfMemoryException]::new()
        }
        function Invoke-ListRecovers {
            param($Request, $TriggerMetadata)
            try { throw [System.OutOfMemoryException]::new() } catch { return (New-Response 200 @('fallback')) }
        }
        function Invoke-ListFails {
            param($Request, $TriggerMetadata)
            try { throw 'Graph said no' } catch { return (New-Response 500 @($_.Exception.Message)) }
        }
        Export-ModuleMember -Function Invoke-*
    }

    function Send-Request($Endpoint, $Query = @{}) {
        New-CippCoreRequest -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = $Endpoint }; Headers = @{}; Query = $Query; Body = $null }) -TriggerMetadata @{}
    }
}

AfterAll {
    Remove-Module OomHintCore, OomHintHttp -Force -ErrorAction SilentlyContinue
}

Describe 'New-CippCoreRequest out-of-memory responses' {
    It 'tells an unpaged request on a paged endpoint to use manualPagination' {
        $Response = Send-Request 'ListPaged'
        [int]$Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Match 'manualPagination=true'
    }

    It 'tells a paged request to ask for a smaller page' {
        $Response = Send-Request 'ListPaged' @{ manualPagination = 'true' }
        $Response.Body.Results | Should -Match 'smaller page'
    }

    It 'tells a request on an endpoint without paging to narrow the tenant' {
        $Response = Send-Request 'ListUnpaged'
        [int]$Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Not -Match 'manualPagination'
        $Response.Body.Results | Should -Match 'single tenant'
    }

    It 'handles an out-of-memory error that escapes the endpoint' {
        $Response = Send-Request 'ListEscapes'
        [int]$Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Match 'single tenant'
    }

    It 'leaves a response alone when the endpoint recovered' {
        $Response = Send-Request 'ListRecovers'
        [int]$Response.StatusCode | Should -Be 200
        $Response.Body | Should -Be @('fallback')
    }

    It 'does not blame a later failure on an earlier request''s out-of-memory error' {
        $null = Send-Request 'ListPaged'
        $Response = Send-Request 'ListFails'
        [int]$Response.StatusCode | Should -Be 500
        $Response.Body | Should -Be @('Graph said no')
    }
}
