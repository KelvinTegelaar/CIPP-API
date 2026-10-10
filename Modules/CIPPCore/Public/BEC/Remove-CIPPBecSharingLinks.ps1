function Remove-CIPPBecSharingLinks {
    <#
    .SYNOPSIS
        Revokes the sharing links a compromised user created on OneDrive/SharePoint items.
    .DESCRIPTION
        BEC containment for exfiltration links. The run records each sharing change as the item's URL
        (the audit log's ObjectId), not as a drive/item/permission triple, so this resolves every URL
        to its drive item through the Graph /shares endpoint, then deletes the link permissions on it.

        Only link permissions are removed (anonymous "anyone" links and organization/company links) -
        direct user grants and inherited permissions are left alone. Each URL is handled in its own
        try/catch so one unreachable item never stops the rest, and a row is returned per outcome in
        the { Target, state, resultText, copyField } shape the containment dispatcher expects.

        Unlike disabling OneDrive sharing (which only turns off the capability), this revokes links that
        already exist and are the actual exposure.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserPrincipalName
        The user the links belong to (for logging).
    .PARAMETER ItemUrls
        The item URLs to revoke links on - the ItemUrl of each flagged sharing change.
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
        [string]$UserPrincipalName,
        [string[]]$ItemUrls,
        $Headers,
        [string]$APIName = 'BECRemediate'
    )

    $Rows = [System.Collections.Generic.List[object]]::new()
    $Add = {
        param($Target, $State, $Text)
        $Rows.Add([pscustomobject]@{ Target = $Target; state = $State; resultText = $Text; copyField = $null })
    }

    # Graph addresses a shared item by "u!" + base64url of its URL (no padding, +/ -> -_). Any item URL
    # the caller can reach resolves this way, which is why the audit-log ObjectId is enough to act on.
    $ToShareId = {
        param($Url)
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Url)
        'u!' + ([System.Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('/', '_').Replace('+', '-'))
    }

    foreach ($Url in @($ItemUrls | Where-Object { $_ } | Select-Object -Unique)) {
        try {
            $ShareId = & $ToShareId $Url
            $Item = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/shares/$ShareId/driveItem?`$select=id,name,webUrl,parentReference&`$expand=permissions" -tenantid $TenantFilter -AsApp $true -noPagination $true
            $DriveId = $Item.parentReference.driveId
            $ItemId = $Item.id
            $Name = $Item.name ?? $Url
            if (-not $DriveId -or -not $ItemId) { & $Add $Url 'error' "Could not resolve a drive item for $Url"; continue }

            # Only link permissions are sharing links; a direct grant has no .link. Inherited ones cannot
            # be deleted on the child, so skip them rather than fail on the 400 they return.
            $Links = @($Item.permissions | Where-Object { $_.link -and -not $_.inheritedFrom })
            if ($Links.Count -eq 0) { & $Add $Name 'info' "No sharing-link permissions remain on $Name"; continue }
            foreach ($Perm in $Links) {
                $Scope = $Perm.link.scope ?? 'link'
                if (-not $PSCmdlet.ShouldProcess($Name, "Remove the $Scope sharing link")) { continue }
                try {
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/drives/$DriveId/items/$ItemId/permissions/$($Perm.id)" -tenantid $TenantFilter -type DELETE -AsApp $true
                    & $Add $Name 'success' "Removed the $Scope sharing link on $Name"
                } catch {
                    $PermError = Get-CippException -Exception $_
                    & $Add $Name 'error' "Failed to remove the $Scope link on $Name`: $($PermError.NormalizedError)"
                }
            }
        } catch {
            $ItemError = Get-CippException -Exception $_
            & $Add $Url 'error' "Could not read sharing links for $Url`: $($ItemError.NormalizedError)"
        }
    }

    if ($Headers) {
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Removed sharing links for $UserPrincipalName ($(@($Rows | Where-Object { $_.state -eq 'success' }).Count) link(s) revoked)" -Sev 'Info'
    }
    return $Rows.ToArray()
}
