# The CPV consent gate: a failed cpvtenants row must re-consent, and the cases
# that must NOT re-consent (legacy rows, direct tenants, success) still don't.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-UpdatePermissionsQueue.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Push-UpdatePermissionsQueue.ps1 under Modules/' }

    # Stubs so Mock has commands to replace.
    function Get-CIPPTable { param($TableName) @{ Context = 'stub' } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors, [switch]$IncludeAll, [switch]$TriggerRefresh) }
    function Set-CIPPCPVConsent { param($TenantFilter, $APIName, $Headers, [bool]$ResetSP) }
    function Add-CIPPApplicationPermission { param($RequiredResourceAccess, $ApplicationId, $TenantFilter) }
    function Add-CIPPDelegatedPermission { param($RequiredResourceAccess, $ApplicationId, $TenantFilter) }
    function Set-CIPPSAMAdminRoles { param($TenantFilter) }
    function Write-LogMessage { param($message, $tenant, $tenantId, $API, $Sev, $Headers, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $FunctionPath

    $script:CurrentAppId = '11111111-1111-1111-1111-111111111111'
    $env:ApplicationID = $script:CurrentAppId

    $script:Item = [pscustomobject]@{
        customerId        = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        defaultDomainName = 'dev.example.com'
        displayName       = 'Example Dev'
    }

    $script:ConsentError = "Could not get token: invalid_grant:AADSTS65001: The user or administrator has not consented to use the application with ID '$($script:CurrentAppId)' named 'CIPP-SAM'."
}

Describe 'Push-UpdatePermissionsQueue CPV consent gate' {
    BeforeEach {
        $script:ConsentCalls = [System.Collections.Generic.List[object]]::new()
        $script:WrittenRow = $null

        Mock -CommandName Set-CIPPCPVConsent -MockWith {
            $script:ConsentCalls.Add([pscustomobject]@{ TenantFilter = $TenantFilter; ResetSP = [bool]$ResetSP })
        }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:WrittenRow = $Entity }
        Mock -CommandName Add-CIPPApplicationPermission -MockWith { @('Succeeded') }
        Mock -CommandName Add-CIPPDelegatedPermission -MockWith { @('Succeeded') }
        Mock -CommandName Set-CIPPSAMAdminRoles -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName Get-Tenants -MockWith {
            [pscustomobject]@{
                customerId               = $script:Item.customerId
                defaultDomainName        = $script:Item.defaultDomainName
                displayName              = $script:Item.displayName
                delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges'
            }
        }
    }

    Context 'when no consent record exists' {
        It 'consents, without resetting the service principal' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }

            Push-UpdatePermissionsQueue -Item $script:Item

            $script:ConsentCalls.Count | Should -Be 1
            $script:ConsentCalls[0].ResetSP | Should -BeFalse
        }
    }

    Context 'when the last run succeeded' {
        It 'does not re-consent' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @([pscustomobject]@{ Tenant = $script:Item.customerId; applicationId = $script:CurrentAppId; LastStatus = 'Success' })
            }

            Push-UpdatePermissionsQueue -Item $script:Item

            $script:ConsentCalls.Count | Should -Be 0
        }
    }

    Context 'when the last run failed because consent is missing' {
        It 're-consents instead of skipping the step forever' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @([pscustomobject]@{
                        Tenant        = $script:Item.customerId
                        applicationId = $script:CurrentAppId
                        LastStatus    = 'Failed'
                        LastError     = $script:ConsentError
                    })
            }

            Push-UpdatePermissionsQueue -Item $script:Item

            $script:ConsentCalls.Count | Should -Be 1
        }

        It 'resets the service principal, because a plain re-consent short-circuits on an existing entry' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @([pscustomobject]@{
                        Tenant        = $script:Item.customerId
                        applicationId = $script:CurrentAppId
                        LastStatus    = 'Failed'
                        LastError     = $script:ConsentError
                    })
            }

            Push-UpdatePermissionsQueue -Item $script:Item

            $script:ConsentCalls[0].ResetSP | Should -BeTrue
        }
    }

    Context 'when the last run failed for an unrelated reason' {
        It 're-consents but does not reset the service principal on the first attempt' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @([pscustomobject]@{
                        Tenant        = $script:Item.customerId
                        applicationId = $script:CurrentAppId
                        LastStatus    = 'Failed'
                        LastError     = 'Set-CIPPSAMAdminRoles: the remote server returned an error (503)'
                    })
            }

            Push-UpdatePermissionsQueue -Item $script:Item

            $script:ConsentCalls.Count | Should -Be 1
            $script:ConsentCalls[0].ResetSP | Should -BeFalse
        }

        It 'escalates to a reset once a plain re-consent has already been tried' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @([pscustomobject]@{
                        Tenant          = $script:Item.customerId
                        applicationId   = $script:CurrentAppId
                        LastStatus      = 'Failed'
                        LastError       = 'something nobody wrote a pattern for'
                        ConsentAttempts = '1'
                    })
            }

            Push-UpdatePermissionsQueue -Item $script:Item

            $script:ConsentCalls[0].ResetSP | Should -BeTrue
        }
    }

    Context 'when consent exists but its scopes are insufficient' {
        BeforeEach {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @([pscustomobject]@{
                        Tenant        = $script:Item.customerId
                        applicationId = $script:CurrentAppId
                        LastStatus    = 'Failed'
                        LastError     = 'Failed to grant 9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30 to 00000003-0000-0000-c000-000000000000: Insufficient privileges to complete the operation.'
                    })
            }
        }

        It 'resets the service principal rather than re-applying the same consent' {
            Push-UpdatePermissionsQueue -Item $script:Item

            $script:ConsentCalls.Count | Should -Be 1
            $script:ConsentCalls[0].ResetSP | Should -BeTrue
        }
    }

    Context 'reset rate limiting' {
        It 'does not reset again within a week of the last one' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @([pscustomobject]@{
                        Tenant          = $script:Item.customerId
                        applicationId   = $script:CurrentAppId
                        LastStatus      = 'Failed'
                        LastError       = $script:ConsentError
                        ConsentAttempts = '3'
                        LastResetUtc    = ([datetime]::UtcNow.AddDays(-2).ToString('o'))
                    })
            }

            Push-UpdatePermissionsQueue -Item $script:Item

            $script:ConsentCalls.Count | Should -Be 1
            $script:ConsentCalls[0].ResetSP | Should -BeFalse
        }

        It 'resets again once the week has elapsed' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @([pscustomobject]@{
                        Tenant          = $script:Item.customerId
                        applicationId   = $script:CurrentAppId
                        LastStatus      = 'Failed'
                        LastError       = $script:ConsentError
                        ConsentAttempts = '3'
                        LastResetUtc    = ([datetime]::UtcNow.AddDays(-8).ToString('o'))
                    })
            }

            Push-UpdatePermissionsQueue -Item $script:Item

            $script:ConsentCalls[0].ResetSP | Should -BeTrue
        }
    }

    Context 'the attempt counter' {
        It 'increments while the tenant keeps failing' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @([pscustomobject]@{
                        Tenant          = $script:Item.customerId
                        applicationId   = $script:CurrentAppId
                        LastStatus      = 'Failed'
                        LastError       = 'unrecognised'
                        ConsentAttempts = '2'
                    })
            }
            Mock -CommandName Add-CIPPApplicationPermission -MockWith { @('Failed to grant something') }

            Push-UpdatePermissionsQueue -Item $script:Item

            $script:WrittenRow.ConsentAttempts | Should -Be '3'
        }

        It 'clears on success, so a recovered tenant starts from zero' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @([pscustomobject]@{
                        Tenant          = $script:Item.customerId
                        applicationId   = $script:CurrentAppId
                        LastStatus      = 'Failed'
                        LastError       = $script:ConsentError
                        ConsentAttempts = '4'
                    })
            }

            Push-UpdatePermissionsQueue -Item $script:Item

            $script:WrittenRow.ConsentAttempts | Should -Be '0'
        }

        It 'does not count an attempt for a direct tenant, which never consents' {
            Mock -CommandName Get-Tenants -MockWith {
                [pscustomobject]@{
                    customerId               = $script:Item.customerId
                    defaultDomainName        = $script:Item.defaultDomainName
                    delegatedPrivilegeStatus = 'directTenant'
                }
            }
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @([pscustomobject]@{ Tenant = $script:Item.customerId; applicationId = $script:CurrentAppId; LastStatus = 'Failed'; LastError = $script:ConsentError })
            }
            Mock -CommandName Add-CIPPApplicationPermission -MockWith { @('Failed to grant something') }

            Push-UpdatePermissionsQueue -Item $script:Item

            $script:ConsentCalls.Count | Should -Be 0
            $script:WrittenRow.ConsentAttempts | Should -BeNullOrEmpty
        }
    }

    Context 'when the record predates the LastStatus field' {
        It 'does not re-consent, so deploying this does not re-consent the whole estate' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @([pscustomobject]@{ Tenant = $script:Item.customerId; applicationId = $script:CurrentAppId })
            }

            Push-UpdatePermissionsQueue -Item $script:Item

            $script:ConsentCalls.Count | Should -Be 0
        }
    }

    Context 'when the consent record names a different application' {
        It 'consents for the new application' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @([pscustomobject]@{ Tenant = $script:Item.customerId; applicationId = '99999999-9999-9999-9999-999999999999'; LastStatus = 'Success' })
            }

            Push-UpdatePermissionsQueue -Item $script:Item

            $script:ConsentCalls.Count | Should -Be 1
        }
    }

    Context 'for a direct tenant' {
        It 'never consents, CPV does not apply' {
            Mock -CommandName Get-Tenants -MockWith {
                [pscustomobject]@{
                    customerId               = $script:Item.customerId
                    defaultDomainName        = $script:Item.defaultDomainName
                    delegatedPrivilegeStatus = 'directTenant'
                }
            }
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @([pscustomobject]@{ Tenant = $script:Item.customerId; applicationId = $script:CurrentAppId; LastStatus = 'Failed'; LastError = $script:ConsentError })
            }

            Push-UpdatePermissionsQueue -Item $script:Item

            $script:ConsentCalls.Count | Should -Be 0
        }
    }

    Context 'the record it leaves behind' {
        It 'records the failure status that the gate now reads' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @([pscustomobject]@{ Tenant = $script:Item.customerId; applicationId = $script:CurrentAppId; LastStatus = 'Success' })
            }
            Mock -CommandName Add-CIPPApplicationPermission -MockWith { throw $script:ConsentError }

            Push-UpdatePermissionsQueue -Item $script:Item

            $script:WrittenRow.LastStatus | Should -Be 'Failed'
            $script:WrittenRow.LastError | Should -Match 'AADSTS65001'
        }
    }
}
