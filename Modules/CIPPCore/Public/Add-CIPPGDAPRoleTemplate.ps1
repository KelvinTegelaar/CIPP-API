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
            # A role can be mapped to several groups, so only the same group and role pair is a duplicate
            foreach ($Mapping in @($RoleMappings)) {
                if (-not @($ExistingRoleMappings).Where({ $_.GroupId -eq $Mapping.GroupId -and $_.roleDefinitionId -eq $Mapping.roleDefinitionId })) {
                    $NewRoleMappings.Add($Mapping)
                }
            }
            $NewRoleMappings = @($NewRoleMappings | Sort-Object -Property GroupName, GroupId, roleDefinitionId -Unique) | ConvertTo-Json -Compress
            $ExistingTemplate.RoleMappings = [string]$NewRoleMappings
            $Template = $ExistingTemplate
            Add-CIPPAzDataTableEntity @Table -Entity $Template -Force
            Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Updated GDAP role template '$TemplateId'" -Sev 'Info'
        } else {
            $Template = [PSCustomObject]@{
                PartitionKey = 'RoleTemplate'
                RowKey       = $TemplateId
                RoleMappings = [string](@($RoleMappings | Sort-Object -Property GroupName, GroupId, roleDefinitionId -Unique) | ConvertTo-Json -Compress)
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
