# Pester tests for Invoke-RemovePolicy Graph URL construction (issue #6384).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-RemovePolicy.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphPostRequest { param($uri, $type, $tenant) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $LogData) }
    function Get-CippException { param($Exception) }

    . $FunctionPath
}

Describe 'Invoke-RemovePolicy Graph URL' {
    BeforeEach {
        $script:deleteUri = $null
        Mock -CommandName New-GraphPostRequest -MockWith {
            $script:deleteUri = $uri
        }
        Mock -CommandName Write-LogMessage -MockWith {}
    }

    It 'maps singular app protection URLNames to the plural deviceAppManagement segment' {
        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'RemovePolicy' }
            Headers = @{}
            Query   = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                ID           = 'T_policy-1'
                URLName      = 'androidManagedAppProtection'
            }
            Body    = [pscustomobject]@{}
        }

        $response = Invoke-RemovePolicy -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:deleteUri | Should -Be "https://graph.microsoft.com/beta/deviceAppManagement/androidManagedAppProtections('T_policy-1')"
    }

    It 'keeps mobileAppConfigurations under deviceAppManagement' {
        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'RemovePolicy' }
            Headers = @{}
            Query   = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                ID           = 'config-1'
                URLName      = 'mobileAppConfigurations'
            }
            Body    = [pscustomobject]@{}
        }

        $null = Invoke-RemovePolicy -Request $request -TriggerMetadata $null

        $script:deleteUri | Should -Be "https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations('config-1')"
    }

    It 'defaults other URLNames to deviceManagement' {
        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'RemovePolicy' }
            Headers = @{}
            Query   = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                ID           = 'policy-2'
                URLName      = 'deviceConfigurations'
            }
            Body    = [pscustomobject]@{}
        }

        $null = Invoke-RemovePolicy -Request $request -TriggerMetadata $null

        $script:deleteUri | Should -Be "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations('policy-2')"
    }
}
