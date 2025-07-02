using namespace System.Net

function Invoke-ListGDAPRoles {
    <#
    .SYNOPSIS
    List Granular Delegated Admin Privileges (GDAP) roles
    
    .DESCRIPTION
    Retrieves a list of GDAP roles and their associated groups for delegated administration
    
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.Read
        
    .NOTES
    Group: GDAP
    Summary: List GDAP Roles
    Description: Retrieves a list of Granular Delegated Admin Privileges (GDAP) roles and their associated groups for delegated administration scenarios
    Tags: GDAP,Delegated Administration,Roles
    Response: Returns an array of GDAP role objects with the following properties:
    Response: - GroupName (string): Name of the Azure AD group associated with the role
    Response: - GroupId (string): Unique identifier of the Azure AD group
    Response: - RoleName (string): Display name of the GDAP role
    Response: - roleDefinitionId (string): Unique identifier of the role definition
    Example: [
      {
        "GroupName": "Help Desk Administrators",
        "GroupId": "12345678-1234-1234-1234-123456789012",
        "RoleName": "Helpdesk Administrator",
        "roleDefinitionId": "729827e3-9c14-49f7-bb1b-9608f691bbb4"
      },
      {
        "GroupName": "Security Administrators",
        "GroupId": "87654321-4321-4321-4321-210987654321",
        "RoleName": "Security Administrator",
        "roleDefinitionId": "194ae4cb-b126-40b2-bd5b-6091b3809bad"
      }
    ]
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

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($MappedGroups)
        })

}
