function Invoke-ExecTenantGroup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Config.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'TenantGroups'
    $MembersTable = Get-CippTable -tablename 'TenantGroupMembers'
    $Action = $Request.Body.Action
    $groupId = $Request.Body.groupId ?? [guid]::NewGuid().ToString()
    $groupName = $Request.Body.groupName
    $groupDescription = $Request.Body.groupDescription
    $membersToAdd = $Request.Body.membersToAdd
    $membersToRemove = $Request.Body.membersToRemove

    switch ($Action) {
        'AddEdit' {
            # Update group details
            $GroupEntity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'TenantGroup' and RowKey eq '$groupId'"
            if ($GroupEntity) {
                if ($groupName) {
                    $GroupEntity.groupName = $groupName
                }
                if ($groupDescription) {
                    $GroupEntity.groupDescription = $groupDescription
                }
                Add-CIPPAzDataTableEntity @Table -Entity $GroupEntity -Force
            } else {
                $GroupEntity = @{
                    PartitionKey = 'TenantGroup'
                    RowKey       = $groupId
                    groupName    = $groupName
                    groupDescription = $groupDescription
                }
                Add-CIPPAzDataTableEntity @Table -Entity $GroupEntity -Force
            }

            # Add members
            foreach ($member in $membersToAdd) {
                $MemberEntity = @{
                    PartitionKey = $groupId
                    RowKey       = $member
                }
                Add-CIPPAzDataTableEntity @MembersTable -Entity $MemberEntity -Force
            }

            # Remove members
            foreach ($member in $membersToRemove) {
                $MemberEntity = Get-CIPPAzDataTableEntity @MembersTable -Filter "PartitionKey eq '$groupId' and RowKey eq '$member'"
                if ($MemberEntity) {
                    Remove-AzDataTableEntity @MembersTable -Entity $MemberEntity -Force
                }
            }

            $Body = @{ Results = "Group '$groupName' saved successfully" }
        }
        'Delete' {
            # Delete group
            $GroupEntity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'TenantGroup' and RowKey eq '$groupId'"
            if ($GroupEntity) {
                Remove-AzDataTableEntity @Table -Entity $GroupEntity -Force
                $Body = @{ Results = "Group '$groupId' deleted successfully" }
            } else {
                $Body = @{ Results = "Group '$groupId' not found" }
            }
        }
        default {
            $Body = @{ Results = 'Invalid action' }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
