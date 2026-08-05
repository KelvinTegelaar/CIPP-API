function Invoke-ListRoles {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.Read
    .DESCRIPTION
        Lists a tenant's Entra ID role definitions along with the active members of each, via the unified RBAC API. Unlike the legacy /directoryRoles endpoint this includes every built-in and custom role definition, even ones with no assignments.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $Definitions = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?$select=id,templateId,displayName,description,isBuiltIn,isEnabled' -tenantid $TenantFilter
        $Assignments = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?$select=id,principalId,roleDefinitionId,directoryScopeId&$top=999' -tenantid $TenantFilter

        # Resolve principals in bulk; $expand=principal costs seconds of Graph server time
        # even for a handful of assignments, while getByIds returns in milliseconds.
        $Principals = @{}
        $PrincipalIds = @($Assignments.principalId | Sort-Object -Unique)
        for ($i = 0; $i -lt $PrincipalIds.Count; $i += 1000) {
            $Body = ConvertTo-Json -InputObject @{ ids = @($PrincipalIds[$i..([Math]::Min($i + 999, $PrincipalIds.Count - 1))]) } -Compress
            $Resolved = New-GraphPOSTRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/v1.0/directoryObjects/getByIds?$select=id,displayName,userPrincipalName' -body $Body
            foreach ($Principal in $Resolved.value) { $Principals[$Principal.id] = $Principal }
        }

        # Group assignments by role definition. A principal assigned at both tenant scope and an
        # administrative-unit scope appears once per scope; keep the first occurrence per principal.
        $MemberMap = @{}
        foreach ($Assignment in $Assignments) {
            if (-not $MemberMap.ContainsKey($Assignment.roleDefinitionId)) {
                $MemberMap[$Assignment.roleDefinitionId] = [System.Collections.Generic.List[object]]::new()
            }
            if ($MemberMap[$Assignment.roleDefinitionId].id -notcontains $Assignment.principalId) {
                $MemberMap[$Assignment.roleDefinitionId].Add([PSCustomObject]@{
                        displayName       = $Principals[$Assignment.principalId].displayName
                        userPrincipalName = $Principals[$Assignment.principalId].userPrincipalName
                        id                = $Assignment.principalId
                        directoryScopeId  = $Assignment.directoryScopeId
                    })
            }
        }

        $GraphRequest = foreach ($Definition in $Definitions) {
            # Built-in definitions have id == templateId; custom roles have templateId = null
            $Members = if ($MemberMap.ContainsKey($Definition.id)) { @($MemberMap[$Definition.id]) } else { @() }
            [PSCustomObject]@{
                Id             = $Definition.id
                roleTemplateId = $Definition.templateId
                DisplayName    = $Definition.displayName
                Description    = $Definition.description
                Members        = @($Members)
                MemberCount    = $Members.Count
                isBuiltIn      = $Definition.isBuiltIn
                isEnabled      = $Definition.isEnabled
                SID            = (Convert-AzureAdObjectIdToSid -ObjectID ($Definition.templateId ?? $Definition.id))
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $GraphRequest = "Failed to list roles for tenant $TenantFilter. $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $GraphRequest
    }
}
