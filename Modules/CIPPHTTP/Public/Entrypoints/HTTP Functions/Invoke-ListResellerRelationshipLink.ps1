function Invoke-ListResellerRelationshipLink {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $StatusCode = [HttpStatusCode]::OK
    $Body = @{}

    # Get the indirect reseller relationship invite link
    try {
        $RelationshipRequest = New-GraphGetRequest -uri 'https://api.partnercenter.microsoft.com/v1/customers/relationshiprequests?dualRoleIndirectRelationship=false' -scope 'https://api.partnercenter.microsoft.com/.default' -NoAuthCheck $true
        $Body.inviteUrl = $RelationshipRequest.url
    } catch {
        $Body.inviteUrl = $null
        $Body.inviteUrlError = "Failed to retrieve relationship invite link: $($_.Exception.Message)"
        Write-Information "ListResellerRelationshipLink: Failed to get invite URL - $($_.Exception.Message)"
    }

    # Get indirect providers (for Tier 2 / indirect resellers)
    try {
        $RelationshipsResponse = New-GraphGetRequest -uri 'https://api.partnercenter.microsoft.com/v1/relationships?relationship_type=IsIndirectResellerOf' -scope 'https://api.partnercenter.microsoft.com/.default' -NoAuthCheck $true
        $Body.indirectProviders = @($RelationshipsResponse.items)
    } catch {
        $Body.indirectProviders = @()
        Write-Information "ListResellerRelationshipLink: Failed to get indirect providers - $($_.Exception.Message)"
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }
}
