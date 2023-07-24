function Set-CIPPGDAPInviteGroups {
    Param()
    $Table = Get-CIPPTable -TableName 'GDAPInvites'
    $InviteList = Get-AzDataTableEntity @Table

    $LastDay = Get-Date (Get-Date).AddHours(-26) -UFormat '+%Y-%m-%dT%H:%M:%S.000Z'
    $NewActivations = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$filter=((status eq 'active') and (activatedDateTime gt $LastDay))"

    $NewActivations

    $InviteList
    foreach ($NewActivation in $NewActivations) {
        if ($InviteList.RowKey -contains $NewActivation.id) {
            Write-Host "Mapping groups for GDAP relationship: $($NewActivation.id)"
            Push-OutputBinding -Name Msg -Value $NewActivation.id
        }
    }
}