#
# Module manifest for module 'Microsoft.Teams.Policy.Administration.Core'
#

@{
# Script module or binary module file associated with this manifest.
RootModule = './Microsoft.Teams.Policy.Administration.Cmdlets.Core.psm1'

# Version number of this module.
ModuleVersion = '31.6.0.1'

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

    'New-CsTeamsPersonalAttendantPolicy',
    'Get-CsTeamsPersonalAttendantPolicy',
    'Remove-CsTeamsPersonalAttendantPolicy',
    'Set-CsTeamsPersonalAttendantPolicy',
    'Grant-CsTeamsPersonalAttendantPolicy',

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
    'Set-CsTeamsClientConfiguration',
    
    'Get-CsTeamsAcsFederationConfiguration',
    'Set-CsTeamsAcsFederationConfiguration',

    'Get-DirectToGroupAssignmentsMigrationStatus',
    'Get-GroupAssignmentRecommendationsPerPolicyName'
    'Get-GroupAssignmentRecommendationsPerPolicyType',
    'Get-GroupPolicyAssignmentConflict',
    'Invoke-ClearDirectToGroupAssignmentMigration',
    'Invoke-StartDirectToGroupAssignmentMigration'
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
# MIInSQYJKoZIhvcNAQcCoIInOjCCJzYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD4G32j3Z30B+0l
# jWZzTAHqNQXashLb2xzHsXWyQJVJ4KCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
# yE7XD1dIAAAAAAIdMA0GCSqGSIb3DQEBCwUAMFcxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBD
# b2RlIFNpZ25pbmcgUENBIDIwMjQwHhcNMjYwNDE2MTg1OTQzWhcNMjcwNDE1MTg1
# OTQzWjB0MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYD
# VQQDExVNaWNyb3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQDQvewXxx9gZZFC6Ys1WBay8BJ8kGA4JQnH5CMafqOASlTpK9H8
# o5ZXTXt0caVQTNMUPt445wXYD+dFtaKWTwDn1I52oUSrC9vJin1Gsqt+zyKJL5Dg
# 3eQXbQNR61DmMy20GLTIO3SFed9Rfi/ophgCLGFLDR3r0KvHjwMb/jYWS0celV/4
# Lz27LfAekm8v9E5IXaeiXbAUYZKK090n4CVl3JBtbN+9DtI9SNu/yjvozW52/u7R
# X/Ttpa/KDlpuokZ+Zcbvmtd9ur9gFLvZzh41o9MsE/clQtdaFWGvuo6Jua/ntpgk
# ey3E5/vBFe+MJPG6phdnuo6r57ZudCudiI1bAgMBAAGjggGbMIIBlzAOBgNVHQ8B
# Af8EBAMCB4AwHwYDVR0lBBgwFgYKKwYBBAGCN0wIAQYIKwYBBQUHAwMwHQYDVR0O
# BBYEFH6QuMwqcPG0hQlQ6c5jCtTTLrVeMEUGA1UdEQQ+MDykOjA4MR4wHAYDVQQL
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xFjAUBgNVBAUTDTIzMDAxMis1MDc1NTkw
# HwYDVR0jBBgwFoAUf1k/VCHarU/vBeXmo9ctBpQSCDEwYAYDVR0fBFkwVzBVoFOg
# UYZPaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0
# JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNybDBtBggrBgEFBQcBAQRh
# MF8wXQYIKwYBBQUHMAKGUWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y2VydHMvTWljcm9zb2Z0JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNy
# dDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4ICAQBKTbYOjzwTG/DXGaz9
# s6+fQeaTtDcFmMY+5UyVFCyj7Pv+5i37qfX8lSL/tBIfYQfWsMuBQlfZurJD6r4H
# VJ2CeH+1fgiq8dcHdVKoZ3Sa2qXoX3cq9iS8cVb06B7+5/XJ7I0OxHH9fDsvJ3T3
# w5V/ZtAIFmLrl+P0CtG+92uzRsn0nTbdFjOkLMLWPLAU3THohKRlSEMgFJpPkm5n
# 5UAZ35xX6FWCrDLsSKb555bTifwa8mJBwdlof0bmfYidH+dxZ1FdDxvLnNl9zeKs
# A4kejaaIqqIPguhwAti5Ql7BlTNoJNwxCvBmqW2MQLnCkYN/VVUsR3V2x/rcTNzo
# Bf/Z/SpROvdaA2ZOOd1uioXJt3tdLQ7vHpqpib0KfWr/FWXW10q38VxfCnRQBqzb
# SuztR7nEMuzX7Ck+B/XaPDXd1qh72+QYyB0Z2VzWmO9zsnb9Uq/dwu8LGeQqnyu6
# 7SDGACvnXii2fb9+US492VTnXSnFKyqwgzUyFMtZK1/sHYTv6bG4TtQUygQxTN+Z
# V+aJIlKO2MqZ7bKrAnOzS9m6NgoTdWOq11bTOZwKlIEV/EhV9SWkDmdpR/hPPT2v
# 6TEj4F8PT/zHjRezIU5c/DGlt/VhY/pK0XkJtEyMmmS1BMtjU/rqBZVMIm3dnxQs
# /TBByr+Cf8Z1r7aifQVQ+WSqzjCCBr0wggSloAMCAQICEzMAAAA5O7Y3Gb8GHWcA
# AAAAADkwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRl
# IEF1dGhvcml0eSAyMDExMB4XDTI0MDgwODIwNTQxOFoXDTM2MDMyMjIyMTMwNFow
# VzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEo
# MCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAyNDCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBANgBnB7jOMeqlRYHNa265v4IY9fH8TKh
# emHfPINe1gpLaV3dhg324WwH06LcHbpnsBukCDNitryo0dtS/EW6I/yEL/bLSY8h
# KpbfQuWusBPr9qazYcDxCW/qnjb5JsI1s8bNOg3bVATvQVL4tcf03aTycsz8QeCd
# M0l/yHRObJ9QqazM1r6VPEOJ7LL+uEEb73w6QCuhs89a1uv1zerOYMnsneRRwCbp
# yW11IcggU0cRKDDq1pjVJzIbIF6+oiXXbReOsgeI8zu1FyQfK0fVkaya8SmVHQ/t
# Of23mZ4W9k0Ri22QW9p3UgSC5OUDktKxxcCmGL6tXLfOGSWHIIV4YrTJTT6PNty5
# REojHJuZHArkF9VnHTERWoTjAzfI3kP+5b4alUdhgAZ7ttOu1bVnXfHaqPYl2rPs
# 20ji03LOVWsh/radgE17es5hL+t6lV0eVHrVhsssROWJuz2MXMCt7iw7lFPG9LXK
# Gjsmonn2gotGdHIuEg5JnJMJVmixd5LRlkmgYRZKzhxSCwyoGIq0PhaA7Y+VPct5
# pCHkijcIIDm0nlkK+0KyepolcqGm0T/GYQRMhHJlGOOmVQop36wUVUYklUy++vDW
# eEgEo4s7hxN6mIbf2MSIQ/iIfMZgJxC69oukMUXCrOC3SkE/xIkgpfl22MM1itkZ
# 35nNXkMolU1lAgMBAAGjggFOMIIBSjAOBgNVHQ8BAf8EBAMCAYYwEAYJKwYBBAGC
# NxUBBAMCAQAwHQYDVR0OBBYEFH9ZP1Qh2q1P7wXl5qPXLQaUEggxMBkGCSsGAQQB
# gjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU
# ci06AjGQQ7kUBU7h6qfHMdEjiTQwWgYDVR0fBFMwUTBPoE2gS4ZJaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0MjAx
# MV8yMDExXzAzXzIyLmNybDBeBggrBgEFBQcBAQRSMFAwTgYIKwYBBQUHMAKGQmh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0MjAx
# MV8yMDExXzAzXzIyLmNydDANBgkqhkiG9w0BAQwFAAOCAgEAFJQfOChP7onn6fLI
# MKrSlN1WYKwDFgAddymOUO3FrM8d7B/W/iQ6DxXsDn7D5W4wMwYeLystcEqfkjz4
# NURRgazyMu5yRzQh4LqjA4tStTcJh1opExo7nn5PuPBYnbu0+THSuVHTe0VTTPVh
# ily/piFrDo3axQ9P4C+Ol5yet+2gTfekICS5xS+cYfSIvgn0JksVBVMYVI5QFu/q
# hnLhsEFEUzG8fvv0hjgkO+lkpV9ty6GkN4vdnd7ya6Q6aR9y34aiM1qmxaxBi6OU
# nyNl6fkuun/diTFnYDLTppOkr/mg5WSfCiDVMNCxtj4wPKC5OmHm1DQIt/MNokbb
# H3UGsFP1QbzsLocuSqLCvH09Io3fDPTmscR9Y75G4qX7RTX8AdBPo0I6OEojf39z
# uFZt0qOHm65YWQE69cZM2ueE1MB05dNNgHK9gTE7zKvK/fg8B2qjW88MT/WF5V5u
# vZGtqa9FSL2RazArA+rDPuf6JGYz4HpgMZHB4S6szWSKYBv0VisCzfxgeU+dquXW
# 9bd0auYlOB58DPcOYKdc3Se94g+xL4pcEhbB54JOgAkwYTu/9dLeH2pDqeJZAABV
# DWRQCaXfO5LgyKwKCLYXpigrZYCjUSBcr+Ve8PFWMhVTQl0v4q8J/AUmQN5W4n10
# 1cY2L4A7GTQG1h32HHAvfQESWP0xghnlMIIZ4QIBATBuMFcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIdTRnITtcPV0gAAAAAAh0w
# DQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIB9f5iqC
# bL2SbrjbdsmdptKcMNmoIfQweNyvHL41vxt8MEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAYYlwzxXdEVqPqQggl2An2/Qo8FVr7Xxtp4l4mljY
# 6DZPVimNS80A7D5TazrzJhkE4SapSaHFNT72IMrwoMtHI0UjrujcKo3pVTWknRe7
# aR3IhQ4qAX8lIqSrkunKm8HgLPtCTUG9nU/ejMNOh6DEwQc0BbDvF2wEKhkaqfLj
# rSLnjG5cckhbBHHibC3tyR5Jp9hn6zxXt4fQ7ghomWGDSatDDinI5rEXVCOavQsj
# nmMD55QnDqhb+Qx8z4+IthxGcosmtfk4zafKxFTFmVOJFQWlX3OfXmj6y0X92k42
# +wLdxZyQMQi9IhEOPNhPCTw/9LgZPRjtxl401k3NKgCSzKGCF5cwgheTBgorBgEE
# AYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCBoFrh1W/WJuMdA+evzMT6vsbApDUev5Xcv2S8N
# vtZPVQIGagXdk1zNGBMyMDI2MDUxNTEwMDY0MC43MTJaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046ODkwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAiJB0vaq/8i1/wABAAAC
# IjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTM5NTZaFw0yNzA1MTcxOTM5NTZaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046ODkwMC0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC1ueKJukIuUsAAJo/AY5DZRqH7
# bhgv7CWGNlEdbRGoITrdE6Wsn57NaNu1BTdjBbFcv7Rfixte0x+HRvXSqsD+WeSX
# /6/y9wE0Mz+xRPTGIY20K7aQDa68OyzVyUeUCypyZC/gW/3ytO/ZOnU9H2ri77kJ
# P8ABrqyy1UxX/OseEgvHsj8yikWT0ARtrjWbXMHFzSOo5hQcfUmMXKqWWz6+N0+U
# ynhGy1n+doW4WZgpH8Y5W7hpSokWj1M/Lu4wi3o6Dz9vVWukcgUFGjLAl4YZpOha
# h7HuiC/alXImMQf8C3A8q/6/1hFoeIZB4UGkywxB/OSTOSsL6+39pDqzM7CgOpf4
# V799kN94yM9uXJI5T/SiA5MdIZIhEW0+bh85RqDh5YW3/oav54RPxw5OPlH64QV6
# KJkl0FIElMVoLNo8UWRQcMD179x7WASjC6LsaNZ7yK0qcESIsL1wiQmdfQBxcqrF
# CpIQfnmQFkOp9IyXUWqza8tmpz8E6aXg9b1eiAT3PVTgrOlPi/hYZCfPxX/6jGty
# Pjy1CiwOmJamohmSU//COAenfRT2G2HMRUpCX1zs+AmDmdQM1XRab4YSALLAlDzG
# CsgI77nnuJjoXAliJmv7NfrvWAcA5KqCUOWQ6kSPt5r28MfKXWJJpSXtFeS/MkDz
# Jy/iJRVyHcFy/B+MtwIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFFkHwGoDJ5ZbEEiu
# 8KstiusqaozQMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQBiAM+nqrpwG29txSXv
# 42o+CsTe2C4boaRfFju9JaWkLTHwq7pknNONL3n+UG3x/B083EKXiFYrAmul7BTH
# CGXU63/xRsZ2wj3ZmR0A4d9nf9saCJVm4juPVFBai/oktOOYH2j+1+zM70woN5on
# gB/pvy7X8AfY6JB4XPvb80Qz7fY5eddbnwjzg1sZhUPFbbcweWeACINrzqFK62mM
# eXKmhtufMraoogJeJXfWY3x4/pbubgENT3+pXT65203CPF9kfdKE7GKAIRYy3xkB
# TDvFd8dufjOpCn38nK6qMlVtnBjDhWQG0PM3E/oxBs5UBrI6pBYkmIHtbjifDquH
# T+ThaVV7xHc6InoSc3aNzX49JHUgQmuvDdMjLkbYXeA0/1q5IxSg2U+ycZBOvAi3
# udZPKhA5VzODjf/ucu/vFtXrYcRkmGKN3jujaK3/yMZi2Ju5NEL3ISWorwp7RjeZ
# g+JMIK0fosuVj+YCm5r64LH/D9QJDAj+XfZaNeFdv90K5A0QRRGP/poB9yTIVjEX
# j/uJzp8L4Dd44sAquqDOiHdkLgxfK8nPqpCSWPZ9G+RCPm85o9cAfxENtrSuOwcp
# yKzxsRCYCL+PK4+98orit9EVJ/LLoCeG+jLlj0KaD4Qy6sZe4rWMr1brQLosTBZN
# wFnXxNjInCWBd0i7is1yTS/4qTCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
# AAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRl
# IEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVow
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX
# 9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1q
# UoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8d
# q6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byN
# pOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2k
# rnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4d
# Pf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgS
# Uei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8
# QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6Cm
# gyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzF
# ER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQID
# AQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQU
# KqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1
# GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0
# bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMA
# QTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbL
# j+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1p
# Y3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0w
# Ni0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIz
# LmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwU
# tj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN
# 3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU
# 5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5
# KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGy
# qVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB6
# 2FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltE
# AY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFp
# AUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcd
# FYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRb
# atGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQd
# VTNYs6FwZvKhggNQMIICOAIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjg5MDAtMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQC7ycXVZx3bsDpJkr7VucgpksozuKCBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7bEEtjAiGA8y
# MDI2MDUxNTAyMzQzMFoYDzIwMjYwNTE2MDIzNDMwWjB3MD0GCisGAQQBhFkKBAEx
# LzAtMAoCBQDtsQS2AgEAMAoCAQACAgWmAgH/MAcCAQACAhJlMAoCBQDtslY2AgEA
# MDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAI
# AgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAMnzxlgACHgug8/waMWz4/ELvZIE
# KqVI7MNoSmqwjR2tebywd4nc5Wcd6iOOaD8O+6scFdfha4YzFq1M16FsQHN7r562
# gKzTg/2am6LdpRNhf5GPIJdsGDAut9BuR94FA0VosoX6Kh1UZWWYiqHFJGksop9D
# 5/NM/rWIUPdcAjwb7ec90p2asp78LaExGO36qXUmxHiqd8x+C3BfuUVP4oXqnVkE
# 100zulhN0UXTPL+xRfwd+Z0FdJqmtiFAi7zl0OQegvlhlkpjsnTI1H8iTy47Sr6M
# wt8oQUPm2CGw4yPDNNkjcgUoK9UsuNRFwxgmQ9NWlscLppa0+56lUf9TrokxggQN
# MIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiJB
# 0vaq/8i1/wABAAACIjANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0G
# CyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCCYfzIOdis2CEbmpRc4t/65k2qo
# TTgER1no83rAC0BrdzCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIAVgXQEK
# BOfGgjNskmDOmbcEIOnHGNwA+QcRufDR5AkTMIGYMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTACEzMAAAIiQdL2qv/Itf8AAQAAAiIwIgQg26aIE62W
# z1dC7WTJ6HmsxCxiLFwniz2h+z8y+/p+gwUwDQYJKoZIhvcNAQELBQAEggIADSXJ
# EprNJ5IyJnCjdVtltUMD+cBFzIp7o7Dd/MWr/+aNiADUAoTxqRemh8FXrR7b0Lqc
# SmQdwoMHLsX9c26HV2xzVCH3fn92EFG96eSTl0PWsIekvY6rmdltpxIlj8p/D24l
# Nw5srET0WdwUYgX1bbhm0LS92yI/1ZDVjOcQxsWqJLNucPyXOWTDeYwb0lxn/mYD
# QIpyP1jqGw7Hhm5HDqlewjJDRRediFc2oug7V/riTY4mHmyZvtPfe42nEniYEs9B
# go06vLEjTbkJacjFFoN4sYVeyBUs29ZNpsaAB9+jzvWWfgmQHjKnak3MMX98tW6j
# pXUaTwcn0jxyzv/6iPRNUcqbaKuHGom8NHIcRhSS2jkFVzk6UfdAej/7sAGrI929
# iKOeYaa4FW0CtMekbIcNG+LGXUl0ma2pVY9NXCtpYYdP0L+gEeIZ8ODTvZCwBe8E
# A7vxYOLNqbkLxyP0lZoTiOdOhxPOxarY4+wTpwhkGMk4EWtglZxr9oXwlmHmxgro
# HAPh8+0ivvzCM19OBZkmaO9zVUxu5MOhHPDs708fD/7XuXsucnyYr72BlKzQPQbo
# XkKTxYEfj+pyC5D8IJkYRhRT3fk7Fr6ssrK0ZUODzL/kYElTkHgjGztSmeWugQ+R
# m7a1Fvj7fZfEtGOWNaErfrtwjb5H+5ugozshz5w=
# SIG # End signature block
