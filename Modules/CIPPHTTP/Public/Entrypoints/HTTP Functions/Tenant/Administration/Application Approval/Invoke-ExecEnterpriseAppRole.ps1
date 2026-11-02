function Invoke-ExecEnterpriseAppRole {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.ReadWrite
    .DESCRIPTION
        Adds or removes Entra directory role assignments held by an enterprise application (service principal).
        Roles are assigned tenant-wide; removal takes the role assignment ids, so assignments scoped to an
        administrative unit can be removed too. The CIPP-SAM application's own roles are refused.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $ServicePrincipalId = "$($Request.Body.ServicePrincipalId)"
    $Action = "$($Request.Body.Action)"
    $Guid = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'

    if (-not $TenantFilter -or $ServicePrincipalId -notmatch $Guid) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantFilter and a valid ServicePrincipalId are required' }
            })
    }
    if ($Action -notin @('Add', 'Remove')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Action must be Add or Remove' }
            })
    }
    $ItemField, $ItemPattern = if ($Action -eq 'Add') { 'RoleDefinitionIds', $Guid } else { 'RoleAssignmentIds', '^[A-Za-z0-9_-]+$' }
    # Autocomplete fields post { label, value } objects.
    $Items = @(foreach ($Item in @($Request.Body.$ItemField)) { if ($Item) { "$($Item.value ?? $Item)".Trim() } })
    if ($Items.Count -eq 0 -or $Items.Where({ $_ -notmatch $ItemPattern }).Count -gt 0) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "$ItemField must hold at least one valid value" }
            })
    }

    $RoleUri = 'https://graph.microsoft.com/v1.0/roleManagement/directory'
    $Results = [System.Collections.Generic.List[object]]::new()
    $Total = 0
    $Failed = 0
    try {
        $Sp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$ServicePrincipalId`?`$select=id,appId,displayName" -tenantid $TenantFilter
        $SamAppId = [System.Environment]::GetEnvironmentVariable('ApplicationID')
        if ($SamAppId -and $Sp.appId -eq $SamAppId) {
            throw [System.ArgumentException]::new('Refusing to change the directory roles of the CIPP-SAM application itself.')
        }
        $RoleNames = @{}
        foreach ($Definition in @(New-GraphGetRequest -uri "$RoleUri/roleDefinitions?`$select=id,displayName" -tenantid $TenantFilter)) {
            if ($Definition.id) { $RoleNames[$Definition.id] = $Definition.displayName }
        }
        # Assignment ids are case-sensitive.
        $Assignments = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
        foreach ($Assignment in @(New-GraphGetRequest -uri "$RoleUri/roleAssignments?`$filter=principalId eq '$ServicePrincipalId'" -tenantid $TenantFilter)) {
            if ($Assignment.id) { $Assignments[$Assignment.id] = $Assignment }
        }

        if ($Action -eq 'Add') {
            $Unknown = $Items.Where({ -not $RoleNames.ContainsKey($_) })
            if ($Unknown.Count -gt 0) {
                throw [System.ArgumentException]::new("Unknown directory role(s): $($Unknown -join ', ')")
            }
            $Held = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($Assignment in $Assignments.Values) {
                if (($Assignment.directoryScopeId ?? '/') -eq '/') { $null = $Held.Add("$($Assignment.roleDefinitionId)") }
            }
            foreach ($RoleDefinitionId in $Items) {
                $Total++
                $Name = $RoleNames[$RoleDefinitionId]
                if ($Held.Contains($RoleDefinitionId)) {
                    $Results.Add([pscustomobject]@{ resultText = "$($Sp.displayName) already holds $Name"; state = 'success' })
                    continue
                }
                try {
                    $Body = ConvertTo-Json -Compress -InputObject @{ principalId = $ServicePrincipalId; roleDefinitionId = $RoleDefinitionId; directoryScopeId = '/' }
                    $null = New-GraphPOSTRequest -uri "$RoleUri/roleAssignments" -tenantid $TenantFilter -type POST -body $Body
                    $Message = "Assigned $Name to $($Sp.displayName)"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
                    $Results.Add([pscustomobject]@{ resultText = $Message; state = 'success' })
                } catch {
                    $Failed++
                    $ErrorMessage = Get-CippException -Exception $_
                    $Message = "Failed to assign $Name to $($Sp.displayName): $($ErrorMessage.NormalizedError)"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
                    $Results.Add([pscustomobject]@{ resultText = $Message; state = 'error' })
                }
            }
        } else {
            if ($Items.Where({ $Assignments.ContainsKey($_) }).Count -eq 0) {
                throw [System.Management.Automation.ItemNotFoundException]::new("None of the role assignments exist on $($Sp.displayName)")
            }
            foreach ($Id in $Items) {
                $Total++
                $Assignment = $null
                if (-not $Assignments.TryGetValue($Id, [ref]$Assignment)) {
                    $Failed++
                    $Results.Add([pscustomobject]@{ resultText = "Role assignment $Id does not exist on $($Sp.displayName)"; state = 'error' })
                    continue
                }
                $Name = $RoleNames["$($Assignment.roleDefinitionId)"] ?? $Assignment.roleDefinitionId
                try {
                    $null = New-GraphPOSTRequest -uri "$RoleUri/roleAssignments/$Id" -tenantid $TenantFilter -type DELETE
                    $Message = "Removed $Name from $($Sp.displayName)"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
                    $Results.Add([pscustomobject]@{ resultText = $Message; state = 'success' })
                } catch {
                    $Failed++
                    $ErrorMessage = Get-CippException -Exception $_
                    $Message = "Failed to remove $Name from $($Sp.displayName): $($ErrorMessage.NormalizedError)"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
                    $Results.Add([pscustomobject]@{ resultText = $Message; state = 'error' })
                }
            }
        }
        $StatusCode = Get-CippBulkStatusCode -Total $Total -Failed $Failed
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to $($Action.ToLower()) directory roles: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        $Results.Add([pscustomobject]@{ resultText = $Message; state = 'error' })
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = @($Results) }
        })
}
