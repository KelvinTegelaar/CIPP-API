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


    if ($Template.RowKey) {
        Write-Host "This is going to be a direct write to table, it's a CIPP template. We're writing $($Template.RowKey)"
        $Template = $Template | Select-Object * -ExcludeProperty timestamp
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

}
