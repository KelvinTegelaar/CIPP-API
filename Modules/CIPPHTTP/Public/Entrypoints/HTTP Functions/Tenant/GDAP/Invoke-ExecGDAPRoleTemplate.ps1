function Invoke-ExecGDAPRoleTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $Table = Get-CIPPTable -TableName 'GDAPRoleTemplates'
    $Templates = Get-CIPPAzDataTableEntity @Table

    if ($Request.Query.TemplateId) {
        $Template = $Templates | Where-Object -Property RowKey -EQ $Request.Query.TemplateId
        if (!$Template) {
            Write-LogMessage -headers $Headers -API $APIName -message "GDAP role template '$($Request.Query.TemplateId)' not found" -sev 'Warning'
            $Body = @{}
        } else {
            Write-LogMessage -headers $Headers -API $APIName -message "Retrieved GDAP role template '$($Request.Query.TemplateId)'" -Sev 'Info'
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
                Write-LogMessage -headers $Headers -API $APIName -message "Added role mappings to GDAP template '$RowKey'" -Sev 'Info'
                $Body = @{
                    Results = "Added role mappings to template $RowKey"
                }
            }
            'Save' {
                # Template-first save: creates any group mappings the editor asked for, then
                # writes the full mapping set to the template in one shot.
                $NewTemplateId = $Request.Body.TemplateId
                $OriginalTemplateId = $Request.Body.OriginalTemplateId
                $SaveResults = [System.Collections.Generic.List[string]]::new()
                $RoleMappings = [System.Collections.Generic.List[object]]::new()

                foreach ($Mapping in @($Request.Body.RoleMappings)) {
                    if ($Mapping) { $RoleMappings.Add($Mapping) }
                }

                $NewRoles = @($Request.Body.NewRoles | Where-Object { $_ })
                if ($NewRoles.Count -gt 0) {
                    $NewMappings = New-CIPPGDAPRoleMapping -Roles $NewRoles -CustomSuffix $Request.Body.CustomSuffix
                    foreach ($Message in $NewMappings.Results) {
                        $SaveResults.Add([string]$Message)
                    }
                    foreach ($Mapping in $NewMappings.RoleMappings) {
                        if ($Mapping.GroupId -notin $RoleMappings.GroupId) {
                            $RoleMappings.Add($Mapping)
                        }
                    }
                }

                if ($OriginalTemplateId -and $OriginalTemplateId -ne $NewTemplateId) {
                    $OldTemplate = $Templates | Where-Object -Property RowKey -EQ $OriginalTemplateId
                    if ($OldTemplate) {
                        Remove-CIPPAzDataTableEntity -Force @Table -Entity $OldTemplate
                        $SaveResults.Add("Renamed template $OriginalTemplateId to $NewTemplateId")
                    }
                }

                Add-CIPPGDAPRoleTemplate -TemplateId $NewTemplateId -RoleMappings @($RoleMappings | Select-Object -Property RoleName, GroupName, GroupId, roleDefinitionId) -Overwrite
                $SaveResults.Add("Saved template $NewTemplateId")
                Write-LogMessage -headers $Headers -API $APIName -message "Saved GDAP role template '$NewTemplateId' with $($RoleMappings.Count) role mappings" -Sev 'Info'
                $Body = @{
                    Results = @($SaveResults)
                }
            }
            'Edit' {
                # Use OriginalTemplateId if provided (for rename), otherwise use TemplateId
                $OriginalRowKey = $Request.Body.OriginalTemplateId ?? $Request.Body.TemplateId
                $NewRowKey = $Request.Body.TemplateId
                $Template = $Templates | Where-Object -Property RowKey -EQ $OriginalRowKey
                if ($Template) {
                    $RoleMappings = $Request.Body.RoleMappings

                    # If the template ID is being changed, delete the old one and create a new one
                    if ($OriginalRowKey -ne $NewRowKey) {
                        Remove-CIPPAzDataTableEntity -Force @Table -Entity $Template
                        Add-CIPPGDAPRoleTemplate -TemplateId $NewRowKey -RoleMappings $RoleMappings -Overwrite
                        Write-LogMessage -headers $Headers -API $APIName -message "Renamed GDAP template from '$OriginalRowKey' to '$NewRowKey' and updated role mappings" -Sev 'Info'
                        $Body = @{
                            Results = "Renamed template from $OriginalRowKey to $NewRowKey and updated role mappings"
                        }
                    } else {
                        # Just update the existing template
                        Add-CIPPGDAPRoleTemplate -TemplateId $NewRowKey -RoleMappings $RoleMappings -Overwrite
                        Write-LogMessage -headers $Headers -API $APIName -message "Updated role mappings for GDAP template '$NewRowKey'" -Sev 'Info'
                        $Body = @{
                            Results = "Updated role mappings for template $NewRowKey"
                        }
                    }
                } else {
                    Write-LogMessage -headers $Headers -API $APIName -message "GDAP role template '$OriginalRowKey' not found for editing" -sev 'Warning'
                    $Body = @{
                        Results = "Template $OriginalRowKey not found"
                    }
                }
            }
            'Delete' {
                $RowKey = $Request.Body.TemplateId
                $Template = $Templates | Where-Object -Property RowKey -EQ $RowKey
                if ($Template) {
                    Remove-CIPPAzDataTableEntity -Force @Table -Entity $Template
                    Write-LogMessage -headers $Headers -API $APIName -message "Deleted GDAP role template '$RowKey'" -Sev 'Info'
                    $Body = @{
                        Results = "Deleted template $RowKey"
                    }
                } else {
                    Write-LogMessage -headers $Headers -API $APIName -message "GDAP role template '$RowKey' not found for deletion" -sev 'Warning'
                    $Body = @{
                        Results = "Template $RowKey not found"
                    }
                }
            }
            default {
                Write-LogMessage -headers $Headers -API $APIName -message "Retrieved $($Templates.Count) GDAP role templates" -Sev 'Info'
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

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
