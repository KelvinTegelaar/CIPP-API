Function Invoke-ExecBrandingSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $StatusCode = [HttpStatusCode]::OK
    @{}

    $AllowedCoverStock = @(
        'none',
        '/reportImages/soc.jpg',
        '/reportImages/board.jpg',
        '/reportImages/glasses.jpg',
        '/reportImages/working.jpg',
        '/reportImages/laptop.jpg',
        '/reportImages/city.jpg'
    )
    $DefaultCoverStock = '/reportImages/soc.jpg'

    function ConvertTo-IdList {
        param($Value)
        # Preserve single-element string[] — `return (…)` unwraps it to a scalar
        # string, which then breaks ConvertTo-IdListJson / [0] indexing.
        $Ids = ConvertTo-CIPPCoverImageIdList -Value $Value
        if ($null -eq $Ids) {
            return , [string[]]@()
        }
        return , [string[]]@($Ids)
    }

    function ConvertTo-IdListJson {
        param($Value)
        $Ids = ConvertTo-IdList -Value $Value
        if ($null -eq $Ids) { $Ids = [string[]]@() }
        # Ids is always a real string[] here — do not use -AsArray (that would
        # wrap a one-element array as [["id"]]).
        return ConvertTo-Json -InputObject ([string[]]$Ids) -Compress
    }

    function Test-ImageIdsExist {
        param(
            [string]$PartitionKey,
            [string[]]$Ids
        )
        $Ids = @($Ids | Where-Object { $_ })
        if ($Ids.Count -eq 0) { return $true }

        if ($Ids.Count -eq 1) {
            $Image = Get-CIPPImage -PartitionKey $PartitionKey -Id @($Ids[0])
            return [bool]$Image
        }

        $Map = Get-CIPPImage -PartitionKey $PartitionKey -Id ([string[]]$Ids)
        if ($Map -isnot [hashtable]) { return $false }
        foreach ($ImageId in $Ids) {
            if (-not $Map.ContainsKey($ImageId)) { return $false }
        }
        return $true
    }

    try {
        $Table = Get-CIPPTable -TableName Config
        $Filter = "PartitionKey eq 'BrandingSettings'"
        $BrandingConfig = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object { $_.RowKey -eq 'BrandingSettings' }

        if (-not $BrandingConfig) {
            $BrandingConfig = @{
                PartitionKey     = 'BrandingSettings'
                RowKey           = 'BrandingSettings'
                colour           = '#F77F00'
                secondaryColour  = ''
                logoImageId      = $null
                logoImageIds     = '[]'
                coverStock       = $DefaultCoverStock
                coverImageId     = $null
                coverImageIds    = '[]'
                footerText       = ''
                coverFooterText  = ''
                showFooter       = $true
                showPageNumbers  = $true
                watermarkText    = ''
                watermarkEnabled = $false
                reportDefaults   = '{}'
                roleColours      = '{}'
            }
        }

        $Action = if ($Request.Body.Action) { $Request.Body.Action } else { $Request.Query.Action }

        $Results = switch ($Action) {
            'Get' {
                Get-CIPPBrandingSettings -PersistMigration
            }
            'UploadImage' {
                $Kind = "$($Request.Body.kind)".ToLowerInvariant()
                $Data = $Request.Body.data
                if ($Kind -eq 'logo') {
                    $PartitionKey = 'logo'
                } elseif ($Kind -eq 'cover') {
                    $PartitionKey = 'brandingCover'
                } else {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: kind must be logo or cover.'
                    break
                }

                try {
                    $Added = Add-CIPPImage -PartitionKey $PartitionKey -Data "$Data"
                    if ($Kind -eq 'logo') {
                        $CurrentIds = ConvertTo-IdList -Value $BrandingConfig.logoImageIds
                        $CurrentIds = @($Added.id) + @($CurrentIds | Where-Object { $_ -ne $Added.id })
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'logoImageIds' -Value (ConvertTo-IdListJson -Value $CurrentIds) -Force
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'logoImageId' -Value $Added.id -Force
                        $BrandingConfig.PartitionKey = 'BrandingSettings'
                        $BrandingConfig.RowKey = 'BrandingSettings'
                        Add-CIPPAzDataTableEntity @Table -Entity $BrandingConfig -Force | Out-Null
                    } elseif ($Kind -eq 'cover') {
                        $CurrentIds = ConvertTo-IdList -Value $BrandingConfig.coverImageIds
                        $CurrentIds = @($Added.id) + @($CurrentIds | Where-Object { $_ -ne $Added.id })
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'coverImageIds' -Value (ConvertTo-IdListJson -Value $CurrentIds) -Force
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'coverImageId' -Value $Added.id -Force
                        $BrandingConfig.PartitionKey = 'BrandingSettings'
                        $BrandingConfig.RowKey = 'BrandingSettings'
                        Add-CIPPAzDataTableEntity @Table -Entity $BrandingConfig -Force | Out-Null
                    }
                    Write-LogMessage -API $APIName -tenant 'Global' -headers $Request.Headers -message "Uploaded branding $Kind image $($Added.id)" -Sev 'Info'
                    $Added
                } catch {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    "Error: $($_.Exception.Message)"
                }
            }
            'DeleteImage' {
                $Kind = "$($Request.Body.kind)".ToLowerInvariant()
                $ImageId = "$($Request.Body.id)"
                if (-not $ImageId) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: id is required.'
                    break
                }
                if ($Kind -eq 'logo') {
                    $PartitionKey = 'logo'
                    Remove-CIPPImage -PartitionKey $PartitionKey -Id $ImageId
                    $CurrentIds = @(ConvertTo-IdList -Value $BrandingConfig.logoImageIds | Where-Object { $_ -ne $ImageId })
                    $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'logoImageIds' -Value (ConvertTo-IdListJson -Value $CurrentIds) -Force
                    if ("$($BrandingConfig.logoImageId)" -eq $ImageId) {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'logoImageId' -Value '' -Force
                    }
                } elseif ($Kind -eq 'cover') {
                    $PartitionKey = 'brandingCover'
                    Remove-CIPPImage -PartitionKey $PartitionKey -Id $ImageId
                    $CurrentIds = @(ConvertTo-IdList -Value $BrandingConfig.coverImageIds | Where-Object { $_ -ne $ImageId })
                    $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'coverImageIds' -Value (ConvertTo-IdListJson -Value $CurrentIds) -Force
                    if ("$($BrandingConfig.coverImageId)" -eq $ImageId) {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'coverImageId' -Value '' -Force
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'coverStock' -Value 'none' -Force
                    }
                } else {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: kind must be logo or cover.'
                    break
                }

                $BrandingConfig.PartitionKey = 'BrandingSettings'
                $BrandingConfig.RowKey = 'BrandingSettings'
                Add-CIPPAzDataTableEntity @Table -Entity $BrandingConfig -Force | Out-Null
                Write-LogMessage -API $APIName -tenant 'Global' -headers $Request.Headers -message "Deleted branding $Kind image $ImageId" -Sev 'Info'
                'Successfully deleted image'
            }
            'Set' {
                $Updated = $false
                $ErrorMessage = $null

                if ($Request.Body.colour) {
                    $Colour = $Request.Body.colour
                    if ($Colour -match '^#[0-9A-Fa-f]{6}$') {
                        $BrandingConfig.colour = $Colour
                        $Updated = $true
                    } else {
                        $StatusCode = [HttpStatusCode]::BadRequest
                        $ErrorMessage = 'Error: Invalid color format. Please use hex format (e.g., #F77F00)'
                    }
                }

                # Secondary brand colour, used for subheadings, callout rules and the second series
                # in charts. An empty string clears it, at which point reports fall back to the
                # primary colour and look exactly as they did before one was set.
                if (-not $ErrorMessage -and $Request.Body.PSObject.Properties.Name -contains 'secondaryColour') {
                    $SecondaryColour = "$($Request.Body.secondaryColour)"
                    if ([string]::IsNullOrWhiteSpace($SecondaryColour)) {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'secondaryColour' -Value '' -Force
                        $Updated = $true
                    } elseif ($SecondaryColour -match '^#[0-9A-Fa-f]{6}$') {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'secondaryColour' -Value $SecondaryColour -Force
                        $Updated = $true
                    } else {
                        $StatusCode = [HttpStatusCode]::BadRequest
                        $ErrorMessage = 'Error: Invalid secondary color format. Please use hex format (e.g., #006666)'
                    }
                }

                # Footer text shown on every report page. Carries %variable% tokens — the same
                # syntax Get-CIPPTextReplacement uses — which the report renderer fills in per
                # report. Stored as written so the tokens survive to render time.
                if (-not $ErrorMessage -and $Request.Body.PSObject.Properties.Name -contains 'footerText') {
                    $FooterText = "$($Request.Body.footerText)"
                    if ($FooterText.Length -gt 200) {
                        $StatusCode = [HttpStatusCode]::BadRequest
                        $ErrorMessage = 'Error: Footer text must be 200 characters or fewer.'
                    } else {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'footerText' -Value $FooterText -Force
                        $Updated = $true
                    }
                }

                # The confidentiality note on report covers. Empty leaves each report's own wording
                # in place — several are more specific than 'Confidential & Proprietary'.
                if (-not $ErrorMessage -and $Request.Body.PSObject.Properties.Name -contains 'coverFooterText') {
                    $CoverFooterText = "$($Request.Body.coverFooterText)"
                    if ($CoverFooterText.Length -gt 200) {
                        $StatusCode = [HttpStatusCode]::BadRequest
                        $ErrorMessage = 'Error: Cover footer text must be 200 characters or fewer.'
                    } else {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'coverFooterText' -Value $CoverFooterText -Force
                        $Updated = $true
                    }
                }

                # Diagonal watermark drawn behind report content, e.g. DRAFT or CONFIDENTIAL.
                if (-not $ErrorMessage -and $Request.Body.PSObject.Properties.Name -contains 'watermarkText') {
                    $WatermarkText = "$($Request.Body.watermarkText)"
                    if ($WatermarkText.Length -gt 40) {
                        $StatusCode = [HttpStatusCode]::BadRequest
                        $ErrorMessage = 'Error: Watermark text must be 40 characters or fewer.'
                    } else {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'watermarkText' -Value $WatermarkText -Force
                        $Updated = $true
                    }
                }

                # Show the branded footer text on report pages.
                if (-not $ErrorMessage -and $Request.Body.PSObject.Properties.Name -contains 'showFooter') {
                    $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'showFooter' -Value ([bool]$Request.Body.showFooter) -Force
                    $Updated = $true
                }

                # Show 'Page X of Y' in the report footer.
                if (-not $ErrorMessage -and $Request.Body.PSObject.Properties.Name -contains 'showPageNumbers') {
                    $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'showPageNumbers' -Value ([bool]$Request.Body.showPageNumbers) -Force
                    $Updated = $true
                }

                # Which preset each report type defaults to, as a report-id -> preset-id map.
                # Stored as JSON: Azure Table has no nested types. Sent whole rather than patched,
                # so clearing a report's default is expressed by omitting it from the map.
                if (-not $ErrorMessage -and $Request.Body.PSObject.Properties.Name -contains 'reportDefaults') {
                    $Defaults = $Request.Body.reportDefaults
                    if ($null -eq $Defaults -or "$Defaults" -eq '') {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'reportDefaults' -Value '{}' -Force
                        $Updated = $true
                    } else {
                        $DefaultsJson = if ($Defaults -is [string]) { $Defaults } else { ConvertTo-Json -InputObject $Defaults -Depth 5 -Compress }
                        try {
                            ConvertFrom-Json -InputObject $DefaultsJson -ErrorAction Stop | Out-Null
                            $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'reportDefaults' -Value $DefaultsJson -Force
                            $Updated = $true
                        } catch {
                            $StatusCode = [HttpStatusCode]::BadRequest
                            $ErrorMessage = 'Error: reportDefaults must be an object mapping report ids to preset ids.'
                        }
                    }
                }

                # Per-role report colours — headings, body, footer, charts, cards — as a
                # setting-name -> hex map. One JSON column rather than a property per role, so the
                # frontend can add a role without a backend change. Sent whole, like reportDefaults
                # above, so clearing a role is expressed by omitting it.
                if (-not $ErrorMessage -and $Request.Body.PSObject.Properties.Name -contains 'roleColours') {
                    $Roles = $Request.Body.roleColours
                    if ($null -eq $Roles -or "$Roles" -eq '') {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'roleColours' -Value '{}' -Force
                        $Updated = $true
                    } else {
                        $RolesJson = if ($Roles -is [string]) { $Roles } else { ConvertTo-Json -InputObject $Roles -Depth 5 -Compress }
                        try {
                            $ParsedRoles = ConvertFrom-Json -InputObject $RolesJson -ErrorAction Stop
                            # Every value has to be a hex colour. An invalid one reaches react-pdf as
                            # black without complaint, so it is rejected here rather than shipped to
                            # every report the setting touches.
                            foreach ($Role in $ParsedRoles.PSObject.Properties) {
                                if ("$($Role.Value)" -ne '' -and "$($Role.Value)" -notmatch '^#[0-9A-Fa-f]{6}$') {
                                    $StatusCode = [HttpStatusCode]::BadRequest
                                    $ErrorMessage = "Error: Invalid color format for $($Role.Name). Please use hex format (e.g., #006666)"
                                    break
                                }
                            }
                            if (-not $ErrorMessage) {
                                $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'roleColours' -Value $RolesJson -Force
                                $Updated = $true
                            }
                        } catch {
                            $StatusCode = [HttpStatusCode]::BadRequest
                            $ErrorMessage = 'Error: roleColours must be an object mapping colour roles to hex values.'
                        }
                    }
                }

                # Draw the watermark on report pages.
                if (-not $ErrorMessage -and $Request.Body.PSObject.Properties.Name -contains 'watermarkEnabled') {
                    $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'watermarkEnabled' -Value ([bool]$Request.Body.watermarkEnabled) -Force
                    $Updated = $true
                }

                if (-not $ErrorMessage -and $Request.Body.PSObject.Properties.Name -contains 'coverStock') {
                    $CoverStock = $Request.Body.coverStock
                    if ($AllowedCoverStock -contains $CoverStock) {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'coverStock' -Value $CoverStock -Force
                        $Updated = $true
                    } else {
                        $StatusCode = [HttpStatusCode]::BadRequest
                        $ErrorMessage = 'Error: Invalid cover stock selection.'
                    }
                }

                if (-not $ErrorMessage -and $Request.Body.PSObject.Properties.Name -contains 'logoImageIds') {
                    $LogoIds = ConvertTo-IdList -Value $Request.Body.logoImageIds
                    if ($LogoIds.Count -eq 0 -or (Test-ImageIdsExist -PartitionKey 'logo' -Ids $LogoIds)) {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'logoImageIds' -Value (ConvertTo-IdListJson -Value $LogoIds) -Force
                        $Updated = $true
                    } else {
                        $StatusCode = [HttpStatusCode]::BadRequest
                        $ErrorMessage = 'Error: One or more logoImageIds were not found.'
                    }
                }

                if (-not $ErrorMessage -and $Request.Body.PSObject.Properties.Name -contains 'logoImageId') {
                    $LogoImageId = $Request.Body.logoImageId
                    if ($null -eq $LogoImageId -or $LogoImageId -eq '') {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'logoImageId' -Value '' -Force
                        $Updated = $true
                    } elseif (Test-ImageIdsExist -PartitionKey 'logo' -Ids @("$LogoImageId")) {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'logoImageId' -Value "$LogoImageId" -Force
                        $Updated = $true
                    } else {
                        $StatusCode = [HttpStatusCode]::BadRequest
                        $ErrorMessage = 'Error: logoImageId was not found.'
                    }
                }

                if (-not $ErrorMessage -and $Request.Body.PSObject.Properties.Name -contains 'coverImageIds') {
                    $CoverIds = ConvertTo-IdList -Value $Request.Body.coverImageIds
                    if ($CoverIds.Count -eq 0 -or (Test-ImageIdsExist -PartitionKey 'brandingCover' -Ids $CoverIds)) {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'coverImageIds' -Value (ConvertTo-IdListJson -Value $CoverIds) -Force
                        $Updated = $true
                    } else {
                        $StatusCode = [HttpStatusCode]::BadRequest
                        $ErrorMessage = 'Error: One or more coverImageIds were not found.'
                    }
                }

                if (-not $ErrorMessage -and $Request.Body.PSObject.Properties.Name -contains 'coverImageId') {
                    $CoverImageId = $Request.Body.coverImageId
                    if ($null -eq $CoverImageId -or $CoverImageId -eq '') {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'coverImageId' -Value '' -Force
                        $Updated = $true
                    } elseif (Test-ImageIdsExist -PartitionKey 'brandingCover' -Ids @("$CoverImageId")) {
                        $BrandingConfig | Add-Member -MemberType NoteProperty -Name 'coverImageId' -Value "$CoverImageId" -Force
                        $Updated = $true
                    } else {
                        $StatusCode = [HttpStatusCode]::BadRequest
                        $ErrorMessage = 'Error: coverImageId was not found.'
                    }
                }

                # Clear legacy inline blobs on any successful modern Set
                if (-not $ErrorMessage -and $Updated) {
                    foreach ($LegacyProp in @('logo', 'coverImage', 'coverUploads', 'logoUploads')) {
                        if ($BrandingConfig.PSObject.Properties.Name -contains $LegacyProp) {
                            $BrandingConfig | Add-Member -MemberType NoteProperty -Name $LegacyProp -Value $null -Force
                        }
                    }
                    $BrandingConfig.PartitionKey = 'BrandingSettings'
                    $BrandingConfig.RowKey = 'BrandingSettings'
                    Add-CIPPAzDataTableEntity @Table -Entity $BrandingConfig -Force | Out-Null
                    Write-LogMessage -API $APIName -tenant 'Global' -headers $Request.Headers -message 'Updated branding settings' -Sev 'Info'
                    'Successfully updated branding settings'
                } elseif ($ErrorMessage) {
                    $ErrorMessage
                } else {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: No valid branding data provided'
                }
            }
            'Reset' {
                $LogoIds = ConvertTo-IdList -Value $BrandingConfig.logoImageIds
                if ($BrandingConfig.logoImageId) {
                    $LogoIds = @("$($BrandingConfig.logoImageId)") + @($LogoIds | Where-Object { $_ -ne "$($BrandingConfig.logoImageId)" })
                }
                $CoverIds = ConvertTo-IdList -Value $BrandingConfig.coverImageIds
                if ($BrandingConfig.coverImageId) {
                    $CoverIds = @("$($BrandingConfig.coverImageId)") + @($CoverIds | Where-Object { $_ -ne "$($BrandingConfig.coverImageId)" })
                }

                if ($LogoIds.Count -gt 0) {
                    Remove-CIPPImage -PartitionKey 'logo' -Id $LogoIds
                }
                if ($CoverIds.Count -gt 0) {
                    Remove-CIPPImage -PartitionKey 'brandingCover' -Id $CoverIds
                }

                $DefaultConfig = @{
                    PartitionKey     = 'BrandingSettings'
                    RowKey           = 'BrandingSettings'
                    colour           = '#F77F00'
                    secondaryColour  = ''
                    logoImageId      = ''
                    logoImageIds     = '[]'
                    coverStock       = $DefaultCoverStock
                    coverImageId     = ''
                    coverImageIds    = '[]'
                    logo             = $null
                    coverImage       = $null
                    coverUploads     = $null
                    logoUploads      = $null
                    footerText       = ''
                    coverFooterText  = ''
                    showFooter       = $true
                    showPageNumbers  = $true
                    watermarkText    = ''
                    watermarkEnabled = $false
                    reportDefaults   = '{}'
                roleColours      = '{}'
                }

                Add-CIPPAzDataTableEntity @Table -Entity $DefaultConfig -Force | Out-Null
                Write-LogMessage -API $APIName -tenant 'Global' -headers $Request.Headers -message 'Reset branding settings to defaults' -Sev 'Info'
                'Successfully reset branding settings to defaults'
            }
            'ListPresets' {
                Get-CIPPBrandingPreset
            }
            'SavePreset' {
                # A preset is a complete branding set, not a patch over the global settings: what
                # the editor shows is what the report gets. The UI seeds a new one from the current
                # global settings so that completeness costs nothing to fill in.
                $PresetName = "$($Request.Body.name)".Trim()
                if ([string]::IsNullOrWhiteSpace($PresetName)) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: Preset name is required.'
                    break
                }
                if ($PresetName.Length -gt 128) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: Preset name must be 128 characters or fewer.'
                    break
                }

                $PresetColour = if ($Request.Body.colour) { "$($Request.Body.colour)" } else { '#F77F00' }
                if ($PresetColour -notmatch '^#[0-9A-Fa-f]{6}$') {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: Invalid color format. Please use hex format (e.g., #F77F00)'
                    break
                }

                $PresetSecondary = "$($Request.Body.secondaryColour)"
                if (-not [string]::IsNullOrWhiteSpace($PresetSecondary) -and $PresetSecondary -notmatch '^#[0-9A-Fa-f]{6}$') {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: Invalid secondary color format. Please use hex format (e.g., #006666)'
                    break
                }

                $PresetCoverStock = if ($Request.Body.coverStock) { "$($Request.Body.coverStock)" } else { 'none' }
                if ($AllowedCoverStock -notcontains $PresetCoverStock) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: Invalid cover stock selection.'
                    break
                }

                $PresetLogoId = "$($Request.Body.logoImageId)"
                if ($PresetLogoId -and -not (Test-ImageIdsExist -PartitionKey 'logo' -Ids @($PresetLogoId))) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: logoImageId was not found.'
                    break
                }

                $PresetCoverId = "$($Request.Body.coverImageId)"
                if ($PresetCoverId -and -not (Test-ImageIdsExist -PartitionKey 'brandingCover' -Ids @($PresetCoverId))) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: coverImageId was not found.'
                    break
                }

                $PresetFooter = "$($Request.Body.footerText)"
                if ($PresetFooter.Length -gt 200) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: Footer text must be 200 characters or fewer.'
                    break
                }

                $PresetCoverFooter = "$($Request.Body.coverFooterText)"
                if ($PresetCoverFooter.Length -gt 200) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: Cover footer text must be 200 characters or fewer.'
                    break
                }

                $PresetWatermark = "$($Request.Body.watermarkText)"
                if ($PresetWatermark.Length -gt 40) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: Watermark text must be 40 characters or fewer.'
                    break
                }

                $PresetId = if ($Request.Body.id) { "$($Request.Body.id)" } else { (New-Guid).Guid }

                Add-CIPPAzDataTableEntity @Table -Force -Entity @{
                    PartitionKey     = 'BrandingPresets'
                    RowKey           = [string]$PresetId
                    name             = $PresetName
                    colour           = $PresetColour
                    secondaryColour  = $PresetSecondary
                    logoImageId      = $PresetLogoId
                    coverStock       = $PresetCoverStock
                    coverImageId     = $PresetCoverId
                    footerText       = $PresetFooter
                    coverFooterText  = $PresetCoverFooter
                    showFooter       = [bool]$Request.Body.showFooter
                    showPageNumbers  = [bool]$Request.Body.showPageNumbers
                    watermarkText    = $PresetWatermark
                    watermarkEnabled = [bool]$Request.Body.watermarkEnabled
                } | Out-Null

                Write-LogMessage -API $APIName -tenant 'Global' -headers $Request.Headers -message "Saved branding preset '$PresetName'" -Sev 'Info'
                @{
                    Results = "Successfully saved branding preset '$PresetName'"
                    id      = $PresetId
                }
            }
            'DeletePreset' {
                $PresetId = "$($Request.Body.id)"
                if ([string]::IsNullOrWhiteSpace($PresetId)) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: Preset id is required.'
                    break
                }

                $Existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'BrandingPresets' and RowKey eq '$($PresetId.Replace("'","''"))'"
                if (-not $Existing) {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    'Error: Preset not found.'
                    break
                }

                # Only the preset row goes: its logo and cover live in the shared image gallery and
                # may still be selected by the global settings or another preset.
                Remove-CIPPAzDataTableEntity @Table -Entity $Existing
                Write-LogMessage -API $APIName -tenant 'Global' -headers $Request.Headers -message "Deleted branding preset $PresetId" -Sev 'Info'
                'Successfully deleted branding preset'
            }
            default {
                $StatusCode = [HttpStatusCode]::BadRequest
                'Error: Invalid action specified'
            }
        }
    } catch {
        Write-LogMessage -API $APIName -tenant 'Global' -headers $Request.Headers -message "Branding Settings API failed: $($_.Exception.Message)" -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
        "Failed to process branding settings: $($_.Exception.Message)"
    }

    $body = [pscustomobject]@{'Results' = $Results }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })
}
