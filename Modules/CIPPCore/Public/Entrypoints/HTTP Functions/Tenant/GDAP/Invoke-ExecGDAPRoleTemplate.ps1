using namespace System.Net

Function Invoke-ExecGDAPRoleTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CIPPTable -TableName 'GDAPRoleTemplates'
    $Templates = Get-CIPPAzDataTableEntity @Table

    if ($Request.Query.TemplateId) {
        $Template = $Templates | Where-Object -Property RowKey -EQ $Request.Query.TemplateId
        if (!$Template) {
            $Body = @{}
        } else {
            $Body = @{
                TemplateId   = $Template.RowKey
                RoleMappings = @($Template.RoleMappings | ConvertFrom-Json)
            }
        }
    } else {
        switch ($Request.Query.Action) {
            'Add' {
                $RowKey = ($Request.Body | Select-Object -First 1 -ExpandProperty TemplateId).value ?? $Request.Body.TemplateId
                if ($Request.Body.GroupId) {
                    $RoleMappings = $Request.Body | Select-Object * -ExcludeProperty TemplateId
                } else {
                    $RoleMappings = $Request.Body.RoleMappings
                }
                Write-Information ($RoleMappings | ConvertTo-Json)
                Add-CIPPGDAPRoleTemplate -TemplateId $RowKey -RoleMappings $RoleMappings
                $Body = @{
                    Results = "Added role mappings to template $RowKey"
                }
            }
            'Edit' {
                $RowKey = $Request.Body.TemplateId
                $Template = $Templates | Where-Object -Property RowKey -EQ $RowKey
                if ($Template) {
                    $RoleMappings = $Request.Body.RoleMappings
                    Add-CIPPGDAPRoleTemplate -TemplateId $RowKey -RoleMappings $RoleMappings -Overwrite
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
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
