function Invoke-ListGDAPAccessAssignments {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Id = $Request.Query.Id
    $TenantFilter = $env:TenantID

    Write-Information "Getting access assignments for $Id"

    $AccessAssignments = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$Id/accessAssignments" -tenantid $TenantFilter

    # get groups asapp
    $Groups = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/groups?`$top=999&`$select=id,displayName&`$filter=securityEnabled eq true" -tenantid $TenantFilter -asApp $true -NoAuthCheck $true


    # Get all the access containers
    $AccessContainers = $AccessAssignments.accessContainer.accessContainerId
    Write-Information "Getting access containers for $($AccessContainers -join ',')"

    $ContainerMembers = foreach ($AccessContainer in $AccessContainers) {
        @{
            'id'     = $AccessContainer
            'url'    = "groups/$AccessContainer/members?`$select=id,displayName,userPrincipalName,isAssignableToRole&`$top=999"
            'method' = 'GET'
        }
    }
    $Members = New-GraphBulkRequest -Requests $ContainerMembers -tenantid $TenantFilter -asApp $true -NoAuthCheck $true

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

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
