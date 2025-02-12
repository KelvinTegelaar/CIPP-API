function Import-CommunityTemplate {
    <#

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Template,
        $SHA,
        [switch]$Force
    )

    $Table = Get-CippTable -TableName 'templates'


    if ($Template.RowKey) {
        Write-Host "This is going to be a direct write to table, it's a CIPP template. We're writing $($Template.RowKey)"
        Add-CIPPAzDataTableEntity @Table -Entity $Template -Force
    } else {
        switch -Wildcard ($Template.'@odata.type') {
            '*conditionalAccessPolicy*' {
                $Template = ([pscustomobject]$Template) | ForEach-Object {
                    $NonEmptyProperties = $_.psobject.Properties | Where-Object { $null -ne $_.Value } | Select-Object -ExpandProperty Name
                    $_ | Select-Object -Property $NonEmptyProperties
                }
                $id = $Template.id
                $Template = $Template | Select-Object * -ExcludeProperty lastModifiedDateTime, 'assignments', '#microsoft*', '*@odata.navigationLink', '*@odata.associationLink', '*@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime', '@odata.id', '@odata.editLink', '*odata.type', 'roleScopeTagIds@odata.type', createdDateTime, 'createdDateTime@odata.type'
                Remove-ODataProperties -Object $Template
                $RawJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress
                $entity = @{
                    JSON         = "$RawJson"
                    PartitionKey = 'CATemplate'
                    SHA          = $SHA
                    GUID         = $ID
                    RowKey       = $ID
                }
                Add-CIPPAzDataTableEntity @Table -Entity $entity -Force
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
