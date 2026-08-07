function Set-CIPPSharePointPerms {
    <#
    .SYNOPSIS
    Add or remove site collection administrators on a SharePoint or OneDrive site

    .DESCRIPTION
    Sets the IsSiteAdmin flag on the target site's user entry through the SharePoint REST API,
    authenticated app-only with the SAM certificate.

    This replaces a CSOM/SOAP ProcessQuery call to Tenant.SetSiteAdmin against the -admin
    endpoint. That path authenticated delegated (refresh token), so it depended on the GDAP
    identity holding SharePoint Administrator in the customer tenant, and failed with
    'Attempted to perform an unauthorized operation' - or a bare 401 - wherever it did not.
    App-only certificate auth carries the application's own SharePoint permission instead, which
    is the channel the rest of the SharePoint permission endpoints already use.

    .PARAMETER UserId
    The UPN or ID of the user whose OneDrive is being changed. Only used to look up the site URL
    when URL is not supplied.

    .PARAMETER OnedriveAccessUser
    The UPN(s) to add or remove. Accepts a plain string, an array of strings, or the
    { value = ... } objects the frontend autoComplete posts.

    .PARAMETER TenantFilter
    The tenant the site belongs to

    .PARAMETER RemovePermission
    Remove the site collection admin rather than add it

    .PARAMETER URL
    The site collection URL. Derived from the user's OneDrive when omitted.
    #>
    [CmdletBinding()]
    param (
        $UserId,
        [array]$OnedriveAccessUser,
        $TenantFilter,
        $APIName = 'Manage SharePoint Owner',
        $RemovePermission,
        $Headers,
        $URL
    )

    # Normalise to a flat array of UPN strings. Callers pass a plain string, an array of strings,
    # or the { value = ... } objects the frontend autoComplete posts - and the deserialised body
    # is not always a PSCustomObject, so probe for the property rather than testing the type.
    $OnedriveAccessUser = @($OnedriveAccessUser) | ForEach-Object {
        if ($_ -is [string]) { $_ } elseif ($_.value) { $_.value } else { $_ }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if (!$OnedriveAccessUser) {
        throw 'No valid user was supplied to grant or remove OneDrive access for.'
    }

    $IsSiteAdmin = $RemovePermission -ne $true
    $Action = $IsSiteAdmin ? 'added' : 'removed'
    $Results = [system.collections.generic.list[string]]::new()

    try {
        if (!$URL) {
            Write-Information 'No URL provided, getting the OneDrive site URL from Graph'
            # sharepointIds.siteUrl is the site collection root, which is the scope the site admin
            # flag belongs to. The drive's own WebUrl points at the document library
            # ('.../personal/<user>/Documents'), and /drives returns a collection, so WebUrl came
            # back as an array whenever the user had more than one drive.
            $URL = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserId)/drive/root?`$select=sharepointIds" -asapp $true -tenantid $TenantFilter).sharepointIds.siteUrl
            if (!$URL) {
                throw "Could not determine the OneDrive site URL for $UserId. The user may not have a provisioned OneDrive."
            }
        }
        $URL = "$URL".TrimEnd('/')

        # No ListId - site collection admin is a property of the site, not of a library.
        $SPScope = Resolve-CIPPSharePointPermissionScope -SiteUrl $URL -TenantFilter $TenantFilter

        # SharePoint updates an entity with a POST tunnelling MERGE. odata=nometadata lets the body
        # carry just the changed property, without a __metadata type declaration.
        $MergeHeaders = @{
            'X-HTTP-Method' = 'MERGE'
            'IF-MATCH'      = '*'
        }
        foreach ($Header in $SPScope.Headers.GetEnumerator()) {
            $MergeHeaders[$Header.Key] = $Header.Value
        }
        $MergeBody = ConvertTo-Json -Compress -InputObject @{ IsSiteAdmin = $IsSiteAdmin }

        foreach ($AccessUser in $OnedriveAccessUser) {
            try {
                # ensureuser resolves the claims-encoded UPN to a site-local user id, adding the
                # entry to the site if the principal has never been referenced there before.
                $EnsureBody = ConvertTo-Json -Compress -InputObject @{ logonName = "i:0#.f|membership|$AccessUser" }
                $EnsuredUser = New-GraphPostRequest -uri "$($SPScope.BaseUri)/web/ensureuser" -tenantid $TenantFilter -scope $SPScope.Scope -type POST -body $EnsureBody -AddedHeaders $SPScope.Headers -UseCertificate -AsApp $true

                if (!$EnsuredUser.Id) {
                    throw 'Could not resolve the user on the site.'
                }

                $null = New-GraphPostRequest -uri "$($SPScope.BaseUri)/web/getuserbyid($($EnsuredUser.Id))" -tenantid $TenantFilter -scope $SPScope.Scope -type POST -body $MergeBody -AddedHeaders $MergeHeaders -ContentType 'application/json;odata=nometadata' -UseCertificate -AsApp $true

                $Message = "Successfully $Action $AccessUser as a site collection admin of $URL"
                Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev Info -tenant $TenantFilter
                $Results.Add($Message)
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Explanation = Get-CIPPSharePointErrorMessage -ErrorMessage $_.Exception.Message
                $Message = "Failed to change access for $($AccessUser) on $URL - $Explanation"
                Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
                $Results.Add($Message)
            }
        }

        return $Results
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to process SharePoint permissions. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        throw $Message
    }
}
