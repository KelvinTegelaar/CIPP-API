function Invoke-CIPPStandardGroupTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) GroupTemplate
    .SYNOPSIS
        (Label) Group Template
    .DESCRIPTION
        (Helptext) Deploy and manage group templates.
        (DocsDescription) Deploy and manage group templates.
    .NOTES
        MULTI
            True
        CAT
            Templates
        DISABLEDFEATURES
            {"report":true,"warn":true,"remediate":false}
        IMPACT
            Medium Impact
        ADDEDDATE
            2023-12-30
        ADDEDCOMPONENT
            {"type":"autoComplete","name":"groupTemplate","label":"Select Group Template","api":{"url":"/api/ListGroupTemplates","labelField":"Displayname","altLabelField":"displayName","valueField":"GUID","queryKey":"ListGroupTemplates"}}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)

    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'GroupTemplate'
    $existingGroups = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/groups?$top=999' -tenantid $tenant

    $TestResult = Test-CIPPStandardLicense -StandardName 'GroupTemplate' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_LITE') -SkipLog

    $Settings.groupTemplate ? ($Settings | Add-Member -NotePropertyName 'TemplateList' -NotePropertyValue $Settings.groupTemplate) : $null

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'GroupTemplate' and (RowKey eq '$($Settings.TemplateList.value -join "' or RowKey eq '")')"
    $GroupTemplates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json

    if ('dynamicDistribution' -in $GroupTemplates.groupType) {
        # Get dynamic distro list from exchange
        $DynamicDistros = New-ExoRequest -cmdlet 'Get-DynamicDistributionGroup' -tenantid $tenant -Select 'Identity,Name,Alias,RecipientFilter,PrimarySmtpAddress'
    }

    if ($Settings.remediate -eq $true) {
        #Because the list name changed from TemplateList to groupTemplate by someone :@, we'll need to set it back to TemplateList

        Write-Host "Settings: $($Settings.TemplateList | ConvertTo-Json)"
        foreach ($Template in $GroupTemplates) {
            Write-Information "Processing template: $($Template.displayName)"
            try {
                $groupobj = $Template

                if ($Template.groupType -eq 'dynamicDistribution') {
                    $CheckExisting = $DynamicDistros | Where-Object { $_.Name -eq $Template.displayName }
                } else {
                    $CheckExisting = $existingGroups | Where-Object -Property displayName -EQ $groupobj.displayName
                }

                if (!$CheckExisting) {
                    Write-Information 'Creating group'
                    $ActionType = 'create'

                    # Check if Exchange license is required for distribution groups
                    if ($groupobj.groupType -in @('distribution', 'dynamicdistribution') -and !$TestResult) {
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Cannot create group $($groupobj.displayname) as the tenant is not licensed for Exchange." -Sev 'Error'
                        continue
                    }

                    # Use the centralized New-CIPPGroup function
                    $Result = New-CIPPGroup -GroupObject $groupobj -TenantFilter $tenant -APIName 'Standards' -ExecutingUser 'CIPP-Standards'

                    if (!$Result.Success) {
                        Write-Information "Failed to create group $($groupobj.displayname): $($Result.Message)"
                        continue
                    }
                } else {
                    $ActionType = 'update'

                    # Normalize group type like New-CIPPGroup does
                    $NormalizedGroupType = switch -Wildcard ($groupobj.groupType.ToLower()) {
                        '*dynamicdistribution*' { 'DynamicDistribution'; break }
                        '*dynamic*' { 'Dynamic'; break }
                        '*generic*' { 'Generic'; break }
                        '*security*' { 'Security'; break }
                        '*azurerole*' { 'AzureRole'; break }
                        '*m365*' { 'M365'; break }
                        '*unified*' { 'M365'; break }
                        '*microsoft*' { 'M365'; break }
                        '*distribution*' { 'Distribution'; break }
                        '*mail*' { 'Distribution'; break }
                        default { $groupobj.groupType }
                    }

                    # Handle Graph API groups (Security, Generic, AzureRole, Dynamic, M365)
                    if ($NormalizedGroupType -in @('Generic', 'Security', 'AzureRole', 'Dynamic', 'M365')) {

                        # Compare existing group with template to determine what needs updating
                        $PatchBody = [PSCustomObject]@{}
                        $ChangesNeeded = [System.Collections.Generic.List[string]]::new()

                        # Check description
                        if ($CheckExisting.description -ne $groupobj.description) {
                            $PatchBody | Add-Member -NotePropertyName 'description' -NotePropertyValue $groupobj.description
                            $ChangesNeeded.Add("description: '$($CheckExisting.description)' → '$($groupobj.description)'")
                        }

                        # Handle membership rules for dynamic groups
                        # Only update if the template specifies this should be a dynamic group
                        if ($NormalizedGroupType -eq 'Dynamic' -and $groupobj.membershipRules) {
                            if ($CheckExisting.membershipRule -ne $groupobj.membershipRules) {
                                $PatchBody | Add-Member -NotePropertyName 'membershipRule' -NotePropertyValue $groupobj.membershipRules
                                $PatchBody | Add-Member -NotePropertyName 'membershipRuleProcessingState' -NotePropertyValue 'On'
                                $ChangesNeeded.Add("membershipRule: '$($CheckExisting.membershipRule)' → '$($groupobj.membershipRules)'")
                            }
                        }

                        # Only patch if there are actual changes
                        if ($ChangesNeeded.Count -gt 0) {
                            $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($CheckExisting.id)" -tenantid $tenant -type PATCH -body (ConvertTo-Json -InputObject $PatchBody -Depth 10)
                            Write-LogMessage -API 'Standards' -tenant $tenant -message "Updated Group '$($groupobj.displayName)' - Changes: $($ChangesNeeded -join ', ')" -Sev Info
                        } else {
                            Write-Information "Group '$($groupobj.displayName)' already matches template - no update needed"
                        }

                    } else {
                        # Handle Exchange Online groups (Distribution, DynamicDistribution)
                        if (!$TestResult) {
                            Write-LogMessage -API 'Standards' -tenant $tenant -message "Cannot update group $($groupobj.displayName) as the tenant is not licensed for Exchange." -Sev 'Error'
                            continue
                        }

                        # Construct email address if needed
                        $Email = if ($groupobj.username -like '*@*') {
                            $groupobj.username
                        } else {
                            "$($groupobj.username)@$($tenant)"
                        }

                        $ExoChangesNeeded = [System.Collections.Generic.List[string]]::new()

                        if ($NormalizedGroupType -eq 'DynamicDistribution') {
                            # Compare Dynamic Distribution Group properties
                            $SetParams = @{
                                Identity = $CheckExisting.Identity
                            }

                            # Check recipient filter change
                            if ($CheckExisting.RecipientFilter -notmatch $groupobj.membershipRules) {
                                $SetParams.RecipientFilter = $groupobj.membershipRules
                                $ExoChangesNeeded.Add("RecipientFilter: '$($CheckExisting.RecipientFilter)' → '$($groupobj.membershipRules)'")
                            }

                            # Only update if there are changes
                            if ($SetParams.Count -gt 1) {
                                $GraphRequest = New-ExoRequest -tenantid $tenant -cmdlet 'Set-DynamicDistributionGroup' -cmdParams $SetParams
                            }

                            # Check external sender restrictions
                            if ($null -ne $groupobj.allowExternal) {
                                $currentAuthRequired = $CheckExisting.RequireSenderAuthenticationEnabled
                                $templateAuthRequired = [bool]!$groupobj.allowExternal

                                if ($currentAuthRequired -ne $templateAuthRequired) {
                                    $ExtParams = @{
                                        Identity                           = $CheckExisting.displayName
                                        RequireSenderAuthenticationEnabled = $templateAuthRequired
                                    }
                                    $null = New-ExoRequest -tenantid $tenant -cmdlet 'Set-DynamicDistributionGroup' -cmdParams $ExtParams
                                    $ExoChangesNeeded.Add("RequireSenderAuthenticationEnabled: '$currentAuthRequired' → '$templateAuthRequired'")
                                }
                            }

                        } else {
                            # Compare Regular Distribution Group properties
                            $SetParams = @{
                                Identity = $CheckExisting.displayName
                            }

                            # Check display name change
                            if ($CheckExisting.displayName -ne $groupobj.displayName) {
                                $SetParams.DisplayName = $groupobj.displayName
                                $ExoChangesNeeded.Add("DisplayName: '$($CheckExisting.displayName)' → '$($groupobj.displayName)'")
                            }

                            # Check description change
                            if ($CheckExisting.description -ne $groupobj.description) {
                                $SetParams.Description = $groupobj.description
                                $ExoChangesNeeded.Add("Description: '$($CheckExisting.description)' → '$($groupobj.description)'")
                            }

                            # Check external sender restrictions
                            if ($null -ne $groupobj.allowExternal) {
                                $currentAuthRequired = $CheckExisting.RequireSenderAuthenticationEnabled
                                $templateAuthRequired = [bool]!$groupobj.allowExternal

                                if ($currentAuthRequired -ne $templateAuthRequired) {
                                    $SetParams.RequireSenderAuthenticationEnabled = $templateAuthRequired
                                    $ExoChangesNeeded.Add("RequireSenderAuthenticationEnabled: '$currentAuthRequired' → '$templateAuthRequired'")
                                }
                            }

                            # Only update if there are changes
                            if ($SetParams.Count -gt 0) {
                                $GraphRequest = New-ExoRequest -tenantid $tenant -cmdlet 'Set-DistributionGroup' -cmdParams $SetParams
                            }
                        }

                        # Log results
                        if ($ExoChangesNeeded.Count -gt 0) {
                            Write-LogMessage -API 'Standards' -tenant $tenant -message "Updated Exchange group '$($groupobj.displayName)' - Changes: $($ExoChangesNeeded -join ', ')" -Sev Info
                        } else {
                            Write-Information "Exchange group '$($groupobj.displayName)' already matches template - no update needed"
                        }
                    }

                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to $ActionType group $($groupobj.displayname). Error: $ErrorMessage" -sev 'Error'
            }
        }
    }
    if ($Settings.report -eq $true) {
        #check if all groups.displayName are in the existingGroups, if not $fieldvalue should contain all missing groups, else it should be true.
        $MissingGroups = foreach ($Group in $GroupTemplates) {
            if ($Group.groupType -eq 'dynamicDistribution') {
                $CheckExisting = $DynamicDistros | Where-Object { $_.Name -eq $Group.displayName }
                if (!$CheckExisting) {
                    $Group.displayName
                }
            } else {
                $CheckExisting = $existingGroups | Where-Object { $_.displayName -eq $Group.displayName }
                if (!$CheckExisting) {
                    $Group.displayName
                }
            }
        }

        if ($MissingGroups.Count -eq 0) {
            $fieldValue = $true
        } else {
            $fieldValue = $MissingGroups -join ', '
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.GroupTemplate' -FieldValue $fieldValue -Tenant $Tenant
    }
}
