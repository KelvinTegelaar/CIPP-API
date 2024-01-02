Function Push-ExecOnboardTenantQueue {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($QueueItem, $TriggerMetadata)
    try {
        $DateFormat = '%Y-%m-%d %H:%M:%S'
        $Id = $QueueItem.id
        #Write-Host ($QueueItem.Roles | ConvertTo-Json)
        $Logs = [System.Collections.Generic.List[object]]::new()
        $OnboardTable = Get-CIPPTable -TableName 'TenantOnboarding'
        $TenantOnboarding = Get-CIPPAzDataTableEntity @OnboardTable -Filter "RowKey eq '$Id'"

        $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = "Starting onboarding for relationship $Id" })
        $OnboardingSteps = $TenantOnboarding.OnboardingSteps | ConvertFrom-Json
        $OnboardingSteps.Step1.Status = 'running'
        $OnboardingSteps.Step1.Message = 'Checking GDAP invite status'
        $TenantOnboarding.OnboardingSteps = [string](ConvertTo-Json -InputObject $OnboardingSteps -Compress)
        $TenantOnboarding.Status = 'running'
        $TenantOnboarding.Logs = [string](ConvertTo-Json -InputObject @($Logs) -Compress -AsArray)
        Add-CIPPAzDataTableEntity @OnboardTable -Entity $TenantOnboarding -Force -ErrorAction Stop

        try {
            $Relationship = $TenantOnboarding.Relationship | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $Relationship = ''
        }

        $ExpectedRoles = @(
            @{ Name = 'Application Administrator'; Id = '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3' },
            @{ Name = 'User Administrator'; Id = 'fe930be7-5e62-47db-91af-98c3a49a38b1' },
            @{ Name = 'Intune Administrator'; Id = '3a2c62db-5318-420d-8d74-23affee5d9d5' },
            @{ Name = 'Exchange Administrator'; Id = '29232cdf-9323-42fd-ade2-1d097af3e4de' },
            @{ Name = 'Security Administrator'; Id = '194ae4cb-b126-40b2-bd5b-6091b380977d' },
            @{ Name = 'Cloud App Security Administrator'; Id = '892c5842-a9a6-463a-8041-72aa08ca3cf6' },
            @{ Name = 'Cloud Device Administrator'; Id = '7698a772-787b-4ac8-901f-60d6b08affd2' },
            @{ Name = 'Teams Administrator'; Id = '69091246-20e8-4a56-aa4d-066075b2a7a8' },
            @{ Name = 'Sharepoint Administrator'; Id = 'f28a1f50-f6e7-4571-818b-6a12f2af6b6c' },
            @{ Name = 'Authentication Policy Administrator'; Id = '0526716b-113d-4c15-b2c8-68e3c22b9f80' },
            @{ Name = 'Privileged Role Administrator'; Id = 'e8611ab8-c189-46e8-94e1-60213ab1f814' },
            @{ Name = 'Privileged Authentication Administrator'; Id = '7be44c8a-adaf-4e2a-84d6-ab2649e08a13' }
        )

        if ($OnboardingSteps.Step1.Status -ne 'succeeded') {
            $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'Checking relationship status' })
            $x = 0
            do {
                $Relationship = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$Id"
                $x++
                Start-Sleep -Seconds 30
            } while ($Relationship.status -ne 'active' -and $x -lt 4)

            if ($Relationship.status -eq 'active') {
                $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'GDAP Invite Accepted' })
                $OnboardingSteps.Step1.Status = 'succeeded'
                $OnboardingSteps.Step1.Message = "GDAP Invite accepted for $($Relationship.customer.displayName)"
                $TenantOnboarding.CustomerId = $Relationship.customer.tenantId
            } else {
                $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'GDAP Invite Failed' })
                $OnboardingSteps.Step1.Status = 'failed'
                $OnboardingSteps.Step1.Message = 'GDAP Invite timeout, retry onboarding after accepting the invite with a GA account in the customer tenant.'
                $TenantOnboarding.Status = 'failed'
            }
            $TenantOnboarding.OnboardingSteps = [string](ConvertTo-Json -InputObject $OnboardingSteps -Compress)
            $TenantOnboarding.Relationship = [string](ConvertTo-Json -InputObject $Relationship -Compress -Depth 10)
            $TenantOnboarding.Logs = [string](ConvertTo-Json -InputObject @($Logs) -Compress)
            Add-CIPPAzDataTableEntity @OnboardTable -Entity $TenantOnboarding -Force -ErrorAction Stop
        }

        if ($OnboardingSteps.Step1.Status -eq 'succeeded') {
            $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'Starting role check' })
            $OnboardingSteps.Step2.Status = 'running'
            $OnboardingSteps.Step2.Message = 'Checking role mapping'
            $TenantOnboarding.OnboardingSteps = [string](ConvertTo-Json -InputObject $OnboardingSteps -Compress)
            $TenantOnboarding.Logs = [string](ConvertTo-Json -InputObject @($Logs) -Compress)
            Add-CIPPAzDataTableEntity @OnboardTable -Entity $TenantOnboarding -Force -ErrorAction Stop

            $MissingRoles = [System.Collections.Generic.List[string]]::new()
            foreach ($Role in $ExpectedRoles) {
                $RoleFound = $false
                foreach ($AvailableRole in $Relationship.accessDetails.unifiedRoles) {
                    if ($AvailableRole.roleDefinitionId -eq $Role.Id) {
                        $RoleFound = $true
                        break
                    }
                }
                if (!$RoleFound) {
                    $MissingRoles.Add($Role.Name)
                }
            }
            if (($MissingRoles | Measure-Object).Count -gt 0) {
                $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'Missing roles for relationship' })
                $TenantOnboarding.Status = 'failed'
                $OnboardingSteps.Step2.Status = 'failed'
                $OnboardingSteps.Step2.Message = "Your GDAP relationship is missing the following roles: $($MissingRoles -join ', ')"
            } else {
                $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'Required roles found' })
                $OnboardingSteps.Step2.Status = 'succeeded'
                $OnboardingSteps.Step2.Message = 'Your GDAP relationship has the required roles'
            }
            $TenantOnboarding.OnboardingSteps = [string](ConvertTo-Json -InputObject $OnboardingSteps -Compress)
            $TenantOnboarding.Logs = [string](ConvertTo-Json -InputObject @($Logs) -Compress)
            Add-CIPPAzDataTableEntity @OnboardTable -Entity $TenantOnboarding -Force -ErrorAction Stop
        }

        if ($OnboardingSteps.Step2.Status -eq 'succeeded') {
            $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'Checking group mapping' })
            $AccessAssignments = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$Id/accessAssignments"
            if ($AccessAssignments.id -and $QueueItem.AutoMapRoles -ne $true) {
                $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'Groups mapped' })
                $OnboardingSteps.Step3.Status = 'succeeded'
                $OnboardingSteps.Step3.Message = 'Your GDAP relationship already has mapped security groups'
            } else {
                $GroupSuccess = $false
                $OnboardingSteps.Step3.Status = 'running'
                $OnboardingSteps.Step3.Message = 'Mapping security groups'
                $TenantOnboarding.OnboardingSteps = [string](ConvertTo-Json -InputObject $OnboardingSteps -Compress)
                $TenantOnboarding.Logs = [string](ConvertTo-Json -InputObject @($Logs) -Compress)
                Add-CIPPAzDataTableEntity @OnboardTable -Entity $TenantOnboarding -Force -ErrorAction Stop

                $InviteTable = Get-CIPPTable -TableName 'GDAPInvites'
                $Invite = Get-CIPPAzDataTableEntity @InviteTable -Filter "RowKey eq '$Id'"

                if ($AccessAssignments.id -and !$Invite) {
                    $MissingRoles = [System.Collections.Generic.List[object]]::new()
                    $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'Relationship has existing access assignments, checking for missing mappings' })
                    #Write-Host ($AccessAssignments | ConvertTo-Json -Depth 5)
                    if ($QueueItem.Roles -and $QueueItem.AutoMapRoles -eq $true) {
                        foreach ($Role in $QueueItem.Roles) {
                            if ($AccessAssignments.accessContainer.accessContainerid -notcontains $Role.GroupId -and $Relationship.accessDetails.unifiedRoles.roleDefinitionId -contains $Role.roleDefinitionId) {
                                $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = "Adding missing group to relationship: $($Role.GroupName)" })
                                $MissingRoles.Add([PSCustomObject]$Role)
                            }
                        }

                        if (($MissingRoles | Measure-Object).Count -gt 0) {
                            $Invite = [PSCustomObject]@{
                                'PartitionKey' = 'invite'
                                'RowKey'       = $Id
                                'InviteUrl'    = 'https://admin.microsoft.com/AdminPortal/Home#/partners/invitation/granularAdminRelationships/{0}' -f $Id
                                'RoleMappings' = [string](@($MissingRoles) | ConvertTo-Json -Depth 10 -Compress)
                            }
                            Add-CIPPAzDataTableEntity @InviteTable -Entity $Invite
                        } else {
                            $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'All roles have been mapped to the M365 GDAP security groups' })
                            $OnboardingSteps.Step3.Status = 'succeeded'
                            $OnboardingSteps.Step3.Message = 'Groups mapped successfully'
                            $GroupSuccess = $true
                        }
                    }
                }

                if (!$AccessAssignments.id -and !$Invite -and $QueueItem.Roles) {
                    $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'No access assignments found, using defined role mapping.' })
                    $MatchingRoles = [System.Collections.Generic.List[object]]::new()
                    foreach ($Role in $QueueItem.Roles) {
                        if ($Relationship.accessDetails.unifiedRoles.roleDefinitionId -contains $Role.roleDefinitionId) {
                            $MatchingRoles.Add([PSCustomObject]$Role)
                        }
                    }

                    if (($MatchingRoles | Measure-Object).Count -gt 0 -and $QueueItem.AutoMapRoles -eq $true) {
                        $Invite = [PSCustomObject]@{
                            'PartitionKey' = 'invite'
                            'RowKey'       = $Id
                            'InviteUrl'    = 'https://admin.microsoft.com/AdminPortal/Home#/partners/invitation/granularAdminRelationships/{0}' -f $Id
                            'RoleMappings' = [string](@($MatchingRoles) | ConvertTo-Json -Depth 10 -Compress)
                        }
                        Add-CIPPAzDataTableEntity @InviteTable -Entity $Invite
                        $GroupSuccess = $true
                    } else {
                        $TenantOnboarding.Status = 'failed'
                        $OnboardingSteps.Step3.Status = 'failed'
                        $OnboardingSteps.Step3.Message = 'No matching roles found, check the relationship and try again.'
                    }
                }

                if ($Invite) {
                    $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'GDAP invite found, starting group/role mapping' })
                    $GroupMapStatus = Set-CIPPGDAPInviteGroups -Relationship $Relationship
                    if ($GroupMapStatus) {
                        $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'Groups mapped successfully' })
                        $OnboardingSteps.Step3.Message = 'Groups mapped successfully, checking access assignment status'
                        $TenantOnboarding.OnboardingSteps = [string](ConvertTo-Json -InputObject $OnboardingSteps -Compress)
                        $TenantOnboarding.Logs = [string](ConvertTo-Json -InputObject @($Logs) -Compress)
                        Add-CIPPAzDataTableEntity @OnboardTable -Entity $TenantOnboarding -Force -ErrorAction Stop

                    } else {
                        $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'Group mapping failed' })
                        $TenantOnboarding.Status = 'failed'
                        $OnboardingSteps.Step3.Status = 'failed'
                        $OnboardingSteps.Step3.Message = 'Group mapping failed, check the log book for details.'
                    }
                } elseif (!$GroupSuccess) {
                    $TenantOnboarding.Status = 'failed'
                    $OnboardingSteps.Step3.Status = 'failed'
                    $OnboardingSteps.Step3.Message = 'Failed to map security groups, no pending invite available'
                }

                $x = 0
                do {
                    $x++
                    $AccessAssignments = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$Id/accessAssignments"
                    Start-Sleep -Seconds 10
                } while ($AccessAssignments.status -contains 'pending' -and $x -le 12)

                if ($AccessAssignments.status -notcontains 'pending') {
                    $OnboardingSteps.Step3.Message = 'Group check: Access assignments are mapped and active'
                    $OnboardingSteps.Step3.Status = 'succeeded'
                } else {
                    $OnboardingSteps.Step3.Message = 'Group check: Access assignments are still pending, try again later'
                    $OnboardingSteps.Step3.Status = 'failed'
                }
            }
            if ($QueueItem.AddMissingGroups -eq $true) {
                $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'Checking for missing groups for SAM user' })
                $SamUserId = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/me?`$select=id").id
                $CurrentMemberships = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/me/transitiveMemberOf?`$select=id,displayName"
                foreach ($Role in $QueueItem.Roles) {
                    if ($CurrentMemberships.id -notcontains $Role.GroupId) {
                        $PostBody = @{
                            '@odata.id' = 'https://graph.microsoft.com/v1.0/directoryObjects/{0}' -f $SamUserId
                        } | ConvertTo-Json -Compress
                        try {
                            New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($Role.GroupId)/members/`$ref" -body $PostBody -AsApp $true -NoAuthCheck $true
                            $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = "Added SAM user to $($Role.GroupName)" })
                        } catch {
                            $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = "Failed to add SAM user to $($Role.GroupName) - $($_.Exception.Message)" })
                        }
                    }
                }
                $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'SAM user group check completed' })
            }
            $TenantOnboarding.OnboardingSteps = [string](ConvertTo-Json -InputObject $OnboardingSteps -Compress)
            $TenantOnboarding.Logs = [string](ConvertTo-Json -InputObject @($Logs) -Compress)
            Add-CIPPAzDataTableEntity @OnboardTable -Entity $TenantOnboarding -Force -ErrorAction Stop
        }

        if ($OnboardingSteps.Step3.Status -eq 'succeeded') {
            $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'Refreshing CPV permissions' })
            $OnboardingSteps.Step4.Status = 'running'
            $OnboardingSteps.Step4.Message = 'Refreshing CPV permissions'
            $TenantOnboarding.OnboardingSteps = [string](ConvertTo-Json -InputObject $OnboardingSteps -Compress)
            $TenantOnboarding.Logs = [string](ConvertTo-Json -InputObject @($Logs) -Compress)
            Add-CIPPAzDataTableEntity @OnboardTable -Entity $TenantOnboarding -Force -ErrorAction Stop

            try {
                Remove-CIPPCache -tenantsOnly $true
            } catch {}

            $Tenant = Get-Tenants | Where-Object { $_.customerId -eq $Relationship.customer.tenantId } | Select-Object -First 1
            if ($Tenant) {
                $y = 0
                $Refreshing = $true
                $CPVSuccess = $false
                do {
                    try {
                        Add-CIPPApplicationPermission -RequiredResourceAccess 'CippDefaults' -ApplicationId $ENV:ApplicationID -tenantfilter $Tenant.defaultDomainName
                        Add-CIPPDelegatedPermission -RequiredResourceAccess 'CippDefaults' -ApplicationId $ENV:ApplicationID -tenantfilter $Tenant.defaultDomainName
                        $CPVSuccess = $true
                        $Refreshing = $false
                    } catch {
                        $y++
                        Start-Sleep -Seconds 30
                    }
                } while ($Refreshing -and $y -lt 4)

                if ($CPVSuccess) {
                    $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'CPV permissions refreshed' })
                    $OnboardingSteps.Step4.Status = 'succeeded'
                    $OnboardingSteps.Step4.Message = 'CPV permissions refreshed'
                } else {
                    $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'CPV permissions failed to refresh' })
                    $TenantOnboarding.Status = 'failed'
                    $OnboardingSteps.Step4.Status = 'failed'
                    $OnboardingSteps.Step4.Message = 'CPV permissions failed to refresh, try again later'
                }
            } else {
                $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'Tenant not found' })
                $TenantOnboarding.Status = 'failed'
                $OnboardingSteps.Step4.Status = 'failed'
                $OnboardingSteps.Step4.Message = 'Tenant not found in customer list, try again later'
            }
            $TenantOnboarding.OnboardingSteps = [string](ConvertTo-Json -InputObject $OnboardingSteps -Compress)
            $TenantOnboarding.Logs = [string](ConvertTo-Json -InputObject @($Logs) -Compress)
            Add-CIPPAzDataTableEntity @OnboardTable -Entity $TenantOnboarding -Force -ErrorAction Stop
        }

        if ($OnboardingSteps.Step4.Status -eq 'succeeded') {
            $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = "Testing API access for $($Tenant.defaultDomainName)" })
            $OnboardingSteps.Step5.Status = 'running'
            $OnboardingSteps.Step5.Message = 'Testing API access'
            $TenantOnboarding.OnboardingSteps = [string](ConvertTo-Json -InputObject $OnboardingSteps -Compress)
            $TenantOnboarding.Logs = [string](ConvertTo-Json -InputObject @($Logs) -Compress)
            Add-CIPPAzDataTableEntity @OnboardTable -Entity $TenantOnboarding -Force -ErrorAction Stop

            try {
                #Write-Host ($Tenant | ConvertTo-Json)
                $UserCount = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$count=true&`$top=1" -ComplexFilter -tenantid $Tenant.defaultDomainName -CountOnly
            } catch {
                $UserCount = 0
                $ApiError = $_.Exception.Message
            }

            if ($UserCount -gt 0) {
                $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'API test successful' })
                $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'Onboarding complete' })
                $OnboardingSteps.Step5.Status = 'succeeded'
                $OnboardingSteps.Step5.Message = 'API Test Successful: {0} users found' -f $UserCount
                $TenantOnboarding.Status = 'succeeded'
                $TenantOnboarding.OnboardingSteps = [string](ConvertTo-Json -InputObject $OnboardingSteps -Compress)
                $TenantOnboarding.Logs = [string](ConvertTo-Json -InputObject @($Logs) -Compress)
                Add-CIPPAzDataTableEntity @OnboardTable -Entity $TenantOnboarding -Force -ErrorAction Stop
            } else {
                $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'API Test failed: {0}' -f $ApiError })
                $OnboardingSteps.Step5.Status = 'failed'
                $OnboardingSteps.Step5.Message = 'API Test failed: {0}' -f $ApiError
                $TenantOnboarding.Status = 'succeeded'
                $TenantOnboarding.OnboardingSteps = [string](ConvertTo-Json -InputObject $OnboardingSteps -Compress)
                $TenantOnboarding.Logs = [string](ConvertTo-Json -InputObject @($Logs) -Compress)
                Add-CIPPAzDataTableEntity @OnboardTable -Entity $TenantOnboarding -Force -ErrorAction Stop
            }
        }
    } catch {
        $Logs.Add([PSCustomObject]@{ Date = Get-Date -UFormat $DateFormat; Log = 'Onboarding failed. Exception: {0}' -f $_.Exception.Message })
        $TenantOnboarding.Status = 'failed'
        $TenantOnboarding.Exception = [string]('{0} - Line {1} - {2}' -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber, $_.InvocationInfo.ScriptName)
        $TenantOnboarding.OnboardingSteps = [string](ConvertTo-Json -InputObject $OnboardingSteps -Compress)
        $TenantOnboarding.Logs = [string](ConvertTo-Json -InputObject @($Logs) -Compress)
        Add-CIPPAzDataTableEntity @OnboardTable -Entity $TenantOnboarding -Force -ErrorAction Stop
    }
}
