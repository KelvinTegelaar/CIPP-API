function Set-CIPPGDAPInviteGroups {
    Param()
    $Table = Get-CIPPTable -TableName 'GDAPInvites'
    $InviteList = Get-CIPPAzDataTableEntity @Table

    if (($InviteList | Measure-Object).Count -gt 0) {
        $Activations = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$filter=status eq 'active'"

        foreach ($Activation in $Activations) {
            if ($InviteList.RowKey -contains $Activation.id) {
                Write-Host "Mapping groups for GDAP relationship: $($Activation.customer.displayName) - $($Activation.id)"
                Push-OutputBinding -Name gdapinvitequeue -Value $Activation
            }
        }
    }
}
