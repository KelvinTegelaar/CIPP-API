function Invoke-ListBrandingSettings {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.User.Read
    .DESCRIPTION
        Returns the report branding: colours, logo and cover images, footer and watermark text.

        Branding was previously returned by ListUserSettings, which put every uploaded cover
        inline on every page load and ran the legacy-image migration - a write - on that read
        path. This read never writes; migration belongs to ExecBrandingSettings -Action Get.

        The role matches ListUserSettings rather than the branding write role, since every user
        who renders a report needs the branding on it.
    .PARAMETER includeGallery
        Return every uploaded logo and cover, not just the selected ones. Only the branding
        settings page needs them, and inline base64 makes it the difference between a response of
        a few hundred KB and several MB. A report uses `logo` and `coverImage`, returned either way.
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
