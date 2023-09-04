function Set-CIPPGDAPInviteGroups {
    Param()
    $Table = Get-CIPPTable -TableName 'GDAPInvites'
    $InviteList = Get-AzDataTableEntity @Table

    if (($InviteList | Measure-Object).Count -gt 0) {
        #$LastDay = Get-Date (Get-Date).AddHours(-26) -UFormat '+%Y-%m-%dT%H:%M:%S.000Z'
        #$NewActivations = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$filter=((status eq 'active') and (activatedDateTime gt $LastDay))"
        $Activations = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$filter=status eq 'active'"

        foreach ($Activation in $Activations) {
            if ($InviteList.RowKey -contains $Activation.id) {
                Write-Host "Mapping groups for GDAP relationship: $($Activation.id)"
                Push-OutputBinding -Name Msg -Value $Activation.id
            }
        }
    }
}
