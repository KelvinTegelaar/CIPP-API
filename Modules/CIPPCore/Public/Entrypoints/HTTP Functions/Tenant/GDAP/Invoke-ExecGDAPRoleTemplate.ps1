using namespace System.Net

Function Invoke-ExecGDAPRoleTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CIPPTable -TableName 'GDAPRoleTemplates'
    $Templates = Get-CIPPAzDataTableEntity @Table

    switch ($Request.Query.Action) {
        'Add' {
            $RowKey = ($Request.Body | Select-Object -First 1 -ExpandProperty TemplateId).value
            $RoleMappings = $Request.Body | Select-Object -ExcludeProperty TemplateId
            if ($Templates.RowKey -contains $RowKey) {
                $ExistingTemplate = $Templates | Where-Object -Property RowKey -EQ $RowKey
                $ExistingRoleMappings = $ExistingTemplate.RoleMappings | ConvertFrom-Json
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
            } else {
                $Template = [PSCustomObject]@{
                    PartitionKey = 'RoleTemplate'
                    RowKey       = $RowKey
                    RoleMappings = [string](@($RoleMappings | Sort-Object -Property GroupName) | ConvertTo-Json -Compress)
                }
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Template -Force
            Write-Information ($Template | ConvertTo-Json)
            $Body = @{
                Results = "Added role mappings to template $RowKey"
            }
        }
        'Edit' {
            $RowKey = $Request.Body.TemplateId
            $Template = $Templates | Where-Object -Property RowKey -EQ $RowKey
            if ($Template) {
                $RoleMappings = $Request.Body.RoleMappings
                $Template.RoleMappings = [string](@($RoleMappings | Sort-Object -Property GroupName) | ConvertTo-Json -Compress)
                Add-CIPPAzDataTableEntity @Table -Entity $Template -Force
                $Body = @{
                    Results = "Updated role mappings for template $RowKey"
                }
            } else {
                $Body = @{
                    Results = "Template $RowKey not found"
                }
            }
        }
        'Delete' {
            $RowKey = $Request.Body.TemplateId
            $Template = $Templates | Where-Object -Property RowKey -EQ $RowKey
            if ($Template) {
                Remove-AzDataTableEntity -Force @Table -Entity $Template
                $Body = @{
                    Results = "Deleted template $RowKey"
                }
            } else {
                $Body = @{
                    Results = "Template $RowKey not found"
                }
            }
        }
        default {
            $Results = foreach ($Template in $Templates) {
                [PSCustomObject]@{
                    TemplateId   = $Template.RowKey
                    RoleMappings = @($Template.RoleMappings | ConvertFrom-Json)
                }
            }
            $Body = @{
                Results  = @($Results)
                Metadata = @{
                    Count = $Results.Count
                }
            }
        }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
