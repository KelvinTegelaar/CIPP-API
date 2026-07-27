function Get-CIPPOfficeAppBody {
    <#
    .SYNOPSIS
        Builds the Graph officeSuiteApp body for a Microsoft 365 Apps deployment.
    .DESCRIPTION
        Shared by Invoke-AddOfficeApp (manual and template deploys) and New-CIPPIntuneAppDeployment
        (queue and standards deploys) so every path produces an identical body. Handles the three
        shapes an Office config can take:
          1. A pre-built IntuneBody, stored when a template is saved from an already deployed app.
          2. A custom Office configuration XML.
          3. The individual fields from the Office app form / application template wizard.
    .PARAMETER Config
        The Office app configuration. Either the request body from the Office app form or the
        config stored in an application template.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Config
    )

    $LargeIcon = @{
        '@odata.type' = 'microsoft.graph.mimeContent'
        'type'        = 'image/png'
        'value'       = 'iVBORw0KGgoAAAANSUhEUgAAAF0AAAAeCAMAAAEOZNKlAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAJhUExURf////7z7/i9qfF1S/KCW/i+qv3q5P/9/PrQwfOMae1RG+s8AOxGDfBtQPWhhPvUx/759/zg1vWgg+9fLu5WIvKFX/rSxP728/nCr/FyR+tBBvOMaO1UH+1RHOs+AvSScP3u6f/+/v3s5vzg1+xFDO9kNPOOa/i7pvzj2/vWyes9Af76+Pzh2PrTxf/6+f7y7vOGYexHDv3t5+1SHfi8qPOIZPvb0O1NFuxDCe9hMPSVdPnFs/3q4/vaz/STcu5VIe5YJPWcfv718v/9/e1MFfF4T/F4TvF2TP3o4exECvF0SexIEPONavzn3/vZze1QGvF3Te5dK+5cKvrPwPrQwvKAWe1OGPexmexKEveulfezm/BxRfamiuxLE/apj/zf1e5YJfSXd/OHYv3r5feznPakiPze1P7x7f739f3w6+xJEfnEsvWdf/Wfge1LFPe1nu9iMvnDsfBqPOs/BPOIY/WZevJ/V/zl3fnIt/vTxuxHD+xEC+9mN+5ZJv749vBpO/KBWvBwRP/8+/SUc/etlPjArP/7+vOLZ/F7UvWae/708e1OF/aihvSWdvi8p+tABfSZefvVyPWihfSVde9lNvami+9jM/zi2fKEXvBuQvOKZvalifF5UPJ/WPSPbe9eLfrKuvvd0uxBB/7w7Pzj2vrRw/rOv+1PGfi/q/eymu5bKf3n4PnJuPBrPf3t6PWfgvWegOxCCO9nOO9oOfaskvSYePi5pPi2oPnGtO5eLPevlvKDXfrNvv739Pzd0/708O9gL+9lNfJ9VfrLu/OPbPnDsPBrPus+A/nArfarkQAAAGr5HKgAAADLdFJOU/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AvuakogAAAAlwSFlzAAAOwwAADsMBx2+oZAAAAz5JREFUOE+tVTtu4zAQHQjppmWzwIJbEVCzpTpjbxD3grQHSOXKRXgCAT6EC7UBVAmp3KwBnmvfzNCyZTmxgeTZJsXx43B+HBHRE34ZkXgkerXFTheeiCkRrbB4UXmp4wSWz5raaQEMTM5TZwuiXoaKgV+6FsmkZQcSy0kA71yMTMGHanX+AzMMGLAQCxU1F/ZwjULPugazl82GM0NEKm/U8EqFwEkO3/EAT4grgl0nucwlk9pcpTTJ4VPA4g/Rb3yIRhhp507e9nTQmZ1OS5RO4sS7nIRPEeHXCHdkw9ZEW2yVE5oIS7peD58Avs7CN+PVCmHh21oOqBdjDzIs+FldPJ74TFESUSJEfVzy9U/dhu+AuOT6eBp6gGKyXEx8euO450ZE4CMfstMFT44broWw/itkYErWXRx+fFArt9Ca9os78TFed0LVIUsmIHrwbwaw3BEOnOk94qVpQ6Ka2HjxewJnfyd6jUtGDQLdWlzmYNYLeKbbGOucJsNabCq1Yub0o92rtR+i30V2dapxYVEePXcOjeCKPnYyit7BtKeNlZqHbr+gt7i+AChWA9RsRs03pxTQc67ouWpxyESvjK5Vs3DVSy3IpkxPm5X+wZoBi+MFHWW69/w8FRhc7VBe6HAhMB2b8Q0XqDzTNZtXUMnKMjwKVaCrB/CSUL7WSx/HsdJC86lFGXwnioTeOMPjV+szlFvrZLA5VMVK4y+41l4e1xfx7Z88o4hkilRUH/qKqwNVlgDgpvYCpH3XwAy5eMCRnezIUxffVXoDql2rTHFDO+pjWnTWzAfrYXn6BFECblUpWGrvPZvBipETjS5ydM7tdXpH41ZCEbBNy/+wFZu71QO2t9pgT+iZEf657Q1vpN94PQNDxUHeKR103LV9nPVOtDikcNKO+2naCw7yKBhOe9Hm79pe8C4/CfC2wDjXnqC94kEeBU3WwN7dt/2UScXas7zDl5GpkY+M8WKv2J7fd4Ib2rGTk+jsC2cleEM7jI9veF7B0MBJrsZqfKd/81q9pR2NZfwJK2JzsmIT1Ns8jUH0UusQBpU8d2JzsHiXg1zXGLqxfitUNTDT/nUUeqDBp2HZVr+Ocqi/Ty3Rf4Jn82xxfSNtAAAAAElFTkSuQmCC'
    }

    # A template saved from an existing app carries the full body: reuse it, minus the read-only
    # properties Graph rejects on create.
    if ($Config.IntuneBody) {
        $IntuneBody = $Config.IntuneBody
        if ($IntuneBody -is [string]) {
            $IntuneBody = $IntuneBody | ConvertFrom-Json -Depth 100
        } else {
            # Copy first so we never strip properties off the caller's stored template config.
            $IntuneBody = $IntuneBody | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
        }

        $ReadOnlyProps = @(
            'id', 'createdDateTime', 'lastModifiedDateTime', 'uploadState', 'publishingState',
            'isAssigned', 'roleScopeTagIds', 'dependentAppCount', 'supersedingAppCount',
            'supersededAppCount', 'committedContentVersion', 'fileName', 'size',
            'assignments@odata.context', 'assignments', 'AppAssignment', 'AppExclude'
        )
        foreach ($Prop in $ReadOnlyProps) {
            if ($IntuneBody.PSObject.Properties[$Prop]) {
                $IntuneBody.PSObject.Properties.Remove($Prop)
            }
        }
        return $IntuneBody
    }

    if ($Config.useCustomXml -and $Config.customXml) {
        return [PSCustomObject]@{
            '@odata.type'            = '#microsoft.graph.officeSuiteApp'
            'displayName'            = 'Microsoft 365 Apps for Windows 10 and later'
            'description'            = 'Microsoft 365 Apps for Windows 10 and later'
            'informationUrl'         = 'https://products.office.com/en-us/explore-office-for-home'
            'privacyInformationUrl'  = 'https://privacy.microsoft.com/en-us/privacystatement'
            'isFeatured'             = $true
            'publisher'              = 'Microsoft'
            'notes'                  = ''
            'owner'                  = 'Microsoft'
            'officeConfigurationXml' = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Config.customXml))
            'largeIcon'              = $LargeIcon
        }
    }

    # Standard configuration built from the individual form fields. Multi-select fields arrive as
    # {label, value} objects from the frontend, but templates and API callers may send plain
    # strings, so accept both.
    $ExcludedAppNames = @($Config.excludedApps | ForEach-Object {
            if ($_ -is [string]) { $_ } else { $_.value }
        } | Where-Object { $_ })
    $Languages = @($Config.languages | ForEach-Object {
            if ($_ -is [string]) { $_ } else { $_.value }
        } | Where-Object { $_ })
    $UpdateChannel = if ($Config.updateChannel.value) { $Config.updateChannel.value } else { $Config.updateChannel }

    $ExcludedApps = [PSCustomObject]@{
        infoPath           = $true
        sharePointDesigner = $true
        excel              = $false
        lync               = $false
        oneNote            = $false
        outlook            = $false
        powerPoint         = $false
        publisher          = $false
        teams              = $false
        word               = $false
        access             = $false
        bing               = $false
    }
    foreach ($ExcludedApp in $ExcludedAppNames) {
        $ExcludedApps.$ExcludedApp = $true
    }

    return [PSCustomObject]@{
        '@odata.type'                          = '#microsoft.graph.officeSuiteApp'
        'displayName'                          = 'Microsoft 365 Apps for Windows 10 and later'
        'description'                          = 'Microsoft 365 Apps for Windows 10 and later'
        'informationUrl'                       = 'https://products.office.com/en-us/explore-office-for-home'
        'privacyInformationUrl'                = 'https://privacy.microsoft.com/en-us/privacystatement'
        'isFeatured'                           = $true
        'publisher'                            = 'Microsoft'
        'notes'                                = ''
        'owner'                                = 'Microsoft'
        'autoAcceptEula'                       = [bool]$Config.AcceptLicense
        'excludedApps'                         = $ExcludedApps
        'officePlatformArchitecture'           = if ($Config.arch) { 'x64' } else { 'x86' }
        'officeSuiteAppDefaultFileFormat'      = 'OfficeOpenXMLFormat'
        'localesToInstall'                     = $Languages
        'shouldUninstallOlderVersionsOfOffice' = [bool]$Config.RemoveVersions
        'updateChannel'                        = $UpdateChannel
        'useSharedComputerActivation'          = [bool]$Config.SharedComputerActivation
        'productIds'                           = @('o365ProPlusRetail')
        'largeIcon'                            = $LargeIcon
    }
}
