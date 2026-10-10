function ConvertTo-CippReportPdf {
    <#
    .SYNOPSIS
        Render a report component tree to PDF bytes server-side.
    .DESCRIPTION
        Thin wrapper over the CIPPSharp component kit ([CIPP.Reporting.ReportPdf]::Render), which is
        loaded with CIPPCore via RequiredAssemblies. Takes the declarative component tree (Report
        Builder blocks, or a fixed report's composed component nodes), the resolved branding, and the
        %variable% values, and returns the finished PDF as a byte array. All layout lives in the shared
        component kit - callers never touch OfficeIMO.
    .PARAMETER Blocks
        The component tree: an array of block/component nodes, or a JSON string of the same.
    .PARAMETER Branding
        Branding settings as an object or JSON string. Omit it to render against the tenant/global
        branding settings, or name a preset with -BrandingPresetId (a missing preset falls back to the
        settings, so a report is always branded).
    .PARAMETER Variables
        %variable% values for footer/watermark/cover text, as a hashtable or JSON string.
    .PARAMETER TenantName
        Client name shown on the cover and available as %tenantname%.
    .PARAMETER ReportName
        Report title shown on the cover and in the page header.
    .PARAMETER GeneratedOn
        Human-readable generation date shown on the cover / available as %reportdate%. Defaults to today
        in the instance's timezone (CIPP_TIMEZONE), not the container's UTC clock.
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory = $true)]$Blocks,
        $Branding,
        [string]$BrandingPresetId,
        $Variables,
        [string]$TenantName = 'Organization',
        [string]$ReportName = 'Report',
        [string]$GeneratedOn,
        [string]$PageSize = 'A4',
        [switch]$Landscape,
        # The tenant whose %variables% (global + tenant custom vars + built-ins like %cippurl%) resolve
        # the branding footer/watermark and cover text. Omit to skip variable replacement.
        [string]$TenantFilter
    )

    # The client prints the viewer's date; the server prints today in the instance's timezone (set at
    # warmup from the configured or region timezone), else UTC.
    if (-not $PSBoundParameters.ContainsKey('GeneratedOn')) {
        $Zone = try { [TimeZoneInfo]::FindSystemTimeZoneById([string]$env:CIPP_TIMEZONE) } catch { [TimeZoneInfo]::Utc }
        $GeneratedOn = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $Zone).ToString('MMMM d, yyyy', [cultureinfo]'en-US')
    }

    if ($null -eq $Branding) {
        $Branding = try {
            $Preset = if ($BrandingPresetId) { Get-CIPPBrandingPreset -Id $BrandingPresetId | Select-Object -First 1 }
            if ($Preset) { $Preset } else { Get-CIPPBrandingSettings }
        } catch { @{} }
    }

    # An Infographic page can use a cover from the branding gallery ('gallery:<id>', as the report
    # builder stores it); the renderer takes image bytes, so the image is read here. An image that is
    # gone leaves the page's plain background rather than failing the report.
    if ($Blocks -isnot [string]) {
        foreach ($Block in @($Blocks)) {
            $HeroImage = [string]$Block.heroImage
            if ($Block.type -ne 'hero' -or $HeroImage -notlike 'gallery:*') { continue }
            $Image = try { Get-CIPPImage -PartitionKey 'brandingCover' -Id $HeroImage.Substring(8) } catch { $null }
            $Resolved = if ($Image.data) { [string]$Image.data } else { '' }
            if ($Block -is [System.Collections.IDictionary]) { $Block['heroImage'] = $Resolved }
            else { $Block | Add-Member -NotePropertyName 'heroImage' -NotePropertyValue $Resolved -Force }
        }
    }

    # Accept objects or pre-serialised JSON for each structured input.
    $BlocksJson = if ($Blocks -is [string]) { $Blocks } else { ConvertTo-Json -InputObject @($Blocks) -Depth 20 -Compress }
    $BrandingJson = if ($null -eq $Branding) { '{}' } elseif ($Branding -is [string]) { $Branding } else { ConvertTo-Json -InputObject $Branding -Depth 10 -Compress }
    $VariablesJson = if ($null -eq $Variables) { '{}' } elseif ($Variables -is [string]) { $Variables } else { ConvertTo-Json -InputObject $Variables -Depth 5 -Compress }

    # Resolve CIPP %variables% (%cippurl%, %tenantname%, custom CippReplacemap vars, ...) through the one
    # central replacement script, JSON-escaped so a value splices safely into these serialized strings.
    # The branding footer/watermark and cover text carry these tokens; unknown tokens are left as written
    # for the component kit to substitute (report-specific vars like %footerlabel%). No-op without a tenant.
    if (-not [string]::IsNullOrWhiteSpace($TenantFilter)) {
        # %tenantname% names the tenant the way the report does (the branding's tenantLabel, resolved
        # by the caller into -TenantName) rather than the way the tenant cache does, so a footer and
        # the cover agree. Substituted before the general replacement, which would use the cache.
        if ($PSBoundParameters.ContainsKey('TenantName')) {
            $EscapedName = (ConvertTo-Json -InputObject $TenantName -Compress).Trim('"')
            $BrandingJson = [regex]::Replace($BrandingJson, '%tenantname%', $EscapedName, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
        $BrandingJson = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $BrandingJson -EscapeForJson
        $VariablesJson = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $VariablesJson -EscapeForJson
    }

    # Unary comma: return the byte[] as a single object so PowerShell does not unroll it into a stream
    # of bytes (which would reach callers as object[] and only work by implicit coercion).
    return , [CIPP.Reporting.ReportPdf]::Render(
        $BlocksJson, $BrandingJson, $VariablesJson,
        $TenantName, $ReportName, $GeneratedOn,
        $PageSize, [bool]$Landscape
    )
}
