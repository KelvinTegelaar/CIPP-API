function Import-CommunityTemplate {
    <#

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Template,
        $SHA,
        $MigrationTable,
        [switch]$Force
    )

    $Table = Get-CippTable -TableName 'templates'

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
            Add-CIPPAzDataTableEntity @Table -Entity $Template -Force
        } else {
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
                        GUID            = $Template.id
                        groupType       = 'generic'
                    } | ConvertTo-Json -Depth 100
                    $entity = @{
                        JSON         = "$RawJsonObj"
                        PartitionKey = 'GroupTemplate'
                        SHA          = $SHA
                        GUID         = $Template.id
                        RowKey       = $Template.id
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
                    $id = $Template.id
                    $Template = $Template | Select-Object * -ExcludeProperty lastModifiedDateTime, 'assignments', '#microsoft*', '*@odata.navigationLink', '*@odata.associationLink', '*@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime', '@odata.id', '@odata.editLink', '*odata.type', 'roleScopeTagIds@odata.type', createdDateTime, 'createdDateTime@odata.type'
                    Remove-ODataProperties -Object $Template
                    $RawJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress
                    #Replace the ids with the displayname by using the migration table, this is a simple find and replace each instance in the JSON.
                    $MigrationTable.objects | ForEach-Object {
                        if ($RawJson -match $_.ID) {
                            $RawJson = $RawJson.Replace($_.ID, $($_.DisplayName))
                        }
                    }
                    $entity = @{
                        JSON         = "$RawJson"
                        PartitionKey = 'CATemplate'
                        SHA          = $SHA
                        GUID         = $ID
                        RowKey       = $ID
                    }
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
                    $id = $Template.id
                    $RawJson = $Template | Select-Object * -ExcludeProperty id, lastModifiedDateTime, 'assignments', '#microsoft*', '*@odata.navigationLink', '*@odata.associationLink', '*@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime', '@odata.id', '@odata.editLink', 'lastModifiedDateTime@odata.type', 'roleScopeTagIds@odata.type', createdDateTime, 'createdDateTime@odata.type'
                    Remove-ODataProperties -Object $RawJson
                    $RawJson = $RawJson | ConvertTo-Json -Depth 100 -Compress

                    #create a new template
                    $RawJsonObj = [PSCustomObject]@{
                        Displayname = $Template.displayName ?? $template.Name
                        Description = $Template.Description
                        RAWJson     = $RawJson
                        Type        = $URLName
                        GUID        = $ID
                    } | ConvertTo-Json -Depth 100 -Compress

                    $entity = @{
                        JSON         = "$RawJsonObj"
                        PartitionKey = 'IntuneTemplate'
                        SHA          = $SHA
                        GUID         = $ID
                        RowKey       = $ID
                    }
                    Add-CIPPAzDataTableEntity @Table -Entity $entity -Force

                }
            }
        }
    } catch {
        Write-Warning "Community template import failed. Error: $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
    }
}
