function Invoke-CIPPBaselineTenantAllowBlockListTemplate {
    <#
    .SYNOPSIS
        TenantAllowBlockListTemplate executor: adds the missing entries.
    .DESCRIPTION
        Adds ONLY the entries the hook found missing - this family is strictly additive, and
        submitting an entry that already exists fails the whole batch, which is exactly why
        the classic pre-filtered too.

        The action parameter is DYNAMIC: the template's listMethod ('Allow' or 'Block')
        becomes the switch name on New-TenantAllowBlockListItems. Expiration is carried from
        the template: NoExpiration, or the classic's fixed 45-day RemoveAfter, or the cmdlet
        default when neither is set.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Missing = @($Current.missingEntries | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") })
    $Template = $Current.templateBody
    if ($Missing.Count -eq 0 -or -not $Template) { return }

    $ListMethod = "$($Template.listMethod)"
    if ($ListMethod -notin @('Allow', 'Block')) {
        throw "Tenant Allow/Block List template '$($Template.templateName)' has an invalid list method '$ListMethod'."
    }

    $CmdParams = @{
        Entries     = @($Missing)
        ListType    = "$($Template.listType)"
        Notes       = "$($Template.notes)"
        $ListMethod = $true
    }
    if ($Template.NoExpiration -eq $true) {
        $CmdParams.NoExpiration = $true
    } elseif ($Template.RemoveAfter -eq $true) {
        $CmdParams.RemoveAfter = 45
    }

    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-TenantAllowBlockListItems' -cmdParams $CmdParams
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Added $($Missing.Count) $ListMethod entries to the $($Template.listType) list from template '$($Template.templateName)'." -Sev 'Info'
}
