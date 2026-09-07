# Pester tests for the AddBinding action of Invoke-ExecAppServiceDomains.
# ARM only validates ownership through the alias record when customHostNameDnsRecordType is set
# explicitly; without it the bind demands an asuid TXT record and fails on a perfectly good CNAME.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Settings/Invoke-ExecAppServiceDomains.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Invoke-ExecAppServiceDomains.ps1 at $FunctionPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPAppServiceSite { param($ApiVersion) }
    function New-CIPPAzRestRequest { param($Uri, $Method, $Body, $ContentType) }
    function Write-LogMessage { param($API, $headers, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $FunctionPath

    function New-DomainRequest {
        param([string]$Action, [string]$Hostname)
        [pscustomobject]@{
            Body    = [pscustomobject]@{ Action = $Action; Hostname = $Hostname }
            Query   = [pscustomobject]@{}
            Headers = @{}
            Params  = @{ CIPPEndpoint = 'ExecAppServiceDomains' }
        }
    }
}

Describe 'Invoke-ExecAppServiceDomains AddBinding' {
    BeforeEach {
        Mock -CommandName Get-CIPPAppServiceSite -MockWith {
            [pscustomobject]@{
                SiteName   = 'cippxyz'
                ArmBase    = 'https://management.azure.com/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Web/sites/cippxyz'
                ApiVersion = '2024-11-01'
                Site       = [pscustomobject]@{ properties = [pscustomobject]@{ defaultHostName = 'cippxyz.azurewebsites.net'; inboundIpAddress = '1.2.3.4' } }
            }
        }
        Mock -CommandName New-CIPPAzRestRequest -MockWith { [pscustomobject]@{} }
        Mock -CommandName Write-LogMessage
    }

    It 'binds a subdomain with CNAME validation' {
        $Response = Invoke-ExecAppServiceDomains -Request (New-DomainRequest -Action 'AddBinding' -Hostname 'Portal.Contoso.com ')

        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        Should -Invoke New-CIPPAzRestRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Uri -like '*/hostNameBindings/portal.contoso.com?*' -and $Body.properties.customHostNameDnsRecordType -eq 'CName'
        }
    }

    It 'binds an apex domain with A record validation' {
        Invoke-ExecAppServiceDomains -Request (New-DomainRequest -Action 'AddBinding' -Hostname 'contoso.com') | Out-Null

        Should -Invoke New-CIPPAzRestRequest -Times 1 -Exactly -ParameterFilter {
            $Body.properties.customHostNameDnsRecordType -eq 'A'
        }
    }

    It 'refuses the platform hostname' {
        $Response = Invoke-ExecAppServiceDomains -Request (New-DomainRequest -Action 'AddBinding' -Hostname 'cippxyz.azurewebsites.net')

        $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
        Should -Invoke New-CIPPAzRestRequest -Times 0
    }
}
