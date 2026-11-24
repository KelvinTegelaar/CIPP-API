# Pester tests for Invoke-ListMailQuarantine
BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListMailQuarantine.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListMailQuarantine.ps1 under Modules/' }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) [pscustomobject]@{ customerId = 'cid' } }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams) }
    function Add-CIPPQuarantineMessageProperties { param($Message, $Tenant, $CustomerId) }
    function Get-NormalizedError { param($Message) "normalized: $Message" }

    . $FunctionPath
}

Describe 'Invoke-ListMailQuarantine' {
    BeforeAll {
        $script:Request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListMailQuarantine' }
            Headers = @{}
            Query   = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com' }
        }
    }

    It 'returns the messages with OK on success' {
        Mock New-ExoRequest { @([pscustomobject]@{ Identity = 'm1'; ReceivedTime = '2026-01-01' }) }
        $Response = Invoke-ListMailQuarantine -Request $script:Request -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        @($Response.Body.Results).Identity | Should -Be 'm1'
    }

    It 'returns the error with a 500 instead of an empty 200 list when Exchange fails' {
        Mock New-ExoRequest { throw 'EXO is down' }
        $Response = Invoke-ListMailQuarantine -Request $script:Request -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::InternalServerError)
        "$($Response.Body.Results)" | Should -Match 'EXO is down'
    }
}
