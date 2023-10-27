# Input bindings are passed in via param block.
param( $QueueItem, $TriggerMetadata)

# Write out the queue message and metadata to the information log.
Write-Host "PowerShell queue trigger function processed work item: $QueueItem"
#$TenantFilter = $env:TenantID

$Table = Get-CIPPTable -TableName 'GDAPInvites'
$Invite = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$QueueItem'"

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
        Write-LogMessage -API $APINAME -message "GDAP Group mapping failed - $($role.GroupId): $($_.Exception.Message)" -Sev 'Debug'
        exit 1
    }
    Write-LogMessage -API $APINAME -message "Groups mapped for GDAP Relationship: $($GdapInvite.RowKey)"
}
Remove-AzDataTableEntity @Table -Entity $Invite
