# Pester tests for Invoke-RemovePolicy Graph URL construction (issue #6384).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-RemovePolicy.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    # The URLName -> Graph segment mapping lives in its own function and is exactly what the
    # assertions below check, so load the real one rather than stubbing it.
    $GraphPathPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPIntunePolicyGraphPath.ps1' -File |
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

    . $GraphPathPath
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

    It 'reports a raised multi-admin approval as pending, not failed' {
        Mock -CommandName New-GraphPostRequest -MockWith {
            $Exception = [System.Exception]::new('Approval request abc has been raised')
            $Exception.Data['IntuneApprovalCode'] = 'abc'
            throw $Exception
        }
        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'RemovePolicy' }
            Headers = @{}
            Query   = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                ID           = 'policy-3'
                URLName      = 'configurationPolicies'
            }
            Body    = [pscustomobject]@{}
        }

        $response = Invoke-RemovePolicy -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Accepted)
        $response.Body.Results.state | Should -Be 'warning'
        $response.Body.Results.copyField | Should -Be 'abc'
        $response.Body.Results.resultText | Should -Match 'not deleted yet. Approval request abc has been raised'
    }

    It 'reports a delete whose approval request is already open as pending' {
        Mock -CommandName New-GraphPostRequest -MockWith {
            throw '{"Message": "An active Approval Request already exists for this entity"}'
        }
        $request = [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'RemovePolicy' }
            Headers = @{}
            Query   = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                ID           = 'policy-4'
                URLName      = 'configurationPolicies'
            }
            Body    = [pscustomobject]@{}
        }

        $response = Invoke-RemovePolicy -Request $request -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Accepted)
        $response.Body.Results.state | Should -Be 'warning'
        $response.Body.Results.resultText | Should -Match 'already waiting'
    }
}
