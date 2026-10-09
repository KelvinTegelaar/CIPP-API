BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Test-CippAccess { param($Request, [switch]$TenantList) 'AllTenants' }
    function Get-Tenants { param([switch]$IncludeErrors) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $useSystemMailbox) }
    function Get-CIPPTextReplacement { param($Text, $TenantFilter, [switch]$EscapeForJson) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Resolve-CIPPTransportRuleTemplate.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Email-Exchange/Transport/Invoke-AddTransportRule.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))
}

Describe 'Invoke-AddTransportRule variables' {
    BeforeEach {
        Mock Get-CIPPTextReplacement { $Text -replace '%tenantname%', ($TenantFilter -split '\.')[0] }
        Mock New-ExoRequest { }
    }

    It 'deploys each tenant with its own resolved name and text' {
        $Request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddTransportRule' }
            Headers = @{}
            Body    = [pscustomobject]@{
                PowerShellCommand = '{"name":"%tenantname% external tag","PrependSubject":"[EXT %tenantname%] ","Enabled":true}'
                selectedTenants   = @([pscustomobject]@{ value = 'contoso.com' }, [pscustomobject]@{ value = 'fabrikam.com' })
            }
        }
        $null = Invoke-AddTransportRule -Request $Request -TriggerMetadata $null
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'New-TransportRule' -and $tenantid -eq 'contoso.com' -and $cmdParams.name -eq 'contoso external tag' -and $cmdParams.PrependSubject -eq '[EXT contoso] ' -and $cmdParams.Enabled -eq $true
        }
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'New-TransportRule' -and $tenantid -eq 'fabrikam.com' -and $cmdParams.name -eq 'fabrikam external tag'
        }
    }

    It 'matches an existing rule by its resolved name and updates it' {
        Mock New-ExoRequest { @([pscustomobject]@{ Identity = 'contoso external tag' }) } -ParameterFilter { $cmdlet -eq 'Get-TransportRule' }
        $Request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddTransportRule' }
            Headers = @{}
            Body    = [pscustomobject]@{
                PowerShellCommand = '{"name":"%tenantname% external tag"}'
                selectedTenants   = @([pscustomobject]@{ value = 'contoso.com' })
            }
        }
        $null = Invoke-AddTransportRule -Request $Request -TriggerMetadata $null
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Set-TransportRule' -and $cmdParams.Identity -eq 'contoso external tag' }
        Should -Invoke New-ExoRequest -Times 0 -Exactly -ParameterFilter { $cmdlet -eq 'New-TransportRule' }
    }

    It 'keeps Enabled out of Set-TransportRule and applies it with <Expected>' -ForEach @(
        @{ Enabled = 'true'; Expected = 'Enable-TransportRule' }
        @{ Enabled = 'false'; Expected = 'Disable-TransportRule' }
    ) {
        Mock New-ExoRequest { @([pscustomobject]@{ Identity = 'Tag' }) } -ParameterFilter { $cmdlet -eq 'Get-TransportRule' }
        $Request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddTransportRule' }
            Headers = @{}
            Body    = [pscustomobject]@{
                PowerShellCommand = "{`"name`":`"Tag`",`"PrependSubject`":`"[EXT] `",`"Enabled`":$Enabled}"
                selectedTenants   = @([pscustomobject]@{ value = 'contoso.com' })
            }
        }
        $null = Invoke-AddTransportRule -Request $Request -TriggerMetadata $null
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Set-TransportRule' -and $cmdParams.PSObject.Properties.Name -notcontains 'Enabled' -and $cmdParams.PrependSubject -eq '[EXT] '
        }
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq $Expected -and $cmdParams.Identity -eq 'Tag' }
    }
}
