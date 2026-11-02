# Pester tests for the error mapping in New-ExoRequest.
#
# The admin API reports failures as {error:{message, innererror:{message, [internalException]}}}.
# The mapping only read innererror.internalException.message, so a body without that nested
# member (Test-Message's result-serialisation failure, for one) was dropped and the caller saw
# only "Response status code does not indicate success: 500".

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/New-ExoRequest.ps1'

    function Get-AuthorisedRequest { param($TenantID) $true }
    function Get-GraphToken { param($Tenantid, $scope, [switch]$AsApp, [switch]$UseCertificate) @{ Authorization = 'Bearer t' } }
    function Get-Tenants { param([switch]$IncludeErrors, $TenantFilter) [pscustomobject]@{ customerId = 'tid'; defaultDomainName = 'contoso.example'; initialDomainName = 'contoso.onmicrosoft.com' } }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Invoke-CIPPRestMethod { param($Uri, $Method, $Body, $Headers, $ContentType, $ResponseHeadersVariable, $MaximumRedirection, [switch]$SkipHttpErrorCheck, $StatusCodeVariable, $TimeoutSec) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData, $headers) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Write-Information { param($MessageData) }

    . $FunctionPath

    function New-HttpError {
        param([string]$Json)
        $Record = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Response status code does not indicate success: 500'), 'Http500', 'InvalidOperation', $null)
        $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Json)
        return $Record
    }
}

Describe 'New-ExoRequest error mapping' {
    It 'surfaces innererror.message when there is no internalException' {
        Mock Invoke-CIPPRestMethod { throw (New-HttpError '{"error":{"code":"InternalServerError","message":"Unable to cast object of type ''TestMessageResult'' to type ''System.Collections.IEnumerable''.","innererror":{"message":"Unable to cast object of type ''TestMessageResult'' to type ''System.Collections.IEnumerable''.","type":"System.InvalidCastException"}}}') }
        { New-ExoRequest -tenantid 'contoso.example' -cmdlet 'Test-Message' -cmdParams @{ Recipients = 'a@b' } } | Should -Throw '*TestMessageResult*'
    }

    It 'still prefers internalException.message when present' {
        Mock Invoke-CIPPRestMethod { throw (New-HttpError '{"error":{"message":"outer","innererror":{"message":"inner","internalException":{"message":"deepest"}}}}') }
        { New-ExoRequest -tenantid 'contoso.example' -cmdlet 'Get-Mailbox' -cmdParams @{ Identity = 'x' } } | Should -Throw 'deepest'
    }
}
