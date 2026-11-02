function Get-CIPPEdgeAppBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Config
    )

    if ($Config.IntuneBody) {
        $IntuneBody = $Config.IntuneBody
        if ($IntuneBody -is [string]) {
            $IntuneBody = $IntuneBody | ConvertFrom-Json -Depth 100
        } else {
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

    $Channel = if ($Config.edgeChannel.value) { $Config.edgeChannel.value } else { $Config.edgeChannel }
    if (-not $Channel) { $Channel = 'stable' }

    $Body = [PSCustomObject]@{
        '@odata.type'          = '#microsoft.graph.windowsMicrosoftEdgeApp'
        'displayName'          = 'Microsoft Edge for Windows 10 and later'
        'description'          = 'Microsoft Edge for Windows 10 and later'
        'publisher'            = 'Microsoft'
        'isFeatured'           = $false
        'informationUrl'       = 'https://www.microsoft.com/edge'
        'privacyInformationUrl' = 'https://privacy.microsoft.com/en-us/privacystatement'
        'owner'                = 'Microsoft'
        'notes'                = ''
        'channel'              = $Channel
    }

    $Locale = if ($Config.displayLanguageLocale.value) { $Config.displayLanguageLocale.value } else { $Config.displayLanguageLocale }
    if ($Locale) {
        $Body | Add-Member -NotePropertyName 'displayLanguageLocale' -NotePropertyValue $Locale
    }

    return $Body
}
