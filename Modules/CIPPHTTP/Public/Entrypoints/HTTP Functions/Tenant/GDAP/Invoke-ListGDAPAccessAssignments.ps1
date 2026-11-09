function Invoke-ListGDAPAccessAssignments {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.Read
    .DESCRIPTION
        Lists GDAP access assignments for a specific delegated admin relationship, including security group members and their role mappings.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Id = $Request.Query.Id
    if (-not $Id) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Id is required' } })
    }
    # Multi-partner: act as the relationship's source partner (defaults to the primary)
    $PartnerTenantId = $Request.Query.partnerTenantId ?? $Request.Body.partnerTenantId
    if (!$PartnerTenantId -or -not (Get-CIPPPartnerTenantList | Where-Object { $_.partnerTenantId -eq $PartnerTenantId })) {
        $PartnerTenantId = $env:TenantID
    }
    $TenantFilter = $PartnerTenantId

    Write-Information "Getting access assignments for $Id"

    $AccessAssignments = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$Id/accessAssignments" -tenantid $TenantFilter

    # get groups asapp
    $Groups = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/groups?`$top=999&`$select=id,displayName&`$filter=securityEnabled eq true" -tenantid $TenantFilter -asApp $true -NoAuthCheck $true


    # Get all the access containers
    # A group mapped again after a removal has a deleted and an active assignment; a batch id must be unique.
    $AccessContainers = @($AccessAssignments.accessContainer.accessContainerId | Sort-Object -Unique)
    Write-Information "Getting access containers for $($AccessContainers -join ',')"

    $ContainerMembers = foreach ($AccessContainer in $AccessContainers) {
        @{
            'id'     = $AccessContainer
            'url'    = "groups/$AccessContainer/members?`$select=id,displayName,userPrincipalName,isAssignableToRole&`$top=999"
            'method' = 'GET'
        }
    }
    $Members = New-GraphBulkRequest -Requests @($ContainerMembers) -tenantid $TenantFilter -asApp $true -NoAuthCheck $true

    $Results = foreach ($AccessAssignment in $AccessAssignments) {
        [PSCustomObject]@{
            'id'               = $AccessAssignment.id
            'status'           = $AccessAssignment.status
            'createdDateTime'  = $AccessAssignment.createdDateTime
            'modifiedDateTime' = $AccessAssignment.modifiedDateTime
            'roles'            = $AccessAssignment.accessDetails.unifiedRoles
            'group'            = $Groups | Where-Object id -EQ $AccessAssignment.accessContainer.accessContainerId
            'members'          = ($Members | Where-Object id -EQ $AccessAssignment.accessContainer.accessContainerId).body.value
        }
    }
    if (!$Results) {
        $Results = @()
    } else {
        $Results = $Results | Sort-Object -Property @{Expression = { $_.group.displayName }; Ascending = $true }
    }

    $Body = @{
        Results = @($Results)
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
