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
                PartitionKey  = 'BrandingSettings'
                RowKey        = 'BrandingSettings'
                colour        = '#F77F00'
                logoImageId   = $null
                logoImageIds  = '[]'
                coverStock    = $DefaultCoverStock
                coverImageId  = $null
                coverImageIds = '[]'
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
                    PartitionKey  = 'BrandingSettings'
                    RowKey        = 'BrandingSettings'
                    colour        = '#F77F00'
                    logoImageId   = ''
                    logoImageIds  = '[]'
                    coverStock    = $DefaultCoverStock
                    coverImageId  = ''
                    coverImageIds = '[]'
                    logo          = $null
                    coverImage    = $null
                    coverUploads  = $null
                    logoUploads   = $null
                }

                Add-CIPPAzDataTableEntity @Table -Entity $DefaultConfig -Force | Out-Null
                Write-LogMessage -API $APIName -tenant 'Global' -headers $Request.Headers -message 'Reset branding settings to defaults' -Sev 'Info'
                'Successfully reset branding settings to defaults'
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
