function Invoke-ListGDAPInvite {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.Read
    .DESCRIPTION
        Lists GDAP relationship invitations and their role mappings, optionally filtered by relationship ID.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $RelationshipId = $Request.Query.RelationshipId

    $Table = Get-CIPPTable -TableName 'GDAPInvites'

    $ResolveOnboardingUrl = {
        param($InviteRow)
        if (![string]::IsNullOrWhiteSpace($InviteRow.OnboardingUrl)) {
            return $InviteRow
        }
        if ([string]::IsNullOrWhiteSpace($InviteRow.RowKey)) {
            return $InviteRow
        }
        $Hostname = Get-CIPPHostname -Headers $Request.Headers -PreferCustomDomain
        if ($Hostname) {
            $InviteRow.OnboardingUrl = "https://$Hostname/tenant/gdap-management/onboarding/start?id=$($InviteRow.RowKey)"
        }
        return $InviteRow
    }

    if (![string]::IsNullOrEmpty($RelationshipId)) {
        $SafeRelationshipId = ConvertTo-CIPPODataFilterValue -Value $RelationshipId -Type String
        $Invite = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$SafeRelationshipId'" | ForEach-Object { & $ResolveOnboardingUrl $_ }
    } else {
        $Invite = Get-CIPPAzDataTableEntity @Table | ForEach-Object {
            $_.RoleMappings = @(try { $_.RoleMappings | ConvertFrom-Json } catch { $_.RoleMappings })
            & $ResolveOnboardingUrl $_
        }
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Invite)
        })
}
