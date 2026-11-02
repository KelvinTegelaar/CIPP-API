# Pester tests for the group handling in Invoke-ExecCAExclusion.
#
# This is Vacation Mode's Conditional Access half (Tenant > Conditional > Deploy Vacation). Rather
# than editing the policy at the start and end of the trip, it parks a per-policy "Vacation
# Exclusion - <policy>" security group in the policy's excludeGroups once, and then schedules two
# group-membership changes: Add-CIPPGroupMember at the start date and Remove-CIPPGroupMember at the
# end date. So a vacation that never ends is a group membership that never gets removed.
#
# The group is reused across vacations, which is why the lookup, the duplicate handling and the
# name-length cap all matter: a second group created by accident would be excluded from nothing.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Conditional/Invoke-ExecCAExclusion.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Invoke-ExecCAExclusion.ps1 at $FunctionPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    # -ComplexFilter is passed as a switch by the group lookup, so it has to be declared as one.
    function New-GraphGetRequest { param($uri, $tenantid, $asApp, [switch]$ComplexFilter, $Select) }
    function New-CIPPGroup { param($GroupObject, $TenantFilter, $APIName, $Headers) }
    function Set-CIPPCAExclusion { param($TenantFilter, $ExclusionType, $PolicyId, $Groups, $Users, $Headers) }
    function Set-CIPPAuditLogUserExclusion { param($Users, $Action, $Type, $TenantFilter, $Headers) }
    function Add-CIPPScheduledTask { param($Task, $hidden, $Headers, $DisallowDuplicateName) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Get-NormalizedError { param($message) $message }

    . $FunctionPath

    function New-ExclusionRequest {
        param([hashtable]$Body = @{})
        $RequestBody = [pscustomobject]@{
            tenantFilter = 'contoso.com'
            PolicyId     = 'policy-guid'
            vacation     = 'true'
            StartDate    = 1785000000
            EndDate      = 1786000000
            Users        = [pscustomobject]@{
                value       = 'user-guid'
                addedFields = [pscustomobject]@{ userPrincipalName = 'sseck@contoso.com' }
            }
        }
        foreach ($Key in $Body.Keys) {
            $RequestBody | Add-Member -NotePropertyName $Key -NotePropertyValue $Body[$Key] -Force
        }
        [pscustomobject]@{
            Body    = $RequestBody
            Headers = @{}
            Params  = @{ CIPPEndpoint = 'ExecCAExclusion' }
        }
    }
}

Describe 'Invoke-ExecCAExclusion - vacation group membership' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Set-CIPPCAExclusion -MockWith { }
        Mock -CommandName Set-CIPPAuditLogUserExclusion -MockWith { }
        Mock -CommandName New-CIPPGroup -MockWith { [pscustomobject]@{ GroupId = 'new-group-guid' } }

        # The endpoint mutates and re-submits one task object, so snapshot each task at call time
        # rather than inspecting the shared reference afterwards.
        $script:ScheduledTasks = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Add-CIPPScheduledTask -MockWith {
            $script:ScheduledTasks.Add(($Task | ConvertTo-Json -Depth 10 | ConvertFrom-Json))
        }

        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id          = 'policy-guid'
                displayName = 'Require MFA'
                conditions  = [pscustomobject]@{
                    users     = [pscustomobject]@{ excludeGroups = @() }
                    locations = [pscustomobject]@{ includeLocations = @('All') }
                }
            }
        } -ParameterFilter { $uri -like '*conditionalAccess/policies*' }

        Mock -CommandName New-GraphGetRequest -MockWith {
            @([pscustomobject]@{ id = 'existing-group-guid'; displayName = 'Vacation Exclusion - Require MFA' })
        } -ParameterFilter { $uri -like '*groups?*' }
    }

    Context 'Scheduling the membership either side of the trip' {
        It 'adds the user to the exclusion group at the start date' {
            $null = Invoke-ExecCAExclusion -Request (New-ExclusionRequest)

            $AddTask = $script:ScheduledTasks | Where-Object { $_.Command.value -eq 'Add-CIPPGroupMember' }
            $AddTask | Should -Not -BeNullOrEmpty
            $AddTask.Parameters.GroupId | Should -Be 'existing-group-guid'
            $AddTask.Parameters.Member | Should -Be 'sseck@contoso.com'
            $AddTask.Parameters.GroupType | Should -Be 'Security'
            $AddTask.ScheduledTime | Should -Be 1785000000
            $AddTask.TenantFilter | Should -Be 'contoso.com'
        }

        It 'removes the user from the exclusion group at the end date' {
            $null = Invoke-ExecCAExclusion -Request (New-ExclusionRequest)

            $RemoveTask = $script:ScheduledTasks | Where-Object { $_.Command.value -eq 'Remove-CIPPGroupMember' }
            $RemoveTask | Should -Not -BeNullOrEmpty
            $RemoveTask.Parameters.GroupId | Should -Be 'existing-group-guid'
            $RemoveTask.Parameters.Member | Should -Be 'sseck@contoso.com'
            $RemoveTask.ScheduledTime | Should -Be 1786000000
        }

        It 'schedules exactly one add and one remove' {
            # A duplicate remove would be harmless, a missing one leaves the exclusion in place.
            $null = Invoke-ExecCAExclusion -Request (New-ExclusionRequest)

            @($script:ScheduledTasks | Where-Object { $_.Command.value -eq 'Add-CIPPGroupMember' }).Count | Should -Be 1
            @($script:ScheduledTasks | Where-Object { $_.Command.value -eq 'Remove-CIPPGroupMember' }).Count | Should -Be 1
        }

        It 'names both tasks after the policy so they are identifiable in the scheduler' {
            $null = Invoke-ExecCAExclusion -Request (New-ExclusionRequest)

            ($script:ScheduledTasks | Where-Object { $_.Command.value -eq 'Add-CIPPGroupMember' }).Name |
                Should -Be 'Add CA Exclusion Vacation Mode: Require MFA'
            ($script:ScheduledTasks | Where-Object { $_.Command.value -eq 'Remove-CIPPGroupMember' }).Name |
                Should -Be 'Remove CA Exclusion Vacation Mode: Require MFA'
        }

        It 'schedules nothing when the request is not a vacation' {
            $null = Invoke-ExecCAExclusion -Request (New-ExclusionRequest -Body @{ vacation = 'false'; ExclusionType = 'Add' })

            @($script:ScheduledTasks | Where-Object { $_.Command.value -like '*GroupMember' }).Count | Should -Be 0
        }
    }

    Context 'Finding or creating the exclusion group' {
        It 'reuses the existing vacation group for the policy' {
            $null = Invoke-ExecCAExclusion -Request (New-ExclusionRequest)

            Should -Invoke New-CIPPGroup -Times 0 -Exactly
            ($script:ScheduledTasks | Select-Object -First 1).Parameters.GroupId | Should -Be 'existing-group-guid'
        }

        It 'creates a security group when the policy has no vacation group yet' {
            Mock -CommandName New-GraphGetRequest -MockWith { @() } -ParameterFilter { $uri -like '*groups?*' }

            $null = Invoke-ExecCAExclusion -Request (New-ExclusionRequest)

            Should -Invoke New-CIPPGroup -Times 1 -Exactly -ParameterFilter {
                $GroupObject.groupType -eq 'generic' -and
                $GroupObject.securityEnabled -eq $true -and
                $GroupObject.displayName -eq 'Vacation Exclusion - Require MFA'
            }
            ($script:ScheduledTasks | Select-Object -First 1).Parameters.GroupId | Should -Be 'new-group-guid'
        }

        It 'picks one group and warns when the tenant has duplicates' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                @(
                    [pscustomobject]@{ id = 'dupe-1'; displayName = 'Vacation Exclusion - Require MFA' }
                    [pscustomobject]@{ id = 'dupe-2'; displayName = 'Vacation Exclusion - Require MFA' }
                )
            } -ParameterFilter { $uri -like '*groups?*' }

            $Response = Invoke-ExecCAExclusion -Request (New-ExclusionRequest)

            Should -Invoke New-CIPPGroup -Times 0 -Exactly
            ($script:ScheduledTasks | Select-Object -First 1).Parameters.GroupId | Should -Be 'dupe-1'
            "$($Response.Body.Results)" | Should -BeLike '*Multiple groups found*'
        }

        It 'keeps the generated group name inside the 120 character limit' {
            $LongName = 'A' * 200
            Mock -CommandName New-GraphGetRequest -MockWith {
                [pscustomobject]@{
                    id          = 'policy-guid'
                    displayName = $LongName
                    conditions  = [pscustomobject]@{ users = [pscustomobject]@{ excludeGroups = @() } }
                }
            } -ParameterFilter { $uri -like '*conditionalAccess/policies*' }
            Mock -CommandName New-GraphGetRequest -MockWith { @() } -ParameterFilter { $uri -like '*groups?*' }

            $null = Invoke-ExecCAExclusion -Request (New-ExclusionRequest)

            Should -Invoke New-CIPPGroup -Times 1 -Exactly -ParameterFilter {
                $GroupObject.displayName.Length -le 120
            }
        }

        It 'adds the group to the policy exclusions when it is not already there' {
            $null = Invoke-ExecCAExclusion -Request (New-ExclusionRequest)

            Should -Invoke Set-CIPPCAExclusion -Times 1 -Exactly -ParameterFilter {
                $ExclusionType -eq 'Add' -and $PolicyId -eq 'policy-guid' -and $Groups.value -contains 'existing-group-guid'
            }
        }

        It 'leaves the policy alone when the group is already excluded' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                [pscustomobject]@{
                    id          = 'policy-guid'
                    displayName = 'Require MFA'
                    conditions  = [pscustomobject]@{ users = [pscustomobject]@{ excludeGroups = @('existing-group-guid') } }
                }
            } -ParameterFilter { $uri -like '*conditionalAccess/policies*' }

            $null = Invoke-ExecCAExclusion -Request (New-ExclusionRequest)

            Should -Invoke Set-CIPPCAExclusion -Times 0 -Exactly
        }
    }

    Context 'Resolving who goes in the group' {
        It 'uses the selected users userPrincipalName' {
            $null = Invoke-ExecCAExclusion -Request (New-ExclusionRequest)

            ($script:ScheduledTasks | Select-Object -First 1).Parameters.Member | Should -Be 'sseck@contoso.com'
        }

        It 'falls back to the raw value when the option has no userPrincipalName' {
            $Request = New-ExclusionRequest -Body @{
                Users = [pscustomobject]@{ value = 'fallback@contoso.com'; addedFields = [pscustomobject]@{} }
            }

            $null = Invoke-ExecCAExclusion -Request $Request

            ($script:ScheduledTasks | Select-Object -First 1).Parameters.Member | Should -Be 'fallback@contoso.com'
        }
    }

    Context 'Failures' {
        It 'reports a missing policy instead of creating an orphan group' {
            Mock -CommandName New-GraphGetRequest -MockWith { $null } -ParameterFilter { $uri -like '*conditionalAccess/policies*' }

            $Response = Invoke-ExecCAExclusion -Request (New-ExclusionRequest)

            Should -Invoke New-CIPPGroup -Times 0 -Exactly
            $script:ScheduledTasks.Count | Should -Be 0
            "$($Response.Body.Results)" | Should -BeLike '*not found*'
        }
    }
}
