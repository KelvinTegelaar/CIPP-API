function Invoke-ExecGDAPRepairRoleMappings {
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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Results = [System.Collections.Generic.List[object]]::new()

    try {
        # Fetch the partner tenant security groups once and reuse them for every store we repair.
        # Groups recreated by one pass are appended so later passes re-link instead of creating duplicates.
        $PartnerGroups = [System.Collections.Generic.List[object]]::new()
        foreach ($Group in (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$filter=securityEnabled eq true&$select=id,displayName&$top=999' -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true)) {
            $PartnerGroups.Add($Group)
        }
        $AddCreatedGroups = {
            param($Check)
            foreach ($Created in ($Check.Results | Where-Object { $_.Status -eq 'Created' })) {
                $PartnerGroups.Add([PSCustomObject]@{ id = $Created.GroupId; displayName = $Created.GroupName })
            }
        }

        # Repair the GDAPRoles registry (stale group ids are remapped to the existing "M365 GDAP" group)
        $RolesTable = Get-CIPPTable -TableName 'GDAPRoles'
        $StoredRoles = Get-CIPPAzDataTableEntity @RolesTable -Filter "PartitionKey eq 'Roles'"
        if (($StoredRoles | Measure-Object).Count -gt 0) {
            $RoleCheck = Test-CIPPGDAPGroupMappings -RoleMappings $StoredRoles -PartnerGroups @($PartnerGroups) -CreateMissing -WriteBack -APIName $APIName -Headers $Headers
            & $AddCreatedGroups $RoleCheck
            foreach ($Result in $RoleCheck.Results) {
                if ($Result.Status -in @('Stale', 'Created')) {
                    $Results.Add(@{ resultText = "GDAP Roles: $($Result.Message)"; state = 'success' })
                } elseif ($Result.Status -eq 'Missing') {
                    $Results.Add(@{ resultText = "GDAP Roles: $($Result.Message)"; state = 'error' })
                }
            }
        }

        # Repair every saved role template so onboarding/reset use the corrected group ids
        $TemplatesTable = Get-CIPPTable -TableName 'GDAPRoleTemplates'
        $Templates = Get-CIPPAzDataTableEntity @TemplatesTable -Filter "PartitionKey eq 'RoleTemplate'"
        foreach ($Template in $Templates) {
            try {
                $TemplateMappings = $Template.RoleMappings | ConvertFrom-Json
            } catch {
                $TemplateMappings = @()
            }
            if (($TemplateMappings | Measure-Object).Count -eq 0) { continue }

            $TemplateCheck = Test-CIPPGDAPGroupMappings -RoleMappings $TemplateMappings -PartnerGroups @($PartnerGroups) -CreateMissing -TemplateId $Template.RowKey -APIName $APIName -Headers $Headers
            & $AddCreatedGroups $TemplateCheck
            foreach ($Result in $TemplateCheck.Results) {
                if ($Result.Status -in @('Stale', 'Created')) {
                    $Results.Add(@{ resultText = "Template '$($Template.RowKey)': $($Result.Message)"; state = 'success' })
                } elseif ($Result.Status -eq 'Missing') {
                    $Results.Add(@{ resultText = "Template '$($Template.RowKey)': $($Result.Message)"; state = 'error' })
                }
            }
        }

        if ($Results.Count -eq 0) {
            $Results.Add(@{ resultText = 'All GDAP role mappings already reference existing security groups'; state = 'success' })
        }

        # Refresh the cached GDAP access check so the card reflects the repair immediately
        $null = Test-CIPPGDAPRelationships -Headers $Headers

        Write-LogMessage -headers $Headers -API $APIName -message 'Repaired GDAP role mappings' -Sev 'Info'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results.Add(@{ resultText = "Failed to repair GDAP role mappings: $($ErrorMessage.NormalizedError)"; state = 'error' })
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to repair GDAP role mappings: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = @($Results) }
        })
}
