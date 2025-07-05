using namespace System.Net

function Invoke-ListGDAPRoles {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'



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

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($MappedGroups)
    }

}
