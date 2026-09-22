Function Invoke-ListGDAPRoles {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.Read
    .DESCRIPTION
        Lists the configured GDAP role-to-security-group mappings used for delegated admin access.
        Pass ?validate=true to annotate each mapping with the state of its partner tenant group.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $Table = Get-CIPPTable -TableName 'GDAPRoles'
    $Groups = Get-CIPPAzDataTableEntity @Table

    $MappedGroups = foreach ($Group in $Groups) {
        [PSCustomObject]@{
            GroupName        = $Group.GroupName
            GroupId          = $Group.GroupId
            RoleName         = $Group.RoleName
            roleDefinitionId = $Group.roleDefinitionId
        }
    }

    # Opt-in only: other consumers of this endpoint depend on the unannotated shape.
    if ($Request.Query.validate -eq $true -and ($MappedGroups | Measure-Object).Count -gt 0) {
        try {
            # The helper fetches the partner tenant groups itself; keeping Graph out of this
            # entrypoint keeps the documented response shape to the mapping fields.
            $Check = Test-CIPPGDAPGroupMappings -RoleMappings $MappedGroups -APIName $APIName -Headers $Headers

            # A read-only check reports one result per mapping; Valid keeps the original id, the
            # other states carry it as OldGroupId.
            $StatusLookup = @{}
            foreach ($Result in $Check.Results) {
                $Key = if ($Result.OldGroupId) { $Result.OldGroupId } else { $Result.GroupId }
                if ($Key) { $StatusLookup[[string]$Key] = $Result }
            }

            $MappedGroups = foreach ($Group in $MappedGroups) {
                $Status = $StatusLookup[[string]$Group.GroupId]
                [PSCustomObject]@{
                    GroupName          = $Group.GroupName
                    GroupId            = $Group.GroupId
                    RoleName           = $Group.RoleName
                    roleDefinitionId   = $Group.roleDefinitionId
                    GroupStatus        = $Status.Status ?? 'Unknown'
                    GroupStatusMessage = $Status.Message ?? ''
                }
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -headers $Headers -API $APIName -message "Could not validate GDAP group mappings: $($ErrorMessage.NormalizedError)" -Sev 'Warning' -LogData $ErrorMessage
            $MappedGroups = foreach ($Group in $MappedGroups) {
                [PSCustomObject]@{
                    GroupName          = $Group.GroupName
                    GroupId            = $Group.GroupId
                    RoleName           = $Group.RoleName
                    roleDefinitionId   = $Group.roleDefinitionId
                    GroupStatus        = 'Unknown'
                    GroupStatusMessage = ''
                }
            }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($MappedGroups)
        })

}
