function Add-CIPPGDAPRoleTemplate {
    <#
    .SYNOPSIS
    This function is used to add a new role template

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        $TemplateId,
        $RoleMappings,
        [switch]$Overwrite,
        $Headers,
        $APIName = 'AddGDAPRoleTemplate'
    )

    try {
        $Table = Get-CIPPTable -TableName 'GDAPRoleTemplates'
        $Templates = Get-CIPPAzDataTableEntity @Table
        if ($Templates.RowKey -contains $TemplateId -and !$Overwrite.IsPresent) {
            $ExistingTemplate = $Templates | Where-Object -Property RowKey -EQ $TemplateId
            try {
                $ExistingRoleMappings = $ExistingTemplate.RoleMappings | ConvertFrom-Json
            } catch {
                $ExistingRoleMappings = @()
            }
            $NewRoleMappings = [System.Collections.Generic.List[object]]@()

            $ExistingRoleMappings | ForEach-Object {
                $NewRoleMappings.Add($_)
            }
            # Merge the new role mappings with the existing role mappings, exclude ones that have a duplicate roleDefinitionId
            $RoleMappings | ForEach-Object {
                if ($_.roleDefinitionId -notin $ExistingRoleMappings.roleDefinitionId) {
                    $NewRoleMappings.Add($_)
                }
            }
            $NewRoleMappings = @($NewRoleMappings | Sort-Object -Property GroupName) | ConvertTo-Json -Compress
            $ExistingTemplate.RoleMappings = [string]$NewRoleMappings
            $Template = $ExistingTemplate
            Add-CIPPAzDataTableEntity @Table -Entity $Template -Force
            Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Updated GDAP role template '$TemplateId'" -Sev 'Info'
        } else {
            $Template = [PSCustomObject]@{
                PartitionKey = 'RoleTemplate'
                RowKey       = $TemplateId
                RoleMappings = [string](@($RoleMappings | Sort-Object -Property GroupName) | ConvertTo-Json -Compress)
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Template -Force
            if ($Overwrite.IsPresent) {
                Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Overwrote GDAP role template '$TemplateId'" -Sev 'Info'
            } else {
                Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Created GDAP role template '$TemplateId'" -Sev 'Info'
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Failed to save GDAP role template '$TemplateId': $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        throw
    }
}
