#
# Module manifest for module 'Microsoft.Teams.Policy.Administration.Core'
#

@{
# Script module or binary module file associated with this manifest.
RootModule = './Microsoft.Teams.Policy.Administration.Cmdlets.Core.psm1'

# Version number of this module.
ModuleVersion = '14.1.41'

# Supported PSEditions
CompatiblePSEditions = 'Core', 'Desktop'

# ID used to uniquely identify this module
GUID = '048c99d9-471a-4935-a810-542687c5f950'

# Author of this module
Author = 'Microsoft Corporation'

# Company or vendor of this module
CompanyName = 'Microsoft Corporation'

# Copyright statement for this module
Copyright = 'Microsoft Corporation. All rights reserved.'

# Description of the functionality provided by this module
Description = 'Microsoft Teams OCE cmdlets module for Policy Administration'

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '5.1'

# Name of the Windows PowerShell host required by this module
# PowerShellHostName = ''

# Minimum version of the Windows PowerShell host required by this module
# PowerShellHostVersion = ''

# Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
DotNetFrameworkVersion = '4.7.2'

# Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
CLRVersion = '4.0'

# Processor architecture (None, X86, Amd64) required by this module
# ProcessorArchitecture = 'Amd64'

# Modules that must be imported into the global environment prior to importing this module
# RequiredModules = @()

# Assemblies that must be loaded prior to importing this module
# RequiredAssemblies = @()

# Script files (.ps1) that are run in the caller's environment prior to importing this module.
# Removed this script from here because this module is used in SAW machines as well where Contraint Language Mode is on.
# Because of CLM constraint we were not able to import Teams module to SAW machines, that is why removing this script.
# ScriptsToProcess = @()

# Type files (.ps1xml) to be loaded when importing this module
# TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
FormatsToProcess = @()

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
NestedModules = @()

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = '*'

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @(
    'New-CsTeamsAppSetupPolicy',
    'Get-CsTeamsAppSetupPolicy',
    'Remove-CsTeamsAppSetupPolicy',
    'Set-CsTeamsAppSetupPolicy',
    'Grant-CsTeamsAppSetupPolicy',


    'New-CsTeamsAppPermissionPolicy',
    'Get-CsTeamsAppPermissionPolicy',
    'Remove-CsTeamsAppPermissionPolicy',
    'Set-CsTeamsAppPermissionPolicy',
    'Grant-CsTeamsAppPermissionPolicy',

    'New-CsTeamsMessagingPolicy',
    'Set-CsTeamsMessagingPolicy',
    'Get-CsTeamsMessagingPolicy',
    'Remove-CsTeamsMessagingPolicy',

    'New-CsTeamsChannelsPolicy',
    'Get-CsTeamsChannelsPolicy',
    'Remove-CsTeamsChannelsPolicy',
    'Set-CsTeamsChannelsPolicy',

    'New-CsTeamsUpdateManagementPolicy',
    'Get-CsTeamsUpdateManagementPolicy',
    'Remove-CsTeamsUpdateManagementPolicy',
    'Set-CsTeamsUpdateManagementPolicy',

    'Get-CsTeamsUpgradeConfiguration',
    'Set-CsTeamsUpgradeConfiguration',

    'New-CsTeamsMeetingPolicy',
    'Get-CsTeamsMeetingPolicy',
    'Remove-CsTeamsMeetingPolicy',
    'Set-CsTeamsMeetingPolicy',

    'Get-CsOnlineVoicemailPolicy',
    'New-CsOnlineVoicemailPolicy',
    'Remove-CsOnlineVoicemailPolicy',
    'Set-CsOnlineVoicemailPolicy',

    'Get-CsOnlineVoicemailValidationConfiguration',
    'Set-CsOnlineVoicemailValidationConfiguration',

    'New-CsTeamsFeedbackPolicy',
    'Get-CsTeamsFeedbackPolicy',
    'Remove-CsTeamsFeedbackPolicy',
    'Set-CsTeamsFeedbackPolicy',

    'New-CsTeamsMeetingBrandingPolicy',
    'Get-CsTeamsMeetingBrandingPolicy',
    'Remove-CsTeamsMeetingBrandingPolicy',
    'Set-CsTeamsMeetingBrandingPolicy',
    'Grant-CsTeamsMeetingBrandingPolicy'

    'New-CsTeamsMeetingBrandingTheme',
    'New-CsTeamsMeetingBackgroundImage',
    'New-CsTeamsNdiAssuranceSlate',

    'New-CsTeamsEmergencyCallingPolicy',
    'Get-CsTeamsEmergencyCallingPolicy',
    'Remove-CsTeamsEmergencyCallingPolicy',
    'Set-CsTeamsEmergencyCallingPolicy',
    'New-CsTeamsEmergencyCallingExtendedNotification',

    'New-CsTeamsCallHoldPolicy',
    'Get-CsTeamsCallHoldPolicy',
    'Remove-CsTeamsCallHoldPolicy',
    'Set-CsTeamsCallHoldPolicy',

    'Get-CsOnlineVoicemailValidationConfiguration',
    'Set-CsOnlineVoicemailValidationConfiguration',
    'Get-CsTeamsMessagingConfiguration',
    'Set-CsTeamsMessagingConfiguration',

    'New-CsTeamsVoiceApplicationsPolicy',
    'Get-CsTeamsVoiceApplicationsPolicy',
    'Remove-CsTeamsVoiceApplicationsPolicy',
    'Set-CsTeamsVoiceApplicationsPolicy',

    'New-CsTeamsHiddenMeetingTemplate',

    'New-CsTeamsMeetingTemplatePermissionPolicy',
    'Get-CsTeamsMeetingTemplatePermissionPolicy',
    'Set-CsTeamsMeetingTemplatePermissionPolicy',
    'Remove-CsTeamsMeetingTemplatePermissionPolicy',
    'Grant-CsTeamsMeetingTemplatePermissionPolicy',

    "Get-CsTeamsAudioConferencingCustomPromptsConfiguration",
    "Set-CsTeamsAudioConferencingCustomPromptsConfiguration",
    "New-CsCustomPrompt",
    "New-CsCustomPromptPackage",

    'Get-CsTeamsMeetingTemplateConfiguration',
    'Get-CsTeamsFirstPartyMeetingTemplateConfiguration',

    'New-CsTeamsEventsPolicy',
    'Get-CsTeamsEventsPolicy',
    'Remove-CsTeamsEventsPolicy',
    'Set-CsTeamsEventsPolicy',
    'Grant-CsTeamsEventsPolicy',

    'New-CsTeamsCallingPolicy',
    'Get-CsTeamsCallingPolicy',
    'Remove-CsTeamsCallingPolicy',
    'Set-CsTeamsCallingPolicy',
    'Grant-CsTeamsCallingPolicy',

    'New-CsExternalAccessPolicy',
    'Get-CsExternalAccessPolicy',
    'Remove-CsExternalAccessPolicy',
    'Set-CsExternalAccessPolicy',
    'Grant-CsExternalAccessPolicy',

    'Get-CsTeamsMultiTenantOrganizationConfiguration',
    'Set-CsTeamsMultiTenantOrganizationConfiguration',

    'New-CsLocationPolicy',
    'Get-CsLocationPolicy',
    'Remove-CsLocationPolicy',
    'Set-CsLocationPolicy',

    'New-CsTeamsCarrierEmergencyCallRoutingPolicy',
    'Get-CsTeamsCarrierEmergencyCallRoutingPolicy',
    'Remove-CsTeamsCarrierEmergencyCallRoutingPolicy',
    'Set-CsTeamsCarrierEmergencyCallRoutingPolicy',
    'Grant-CsTeamsCarrierEmergencyCallRoutingPolicy',

    'Get-CsTenantConfiguration',
    'Set-CsTenantConfiguration',

    'Get-CsTenantNetworkSite',

    'New-CsTeamsShiftsPolicy',
    'Get-CsTeamsShiftsPolicy',
    'Remove-CsTeamsShiftsPolicy',
    'Set-CsTeamsShiftsPolicy',
    'Grant-CsTeamsShiftsPolicy',

    'New-CsTeamsHiddenTemplate',

    'New-CsTeamsTemplatePermissionPolicy',
    'Get-CsTeamsTemplatePermissionPolicy',
    'Remove-CsTeamsTemplatePermissionPolicy',
    'Set-CsTeamsTemplatePermissionPolicy',

    'Get-CsTeamsAppPolicyConfiguration',
    'Set-CsTeamsAppPolicyConfiguration',

    'Get-CsTeamsSipDevicesConfiguration',
    'Set-CsTeamsSipDevicesConfiguration',

    'New-CsTeamsVirtualAppointmentsPolicy',
    'Get-CsTeamsVirtualAppointmentsPolicy',
    'Remove-CsTeamsVirtualAppointmentsPolicy',
    'Set-CsTeamsVirtualAppointmentsPolicy',
    'Grant-CsTeamsVirtualAppointmentsPolicy',

    'New-CsTeamsComplianceRecordingPolicy',
    'Get-CsTeamsComplianceRecordingPolicy',
    'Remove-CsTeamsComplianceRecordingPolicy',
    'Set-CsTeamsComplianceRecordingPolicy',

    'New-CsTeamsComplianceRecordingApplication',
    'Get-CsTeamsComplianceRecordingApplication',
    'Remove-CsTeamsComplianceRecordingApplication',
    'Set-CsTeamsComplianceRecordingApplication',

    'New-CsTeamsComplianceRecordingPairedApplication',

    'New-CsTeamsSharedCallingRoutingPolicy',
    'Get-CsTeamsSharedCallingRoutingPolicy',
    'Remove-CsTeamsSharedCallingRoutingPolicy',
    'Set-CsTeamsSharedCallingRoutingPolicy',
    'Grant-CsTeamsSharedCallingRoutingPolicy',

    'New-CsTeamsVdiPolicy',
    'Get-CsTeamsVdiPolicy',
    'Remove-CsTeamsVdiPolicy',
    'Set-CsTeamsVdiPolicy',
    'Grant-CsTeamsVdiPolicy',

    'Get-CsTeamsMeetingConfiguration',
    'Set-CsTeamsMeetingConfiguration',

    'New-CsTeamsCustomBannerText',
    'Get-CsTeamsCustomBannerText',
    'Set-CsTeamsCustomBannerText',
    'Remove-CsTeamsCustomBannerText',
    
    'Get-CsTeamsEducationConfiguration',
    'Set-CsTeamsEducationConfiguration',

    'New-CsTeamsWorkLocationDetectionPolicy',
    'Get-CsTeamsWorkLocationDetectionPolicy',
    'Remove-CsTeamsWorkLocationDetectionPolicy',
    'Set-CsTeamsWorkLocationDetectionPolicy',
    'Grant-CsTeamsWorkLocationDetectionPolicy', 

    'New-CsTeamsMediaConnectivityPolicy',
    'Get-CsTeamsMediaConnectivityPolicy',
    'Remove-CsTeamsMediaConnectivityPolicy',
    'Set-CsTeamsMediaConnectivityPolicy',
    'Grant-CsTeamsMediaConnectivityPolicy',

    'New-CsTeamsRecordingRollOutPolicy',
    'Get-CsTeamsRecordingRollOutPolicy',
    'Remove-CsTeamsRecordingRollOutPolicy',
    'Set-CsTeamsRecordingRollOutPolicy',
    'Grant-CsTeamsRecordingRollOutPolicy',
	
	'New-CsTeamsFilesPolicy',
    'Get-CsTeamsFilesPolicy',
    'Remove-CsTeamsFilesPolicy',
    'Set-CsTeamsFilesPolicy',
    'Grant-CsTeamsFilesPolicy',
    
    'Get-CsTeamsExternalAccessConfiguration',
    'Set-CsTeamsExternalAccessConfiguration',

    'New-CsConversationRole',
    'Remove-CsConversationRole',
    'Get-CsConversationRole',
    'Set-CsConversationRole',

    'Get-CsConversationRolesSetting',
    'Set-CsConversationRolesSetting',

    'Get-CsTeamsAIPolicy',
    'Set-CsTeamsAIPolicy',
    'New-CsTeamsAIPolicy',
    'Remove-CsTeamsAIPolicy',
    'Grant-CsTeamsAIPolicy',

    'New-CsTeamsBYODAndDesksPolicy',
    'Get-CsTeamsBYODAndDesksPolicy',
    'Remove-CsTeamsBYODAndDesksPolicy',
    'Set-CsTeamsBYODAndDesksPolicy',
    'Grant-CsTeamsBYODAndDesksPolicy',

    'Get-CsTeamsTenantAbuseConfiguration',
    'Set-CsTeamsTenantAbuseConfiguration',

    'Get-CsTeamsEducationAssignmentsAppPolicy',
    'Set-CsTeamsEducationAssignmentsAppPolicy',

    'Get-CsPrivacyConfiguration',
    'Set-CsPrivacyConfiguration',

    'Get-CsTeamsNotificationAndFeedsPolicy',
    'Set-CsTeamsNotificationAndFeedsPolicy',
    'Remove-CsTeamsNotificationAndFeedsPolicy'
    
    'Get-CsTeamsClientConfiguration',
    'Set-CsTeamsClientConfiguration'
)

# Variables to export from this module
VariablesToExport = @()

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = @()

# DSC resources to export from this module
# DscResourcesToExport = @()

# List of all modules packaged with this module
# ModuleList = @()

# List of all files packaged with this module
# FileList = @()

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{}

# HelpInfo URI of this module
# HelpInfoURI = ''

# Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
# DefaultCommandPrefix = ''
}
# SIG # Begin signature block
# MIIoRQYJKoZIhvcNAQcCoIIoNjCCKDICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCANAK8NLwgKddO1
# 9Yig7LqADOvFdgAd/ZjVP4Qk4mEa+6CCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
# Bv9XKydyAAAAAAQEMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjQwOTEyMjAxMTE0WhcNMjUwOTExMjAxMTE0WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC0KDfaY50MDqsEGdlIzDHBd6CqIMRQWW9Af1LHDDTuFjfDsvna0nEuDSYJmNyz
# NB10jpbg0lhvkT1AzfX2TLITSXwS8D+mBzGCWMM/wTpciWBV/pbjSazbzoKvRrNo
# DV/u9omOM2Eawyo5JJJdNkM2d8qzkQ0bRuRd4HarmGunSouyb9NY7egWN5E5lUc3
# a2AROzAdHdYpObpCOdeAY2P5XqtJkk79aROpzw16wCjdSn8qMzCBzR7rvH2WVkvF
# HLIxZQET1yhPb6lRmpgBQNnzidHV2Ocxjc8wNiIDzgbDkmlx54QPfw7RwQi8p1fy
# 4byhBrTjv568x8NGv3gwb0RbAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQU8huhNbETDU+ZWllL4DNMPCijEU4w
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzUwMjkyMzAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAIjmD9IpQVvfB1QehvpC
# Ge7QeTQkKQ7j3bmDMjwSqFL4ri6ae9IFTdpywn5smmtSIyKYDn3/nHtaEn0X1NBj
# L5oP0BjAy1sqxD+uy35B+V8wv5GrxhMDJP8l2QjLtH/UglSTIhLqyt8bUAqVfyfp
# h4COMRvwwjTvChtCnUXXACuCXYHWalOoc0OU2oGN+mPJIJJxaNQc1sjBsMbGIWv3
# cmgSHkCEmrMv7yaidpePt6V+yPMik+eXw3IfZ5eNOiNgL1rZzgSJfTnvUqiaEQ0X
# dG1HbkDv9fv6CTq6m4Ty3IzLiwGSXYxRIXTxT4TYs5VxHy2uFjFXWVSL0J2ARTYL
# E4Oyl1wXDF1PX4bxg1yDMfKPHcE1Ijic5lx1KdK1SkaEJdto4hd++05J9Bf9TAmi
# u6EK6C9Oe5vRadroJCK26uCUI4zIjL/qG7mswW+qT0CW0gnR9JHkXCWNbo8ccMk1
# sJatmRoSAifbgzaYbUz8+lv+IXy5GFuAmLnNbGjacB3IMGpa+lbFgih57/fIhamq
# 5VhxgaEmn/UjWyr+cPiAFWuTVIpfsOjbEAww75wURNM1Imp9NJKye1O24EspEHmb
# DmqCUcq7NqkOKIG4PVm3hDDED/WQpzJDkvu4FrIbvyTGVU01vKsg4UfcdiZ0fQ+/
# V0hf8yrtq9CkB8iIuk5bBxuPMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGiUwghohAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAQEbHQG/1crJ3IAAAAABAQwDQYJYIZIAWUDBAIB
# BQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIDvW1VEWkKR+opQJ0eNZagku
# BtzDJSdiqsBWxcY8oFA+MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
# BQAEggEASOXr5mkipagNQf0tik6FfDw1h8hgp3oYkYtdZYNypJrXeBPDHhryozc1
# stXOSWx2DJTE5DMhxv8Qk0qTH4u/pXXvZ//p57MTV4Puw5G09v5yzLA5fNJFz+gA
# iSo1OeL5Chspa77YPYNk/cfYI7BzgM+kgEBdvJjpkHUNrqOykhyCasEY3mc1ea9k
# dHJh0aYReaBH7NWhZwY9dcOeZToTg5dz26293qVTmvyvD+Jvus+dE5NWPqYVSRfJ
# hoDBY39q4tIj+T8F8+U3O1/A6ATAiSLSkSc5VBLdjp8Q7u1nehV52AJ7YNWK98DC
# OVf6C98rVdamTVT20cbEwiwPwuz+iKGCF68wgherBgorBgEEAYI3AwMBMYIXmzCC
# F5cGCSqGSIb3DQEHAqCCF4gwgheEAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFZBgsq
# hkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFl
# AwQCAQUABCC0YoIGIev5IeW7k0coL1hC0mtSBTJnRHltfVrOOued9AIGZ7Ypj94Y
# GBIyMDI1MDMxMzA4NDcyMi42NlowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVs
# YW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNO
# OjU5MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNloIIR/jCCBygwggUQoAMCAQICEzMAAAH0F0aFwMs/OeUAAQAAAfQwDQYJ
# KoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMjQw
# NzI1MTgzMDU5WhcNMjUxMDIyMTgzMDU5WjCB0zELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3Bl
# cmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046NTkxQS0w
# NUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Uw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCnCE4TptCAL2qriMkZfYDX
# Kg5t+TSp61DySSP7mbftYHEOWxnmgmeN/Meymo+I4RXNnbLbKAaA1nf/F1lA3t/0
# DVanUB2HmoddlmHdIFfwAG5zr1NvdwnkoJlxcOy5/CZd4KPzUTMkQhmq5V1XxJOV
# C54H9vUwhi3lEqKze7DN2V9KXRyQdsbOg73VhMqDogTGopiiMat4KimcgrE6+Svl
# VmyPZ/3kFvUsYS+6EEib8LsnKy8m8FlY22uynPJdWe6j6QMTJnCmSmGxHxm92L6z
# +lCKh+Z1tbVSrNaWpdBWChhdtpiQTJpKH+F4G3CPW2574ty45wcA+BvBm9AuSwpo
# rjqiS2t6A5Hh7SJywaIBZH0gv6fLiaUJQ0DzgXsYQRY4S+JuKDvCytNrplvO4yzJ
# OLYDPio9XdBGQWDFJunhHg4QqeKfwnPhcsjXBeEGEikwZ8DcFPznSepqbNKIPkvm
# nH5W18KLQwlNLYsMXU9pVnCXJVkhWNUcryiHYdgb1PboWNH38jzmLkTHGaEenEzZ
# n5SEl5kDovPjnab/7GsDjGt1hqzlybsVSHLbis8tUf4XL5nLAcCn1z2hZOu2N8gq
# osi9i2AlzjVDxbFtk9HsHW5+3wEWy/PZ05IuTE8MtxdbLXoA3Lve/SKkLEDBQQL2
# GyyLQt0HxOGI1//gD5FnywIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFCt0ZaEK0Sw+
# J3UsnOxNotMpBt+bMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8G
# A1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBs
# BggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUy
# MDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUH
# AwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQDdwdIPEkpQOyBp
# wh9FfrS6A4NKGwGrC0RRFRtRd4OZhhJrmgWPfhG6NbeA54K385sM7jm9+mdgbk5L
# lijDCwXDX2CIIjolX5xwb+qozTyfEBJvPBa2q2ivNCImH26mwThNVl4pheZvLHtY
# 3211tUisJ6VWPs/qJ8wdNIu3oGbKhLbGULZx+Ao88DXe9Ld66pSXrPB7sYCGN+M1
# eMqUThI1Ym92qCu/QZREqOqZqY2+GZIlqd7pNjOl0MJ6Crxp2UYfzkjURYqZ8RFv
# WXMrLk4w7Z70iQCW/J2lS6fQLew0S2nR6GWJPRKtqryNxhUMfgDYL8xssEjCKSPC
# IUZDhKUUtPZOBvga++lxZXMHHAOj0hEHCnOeBvLNuGH3lRU6tAvattYescNITd2B
# 0vbK5odGBjsdhguzku2zfTBT066Hw3nhFS1roYVkXHkDi4hODIlxV1ZVo3SqOzR4
# SPATI1S/RxEu4dYkF6OQx7epECG8KOeGujsMZFZoiV3J/NmqWfoWyctDduX5m9Ul
# ZNgm4v4hksjZKLcishF+Nxyfb1fYFf+/PYpxi5siMrpd9i+tlA3hcpue9KoE0DAg
# 9jbEl4Hij08MQUjatw9otTLPkhXsk/clGmCDfGxSq8UeVIbq4whaPAfQZAgjCsLb
# NHL6U1mw4qeu7LIcxBM/uPLlT3aoQTCCB3EwggVZoAMCAQICEzMAAAAVxedrngKb
# SZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmlj
# YXRlIEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIy
# NVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UE
# AxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXI
# yjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjo
# YH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1y
# aa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v
# 3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pG
# ve2krnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viS
# kR4dPf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYr
# bqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlM
# jgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSL
# W6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AF
# emzFER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIu
# rQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIE
# FgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWn
# G1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEW
# M2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5
# Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBi
# AEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV
# 9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3Js
# Lm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAx
# MC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2
# LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv
# 6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZn
# OlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1
# bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4
# rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU
# 6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDF
# NLB62FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/
# HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdU
# CbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKi
# excdFYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTm
# dHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZq
# ELQdVTNYs6FwZvKhggNZMIICQQIBATCCAQGhgdmkgdYwgdMxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVs
# YW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNO
# OjU5MUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQC/4tn9WDSzXtd6TiIb1H1z/v4AjqCBgzCB
# gKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUA
# AgUA63z+gTAiGA8yMDI1MDMxMzA2NDkzN1oYDzIwMjUwMzE0MDY0OTM3WjB3MD0G
# CisGAQQBhFkKBAExLzAtMAoCBQDrfP6BAgEAMAoCAQACAgb8AgH/MAcCAQACAhMe
# MAoCBQDrflABAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAI
# AgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAJugOwKeAhMG
# OAjBxYtfOPkD/1lTdB5qTMa7Aya2e/5vGGvwMMwO7ACKcIgL2Bt43ehshHrJRRrt
# rGWwhjb02OSgc1mWJSUeAFsbOy7Kob8cjvhL8o1QOmOmX6lpIUp2OtefY1oTGELX
# Wb6K1XsWjdBFLRHXpOPFJkHLoB9ytwbWosmUHgwgIeEgDuSA24UX1bu34bsU4ciF
# P5c8T2GfBgSD/LMYIOCbXppgV9HDr1a5O8wTfPrJj/m6nmXNZIEqq3eVMjVDWQ8d
# A1csciDpllLU+MrE1cycO+85adsvtr4jmsOhiZcRrCL7Lhqw1D/lYy6cYGbxrQXd
# 77hx07DrMV8xggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMAITMwAAAfQXRoXAyz855QABAAAB9DANBglghkgBZQMEAgEFAKCCAUowGgYJ
# KoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCApLD6jPJnZ
# zK61UfDSoarUOuE190X3/u5jaKDRjYl+lTCB+gYLKoZIhvcNAQkQAi8xgeowgecw
# geQwgb0EID9YwnxuJpPqeO+SScHxDuFJAiLzKzq8gG9mDrREGNZrMIGYMIGApH4w
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH0F0aFwMs/OeUAAQAA
# AfQwIgQgeyvumxbXmilnjXajcZKwkCkngQLQaAb7YPoPXSRjUCcwDQYJKoZIhvcN
# AQELBQAEggIAIx2BKQnTNsUdEcJRpObNP03hdV9aHf6DacA075s1rYKP1j8LPeKJ
# yoRzbbtkZuuY05XIXwzwk6y5JFRbmTnqLBhJlTISC1l6FJUs0rdeGc9sz226PEsm
# JatlPaxBh8s2dAhykKhqEq3HCnMC2jMtaH7e8elAj943agLzmwGF9/I1RVuCQSGk
# yzltB/RFURaffc1uKkRcmE/Fz4QckNRdK/U/63otWDlSFZz4+U8J6qWDmy7ZZcR+
# x072UDS1bEeZeYRwDQ1xVmghfu2KZjFG2a8IyWD6bajV4IQgAeUG2qnKvzGYok7k
# viLdhNwR53PY8HL67Hu2I1jNb9Kt1nlIP573CW/6ISHBHWGdiUrKH/uFJZqYL72p
# 90qFV7yEUugGLs1hSPkS1kVMT+veNgE7kFEtAD3GE6v0ngLHKJNVaojpxmaWZWpH
# /3RYr6yrlxmrtErSTuTnzIEelQHTdAWSRDzdTNNBJqZLcyTaYAcWydUX2uYld3AK
# 5ebG7YcjarTz3NfA7rFpPv3Th//XRDMHgJ1lbUyNTPctmWO2NtgfpwKh934YyYzE
# NXGymWnuoGrM9ygiq5/X2XlRVpWrSn1XD6/SpI4Hd5PECCgWjIkabuNZvwY1kwvv
# 5EtSaGR3jKn2E5Go75wqZObN0VQWuDaGH9QF1F+nKePZ0NY4M+mWlJ0=
# SIG # End signature block
