function Import-CommunityTemplate {
    <#

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Template,
        $SHA,
        $MigrationTable,
        $LocationData,
        $Source,
        [switch]$Force
    )

    $Table = Get-CippTable -TableName 'templates'
    $StatusMessage = $null

    try {
        if ($Template.RowKey) {
            Write-Host "This is going to be a direct write to table, it's a CIPP template. We're writing $($Template.RowKey)"
            $Template = $Template | Select-Object * -ExcludeProperty Timestamp

            # Support both objects and json string in repo (support pretty printed json in repo)
            if (Test-Json $Template.JSON -ErrorAction SilentlyContinue) {
                $NewJSON = $Template.JSON | ConvertFrom-Json
            } else {
                $NewJSON = $Template.JSON
            }

            # Check for existing object
            $Existing = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($Template.RowKey)' and PartitionKey eq '$($Template.PartitionKey)'" -ErrorAction SilentlyContinue

            if ($Existing) {
                if ($Existing.PartitionKey -eq 'StandardsTemplateV2') {
                    # Convert existing JSON to object for updates
                    if (Test-Json $Existing.JSON -ErrorAction SilentlyContinue) {
                        $ExistingJSON = $Existing.JSON | ConvertFrom-Json
                    } else {
                        $ExistingJSON = $Existing.JSON
                    }
                    # Extract existing tenantFilter and excludedTenants
                    $tenantFilter = $ExistingJSON.tenantFilter
                    $excludedTenants = $ExistingJSON.excludedTenants
                    $NewJSON.tenantFilter = $tenantFilter
                    $NewJSON.excludedTenants = $excludedTenants
                }
            }

            if ($Template.PartitionKey -eq 'AppApprovalTemplate') {
                # Extract the Permission Set name,id,permissions from the JSON and add to the AppPermissions table
                $AppPermissionsTable = Get-CIPPTable -TableName 'AppPermissions'
                $Permissions = $NewJSON.Permissions
                $Entity = @{
                    'PartitionKey' = 'Templates'
                    'RowKey'       = $NewJSON.PermissionSetId
                    'TemplateName' = $NewJSON.PermissionSetName
                    'Permissions'  = [string]($Permissions | ConvertTo-Json -Depth 10 -Compress)
                    'UpdatedBy'    = $NewJSON.UpdatedBy ?? $NewJSON.CreatedBy ?? 'System'
                }
                $null = Add-CIPPAzDataTableEntity @AppPermissionsTable -Entity $Entity -Force
                Write-Information 'Added App Permissions to AppPermissions table'
            }

            # Re-compress JSON and save to table
            $NewJSON = [string]($NewJSON | ConvertTo-Json -Depth 100 -Compress)
            $Template.JSON = $NewJSON
            $Template | Add-Member -MemberType NoteProperty -Name SHA -Value $SHA -Force
            $Template | Add-Member -MemberType NoteProperty -Name Source -Value $Source -Force
            Add-CIPPAzDataTableEntity @Table -Entity $Template -Force
            
            if ($Existing -and $Existing.SHA -ne $SHA) {
                $StatusMessage = "Updated template '$($Template.RowKey)' from source '$Source' (SHA changed)."
            } elseif ($Existing) {
                $StatusMessage = "Template '$($Template.RowKey)' from source '$Source' is already up to date."
            } else {
                $StatusMessage = "Created template '$($Template.RowKey)' from source '$Source'."
            }
        } else {
            $id = [guid]::NewGuid().ToString()
            if ($Template.mailNickname) { $Type = 'Group' }
            if ($Template.'@odata.type' -like '*conditionalAccessPolicy*') { $Type = 'ConditionalAccessPolicy' }
            Write-Host "The type is $Type"

            switch -Wildcard ($Type) {
                '*Group*' {
                    $RawJsonObj = [PSCustomObject]@{
                        Displayname     = $Template.displayName
                        Description     = $Template.Description
                        MembershipRules = $Template.membershipRule
                        username        = $Template.mailNickname
                        GUID            = $id
                        groupType       = 'generic'
                    } | ConvertTo-Json -Depth 100

                    # Check for duplicate template
                    $DuplicateFilter = "PartitionKey eq 'GroupTemplate'"
                    $ExistingTemplates = Get-CIPPAzDataTableEntity @Table -Filter $DuplicateFilter -ErrorAction SilentlyContinue
                    $Duplicate = $ExistingTemplates | Where-Object {
                        try {
                            $ExistingJSON = if (Test-Json $_.JSON -ErrorAction SilentlyContinue) {
                                $_.JSON | ConvertFrom-Json
                            } else {
                                $_.JSON
                            }
                            $ExistingJSON.Displayname -eq $Template.displayName -and $_.Source -eq $Source
                        } catch {
                            $false
                        }
                    } | Select-Object -First 1

                    if ($Duplicate -and $Duplicate.SHA -eq $SHA -and -not $Force) {
                        $StatusMessage = "Group template '$($Template.displayName)' from source '$Source' is already up to date. Skipping import."
                        Write-Information $StatusMessage
                        break
                    }

                    if ($Duplicate) {
                        $StatusMessage = "Updating Group template '$($Template.displayName)' from source '$Source' (SHA changed)."
                        Write-Information $StatusMessage
                    } else {
                        $StatusMessage = "Created Group template '$($Template.displayName)' from source '$Source'."
                    }

                    $entity = @{
                        JSON         = "$RawJsonObj"
                        PartitionKey = 'GroupTemplate'
                        SHA          = $SHA
                        GUID         = if ($Duplicate) { $Duplicate.GUID } else { $id }
                        RowKey       = if ($Duplicate) { $Duplicate.RowKey } else { $id }
                        Source       = $Source
                    }
                    Add-CIPPAzDataTableEntity @Table -Entity $entity -Force
                    break
                }
                '*conditionalAccessPolicy*' {
                    Write-Host $MigrationTable
                    $Template = ([pscustomobject]$Template) | ForEach-Object {
                        $NonEmptyProperties = $_.psobject.Properties | Where-Object { $null -ne $_.Value } | Select-Object -ExpandProperty Name
                        $_ | Select-Object -Property $NonEmptyProperties
                    }
                    $Template = $Template | Select-Object * -ExcludeProperty lastModifiedDateTime, 'assignments', '#microsoft*', '*@odata.navigationLink', '*@odata.associationLink', '*@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime', '@odata.id', '@odata.editLink', '*odata.type', 'roleScopeTagIds@odata.type', createdDateTime, 'createdDateTime@odata.type', 'templateId'
                    Remove-ODataProperties -Object $Template

                    $LocationInfo = [system.collections.generic.list[object]]::new()
                    if ($LocationData) {
                        $LocationData | ForEach-Object {
                            if ($Template.conditions.locations.includeLocations -contains $_.id -or $Template.conditions.locations.excludeLocations -contains $_.id) {
                                Write-Information "Adding location info for location ID $($_.id)"
                                $LocationInfo.Add($_)
                            }
                        }
                        if ($LocationInfo.Count -gt 0) {
                            $Template | Add-Member -MemberType NoteProperty -Name LocationInfo -Value $LocationInfo -Force
                        }
                    }

                    $RawJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress

                    Write-Information "Raw JSON before ID replacement: $RawJson"
                    #Replace the ids with the displayname by using the migration table, this is a simple find and replace each instance in the JSON.
                    $MigrationTable.objects | ForEach-Object {
                        if ($RawJson -match $_.ID) {
                            $RawJson = $RawJson.Replace($_.ID, $($_.DisplayName))
                        }
                    }

                    # Check for duplicate template
                    $DuplicateFilter = "PartitionKey eq 'CATemplate'"
                    $ExistingTemplates = Get-CIPPAzDataTableEntity @Table -Filter $DuplicateFilter -ErrorAction SilentlyContinue
                    $Duplicate = $ExistingTemplates | Where-Object {
                        try {
                            $ExistingJSON = if (Test-Json $_.JSON -ErrorAction SilentlyContinue) {
                                $_.JSON | ConvertFrom-Json
                            } else {
                                $_.JSON
                            }
                            $ExistingJSON.displayName -eq $Template.displayName -and $_.Source -eq $Source
                        } catch {
                            $false
                        }
                    } | Select-Object -First 1

                    if ($Duplicate -and $Duplicate.SHA -eq $SHA -and -not $Force) {
                        $StatusMessage = "Conditional Access template '$($Template.displayName)' from source '$Source' is already up to date. Skipping import."
                        Write-Information $StatusMessage
                        break
                    }

                    if ($Duplicate) {
                        $StatusMessage = "Updating Conditional Access template '$($Template.displayName)' from source '$Source' (SHA changed)."
                        Write-Information $StatusMessage
                    } else {
                        $StatusMessage = "Created Conditional Access template '$($Template.displayName)' from source '$Source'."
                    }

                    $entity = @{
                        JSON         = "$RawJson"
                        PartitionKey = 'CATemplate'
                        SHA          = $SHA
                        GUID         = if ($Duplicate) { $Duplicate.GUID } else { $id }
                        RowKey       = if ($Duplicate) { $Duplicate.RowKey } else { $id }
                        Source       = $Source
                    }
                    Write-Information "Final entity: $($entity | ConvertTo-Json -Depth 10)"

                    Add-CIPPAzDataTableEntity @Table -Entity $entity -Force
                    break
                }
                default {
                    $URLName = switch -Wildcard ($Template.'@odata.id') {
                        '*CompliancePolicies*' { 'DeviceCompliancePolicies' }
                        '*deviceConfigurations*' { 'Device' }
                        '*DriverUpdateProfiles*' { 'windowsDriverUpdateProfiles' }
                        '*SettingsCatalog*' { 'Catalog' }
                        '*configurationPolicies*' { 'Catalog' }
                        '*managedAppPolicies*' { 'AppProtection' }
                        '*deviceAppManagement*' { 'AppProtection' }
                    }
                    $RawJson = $Template | Select-Object * -ExcludeProperty id, lastModifiedDateTime, 'assignments', '#microsoft*', '*@odata.navigationLink', '*@odata.associationLink', '*@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime', '@odata.id', '@odata.editLink', 'lastModifiedDateTime@odata.type', 'roleScopeTagIds@odata.type', createdDateTime, 'createdDateTime@odata.type'
                    Remove-ODataProperties -Object $RawJson
                    $RawJson = $RawJson | ConvertTo-Json -Depth 100 -Compress

                    #create a new template
                    $DisplayName = $Template.displayName ?? $template.Name

                    $RawJsonObj = [PSCustomObject]@{
                        Displayname = $DisplayName
                        Description = $Template.Description
                        RAWJson     = $RawJson
                        Type        = $URLName
                        GUID        = $id
                    } | ConvertTo-Json -Depth 100 -Compress

                    # Check for duplicate template
                    $DuplicateFilter = "PartitionKey eq 'IntuneTemplate'"
                    $ExistingTemplates = Get-CIPPAzDataTableEntity @Table -Filter $DuplicateFilter -ErrorAction SilentlyContinue
                    $Duplicate = $ExistingTemplates | Where-Object {
                        try {
                            $ExistingJSON = if (Test-Json $_.JSON -ErrorAction SilentlyContinue) {
                                $_.JSON | ConvertFrom-Json
                            } else {
                                $_.JSON
                            }
                            $ExistingJSON.Displayname -eq $DisplayName -and $_.Source -eq $Source
                        } catch {
                            $false
                        }
                    } | Select-Object -First 1

                    if ($Duplicate -and $Duplicate.SHA -eq $SHA -and -not $Force) {
                        $StatusMessage = "Intune template '$DisplayName' from source '$Source' is already up to date. Skipping import."
                        Write-Information $StatusMessage
                        return $StatusMessage
                    }

                    if ($Duplicate) {
                        $StatusMessage = "Updating Intune template '$DisplayName' from source '$Source' (SHA changed)."
                        Write-Information $StatusMessage
                    } else {
                        $StatusMessage = "Created Intune template '$DisplayName' from source '$Source'."
                    }

                    $entity = @{
                        JSON         = "$RawJsonObj"
                        PartitionKey = 'IntuneTemplate'
                        SHA          = $SHA
                        GUID         = if ($Duplicate) { $Duplicate.GUID } else { $id }
                        RowKey       = if ($Duplicate) { $Duplicate.RowKey } else { $id }
                        Source       = $Source
                    }

                    if ($Existing -and $Existing.Package) {
                        $entity.Package = $Existing.Package
                    }

                    if ($Duplicate -and $Duplicate.Package) {
                        $entity.Package = $Duplicate.Package
                    }

                    Add-CIPPAzDataTableEntity @Table -Entity $entity -Force

                }
            }
        }
    } catch {
        $StatusMessage = "Community template import failed. Error: $($_.Exception.Message)"
        Write-Warning $StatusMessage
        Write-Information $_.InvocationInfo.PositionMessage
    }
    
    return $StatusMessage
}
