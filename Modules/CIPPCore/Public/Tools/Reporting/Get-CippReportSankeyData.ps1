function Get-CippReportSankeyData {
    <#
    .SYNOPSIS
        Build the { nodes, links } for a dashboard-style sankey from its source collection rows.
    .DESCRIPTION
        Faithful server-side ports of the dashboard cards' sankey computations so a report renders the
        SAME sankey a user sees on the dashboard. Each preset reads the raw collection rows and returns
        @{ nodes = @(@{ id; label; nodeColor }, ...); links = @(@{ source; target; value }, ...) }.

        Ported one-to-one from the frontend cards (keep them in step):
          mfaCoverage       <- MFACard.jsx        (MFAState)        enabled -> registered/not -> enforcement
          authMethods       <- AuthMethodCard.jsx (MFAState)        users -> factor class -> method breakdown
          licenseAllocation <- LicenseCard.jsx    (LicenseOverview) top-5 licence -> assigned/available
          deviceCompliance  <- managed devices    (ManagedDevices)  devices -> OS -> compliance state

        Nodes with no link are dropped by the renderer, so declaring the full node set is safe.
    .PARAMETER Preset
        Which dashboard sankey to build.
    .PARAMETER Rows
        The raw collection rows for that sankey's source (unfiltered; each builder filters as the card does).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Preset,
        [AllowEmptyCollection()][object[]]$Rows = @()
    )

    $Nodes = [System.Collections.Generic.List[object]]::new()
    $Links = [System.Collections.Generic.List[object]]::new()
    $AddNode = { param($Id, $Label, $Colour) $Nodes.Add([ordered]@{ id = $Id; label = $Label; nodeColor = $Colour }) }
    $AddLink = { param($Source, $Target, $Value) if ($Value -gt 0) { $Links.Add([ordered]@{ source = $Source; target = $Target; value = $Value }) } }

    switch ($Preset) {
        'mfaCoverage' {
            # MFACard.jsx: enabled users -> MFA registered / Not registered -> how it is enforced.
            $Enabled = @($Rows | Where-Object { $_.AccountEnabled -eq $true })
            $RegisteredUsers = 0; $NotRegisteredUsers = 0
            $RegCA = 0; $RegSD = 0; $RegPerUser = 0; $RegNone = 0
            $NotCA = 0; $NotSD = 0; $NotNone = 0
            foreach ($User in $Enabled) {
                $HasRegistered = $User.MFARegistration -eq $true
                $CoveredByCA = "$($User.CoveredByCA)".StartsWith('Enforced')
                $CoveredBySD = $User.CoveredBySD -eq $true
                $PerUser = "$($User.PerUser)"
                $PerUserOn = $PerUser -eq 'enforced' -or $PerUser -eq 'enabled'
                if ($HasRegistered -or $PerUserOn) {
                    $RegisteredUsers++
                    if ($PerUserOn) { $RegPerUser++ }
                    elseif ($CoveredByCA) { $RegCA++ }
                    elseif ($CoveredBySD) { $RegSD++ }
                    else { $RegNone++ }
                } else {
                    $NotRegisteredUsers++
                    if ($CoveredByCA) { $NotCA++ }
                    elseif ($CoveredBySD) { $NotSD++ }
                    else { $NotNone++ }
                }
            }
            & $AddNode 'Enabled users' 'Enabled users' 'hsl(28, 100%, 53%)'
            & $AddNode 'MFA registered' 'MFA registered' 'hsl(99, 70%, 50%)'
            & $AddNode 'Not registered' 'Not registered' 'hsl(39, 100%, 50%)'
            & $AddNode 'CA policy' 'CA policy' 'hsl(99, 70%, 50%)'
            & $AddNode 'Security defaults' 'Security defaults' 'hsl(140, 70%, 50%)'
            & $AddNode 'Per-user MFA' 'Per-user MFA' 'hsl(200, 70%, 50%)'
            & $AddNode 'No enforcement' 'No enforcement' 'hsl(0, 100%, 50%)'
            & $AddLink 'Enabled users' 'MFA registered' $RegisteredUsers
            & $AddLink 'Enabled users' 'Not registered' $NotRegisteredUsers
            & $AddLink 'MFA registered' 'CA policy' $RegCA
            & $AddLink 'MFA registered' 'Security defaults' $RegSD
            & $AddLink 'MFA registered' 'Per-user MFA' $RegPerUser
            & $AddLink 'MFA registered' 'No enforcement' $RegNone
            & $AddLink 'Not registered' 'CA policy' $NotCA
            & $AddLink 'Not registered' 'Security defaults' $NotSD
            & $AddLink 'Not registered' 'No enforcement' $NotNone
        }
        'authMethods' {
            # AuthMethodCard.jsx: users -> single/multi factor, phishable vs phish-resistant, + breakdown.
            $Enabled = @($Rows | Where-Object { $_.AccountEnabled -eq $true })
            $Phishable = @('mobilePhone', 'alternateMobilePhone', 'officePhone', 'email', 'microsoftAuthenticatorPush', 'softwareOneTimePasscode', 'hardwareOneTimePasscode')
            $Passkey = @('fido2SecurityKey', 'passKeyDeviceBound', 'passKeyDeviceBoundAuthenticator', 'passKeyDeviceBoundWindowsHello', 'x509Certificate')
            $PhishResistant = @($Passkey + 'windowsHelloForBusiness')
            $SingleFactor = 0; $PhishableCount = 0; $PhishResistantCount = 0; $PerUserMFA = 0
            $PhoneCount = 0; $AuthenticatorCount = 0; $PasskeyCount = 0; $WhfbCount = 0
            foreach ($User in $Enabled) {
                $Methods = @($User.MFAMethods | Where-Object { $null -ne $_ -and "$_" -ne '' })
                $PerUser = "$($User.PerUser)"
                $PerUserOn = $PerUser -eq 'enforced' -or $PerUser -eq 'enabled'
                $HasRegistered = $User.MFARegistration -eq $true
                if ($PerUserOn -and -not $HasRegistered -and $Methods.Count -eq 0) { $PerUserMFA++; continue }
                if (-not $HasRegistered -or $Methods.Count -eq 0) { $SingleFactor++; continue }
                $HasPR = @($Methods | Where-Object { $PhishResistant -contains $_ }).Count -gt 0
                $HasPh = @($Methods | Where-Object { $Phishable -contains $_ }).Count -gt 0
                if ($HasPR) {
                    $PhishResistantCount++
                    if (@($Methods | Where-Object { $Passkey -contains $_ }).Count -gt 0) { $PasskeyCount++ }
                    if ($Methods -contains 'windowsHelloForBusiness') { $WhfbCount++ }
                } elseif ($HasPh) {
                    $PhishableCount++
                    if (($Methods -contains 'mobilePhone') -or ($Methods -contains 'alternateMobilePhone') -or ($Methods -contains 'officePhone') -or ($Methods -contains 'email')) { $PhoneCount++ }
                    if (($Methods -contains 'microsoftAuthenticatorPush') -or ($Methods -contains 'softwareOneTimePasscode') -or ($Methods -contains 'hardwareOneTimePasscode')) { $AuthenticatorCount++ }
                } else {
                    $PhishableCount++; $AuthenticatorCount++
                }
            }
            & $AddNode 'Users' 'Users' 'hsl(28, 100%, 53%)'
            & $AddNode 'Single factor' 'Single factor' 'hsl(0, 100%, 50%)'
            & $AddNode 'Multi factor' 'Multi factor' 'hsl(200, 70%, 50%)'
            & $AddNode 'Phishable' 'Phishable' 'hsl(39, 100%, 50%)'
            & $AddNode 'Phone' 'Phone' 'hsl(39, 100%, 45%)'
            & $AddNode 'Authenticator' 'Authenticator' 'hsl(39, 100%, 55%)'
            & $AddNode 'Phish resistant' 'Phish resistant' 'hsl(99, 70%, 50%)'
            & $AddNode 'Passkey' 'Passkey' 'hsl(140, 70%, 50%)'
            & $AddNode 'WHfB' 'WHfB' 'hsl(160, 70%, 50%)'
            & $AddLink 'Users' 'Single factor' $SingleFactor
            & $AddLink 'Users' 'Multi factor' $PerUserMFA
            & $AddLink 'Users' 'Phishable' $PhishableCount
            & $AddLink 'Users' 'Phish resistant' $PhishResistantCount
            & $AddLink 'Phishable' 'Phone' $PhoneCount
            & $AddLink 'Phishable' 'Authenticator' $AuthenticatorCount
            & $AddLink 'Phish resistant' 'Passkey' $PasskeyCount
            & $AddLink 'Phish resistant' 'WHfB' $WhfbCount
        }
        'licenseAllocation' {
            # LicenseCard.jsx: the top-5 licences by total, each fanning out to its own assigned/available.
            $Top = @($Rows | Where-Object { ($_.TotalLicenses -as [int]) -gt 0 } |
                    Sort-Object -Property @{ Expression = { $_.TotalLicenses -as [int] }; Descending = $true } |
                    Select-Object -First 5)
            $Index = 0
            foreach ($Lic in $Top) {
                $Name = if ($Lic.License) { "$($Lic.License)" } elseif ($Lic.skuPartNumber) { "$($Lic.skuPartNumber)" } elseif ($Lic.SkuPartNumber) { "$($Lic.SkuPartNumber)" } else { 'Unknown License' }
                $Short = if ($Name.Length -gt 30) { $Name.Substring(0, 27) + '...' } else { $Name }
                $Assigned = ($Lic.CountUsed -as [int]); if ($null -eq $Assigned) { $Assigned = 0 }
                $Available = ($Lic.CountAvailable -as [int]); if ($null -eq $Available) { $Available = 0 }
                $NodeId = "$Index-$Short"
                & $AddNode $NodeId $Short ('hsl({0}, 70%, 50%)' -f (210 + $Index * 30))
                if ($Assigned -gt 0) {
                    & $AddNode "$NodeId - Assigned" "$Short - Assigned" 'hsl(99, 70%, 50%)'
                    & $AddLink $NodeId "$NodeId - Assigned" $Assigned
                }
                if ($Available -gt 0) {
                    & $AddNode "$NodeId - Available" "$Short - Available" 'hsl(28, 100%, 53%)'
                    & $AddLink $NodeId "$NodeId - Available" $Available
                }
                $Index++
            }
        }
        'deviceCompliance' {
            # Managed devices -> operating system -> compliance state. Compliant green, non-compliant red,
            # in-grace amber, anything else (unknown/error/conflict) grey.
            $StateColour = {
                param($State)
                switch -Regex ("$State".ToLowerInvariant()) {
                    '^compliant$' { 'hsl(99, 70%, 50%)' }
                    '^noncompliant$' { 'hsl(0, 100%, 50%)' }
                    '^ingraceperiod$' { 'hsl(39, 100%, 50%)' }
                    default { 'hsl(220, 10%, 60%)' }
                }
            }
            $OsOrder = [System.Collections.Generic.List[string]]::new()
            $StateSeen = @{}
            $OsTotals = @{}
            $PairCounts = [ordered]@{}
            foreach ($Device in $Rows) {
                $Os = "$($Device.operatingSystem)"; if (-not $Os) { $Os = 'Unknown' }
                $State = "$($Device.complianceState)"; if (-not $State) { $State = 'unknown' }
                if (-not $OsOrder.Contains($Os)) { $OsOrder.Add($Os) }
                $OsTotals[$Os] = ([int]$OsTotals[$Os]) + 1
                $Key = "$Os`n$State"
                $PairCounts[$Key] = ([int]$PairCounts[$Key]) + 1
            }
            if ($OsOrder.Count -gt 0) {
                & $AddNode 'Managed devices' 'Managed devices' 'hsl(28, 100%, 53%)'
                $OsIndex = 0
                foreach ($Os in $OsOrder) {
                    & $AddNode "os:$Os" $Os ('hsl({0}, 70%, 50%)' -f ((200 + $OsIndex * 35) % 360))
                    & $AddLink 'Managed devices' "os:$Os" ([int]$OsTotals[$Os])
                    $OsIndex++
                }
                foreach ($Key in $PairCounts.Keys) {
                    $Parts = $Key -split "`n", 2
                    $Os = $Parts[0]; $State = $Parts[1]
                    $StateId = "state:$State"
                    if (-not $StateSeen.ContainsKey($StateId)) { & $AddNode $StateId $State (& $StateColour $State); $StateSeen[$StateId] = $true }
                    & $AddLink "os:$Os" $StateId ([int]$PairCounts[$Key])
                }
            }
        }
        default { }
    }

    return @{ nodes = @($Nodes); links = @($Links) }
}
