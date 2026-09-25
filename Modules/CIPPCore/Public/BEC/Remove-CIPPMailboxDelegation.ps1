function Remove-CIPPMailboxDelegation {
    <#
    .SYNOPSIS
        Removes mailbox delegations of every type the BEC inventory reports.
    .DESCRIPTION
        Takes delegation rows shaped like Get-CIPPBecMailboxInventory's Delegations output
        ({ PermissionType, Trustee, Identity, AccessRights }) and removes each one: FullAccess, SendAs
        and SendOnBehalf through Set-CIPPMailboxPermission, folder rights through
        Remove-CIPPFolderPermission (by folder id, so localised folder names do not matter) and
        resource delegates through Set-CalendarProcessing. One failure never stops the rest.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserPrincipalName
        The mailbox.
    .PARAMETER Delegations
        The delegation rows to remove.
    .PARAMETER Headers
        CIPP request headers for logging.
    .PARAMETER APIName
        Logging API name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [Parameter(Mandatory = $true)]$Delegations,
        $Headers,
        [string]$APIName = 'BECRemediate'
    )

    $Results = [System.Collections.Generic.List[object]]::new()
    foreach ($Delegation in @($Delegations | Where-Object { $_ })) {
        $Type = [string]$Delegation.PermissionType
        $Trustee = [string]$Delegation.Trustee
        $Target = "$Type $Trustee"
        if ([string]::IsNullOrWhiteSpace($Trustee)) {
            $Results.Add([pscustomobject]@{ Target = $Target; state = 'error'; resultText = "A $Type delegation without a trustee cannot be removed" })
            continue
        }
        if (-not $PSCmdlet.ShouldProcess("$UserPrincipalName $Target", 'Remove delegation')) { continue }
        try {
            switch ($Type) {
                { $_ -in @('FullAccess', 'SendAs', 'SendOnBehalf') } {
                    $null = Set-CIPPMailboxPermission -UserId $UserPrincipalName -AccessUser $Trustee -PermissionLevel $Type -Action 'Remove' -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers
                    $Text = "Removed $Type for $Trustee from $UserPrincipalName"
                }
                'Folder' {
                    $FolderIdentity = if ($Delegation.Identity) { [string]$Delegation.Identity } else { [string]$Delegation.Resource }
                    $null = Remove-CIPPFolderPermission -TenantFilter $TenantFilter -FolderIdentity $FolderIdentity -User $Trustee -AccessRights ([string]$Delegation.AccessRights) -Anchor $UserPrincipalName
                    $Text = "Removed folder permission for $Trustee on $($Delegation.Resource ?? $FolderIdentity)"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Text -Sev 'Info'
                }
                'ResourceDelegate' {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-CalendarProcessing' -cmdParams @{ Identity = $UserPrincipalName; ResourceDelegates = @{ '@odata.type' = '#Exchange.GenericHashTable'; remove = @($Trustee) } } -Anchor $UserPrincipalName
                    $Text = "Removed resource delegate $Trustee from $UserPrincipalName"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Text -Sev 'Info'
                }
                default { throw "Unknown delegation type '$Type'" }
            }
            $Results.Add([pscustomobject]@{ Target = $Target; state = 'success'; resultText = $Text })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Text = "Failed to remove $Type for $Trustee from $UserPrincipalName`: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Text -Sev 'Error' -LogData $ErrorMessage
            $Results.Add([pscustomobject]@{ Target = $Target; state = 'error'; resultText = $Text })
        }
    }
    return $Results.ToArray()
}
