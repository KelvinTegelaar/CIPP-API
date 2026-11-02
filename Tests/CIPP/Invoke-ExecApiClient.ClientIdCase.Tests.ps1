# ApiClients rows are keyed by Graph's canonical lowercase appId. The AddUpdate role-grant check looks up the
# existing client by the caller's ClientId; if that lookup is case-sensitive, an upper-cased GUID matches no
# row, the existing (e.g. superadmin) role is never added to the grant check, and an editor can hijack the
# client. ExecApiClient must normalise the ClientId before the lookup so the existing role is always evaluated.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Settings/Invoke-ExecApiClient.ps1'
    $FilterHelper = Join-Path $BackendRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }

    function Get-CippTable { param($tablename) @{} }
    function Get-CippProtectedAppId { @() }
    function Write-LogMessage { param($headers, $API, $message, $Sev) }
    function Test-CippApiClientRoleGrant { param($Request, $Role) }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function New-CIPPAPIConfig { }
    function Get-CippException { param($Exception) @{} }

    . $FilterHelper
    . $FunctionPath

    $script:StoredId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'   # canonical lowercase row key
    $script:UpperId = $script:StoredId.ToUpperInvariant()        # what an attacker sends
}

Describe 'Invoke-ExecApiClient ClientId case normalisation' {
    BeforeEach {
        $script:GrantRoles = $null
        # Azure Table RowKey eq is case-sensitive, so model it with -cmatch (not the default case-insensitive -match).
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -cmatch $script:StoredId) {
                [pscustomobject]@{ RowKey = $script:StoredId; Role = 'superadmin'; AppName = 'Integration' }
            } else { $null }
        }
        Mock Test-CippApiClientRoleGrant {
            $script:GrantRoles = @($Role)
            @{ Allowed = $false; Message = 'denied' }   # stop before any write
        }
        Mock Get-CippProtectedAppId { @() }
    }

    It 'evaluates the existing superadmin role even when the ClientId is upper-cased' {
        $Request = [pscustomobject]@{
            Headers = @{}
            Query   = @{}
            Body    = [pscustomobject]@{ Action = 'AddUpdate'; ClientId = $script:UpperId; Role = @{ value = 'readonly' } }
        }
        $Response = Invoke-ExecApiClient -Request $Request
        $script:GrantRoles | Should -Contain 'superadmin' -Because 'the existing role must be checked regardless of ClientId casing'
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Forbidden)
    }

    It 'rejects a ClientId that is not a GUID' {
        $Request = [pscustomobject]@{
            Headers = @{}
            Query   = @{}
            Body    = [pscustomobject]@{ Action = 'AddUpdate'; ClientId = "x' or RowKey eq 'y"; Role = @{ value = 'readonly' } }
        }
        $Response = Invoke-ExecApiClient -Request $Request
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }
}
