function Invoke-ListUserSettings {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.User.Read
    .DESCRIPTION
        Retrieves the current CIPP user's personal settings and preferences.
    #>
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers


    $Username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails

    try {
        $Table = Get-CippTable -tablename 'UserSettings'
        $ConvertUserSettings = {
            param($Entity)
            if (!$Entity -or !$Entity.JSON) { return $null }
            try {
                return $Entity.JSON | ConvertFrom-Json -Depth 10 -ErrorAction Stop
            } catch {
                Write-Warning "UserSettings JSON for '$($Entity.RowKey)' had a key case collision, self-healing: $($_.Exception.Message)"
                try {
                    $Hash = $Entity.JSON | ConvertFrom-Json -Depth 10 -AsHashtable
                    if ($Hash.offboardingDefaults -is [System.Collections.IDictionary]) {
                        $Offboarding = $Hash.offboardingDefaults
                        $Variants = @($Offboarding.Keys | Where-Object { $_ -ieq 'keepCopy' })
                        if ($Variants.Count -gt 0) {
                            $CanonicalValue = if ($Offboarding.Contains('KeepCopy')) { $Offboarding['KeepCopy'] } else { $Offboarding[$Variants[0]] }
                            foreach ($Variant in $Variants) { $null = $Offboarding.Remove($Variant) }
                            $Offboarding['KeepCopy'] = $CanonicalValue
                        }
                    }
                    $HealedJson = $Hash | ConvertTo-Json -Depth 10 -Compress
                    $Healed = $HealedJson | ConvertFrom-Json -Depth 10 -ErrorAction Stop
                    $HealTable = Get-CippTable -tablename 'UserSettings'
                    $HealTable.Force = $true
                    Add-CIPPAzDataTableEntity @HealTable -Entity @{
                        JSON         = "$HealedJson"
                        RowKey       = "$($Entity.RowKey)"
                        PartitionKey = "$($Entity.PartitionKey)"
                    }
                    return $Healed
                } catch {
                    Write-Warning "Failed to self-heal UserSettings JSON for '$($Entity.RowKey)': $($_.Exception.Message)"
                    return $null
                }
            }
        }

        $UserSettingsEntity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'UserSettings' and RowKey eq 'allUsers'"
        if (!$UserSettingsEntity) { $UserSettingsEntity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'UserSettings' and RowKey eq '$Username'" }
        $UserSettings = & $ConvertUserSettings $UserSettingsEntity

        if (!$UserSettings) {
            $UserSettings = [pscustomobject]@{
                direction      = 'ltr'
                paletteMode    = 'light'
                currentTheme   = @{ value = 'light'; label = 'light' }
                pinNav         = $true
                showDevtools   = $false
                customBranding = @{
                    colour = '#F77F00'
                    logo   = $null
                }
            }
        }

        $UserSpecificEntity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'UserSettings' and RowKey eq '$Username'"
        $UserSpecificSettings = & $ConvertUserSettings $UserSpecificEntity

        $TestOffboardingConfigured = {
            param($Offboarding)
            if (-not $Offboarding) { return $false }
            foreach ($Property in $Offboarding.PSObject.Properties) {
                if ($Property.Value -eq $true) { return $true }
            }
            return $false
        }

        $AllUsersOffboardingConfigured = & $TestOffboardingConfigured $UserSettings.offboardingDefaults
        $UserOffboardingConfigured = & $TestOffboardingConfigured $UserSpecificSettings.offboardingDefaults

        $OffboardingDefaultsSource = 'allUsers'
        if (-not $AllUsersOffboardingConfigured -and $UserOffboardingConfigured) {
            $UserSettings | Add-Member -MemberType NoteProperty -Name 'offboardingDefaults' -Value $UserSpecificSettings.offboardingDefaults -Force | Out-Null
            $OffboardingDefaultsSource = 'user'
        }
        $UserSettings | Add-Member -MemberType NoteProperty -Name 'offboardingDefaultsSource' -Value $OffboardingDefaultsSource -Force | Out-Null

        # Get user bookmarks
        try {
            $UserBookmarks = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'UserBookmarks' and RowKey eq '$Username'"
            $UserBookmarks = $UserBookmarks.JSON | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue
            if ($UserBookmarks -and $UserBookmarks -isnot [System.Array]) {
                $UserBookmarks = @($UserBookmarks)
            }
        } catch {
            Write-Warning "Failed to convert UserBookmarks JSON: $($_.Exception.Message)"
        }

        #Get branding settings
        if ($UserSettings) {
            $brandingTable = Get-CippTable -tablename 'Config'
            $BrandingSettings = Get-CIPPAzDataTableEntity @brandingTable -Filter "PartitionKey eq 'BrandingSettings' and RowKey eq 'BrandingSettings'"
            if ($BrandingSettings) {
                $UserSettings | Add-Member -MemberType NoteProperty -Name 'customBranding' -Value $BrandingSettings -Force | Out-Null
            }
        }

        if ($UserSpecificSettings) {
            $UserSettings | Add-Member -MemberType NoteProperty -Name 'UserSpecificSettings' -Value $UserSpecificSettings -Force | Out-Null
        }

        if ($UserBookmarks) {
            $UserSettings | Add-Member -MemberType NoteProperty -Name 'UserBookmarks' -Value $UserBookmarks -Force | Out-Null
        }

        $StatusCode = [HttpStatusCode]::OK
        $Results = $UserSettings
    } catch {
        $Results = "Function Error: $($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
