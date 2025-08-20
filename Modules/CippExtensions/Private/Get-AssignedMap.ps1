function Get-AssignedMap {
    # Assigned Licenses Map
    $AssignedMap = [pscustomobject]@{
        'AADPremiumService'             = 'o-skypeforbusiness'
        'MultiFactorService'            = 'o-skypeforbusiness'
        'RMSOnline'                     = 'o-skypeforbusiness'
        'MicrosoftPrint'                = 'o-yammer'
        'WindowsDefenderATP'            = 'o-skypeforbusiness'
        'exchange'                      = 'o-exchange'
        'ProcessSimple'                 = 'o-onedrive'
        'OfficeForms'                   = 'o-yammer'
        'SCO'                           = 'o-skypeforbusiness'
        'MicrosoftKaizala'              = 'o-yammer'
        'Adallom'                       = 'o-skypeforbusiness'
        'ProjectWorkManagement'         = 'o-yammer'
        'TeamspaceAPI'                  = 'o-teams'
        'MicrosoftOffice'               = 'o-yammer'
        'PowerAppsService'              = 'o-onedrive'
        'SharePoint'                    = 'o-sharepoint'
        'MicrosoftCommunicationsOnline' = 'o-teams'
        'Deskless'                      = 'o-yammer'
        'MicrosoftStream'               = 'o-yammer'
        'Sway'                          = 'o-yammer'
        'To-Do'                         = 'o-yammer'
        'WhiteboardServices'            = 'o-yammer'
        'Windows'                       = 'o-skypeforbusiness'
        'YammerEnterprise'              = 'o-yammer'
    }

    return $AssignedMap

}
