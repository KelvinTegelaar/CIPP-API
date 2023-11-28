using namespace System.Net

Function Invoke-ExecGDAPInviteQueue {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    #$TenantFilter = $env:TenantID

    $Table = Get-CIPPTable -TableName 'GDAPInvites'
    $Invite = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$QueueItem'"
    $APINAME = 'GDAPInvites'
    $RoleMappings = $Invite.RoleMappings | ConvertFrom-Json
    Write-Host ($Invite | ConvertTo-Json -Compress)

    foreach ($role in $RoleMappings) {
        try {
            $Mappingbody = ConvertTo-Json -Depth 10 -InputObject @{
                'accessContainer' = @{
                    'accessContainerId'   = "$($Role.GroupId)"
                    'accessContainerType' = 'securityGroup'
                }
                'accessDetails'   = @{
                    'unifiedRoles' = @(@{
                            'roleDefinitionId' = "$($Role.roleDefinitionId)"
                        })
                }
            }
            New-GraphPostRequest -NoAuthCheck $True -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$($QueueItem)/accessAssignments" -tenantid $env:TenantID -type POST -body $MappingBody -verbose
            Start-Sleep -Milliseconds 100
        } catch {
            Write-LogMessage -API $APINAME -message "GDAP Group mapping failed - $($role.GroupId): $($_.Exception.Message)" -Sev Error
            exit 1
        }
        Write-LogMessage -API $APINAME -message "Groups mapped for GDAP Relationship: $($GdapInvite.RowKey)" -Sev Info
    }
    Remove-AzDataTableEntity @Table -Entity $Invite

}
