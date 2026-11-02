# Pester tests for Update-CIPPInstanceHostname
# Config/InstanceProperties/CIPPURL is what background jobs build links from and what the Partner
# Center webhook is registered against, so warmup correcting it is only safe if it can tell "the
# custom domain changed" from "ARM did not answer". The tests that matter are the ones proving it
# writes nothing on an inconclusive lookup - a bad write here silently breaks every emailed link.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Update-CIPPInstanceHostname.ps1'

    # Minimal stubs so Mock has commands to replace during tests
    function Get-CIPPSiteHostname { param([switch]$AsRedirectUri, [switch]$IncludeStatus, [switch]$NoFallback) }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }

    . $FunctionPath
}

Describe 'Update-CIPPInstanceHostname' {
    BeforeEach {
        $script:DefaultHost = 'cippxyz.azurewebsites.net'
        $script:CustomHostA = 'cipp.contoso.com'
        $script:CustomHostB = 'portal.fabrikam.com'
        $script:StoredValue = $script:DefaultHost

        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'Config' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($null -eq $script:StoredValue) { return $null }
            [PSCustomObject]@{
                PartitionKey = 'InstanceProperties'
                RowKey       = 'CIPPURL'
                Value        = $script:StoredValue
            }
        }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Get-CIPPSiteHostname -MockWith {
            [PSCustomObject]@{
                Hostnames         = @($script:DefaultHost, $script:CustomHostA)
                DefaultHostname   = $script:DefaultHost
                CustomHostnames   = @($script:CustomHostA)
                PreferredHostname = $script:CustomHostA
                Discovered        = $true
                Error             = $null
            }
        }
    }

    Context 'When the stored URL has drifted from the bound custom domain' {
        It 'writes the custom domain to Config/InstanceProperties/CIPPURL' {
            $Result = Update-CIPPInstanceHostname

            $Result.Updated | Should -BeTrue
            $Result.ResolvedHostname | Should -Be $script:CustomHostA
            $Result.StoredHostname | Should -Be $script:DefaultHost
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
                $Entity.PartitionKey -eq 'InstanceProperties' -and
                $Entity.RowKey -eq 'CIPPURL' -and
                $Entity.Value -eq $script:CustomHostA
            }
        }

        It 'writes when nothing has ever been stored' {
            $script:StoredValue = $null

            $Result = Update-CIPPInstanceHostname

            $Result.Updated | Should -BeTrue
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
        }

        It 'demotes to the platform hostname once the custom domain is unbound' {
            # The reverse case is real: a customer removes the custom domain and the stored value
            # keeps pointing at a hostname that no longer resolves to this instance.
            $script:StoredValue = $script:CustomHostA
            Mock -CommandName Get-CIPPSiteHostname -MockWith {
                [PSCustomObject]@{
                    Hostnames         = @($script:DefaultHost)
                    DefaultHostname   = $script:DefaultHost
                    CustomHostnames   = @()
                    PreferredHostname = $script:DefaultHost
                    Discovered        = $true
                    Error             = $null
                }
            }

            $Result = Update-CIPPInstanceHostname

            $Result.Updated | Should -BeTrue
            $Result.ResolvedHostname | Should -Be $script:DefaultHost
        }

        It 'takes the first custom domain when several are bound' {
            Mock -CommandName Get-CIPPSiteHostname -MockWith {
                [PSCustomObject]@{
                    Hostnames         = @($script:DefaultHost, $script:CustomHostA, $script:CustomHostB)
                    DefaultHostname   = $script:DefaultHost
                    CustomHostnames   = @($script:CustomHostA, $script:CustomHostB)
                    PreferredHostname = $script:CustomHostA
                    Discovered        = $true
                    Error             = $null
                }
            }

            $Result = Update-CIPPInstanceHostname

            $Result.ResolvedHostname | Should -Be $script:CustomHostA
            $Result.CustomHostnames | Should -HaveCount 2
        }
    }

    Context 'When the stored URL is already correct' {
        It 'does not write' {
            $script:StoredValue = $script:CustomHostA

            $Result = Update-CIPPInstanceHostname

            $Result.Updated | Should -BeFalse
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'ignores casing differences rather than rewriting every warmup' {
            $script:StoredValue = $script:CustomHostA.ToUpper()

            $Result = Update-CIPPInstanceHostname

            $Result.Updated | Should -BeFalse
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }
    }

    Context 'When the bound hostnames cannot be enumerated' {
        # This is the important one. An unreachable ARM is not evidence that the custom domain is
        # gone, and writing the platform hostname here would break every link CIPP sends out until
        # someone re-saved the automated onboarding page by hand.
        It 'leaves the stored URL alone when discovery was not authoritative' {
            Mock -CommandName Get-CIPPSiteHostname -MockWith {
                [PSCustomObject]@{
                    Hostnames         = @()
                    DefaultHostname   = $script:DefaultHost
                    CustomHostnames   = @()
                    PreferredHostname = $script:DefaultHost
                    Discovered        = $false
                    Error             = 'AuthorizationFailed'
                }
            }

            $Result = Update-CIPPInstanceHostname

            $Result.Updated | Should -BeFalse
            $Result.Reason | Should -Match 'AuthorizationFailed'
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'does not even read the stored value when discovery failed' {
            Mock -CommandName Get-CIPPSiteHostname -MockWith {
                [PSCustomObject]@{ Discovered = $false; CustomHostnames = @(); PreferredHostname = $null; Error = 'boom' }
            }

            Update-CIPPInstanceHostname | Out-Null

            Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'writes nothing when ARM answered but there is no usable hostname' {
            # Local development: no App Service, so the list comes back empty by design.
            Mock -CommandName Get-CIPPSiteHostname -MockWith {
                [PSCustomObject]@{ Discovered = $true; CustomHostnames = @(); PreferredHostname = ''; Error = $null }
            }

            $Result = Update-CIPPInstanceHostname

            $Result.Updated | Should -BeFalse
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }
    }

    Context 'When storage misbehaves' {
        It 'never throws out of warmup' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { throw 'table storage unavailable' }

            { Update-CIPPInstanceHostname } | Should -Not -Throw

            $Result = Update-CIPPInstanceHostname
            $Result.Updated | Should -BeFalse
            $Result.Reason | Should -Match 'table storage unavailable'
        }

        It 'reports the failure rather than claiming an update when the write throws' {
            Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { throw 'write conflict' }

            $Result = Update-CIPPInstanceHostname

            $Result.Updated | Should -BeFalse
            $Result.Reason | Should -Match 'write conflict'
        }
    }
}
