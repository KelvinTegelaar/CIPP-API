function Invoke-ListBrandingSettings {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.User.Read
    .DESCRIPTION
        Returns the report branding: colours, logo and cover images, footer and watermark text.

        This used to ride along inside ListUserSettings, which meant every page load carried every
        uploaded cover as an inline data URL — megabytes of images fetched to render a settings
        menu. Worse, hydrating branding also ran the legacy-image migration, so a GET issued on
        every page load wrote the BrandingSettings row back from a snapshot it had read moments
        earlier, and any upload that landed in between was overwritten.

        Branding therefore has its own endpoint, fetched by the things that actually draw it, and
        this read never writes. Migration belongs to ExecBrandingSettings -Action Get: the settings
        page opening is a deliberate, infrequent, single-user action, which is the one place where
        rewriting the row is safe.

        Its role matches ListUserSettings rather than the branding write role — every user who
        renders a report needs the branding on it, and that is exactly who could read it before.
    .PARAMETER includeGallery
        Return every uploaded logo and cover, not just the selected ones.

        Only the branding settings page needs the galleries, and it is the difference between a
        response of a few hundred KB and one of several MB: the uploads are inline base64 and an
        MSP accumulates them. A report needs the logo and cover that are actually selected, which
        `logo` and `coverImage` already carry, so it asks for neither list.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $IncludeGallery = [bool]::TryParse("$($Request.Query.includeGallery)", [ref]$null) -and [bool]::Parse("$($Request.Query.includeGallery)")

    try {
        $Branding = Get-CIPPBrandingSettings
        if ($Branding -and -not $IncludeGallery) {
            # The ids stay: they are what tells the caller a gallery exists and what is selected in
            # it. Only the payloads are dropped.
            $Branding | Add-Member -MemberType NoteProperty -Name 'logoUploads' -Value ([string[]]@()) -Force
            $Branding | Add-Member -MemberType NoteProperty -Name 'coverUploads' -Value ([string[]]@()) -Force
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        # Branding is chrome. A report rendered with default colours is worth far more than an
        # error where the report should be, so this degrades to the defaults rather than failing.
        Write-LogMessage -API $APIName -tenant 'Global' -headers $Request.Headers -message "Failed to load branding settings: $($_.Exception.Message)" -Sev 'Error'
        $Branding = $null
        $StatusCode = [HttpStatusCode]::OK
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Branding
        })
}
