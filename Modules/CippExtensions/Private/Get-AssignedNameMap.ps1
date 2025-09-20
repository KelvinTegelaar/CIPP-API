function Get-AssignedNameMap {

    $AssignedNameMap = @{
        'AADPremiumService'             = 'Azure Active Directory Premium'
        'MultiFactorService'            = 'Azure Multi-Factor Authentication'
        'RMSOnline'                     = 'Azure Rights Management'
        'MicrosoftPrint'                = 'Cloud Print'
        'WindowsDefenderATP'            = 'Defender for Endpoint'
        'exchange'                      = 'Exchange Online'
        'ProcessSimple'                 = 'Flow'
        'OfficeForms'                   = 'Forms'
        'SCO'                           = 'Intune'
        'MicrosoftKaizala'              = 'Kaizala'
        'Adallom'                       = 'Microsoft Cloud App Security'
        'ProjectWorkManagement'         = 'Microsoft Planner'
        'TeamspaceAPI'                  = 'Microsoft Teams'
        'MicrosoftOffice'               = 'Office 365'
        'PowerAppsService'              = 'PowerApps'
        'SharePoint'                    = 'SharePoint Online'
        'MicrosoftCommunicationsOnline' = 'Skype for Business'
        'Deskless'                      = 'Staff Hub'
        'MicrosoftStream'               = 'Stream'
        'Sway'                          = 'Sway'
        'To-Do'                         = 'To-Do'
        'WhiteboardServices'            = 'Whiteboard'
        'Windows'                       = 'Windows'
        'YammerEnterprise'              = 'Yammer'
    }

    return $AssignedNameMap

}
