# Pester tests for Invoke-CIPPCustomDomainCertificate
# Managed certificate issuance outlives a request, so the function has to hand off to a hidden
# retry task - and stop handing off once the certificate is bound, the domain is gone, or the
# attempt budget is spent. An unbounded reschedule is the bug these tests guard.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Invoke-CIPPCustomDomainCertificate.ps1'

    function Get-CIPPAppServiceSite { param($ApiVersion) }
    function New-CIPPAzRestRequest { param($Uri, $Method, $Body) }
    function Add-CIPPScheduledTask { param($Task, $Hidden) }
    function Write-LogMessage { param($API, $message, $sev, $tenant, $headers, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $FunctionPath
}

Describe 'Invoke-CIPPCustomDomainCertificate' {
    BeforeEach {
        $script:Hostname = 'portal.contoso.com'
        $script:SiteState = [pscustomobject]@{
            SiteName     = 'cippxyz'
            ArmBase      = 'https://management.azure.com/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Web/sites/cippxyz'
            CertBase     = 'https://management.azure.com/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Web/certificates'
            ApiVersion   = '2024-11-01'
            Site         = [pscustomobject]@{
                location   = 'westeurope'
                properties = [pscustomobject]@{
                    serverFarmId      = '/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Web/serverfarms/plan'
                    hostNames         = @('cippxyz.azurewebsites.net', $script:Hostname)
                    hostNameSslStates = @([pscustomobject]@{ name = $script:Hostname; sslState = 'Disabled' })
                }
            }
            Certificates = @()
        }
        Mock -CommandName Get-CIPPAppServiceSite -MockWith { $script:SiteState }
        # Nothing issued yet: the PUT returns a cert without a thumbprint and the poll list stays empty
        Mock -CommandName New-CIPPAzRestRequest -MockWith {
            if ($Method -eq 'PUT') { [pscustomobject]@{ properties = [pscustomobject]@{ thumbprint = $null } } }
            else { [pscustomobject]@{ value = @() } }
        }
        Mock -CommandName Add-CIPPScheduledTask -MockWith { 'Task created' }
        Mock -CommandName Write-LogMessage
        Mock -CommandName Start-Sleep
    }

    It 'does nothing when the hostname is not bound (the domain was removed)' {
        $script:SiteState.Site.properties.hostNames = @('cippxyz.azurewebsites.net')

        $Result = Invoke-CIPPCustomDomainCertificate -Hostname $script:Hostname

        $Result | Should -Match 'No hostname binding'
        Should -Invoke New-CIPPAzRestRequest -Times 0
        Should -Invoke Add-CIPPScheduledTask -Times 0
    }

    It 'does nothing when the binding is already secured' {
        $script:SiteState.Site.properties.hostNameSslStates[0].sslState = 'SniEnabled'

        Invoke-CIPPCustomDomainCertificate -Hostname $script:Hostname | Should -Match 'already secured'
        Should -Invoke New-CIPPAzRestRequest -Times 0
        Should -Invoke Add-CIPPScheduledTask -Times 0
    }

    It 'binds an already-issued certificate for the hostname without creating another' {
        $script:SiteState.Certificates = @([pscustomobject]@{
                name       = 'whatever-the-portal-called-it'
                properties = [pscustomobject]@{ canonicalName = $script:Hostname; thumbprint = 'ABC123' }
            })

        Invoke-CIPPCustomDomainCertificate -Hostname $script:Hostname | Should -Match 'SNI SSL enabled'

        Should -Invoke New-CIPPAzRestRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Uri -like '*/hostNameBindings/portal.contoso.com?*' -and $Body.properties.thumbprint -eq 'ABC123' -and $Body.properties.sslState -eq 'SniEnabled'
        }
        Should -Invoke Add-CIPPScheduledTask -Times 0
    }

    It 'creates the certificate in the plan resource group and schedules a hidden retry when it is not issued yet' {
        $Result = Invoke-CIPPCustomDomainCertificate -Hostname $script:Hostname

        $Result | Should -Match 'attempt 1 of 4'
        Should -Invoke New-CIPPAzRestRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Uri -like "*/certificates/portal.contoso.com-cippxyz?*" -and $Body.properties.canonicalName -eq 'portal.contoso.com'
        }
        Should -Invoke New-CIPPAzRestRequest -Times 0 -ParameterFilter { $Uri -like '*/hostNameBindings/*' }
        Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
            $Hidden -eq $true -and $Task.Parameters.Attempt -eq 2 -and $Task.Parameters.Hostname -eq 'portal.contoso.com' -and $Task.Reference -eq 'CustomDomainCert-portal.contoso.com'
        }
    }

    It 'treats a 409 on create as an issuance already in flight rather than a failure' {
        Mock -CommandName New-CIPPAzRestRequest -MockWith {
            if ($Method -eq 'PUT') { throw 'Azure REST API call failed: Found a duplicate certificate (Status: Conflict)' }
            [pscustomobject]@{ value = @() }
        }

        $Result = Invoke-CIPPCustomDomainCertificate -Hostname $script:Hostname

        $Result | Should -Match 'still being issued'
        Should -Invoke Add-CIPPScheduledTask -Times 1
    }

    It 'gives up on the last attempt instead of rescheduling again' {
        $Result = Invoke-CIPPCustomDomainCertificate -Hostname $script:Hostname -Attempt 4

        $Result | Should -Match 'Giving up after 4 attempts'
        Should -Invoke Add-CIPPScheduledTask -Times 0
    }

    It 'reschedules after a failed attempt so a transient ARM error does not strand the domain' {
        Mock -CommandName New-CIPPAzRestRequest -MockWith { throw 'Azure REST API call failed: boom (Status: 500)' }

        $Result = Invoke-CIPPCustomDomainCertificate -Hostname $script:Hostname -Attempt 2

        $Result | Should -Match 'failed: .*boom.*attempt 2 of 4'
        Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter { $Task.Parameters.Attempt -eq 3 }
    }
}
